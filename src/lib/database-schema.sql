-- src/lib/database-schema.sql

-- Enable the "pgcrypto" extension for generating UUIDs
create extension if not exists "pgcrypto" with schema "extensions";
-- Enable the "vector" extension for AI-powered semantic search
create extension if not exists "vector" with schema "extensions";
-- Enable the "vault" extension for encrypting and decrypting secrets
create extension if not exists "supabase_vault" with schema "vault";

-- Drop existing tables to ensure a clean slate, handling dependencies.
-- This is useful for development but should be used cautiously in production.
drop table if exists "public"."feedback" cascade;
drop table if exists "public"."messages" cascade;
drop table if exists "public"."conversations" cascade;
drop table if exists "public"."audit_log" cascade;
drop table if exists "public"."purchase_order_line_items" cascade;
drop table if exists "public"."purchase_orders" cascade;
drop table if exists "public"."order_line_items" cascade;
drop table if exists "public"."refunds" cascade;
drop table if exists "public"."orders" cascade;
drop table if exists "public"."customers" cascade;
drop table if exists "public"."inventory_ledger" cascade;
drop table if exists "public"."product_variants" cascade;
drop table if exists "public"."products" cascade;
drop table if exists "public"."suppliers" cascade;
drop table if exists "public"."channel_fees" cascade;
drop table if exists "public"."imports" cascade;
drop table if exists "public"."export_jobs" cascade;
drop table if exists "public"."webhook_events" cascade;
drop table if exists "public"."integrations" cascade;
drop table if exists "public"."company_settings" cascade;
drop table if exists "public"."company_users" cascade;
drop table if exists "public"."companies" cascade;
drop type if exists "public"."company_role";
drop type if exists "public"."feedback_type";
drop type if exists "public"."message_role";
drop type if exists "public"."integration_platform";
drop function if exists "public"."handle_new_user"();
drop function if exists "public"."get_company_id_for_user"(uuid);
drop function if exists "public"."check_user_permission"(uuid, company_role);
drop function if exists "public"."get_users_for_company"(uuid);
drop function if exists "public"."remove_user_from_company"(uuid, uuid);
drop function if exists "public"."update_user_role_in_company"(uuid, uuid, company_role);
drop function if exists "public"."record_order_from_platform"(jsonb, uuid, text);
drop function if exists "public"."update_inventory_from_ledger"();
drop function if exists "public"."get_reorder_suggestions"(uuid);
drop function if exists "public"."get_dead_stock_report"(uuid);
drop function if exists "public"."get_supplier_performance_report"(uuid);
drop function if exists "public"."get_dashboard_metrics"(uuid, int);
drop function if exists "public"."get_inventory_turnover"(uuid, int);
drop function if exists "public"."create_purchase_orders_from_suggestions"(uuid, uuid, jsonb, text);

-- Custom Types
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');
create type "public"."message_role" as enum ('user', 'assistant', 'tool');
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');

-- Companies Table: Stores information about each business/tenant.
create table "public"."companies" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "name" text not null,
    "owner_id" uuid not null references auth.users(id),
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."companies" enable row level security;

-- Company Users Table: A junction table linking users to companies.
create table "public"."company_users" (
    "user_id" uuid not null references auth.users(id) on delete cascade,
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "role" company_role not null default 'Member',
    primary key (user_id, company_id)
);
alter table "public"."company_users" enable row level security;

-- Company Settings Table: Stores business logic settings for each company.
create table "public"."company_settings" (
    "company_id" uuid primary key references public.companies(id) on delete cascade,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "overstock_multiplier" numeric not null default 3,
    "high_value_threshold" integer not null default 100000,
    "predictive_stock_days" integer not null default 7,
    "currency" text not null default 'USD',
    "tax_rate" numeric not null default 0,
    "timezone" text not null default 'UTC',
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."company_settings" enable row level security;

-- Suppliers Table
create table "public"."suppliers" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "name" text not null,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "company_id" uuid not null references public.companies(id) on delete cascade
);
alter table "public"."suppliers" enable row level security;

-- Products Table
create table "public"."products" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "title" text not null,
    "description" text,
    "handle" text,
    "product_type" text,
    "tags" text[],
    "status" text,
    "image_url" text,
    "external_product_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    unique(company_id, external_product_id)
);
alter table "public"."products" enable row level security;

