-- This script creates the required function and trigger to automatically
-- set up a new company and user profile upon Supabase auth signup.
-- It is designed to be run on an existing database that is missing this logic.

-- Grant necessary permissions to the 'postgres' role to interact with the 'auth' schema.
grant usage on schema auth to postgres;
grant all on all tables in schema auth to postgres;
grant all on all sequences in schema auth to postgres;
grant all on all functions in schema auth to postgres;

-- 1. Helper function to get the company_id from the user's JWT claims.
-- Casts the text result to a uuid.
create or replace function public.get_company_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;


-- 2. The core function to handle new user setup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- This is crucial for allowing the function to access the auth schema.
set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from the user's metadata provided during signup.
  user_company_name := new.raw_app_meta_data->>'company_name';

  -- Create a new company for the user.
  insert into public.companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Create a corresponding user profile in the public.users table.
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in the auth schema with the new company_id.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;

  return new;
end;
$$;


-- 3. A SECURITY DEFINER function to create the trigger on the auth.users table.
-- This is necessary because the 'postgres' user (which runs migrations) does not
-- own the auth.users table and cannot directly create triggers on it.
create or replace function public.security_definer_handle_new_user()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Drop the trigger if it already exists to make this script re-runnable.
  if exists (
      select 1
      from pg_trigger
      where not tgisinternal
      and tgname = 'on_auth_user_created'
  ) then
      drop trigger on_auth_user_created on auth.users;
  end if;

  -- Create the trigger to call handle_new_user on each new user insertion.
  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();
end;
$$;

-- 4. Execute the function to create the trigger.
select public.security_definer_handle_new_user();
