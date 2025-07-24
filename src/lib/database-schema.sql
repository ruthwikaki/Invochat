-- InvoChat Database Schema
-- Version: 1.5.0

-- Extensions
-- These extensions are required for the application to function correctly.
create extension if not exists "uuid-ossp" with schema "extensions";
create extension if not exists "vector" with schema "extensions";
create extension if not exists "pg_trgm" with schema "extensions";

-- Drop existing objects in reverse order of dependency
-- This section is for development convenience to allow re-running the script.
-- In production, you would use a migration tool.

-- Drop RLS Policies first
drop policy if exists "User can see other users in their company" on "auth"."users";
drop policy if exists "User can access their own company settings" on "public"."company_settings";
drop policy if exists "User can access their own company data" on "public"."audit_log";
drop policy if exists "User can access their own company data" on "public"."messages";
drop policy if exists "User can access their own company data" on "public"."inventory_ledger";
drop policy if exists "User can access their own company data" on "public"."webhook_events";
drop policy if exists "User can access their own company data" on "public"."integrations";
drop policy if exists "User can access their own company data" on "public"."purchase_order_line_items";
drop policy if exists "User can access their own company data" on "public"."purchase_orders";
drop policy if exists "User can access their own company data" on "public"."suppliers";
drop policy if exists "User can access their own company data" on "public"."customers";
drop policy if exists "User can access their own company data" on "public"."order_line_items";
drop policy if exists "User can access their own company data" on "public"."orders";
drop policy if exists "User can access their own company data" on "public"."product_variants";
drop policy if exists "User can access their own company data" on "public"."products";
drop policy if exists "User can manage their own company" on "public"."companies";

-- Drop Functions that policies depend on
drop function if exists "public"."check_user_permission"(p_user_id uuid, p_required_role public.company_role);
drop function if exists "public"."get_company_id_for_user"(p_user_id uuid);

-- Drop other functions
drop function if exists "public"."handle_new_user"();
drop function if exists "public"."record_order_from_platform"(p_company_id uuid, p_order_payload jsonb, p_platform text);
drop function if exists "public"."update_fts_document"();

-- Drop types
drop type if exists "public"."company_role";
drop type if exists "public"."feedback_type";
drop type if exists "public"."integration_platform";
drop type if exists "public"."message_role";


-- Custom Types
-- These enums define the possible values for certain columns.
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');
create type "public"."message_role" as enum ('user', 'assistant', 'tool');

-- Tables
-- The core data structures for the application.

-- Companies Table: Represents a tenant in the multi-tenant system.
create table "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "name" text not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."companies" enable row level security;
alter table "public"."companies" add constraint "companies_pkey" primary key using index on ("id");

