-- This script fixes the new user signup flow by creating the necessary function and trigger.
-- It is designed to be run once on an existing database where user signups are failing.

-- 1. Grant necessary permissions to the 'postgres' role
-- This allows the 'postgres' user (which runs functions) to read from the auth.users table.
grant usage on schema auth to postgres;
grant select on table auth.users to postgres;

-- 2. Create the user setup function
-- This function is called by a trigger when a new user is created.
-- It creates a new company and links the user to it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  company_name text;
begin
  -- Extract company name from the user's metadata, defaulting if not present.
  company_name := new.raw_app_meta_data->>'company_name';
  if company_name is null or company_name = '' then
    company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the user.
  insert into public.companies (name)
  values (company_name)
  returning id into new_company_id;

  -- Insert the user into the public users table, linking to the new company.
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in the auth schema with the new company_id.
  -- This is critical for the application to identify the user's company on subsequent logins.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- 3. Create the trigger to activate the function on new user signup
-- This attaches the handle_new_user function to the auth.users table.
-- It will fire after a new user record is inserted.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Grant execute permissions on the function to the 'authenticated' role
-- This ensures any authenticated user can call this function if needed, though it's primarily for the trigger.
grant execute on function public.handle_new_user() to authenticated;