-- Product Variants Table
create table "public"."product_variants" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "product_id" uuid not null references public.products(id) on delete cascade,
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "sku" text not null,
    "title" text,
    "option1_name" text,
    "option1_value" text,
    "option2_name" text,
    "option2_value" text,
    "option3_name" text,
    "option3_value" text,
    "barcode" text,
    "price" integer,
    "compare_at_price" integer,
    "cost" integer,
    "inventory_quantity" integer not null default 0,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "location" text,
    "supplier_id" uuid references public.suppliers(id),
    "external_variant_id" text,
    "version" integer not null default 1,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    unique(company_id, sku)
);
alter table "public"."product_variants" enable row level security;
create index "product_variants_company_id_inventory_quantity_idx" on "public"."product_variants" (company_id, inventory_quantity);

-- Customers Table
create table "public"."customers" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone,
     unique(company_id, external_customer_id)
);
alter table "public"."customers" enable row level security;

-- Orders Table
create table "public"."orders" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "order_number" text not null,
    "external_order_id" text,
    "customer_id" uuid references public.customers(id),
    "financial_status" text,
    "fulfillment_status" text,
    "currency" text,
    "subtotal" integer not null,
    "total_tax" integer,
    "total_shipping" integer,
    "total_discounts" integer,
    "total_amount" integer not null,
    "source_platform" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    unique(company_id, external_order_id)
);
alter table "public"."orders" enable row level security;

-- Order Line Items Table
create table "public"."order_line_items" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "order_id" uuid not null references public.orders(id) on delete cascade,
    "variant_id" uuid references public.product_variants(id),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "product_name" text,
    "variant_title" text,
    "sku" text,
    "quantity" integer not null,
    "price" integer not null,
    "total_discount" integer,
    "tax_amount" integer,
    "cost_at_time" integer,
    "external_line_item_id" text
);
alter table "public"."order_line_items" enable row level security;

-- Refunds Table
create table "public"."refunds" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "order_id" uuid not null references public.orders(id) on delete cascade,
  "refund_number" text not null,
  "status" text not null,
  "reason" text,
  "note" text,
  "total_amount" integer not null,
  "created_by_user_id" uuid references auth.users(id),
  "external_refund_id" text,
  "created_at" timestamp with time zone not null default now()
);
alter table "public"."refunds" enable row level security;


-- Inventory Ledger Table
create table "public"."inventory_ledger" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "variant_id" uuid not null references public.product_variants(id) on delete cascade,
    "change_type" text not null,
    "quantity_change" integer not null,
    "new_quantity" integer not null,
    "related_id" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."inventory_ledger" enable row level security;

-- Purchase Orders Table
create table "public"."purchase_orders" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "supplier_id" uuid references public.suppliers(id),
    "status" text not null default 'Draft',
    "po_number" text not null,
    "total_cost" integer not null,
    "expected_arrival_date" date,
    "idempotency_key" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."purchase_orders" enable row level security;

-- Purchase Order Line Items Table
create table "public"."purchase_order_line_items" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "purchase_order_id" uuid not null references public.purchase_orders(id) on delete cascade,
    "variant_id" uuid not null references public.product_variants(id),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "quantity" integer not null,
    "cost" integer not null
);
alter table "public"."purchase_order_line_items" enable row level security;

-- Integrations Table
create table "public"."integrations" (
    "id" uuid primary key default extensions.gen_random_uuid(),
    "company_id" uuid not null references public.companies(id) on delete cascade,
    "platform" integration_platform not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean not null default true,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    unique(company_id, platform)
);
alter table "public"."integrations" enable row level security;

-- Webhook Events Table
create table "public"."webhook_events" (
  id uuid primary key default extensions.gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  created_at timestamp with time zone not null default now(),
  unique (integration_id, webhook_id)
);
alter table "public"."webhook_events" enable row level security;

-- Import Jobs Table
create table "public"."imports" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "created_by" uuid not null references auth.users(id),
  "import_type" text not null,
  "file_name" text not null,
  "status" text not null default 'pending',
  "total_rows" integer,
  "processed_rows" integer,
  "error_count" integer,
  "errors" jsonb,
  "summary" jsonb,
  "created_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone
);
alter table "public"."imports" enable row level security;

