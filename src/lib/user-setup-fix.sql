-- This script is a minimal fix for the user signup process.
-- It adds the necessary function and trigger to handle new user setup.

-- Grant usage on the auth schema to the postgres role
grant usage on schema auth to postgres;

-- Grant select on all tables in the auth schema to the postgres role
grant select on all tables in schema auth to postgres;

-- Create the function to handle new user setup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into new_company_id;

  -- Create a new user profile in the public schema
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Drop the existing trigger if it exists
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger to run the function on new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
