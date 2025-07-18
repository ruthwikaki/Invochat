-- ARVO - MINIMAL USER SETUP FIX SCRIPT
-- This script fixes the user signup process by adding the necessary
-- function and trigger to create a company and user profile on signup.
-- It is designed to be run once on an existing database.

-- 1. Grant necessary permissions to the postgres user.
-- This allows the user to access and modify objects in the auth schema.
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema auth to postgres;

-- 2. Create the function to handle new user setup.
-- This function is called by a trigger when a new user signs up.
-- It creates a new company, a user profile in the public schema,
-- and updates the auth user's metadata with the new company ID and role.
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

  -- Create a corresponding user profile in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- 3. Create the trigger to activate the function on new user creation.
-- This trigger fires after a new user is inserted into the auth.users table.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Grant execute permissions on the function to the authenticated role.
grant execute on function public.handle_new_user() to authenticated;

-- Final success message for the log
select 'User setup script completed successfully.';
