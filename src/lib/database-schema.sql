-- This file contains the full database schema for the application.
-- It is used to set up the database for new installations.

-- Enable UUID generation
create extension if not exists "uuid-ossp";

-- ## Public Schema Tables ##

-- Companies Table: Stores basic information about each company tenant.
create table public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  owner_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- Company Users Table: A junction table linking users to companies with specific roles.
-- This table is central to the multi-tenancy model.
create table public.company_users (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.company_role not null default 'Member',
  primary key (company_id, user_id)
);


-- Company Settings Table: Contains tenant-specific settings for business logic.
create table public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- Stored in cents, e.g., 1000.00
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    alert_settings jsonb default '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00"}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- ## ENUM Types ##

-- Defines the possible roles a user can have within a company.
create type public.company_role as enum ('Owner', 'Admin', 'Member');

-- Defines the possible platforms for integrations.
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');

-- Defines the roles messages can have in the chat interface.
create type public.message_role as enum ('user', 'assistant', 'tool');

-- Defines feedback types.
create type public.feedback_type as enum ('helpful', 'unhelpful');


-- ## Functions and Triggers ##

-- This function is called by a trigger whenever a new user signs up.
-- It creates a new company for the user and assigns them as the owner.
create or replace function public.create_company_and_user(
  p_company_name text,
  p_user_email text,
  p_user_password text,
  p_email_redirect_to text
)
returns uuid
language plpgsql
security definer -- This is crucial for allowing the function to create a user in the auth schema
set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_id uuid;
begin
  -- 1. Create the company first.
  insert into public.companies (name)
  values (p_company_name)
  returning id into new_company_id;

  -- 2. Create the user in auth.users, passing the new company_id in the metadata.
  -- This ensures the automatic mirroring to public.users works correctly.
  select auth.admin_create_user(
    p_user_email,
    p_user_password,
    jsonb_build_object(
        'company_id', new_company_id,
        'company_name', p_company_name
    ),
    p_email_redirect_to
  ) into new_user_id;

  -- 3. Update the company with the owner's ID now that the user exists.
  update public.companies
  set owner_id = new_user_id
  where id = new_company_id;
  
  -- 4. Create the link in company_users to establish the Owner role.
  insert into public.company_users(user_id, company_id, role)
  values(new_user_id, new_company_id, 'Owner');

  return new_user_id;
end;
$$;
