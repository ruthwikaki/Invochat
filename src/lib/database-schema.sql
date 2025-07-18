-- This script fixes the user setup process by creating the necessary
-- function and trigger to handle new user sign-ups. It is designed
-- to be run safely on an existing database.

-- Grant usage on the 'auth' schema to the 'postgres' user.
-- This is necessary so that the trigger function can be created.
grant usage on schema auth to postgres;

-- Grant SELECT permission on the 'users' table in the 'auth' schema.
-- This allows the function to read user data.
grant select on table auth.users to postgres;

-- Create the user_role type if it doesn't already exist.
-- This defines the possible roles a user can have within a company.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- Main function to handle new user setup.
-- This function is called by a trigger when a new user is created in auth.users.
-- It creates a company, a corresponding public user profile, and sets the user's role to 'Owner'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  new_company_name text;
begin
  -- 1. Extract the company name from the user's metadata.
  -- This is set during the signup process.
  new_company_name := new.raw_app_meta_data->>'company_name';

  -- 2. Create a new company for the user.
  insert into public.companies (name)
  values (new_company_name)
  returning id into new_company_id;

  -- 3. Create a profile for the new user in the public.users table.
  -- This links the auth.users record to the application's data.
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- 4. Update the user's app_metadata in the auth schema with the new company_id.
  -- This makes the company_id easily accessible in the JWT and for RLS policies.
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;

  return new;
end;
$$;

-- Drop the existing trigger if it exists.
-- This makes the script safe to re-run.
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger that calls the handle_new_user function.
-- This fires after a new user is inserted into the auth.users table.
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Grant execute permission on the function to the 'authenticated' role.
-- While the trigger runs as the definer, this is good practice for functions
-- that might be called from the application layer in other contexts.
grant execute on function public.handle_new_user() to authenticated;