-- Company Users Table: A junction table linking users to companies and their roles.
create table "public"."company_users" (
    "company_id" uuid not null,
    "user_id" uuid not null,
    "role" public.company_role not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
alter table "public"."company_users" add constraint "company_users_pkey" primary key using index on ("company_id", "user_id");
alter table "public"."company_users" add constraint "company_users_company_id_fkey" foreign key ("company_id") references "public"."companies"(id) on delete cascade not valid;
alter table "public"."company_users" validate constraint "company_users_company_id_fkey";
alter table "public"."company_users" add constraint "company_users_user_id_fkey" foreign key ("user_id") references "auth"."users"(id) on delete cascade not valid;
alter table "public"."company_users" validate constraint "company_users_user_id_fkey";


-- Products Table: Stores the main product information.
create table "public"."products" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
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
    "fts_document" tsvector,
    "deleted_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
alter table "public"."products" add constraint "products_pkey" primary key using index on ("id");
alter table "public"."products" add constraint "products_company_id_fkey" foreign key ("company_id") references "public"."companies"(id) on delete cascade not valid;
alter table "public"."products" validate constraint "products_company_id_fkey";
create index "idx_products_company_id" on "public"."products" using btree ("company_id");
create unique index "products_company_id_external_product_id_key" on "public"."products" using btree ("company_id", "external_product_id");
create index "products_fts_document_idx" on "public"."products" using gin ("fts_document");

-- Suppliers Table
create table "public"."suppliers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text not null,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."suppliers" enable row level security;
alter table "public"."suppliers" add constraint "suppliers_pkey" primary key using index on ("id");
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" foreign key ("company_id") references "public"."companies"(id) on delete cascade;


-- Product Variants Table
create table "public"."product_variants" (
    "id" uuid not null default gen_random_uuid(),
    "product_id" uuid not null,
    "company_id" uuid not null,
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
    "lead_time_days" integer,
    "supplier_id" uuid,
    "location" text,
    "external_variant_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "deleted_at" timestamp with time zone
);
alter table "public"."product_variants" enable row level security;
alter table "public"."product_variants" add constraint "product_variants_pkey" primary key using index on ("id");
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" foreign key (product_id) references public.products(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" foreign key (supplier_id) references public.suppliers(id) on delete set null;
alter table "public"."product_variants" add constraint "inventory_quantity_non_negative" check ((inventory_quantity >= 0));
create unique index "product_variants_company_id_sku_key" on "public"."product_variants" using btree ("company_id", "sku");
create index "idx_product_variants_company_id" on "public"."product_variants" using btree (company_id);
create unique index "product_variants_company_id_external_variant_id_key" on "public"."product_variants" using btree (company_id, external_variant_id);


-- Customers Table
create table "public"."customers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
alter table "public"."customers" enable row level security;
alter table "public"."customers" add constraint "customers_pkey" primary key using index on ("id");
alter table "public"."customers" add constraint "customers_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
create unique index "customers_company_id_email_key" on "public"."customers" using btree (company_id, email);
create unique index "customers_company_id_external_customer_id_key" on "public"."customers" using btree (company_id, external_customer_id);

-- Orders Table
create table "public"."orders" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "order_number" text not null,
    "external_order_id" text,
    "customer_id" uuid,
    "financial_status" text,
    "fulfillment_status" text,
    "currency" text,
    "subtotal" integer not null default 0,
    "total_tax" integer default 0,
    "total_shipping" integer default 0,
    "total_discounts" integer default 0,
    "total_amount" integer not null,
    "source_platform" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."orders" enable row level security;
alter table "public"."orders" add constraint "orders_pkey" primary key using index on ("id");
alter table "public"."orders" add constraint "orders_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."orders" add constraint "orders_customer_id_fkey" foreign key (customer_id) references public.customers(id) on delete set null;
create unique index "orders_company_id_external_order_id_key" on "public"."orders" using btree ("company_id", "external_order_id");
create index "idx_orders_company_id_created_at" on "public"."orders" using btree (company_id, created_at desc);

-- Order Line Items Table
create table "public"."order_line_items" (
    "id" uuid not null default gen_random_uuid(),
    "order_id" uuid not null,
    "variant_id" uuid,
    "company_id" uuid not null,
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
alter table "public"."order_line_items" add constraint "order_line_items_pkey" primary key using index on ("id");
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" foreign key (order_id) references public.orders(id) on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" foreign key (variant_id) references public.product_variants(id) on delete set null;

-- Purchase Orders Table
create table "public"."purchase_orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "supplier_id" uuid,
    "status" text not null default 'Draft'::text,
    "po_number" text not null,
    "total_cost" integer not null,
    "expected_arrival_date" date,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "idempotency_key" uuid
);
alter table "public"."purchase_orders" enable row level security;
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" primary key using index on ("id");
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" foreign key (supplier_id) references public.suppliers(id) on delete set null;
create unique index "purchase_orders_company_id_po_number_key" on public.purchase_orders using btree (company_id, po_number);
create index "idx_purchase_orders_company_id" on public.purchase_orders using btree (company_id);

-- Purchase Order Line Items Table
create table "public"."purchase_order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
    "purchase_order_id" uuid not null,
    "variant_id" uuid not null,
    "company_id" uuid not null,
    "quantity" integer not null,
    "cost" integer not null
);
alter table "public"."purchase_order_line_items" enable row level security;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_pkey" primary key using index on ("id");
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" foreign key (purchase_order_id) references public.purchase_orders(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" foreign key (variant_id) references public.product_variants(id) on delete cascade;


-- Inventory Ledger Table
create table "public"."inventory_ledger" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "variant_id" uuid not null,
    "change_type" text not null,
    "quantity_change" integer not null,
    "new_quantity" integer not null,
    "related_id" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."inventory_ledger" enable row level security;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_pkey" primary key using index on ("id");
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" foreign key (variant_id) references public.product_variants(id) on delete cascade;
create index "idx_inventory_ledger_variant_id_created_at" on "public"."inventory_ledger" using btree (variant_id, created_at desc);

