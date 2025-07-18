
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema public;

-- Grant usage on the auth schema to the postgres role
grant usage on schema auth to postgres;
grant select on table auth.users to postgres;

-- Custom user role type
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;


-- Helper functions to get user information from JWT
create or replace function auth.get_user_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid;
$$;

create or replace function auth.get_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'user_role', '');
$$;

create or replace function auth.get_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;


-- Companies Table
create table if not exists companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Users Table (public schema)
create table if not exists users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  email text,
  role user_role not null default 'Member',
  created_at timestamptz default now(),
  deleted_at timestamptz
);

-- Function to handle new user signup
create or replace function public.handle_new_user()
returns trigger
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_email text;
  user_metadata jsonb;
begin
  -- Extract user metadata
  user_metadata := new.raw_app_meta_data;

  -- Create a new company for the user
  insert into public.companies (name)
  values (user_metadata->>'company_name')
  returning id into new_company_id;

  -- Insert a corresponding entry into the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = jsonb_set(
    jsonb_set(raw_app_meta_data, '{company_id}', to_jsonb(new_company_id)),
    '{role}', '"Owner"'::jsonb
  )
  where id = new.id;

  return new;
end;
$$ language plpgsql;


-- Trigger to call handle_new_user on new user signup
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Enable Row Level Security (RLS) for all tables
alter table companies enable row level security;
alter table users enable row level security;

-- RLS Policies
create or replace policy "Allow users to see their own company"
  on companies for select
  using (id = auth.get_company_id());

create or replace policy "Allow users to see other members of their company"
  on users for select
  using (company_id = auth.get_company_id());
  
create or replace policy "Allow owners to manage their company members"
  on users for all
  using (company_id = auth.get_company_id() and auth.get_user_role() = 'Owner')
  with check (company_id = auth.get_company_id() and auth.get_user_role() = 'Owner');
