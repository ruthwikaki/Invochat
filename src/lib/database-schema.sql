-- This script fixes the new user signup flow by creating the necessary
-- trigger and function to automatically provision a company and user profile.
-- It is idempotent and safe to run on an existing database.

-- 1. Grant necessary permissions to the postgres user
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all sequences in schema auth to postgres;
grant all on all functions in schema auth to postgres;

-- 2. Create the function to handle new user setup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  user_email text;
  company_name text;
begin
  -- Extract company name and email from the new user's metadata
  company_name := new.raw_app_meta_data->>'company_name';
  user_email := new.raw_app_meta_data->>'email';
  
  -- Create a new company for the user
  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- Create a corresponding user profile in the public schema
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, user_email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- 3. Create the trigger to fire the function after a new user is created in auth.users
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Grant execute permission on the function to the 'anon' role,
-- which is the role Supabase uses for unauthenticated or newly authenticated users.
grant execute on function public.handle_new_user() to anon;