-- Integrations Table
create table "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" public.integration_platform not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean default false,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."integrations" enable row level security;
alter table "public"."integrations" add constraint "integrations_pkey" primary key using index on ("id");
alter table "public"."integrations" add constraint "integrations_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
create unique index "integrations_company_id_platform_key" on "public"."integrations" using btree (company_id, platform);

-- Webhook Events Table
create table "public"."webhook_events" (
    "id" uuid not null default gen_random_uuid(),
    "integration_id" uuid not null,
    "webhook_id" text not null,
    "created_at" timestamp with time zone default now()
);
alter table "public"."webhook_events" enable row level security;
alter table "public"."webhook_events" add constraint "webhook_events_pkey" primary key using index on ("id");
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" foreign key (integration_id) references public.integrations(id) on delete cascade;
create unique index "webhook_events_integration_id_webhook_id_key" on "public"."webhook_events" using btree (integration_id, webhook_id);

-- Conversations Table
create table "public"."conversations" (
    "id" uuid not null default uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone default now(),
    "last_accessed_at" timestamp with time zone default now(),
    "is_starred" boolean default false
);
alter table "public"."conversations" enable row level security;
alter table "public"."conversations" add constraint "conversations_pkey" primary key using index on ("id");
alter table "public"."conversations" add constraint "conversations_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."conversations" add constraint "conversations_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;

-- Messages Table
create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" public.message_role not null,
    "content" text not null,
    "visualization" jsonb,
    "component" text,
    "componentProps" jsonb,
    "confidence" numeric,
    "assumptions" text[],
    "isError" boolean default false,
    "created_at" timestamp with time zone default now()
);
alter table "public"."messages" enable row level security;
alter table "public"."messages" add constraint "messages_pkey" primary key using index on ("id");
alter table "public"."messages" add constraint "messages_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."messages" add constraint "messages_conversation_id_fkey" foreign key (conversation_id) references public.conversations(id) on delete cascade;


-- Company Settings Table
create table "public"."company_settings" (
    "company_id" uuid not null,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "predictive_stock_days" integer not null default 7,
    "overstock_multiplier" real not null default 2.5,
    "high_value_threshold" integer not null default 100000, -- in cents
    "currency" text default 'USD',
    "timezone" text default 'UTC',
    "tax_rate" numeric default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."company_settings" enable row level security;
alter table "public"."company_settings" add constraint "company_settings_pkey" primary key using index on ("company_id");
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;

-- Channel Fees Table
create table "public"."channel_fees" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "channel_name" text not null,
    "fixed_fee" integer, -- in cents
    "percentage_fee" numeric,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."channel_fees" enable row level security;
alter table "public"."channel_fees" add constraint "channel_fees_pkey" primary key using index on ("id");
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
create unique index "channel_fees_company_id_channel_name_key" on "public"."channel_fees" using btree (company_id, channel_name);

-- Audit Log Table
create table "public"."audit_log" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "user_id" uuid,
    "action" text not null,
    "details" jsonb,
    "created_at" timestamp with time zone default now()
);
alter table "public"."audit_log" enable row level security;
alter table "public"."audit_log" add constraint "audit_log_pkey" primary key using index on ("id");
alter table "public"."audit_log" add constraint "audit_log_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."audit_log" add constraint "audit_log_user_id_fkey" foreign key (user_id) references auth.users(id) on delete set null;

-- Feedback Table
create table "public"."feedback" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "subject_id" text not null,
    "subject_type" text not null,
    "feedback" public.feedback_type not null,
    "created_at" timestamp with time zone default now()
);
alter table "public"."feedback" enable row level security;
alter table "public"."feedback" add constraint "feedback_pkey" primary key using index on ("id");
alter table "public"."feedback" add constraint "feedback_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."feedback" add constraint "feedback_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;