-- Export Jobs Table
create table "public"."export_jobs" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "requested_by_user_id" uuid not null references auth.users(id),
  "status" text not null default 'pending',
  "download_url" text,
  "expires_at" timestamp with time zone,
  "error_message" text,
  "created_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone
);
alter table "public"."export_jobs" enable row level security;

-- Channel Fees Table
create table "public"."channel_fees" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "channel_name" text not null,
  "fixed_fee" integer,
  "percentage_fee" numeric,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone,
  unique(company_id, channel_name)
);
alter table "public"."channel_fees" enable row level security;

-- Audit Log Table
create table "public"."audit_log" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "user_id" uuid references auth.users(id),
  "action" text not null,
  "details" jsonb,
  "created_at" timestamp with time zone not null default now()
);
alter table "public"."audit_log" enable row level security;


-- Conversations Table (for AI Chat)
create table "public"."conversations" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "user_id" uuid not null references auth.users(id) on delete cascade,
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "title" text not null,
  "is_starred" boolean not null default false,
  "created_at" timestamp with time zone not null default now(),
  "last_accessed_at" timestamp with time zone not null default now()
);
alter table "public"."conversations" enable row level security;

-- Messages Table (for AI Chat)
create table "public"."messages" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "conversation_id" uuid not null references public.conversations(id) on delete cascade,
  "company_id" uuid not null references public.companies(id) on delete cascade,
  "role" message_role not null,
  "content" text not null,
  "visualization" jsonb,
  "confidence" numeric,
  "assumptions" text[],
  "component" text,
  "componentProps" jsonb,
  "isError" boolean default false,
  "created_at" timestamp with time zone not null default now()
);
alter table "public"."messages" enable row level security;
alter table "public"."messages" add column "embedding" vector(1536);

-- Feedback Table (for AI responses)
create table "public"."feedback" (
  "id" uuid primary key default extensions.gen_random_uuid(),
  "user_id" uuid not null references auth.users(id),
  "company_id" uuid not null references public.companies(id),
  "subject_id" uuid not null,
  "subject_type" text not null, -- e.g., 'message', 'alert'
  "feedback" feedback_type not null,
  "created_at" timestamp with time zone not null default now()
);
alter table "public"."feedback" enable row level security;

-- RLS Policies
-- Companies
create policy "Users can only see companies they belong to."
on public.companies for select
using (auth.uid() in (
    select user_id from public.company_users where company_id = id
));

-- Company Users
create policy "Users can see other members of their own company."
on public.company_users for select
using (company_id in (
    select company_id from public.company_users where user_id = auth.uid()
));

-- All other tables are protected by checking the company_id column
create policy "Users can only access data within their own company."
on public.company_settings for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.suppliers for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.products for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.product_variants for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.orders for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.order_line_items for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.inventory_ledger for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.purchase_orders for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.purchase_order_line_items for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.integrations for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.customers for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.refunds for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access data within their own company."
on public.channel_fees for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access their own audit logs."
on public.audit_log for all
using (company_id in (select company_id from public.company_users where user_id = auth.uid()))
with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

create policy "Users can only access their own conversations and messages."
on public.conversations for all
using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "Users can only access messages in their own conversations."
on public.messages for all
using (conversation_id in (select id from public.conversations where user_id = auth.uid()))
with check (conversation_id in (select id from public.conversations where user_id = auth.uid()));


-- Database Functions and Triggers
-- This function is called when a new user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into new_company_id;

  -- Link the user to the new company
  insert into public.company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');
  
  -- Add default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  return new;
end;
$$;

-- This trigger calls the function when a new user is created.
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- This function updates inventory levels based on ledger entries.
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
drop function if exists public.update_inventory_from_ledger();

create or replace function public.update_inventory_from_ledger()
returns trigger
language plpgsql
as $$
begin
  update public.product_variants
  set 
    inventory_quantity = new.new_quantity,
    version = version + 1 -- Increment version for optimistic locking
  where id = new.variant_id;
  
  return new;
