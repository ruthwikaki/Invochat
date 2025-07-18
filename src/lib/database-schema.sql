-- InvoChat Database Schema
-- Version: 1.1.0
-- Description: Sets up the complete database schema for the InvoChat application,
-- including tables, roles, functions, triggers, and row-level security policies.
-- This script is designed to be idempotent and can be run safely multiple times.

-- 1. EXTENSIONS
-- -----------------------------------------------------------------------------
-- Enable necessary PostgreSQL extensions.
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- 2. TYPE DEFINITIONS
-- -----------------------------------------------------------------------------
-- Define a custom type for user roles to ensure data consistency.
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- 3. HELPER FUNCTIONS
-- -----------------------------------------------------------------------------
-- These functions provide a secure way to access claims from the JSON Web Token (JWT).
-- They are essential for Row-Level Security (RLS) policies.

-- Function to get the currently authenticated user's ID.
create or replace function public.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;
comment on function public.get_user_id() is 'Gets the user ID from the JWT claims.';

-- Function to get the company ID associated with the currently authenticated user.
create or replace function public.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
comment on function public.get_company_id() is 'Gets the company ID from the JWT claims.';

-- Function to get the role of the currently authenticated user.
create or replace function public.get_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '');
$$;
comment on function public.get_user_role() is 'Gets the user role from the JWT claims.';


-- 4. TABLES
-- -----------------------------------------------------------------------------
-- Core tables for the application.

create table if not exists public.companies (
    id uuid primary key default extensions.uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company information.';

create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Stores user profiles linked to companies and auth.users.';


-- 5. USER ONBOARDING LOGIC
-- -----------------------------------------------------------------------------
-- This function and trigger handle the critical process of setting up a new user's
-- company and profile upon their first sign-up.

-- Grant permissions to the postgres role on the auth schema
grant all on all tables in schema auth to postgres;
grant all on all functions in schema auth to postgres;
grant all on all sequences in schema auth to postgres;
grant all on all tables in schema auth to service_role;
grant all on all functions in schema auth to service_role;
grant all on all sequences in schema auth to service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from the user's metadata, defaulting if not present.
  user_company_name := new.raw_app_meta_data->>'company_name';
  if user_company_name is null or user_company_name = '' then
    user_company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the user.
  insert into public.companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Create a corresponding user profile in the public.users table.
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in auth.users to include their new company_id and role.
  -- This is crucial for RLS policies and application logic.
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object(
      'company_id', new_company_id,
      'user_role', 'Owner'
    )
  where id = new.id;

  return new;
end;
$$;
comment on function public.handle_new_user() is 'Trigger function to create a company and user profile for new sign-ups.';


-- Drop the trigger if it already exists, then create it.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

comment on trigger on_auth_user_created on auth.users is 'Fires after a new user signs up to set up their company and profile.';


-- 6. ROW-LEVEL SECURITY (RLS) POLICIES
-- -----------------------------------------------------------------------------
-- These policies are the cornerstone of the multi-tenant security model.
-- They ensure that users can only access data belonging to their own company.

-- Enable RLS for all relevant tables.
alter table public.companies enable row level security;
alter table public.users enable row level security;

-- Drop policies before creating them to ensure idempotency.
drop policy if exists "Allow users to see their own company" on public.companies;
create policy "Allow users to see their own company"
on public.companies for select
using (id = public.get_company_id());

drop policy if exists "Allow users to see members of their own company" on public.users;
create policy "Allow users to see members of their own company"
on public.users for select
using (company_id = public.get_company_id());

drop policy if exists "Allow admins to update their own company users" on public.users;
create policy "Allow admins to update their own company users"
on public.users for update
using (company_id = public.get_company_id() and public.get_user_role() = 'Admin')
with check (company_id = public.get_company_id());


-- 7. INITIAL DATA AND CONSTRAINTS (Example)
-- -----------------------------------------------------------------------------
-- This section is a placeholder for any initial data your application might need,
-- or for adding constraints after tables and functions are set up.

-- Example of adding a unique constraint idempotently:
-- alter table public.integrations drop constraint if exists integrations_company_id_platform_key;
-- alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);

-- Final success message
select 'ARVO database schema setup is complete.';