-- Export Jobs Table
create table "public"."export_jobs" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "requested_by_user_id" uuid not null,
    "status" text not null default 'pending',
    "download_url" text,
    "expires_at" timestamp with time zone,
    "error_message" text,
    "created_at" timestamp with time zone not null default now(),
    "completed_at" timestamp with time zone
);
alter table "public"."export_jobs" enable row level security;
alter table "public"."export_jobs" add constraint "export_jobs_pkey" primary key using index on ("id");
alter table "public"."export_jobs" add constraint "export_jobs_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."export_jobs" add constraint "export_jobs_requested_by_user_id_fkey" foreign key (requested_by_user_id) references auth.users(id) on delete cascade;

-- Imports Table
create table "public"."imports" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "created_by" uuid not null,
    "import_type" text not null,
    "file_name" text not null,
    "total_rows" integer,
    "processed_rows" integer,
    "failed_rows" integer,
    "status" text not null default 'pending',
    "errors" jsonb,
    "summary" jsonb,
    "created_at" timestamp with time zone default now(),
    "completed_at" timestamp with time zone
);
alter table "public"."imports" enable row level security;
alter table "public"."imports" add constraint "imports_pkey" primary key using index on ("id");
alter table "public"."imports" add constraint "imports_company_id_fkey" foreign key (company_id) references public.companies(id) on delete cascade;
alter table "public"."imports" add constraint "imports_created_by_fkey" foreign key (created_by) references auth.users(id) on delete cascade;


-- Functions
-- Helper functions for database logic.

-- Function to get the company_id for a given user_id
create or replace function "public"."get_company_id_for_user"(p_user_id uuid)
returns uuid
language sql
security definer
set search_path = public
as $$
    select company_id from company_users where user_id = p_user_id limit 1;
$$;


-- Function to check if a user has the required role
create or replace function "public"."check_user_permission"(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    user_role company_role;
begin
    select role into user_role from company_users where user_id = p_user_id;

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


-- Function to automatically handle new user creation
create or replace function "public"."handle_new_user"()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Extract company name from metadata, default if not present
  company_name := new.raw_app_meta_data ->> 'company_name';
  if company_name is null or company_name = '' then
    company_name := new.email;
  end if;

  -- Create a new company for the new user
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Link the new user to the new company as 'Owner'
  insert into public.company_users (user_id, company_id, role)
  values (new.id, company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- Function to update the fts_document for products
create or replace function public.update_fts_document()
returns trigger
language plpgsql
as $$
begin
  new.fts_document := to_tsvector('english',
    coalesce(new.title, '') || ' ' ||
    coalesce(new.description, '') || ' ' ||
    (select string_agg(pv.sku, ' ') from public.product_variants pv where pv.product_id = new.id) || ' ' ||
    coalesce(new.product_type, '')
  );
  return new;
end;
$$;


-- Triggers
-- Automated actions that fire on database events.

-- Trigger to call handle_new_user on new user signup
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger to update the FTS document on product insert/update
create trigger products_fts_update
  before insert or update on public.products
  for each row execute procedure public.update_fts_document();


-- Row Level Security (RLS) Policies
-- These policies restrict data access to only authorized users.

-- Users can only manage their own company
create policy "User can manage their own company"
on "public"."companies"
as permissive for all
to authenticated
using ((auth.uid() = (select user_id from company_users where company_users.company_id = id and role = 'Owner' limit 1)))
with check ((auth.uid() = (select user_id from company_users where company_users.company_id = id and role = 'Owner' limit 1)));


-- Generic policy for most tables: User can access data if they belong to the company.
create policy "User can access their own company data" on "public"."products"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."product_variants"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."orders"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."order_line_items"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."customers"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."suppliers"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."purchase_orders"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."purchase_order_line_items"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."integrations"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."webhook_events"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."inventory_ledger"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."messages"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));
create policy "User can access their own company data" on "public"."audit_log"
as permissive for all to authenticated using ((get_company_id_for_user(auth.uid()) = company_id));

-- Special policy for company_settings: users can read, but only admins/owners can write.
create policy "User can access their own company settings" on "public"."company_settings"
as permissive for all to authenticated
using ((get_company_id_for_user(auth.uid()) = company_id))
with check ((get_company_id_for_user(auth.uid()) = company_id and check_user_permission(auth.uid(), 'Admin')));

-- Users should be able to see other users in their own company.
create policy "User can see other users in their company" on "auth"."users"
as permissive for select to authenticated
using (get_company_id_for_user(auth.uid()) in (select company_id from company_users where user_id = auth.users.id));