end;
$$;

create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_inventory_from_ledger();

-- New trigger to log manual inventory changes to the audit log
create or replace function public.log_inventory_changes()
returns trigger
language plpgsql
as $$
declare
  user_id uuid;
  change_source text;
begin
  -- Attempt to get the user ID from the current session
  user_id := auth.uid();

  -- Determine the source of the change based on the notes in the ledger
  select
    case
      when L.notes like 'PO-%' then 'Purchase Order'
      when L.notes like 'Order-%' then 'Sale'
      when L.notes like 'Reconciliation%' then 'Reconciliation'
      else 'Manual Adjustment'
    end into change_source
  from public.inventory_ledger L
  where L.id = NEW.related_id;

  -- Only log if it's a manual adjustment
  if change_source = 'Manual Adjustment' then
    insert into public.audit_log(company_id, user_id, action, details)
    values (
      NEW.company_id,
      user_id,
      'inventory_adjusted',
      jsonb_build_object(
        'variant_id', NEW.id,
        'sku', NEW.sku,
        'previous_quantity', OLD.inventory_quantity,
        'new_quantity', NEW.inventory_quantity,
        'change', NEW.inventory_quantity - OLD.inventory_quantity
      )
    );
  end if;

  return NEW;
end;
$$;

-- Drop the trigger if it exists before creating
drop trigger if exists on_inventory_quantity_change on public.product_variants;

create trigger on_inventory_quantity_change
  after update of inventory_quantity on public.product_variants
  for each row
  when (OLD.inventory_quantity is distinct from NEW.inventory_quantity)
  execute procedure public.log_inventory_changes();


-- Function to get the company ID for a given user
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users where user_id = p_user_id limit 1;
$$;

-- Function to check user permissions
create or replace function public.check_user_permission(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
as $$
declare
  user_role company_role;
begin
  select role into user_role from public.company_users where user_id = p_user_id;
  if user_role is null then
    return false;
  end if;

  if p_required_role = 'Admin' then
    return user_role in ('Owner', 'Admin');
  elsif p_required_role = 'Owner' then
    return user_role = 'Owner';
  end if;
  
  return false;
end;
$$;

-- Function to get all users for a company
create or replace function public.get_users_for_company(p_company_id uuid)
returns table(id uuid, email text, role company_role)
language sql
security definer
as $$
  select u.id, u.email, cu.role
  from auth.users u
  join public.company_users cu on u.id = cu.user_id
  where cu.company_id = p_company_id;
$$;

-- Function to remove a user from a company
create or replace function public.remove_user_from_company(p_user_id uuid, p_company_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  delete from public.company_users
  where user_id = p_user_id and company_id = p_company_id;
end;
$$;

-- Function to update a user's role in a company
create or replace function public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role company_role)
returns void
language plpgsql
security definer
as $$
begin
  update public.company_users
  set role = p_new_role
  where user_id = p_user_id and company_id = p_company_id;
end;
$$;

-- Materialized Views for performance
drop materialized view if exists public.product_variants_with_details_mat;
create materialized view public.product_variants_with_details_mat as
select 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
from public.product_variants pv
join public.products p on pv.product_id = p.id;

create unique index on public.product_variants_with_details_mat(id);

drop materialized view if exists public.customers_view;
create materialized view public.customers_view as
select 
  c.id, c.company_id, c.name as customer_name, c.email, c.created_at,
  count(o.id) as total_orders,
  sum(o.total_amount) as total_spent,
  min(o.created_at) as first_order_date
from public.customers c
left join public.orders o on c.id = o.customer_id
group by c.id, c.company_id, c.name, c.email;

create unique index on public.customers_view(id);

drop materialized view if exists public.orders_view;
create materialized view public.orders_view as
select 
    o.*,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

create unique index on public.orders_view(id);


-- Function to refresh all materialized views for a company
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void as $$
begin
    -- These views are not company-specific but are refreshed globally for simplicity.
    -- In a larger system, you might pass company_id to refresh specific partitions.
    refresh materialized view concurrently public.product_variants_with_details_mat;
    refresh materialized view concurrently public.customers_view;
    refresh materialized view concurrently public.orders_view;
end;
$$ language plpgsql;
