-- supabase/seed.sql

-- Initial database schema for InvoChat. This file is intended to be run
-- once during the initial setup of the Supabase project. It defines the tables,
-- functions, and row-level security policies required for the application to function.

-- === Extensions ===
-- Enable the pgcrypto extension for UUID generation.
create extension if not exists "uuid-ossp" with schema "extensions";
-- Enable the pg_stat_statements extension for query performance monitoring.
create extension if not exists "pg_stat_statements" with schema "extensions";

-- === Custom Types ===
-- Define an ENUM for user roles within a company.
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
-- Define an ENUM for feedback types.
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');
-- Define an ENUM for supported integration platforms.
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');
-- Define an ENUM for chat message roles.
create type "public"."message_role" as enum ('user', 'assistant', 'tool');


-- === Tables ===

-- Table to store company information. Each user belongs to one company.
create table "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "name" text not null,
    "created_at" timestamp with time zone not null default now(),
    "owner_id" uuid not null
);
alter table "public"."companies" enable row level security;
CREATE UNIQUE INDEX companies_pkey ON public.companies USING btree (id);
alter table "public"."companies" add constraint "companies_pkey" PRIMARY KEY using index "companies_pkey";
alter table "public"."companies" add constraint "companies_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Junction table to link users to companies and define their roles.
create table "public"."company_users" (
    "company_id" uuid not null,
    "user_id" uuid not null,
    "role" company_role not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
CREATE UNIQUE INDEX company_users_pkey ON public.company_users USING btree (company_id, user_id);
alter table "public"."company_users" add constraint "company_users_pkey" PRIMARY KEY using index "company_users_pkey";
alter table "public"."company_users" add constraint "company_users_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."company_users" add constraint "company_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Table to store product information.
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
    "deleted_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
CREATE UNIQUE INDEX products_pkey ON public.products USING btree (id);
CREATE INDEX idx_products_company_id ON public.products USING btree (company_id);
alter table "public"."products" add constraint "products_pkey" PRIMARY KEY using index "products_pkey";
alter table "public"."products" add constraint "products_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Table to store product variants (SKUs).
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
    "supplier_id" uuid,
    "location" text,
    "external_variant_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."product_variants" enable row level security;
CREATE UNIQUE INDEX product_variants_pkey ON public.product_variants USING btree (id);
CREATE INDEX idx_product_variants_company_id ON public.product_variants USING btree (company_id);
CREATE INDEX idx_product_variants_sku ON public.product_variants USING btree (sku, company_id);
alter table "public"."product_variants" add constraint "product_variants_pkey" PRIMARY KEY using index "product_variants_pkey";
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


-- Table to store supplier information.
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
CREATE UNIQUE INDEX suppliers_pkey ON public.suppliers USING btree (id);
alter table "public"."suppliers" add constraint "suppliers_pkey" PRIMARY KEY using index "suppliers_pkey";
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


-- Table to store purchase orders.
create table "public"."purchase_orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "supplier_id" uuid,
    "status" text not null default 'Draft'::text,
    "po_number" text not null,
    "total_cost" integer not null,
    "expected_arrival_date" date,
    "notes" text,
    "idempotency_key" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."purchase_orders" enable row level security;
CREATE UNIQUE INDEX purchase_orders_pkey ON public.purchase_orders USING btree (id);
CREATE INDEX idx_purchase_orders_company_id ON public.purchase_orders USING btree (company_id);
CREATE UNIQUE INDEX po_idempotency_key_idx ON public.purchase_orders USING btree (idempotency_key);
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" PRIMARY KEY using index "purchase_orders_pkey";
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


-- Table to store line items for purchase orders.
create table "public"."purchase_order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
    "purchase_order_id" uuid not null,
    "variant_id" uuid not null,
    "company_id" uuid not null,
    "quantity" integer not null,
    "cost" integer not null
);
alter table "public"."purchase_order_line_items" enable row level security;
CREATE UNIQUE INDEX purchase_order_line_items_pkey ON public.purchase_order_line_items USING btree (id);
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_pkey" PRIMARY KEY using index "purchase_order_line_items_pkey";
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- Table to store customer information.
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
CREATE UNIQUE INDEX customers_pkey ON public.customers USING btree (id);
alter table "public"."customers" add constraint "customers_pkey" PRIMARY KEY using index "customers_pkey";
alter table "public"."customers" add constraint "customers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Table to store sales orders.
create table "public"."orders" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "order_number" text not null,
    "external_order_id" text,
    "customer_id" uuid,
    "financial_status" text,
    "fulfillment_status" text,
    "currency" text,
    "subtotal" integer not null,
    "total_tax" integer,
    "total_shipping" integer,
    "total_discounts" integer,
    "total_amount" integer not null,
    "source_platform" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."orders" enable row level security;
CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (id);
CREATE INDEX idx_orders_company_id ON public.orders USING btree (company_id);
alter table "public"."orders" add constraint "orders_pkey" PRIMARY KEY using index "orders_pkey";
alter table "public"."orders" add constraint "orders_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."orders" add constraint "orders_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;


-- Table to store line items for sales orders.
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
CREATE UNIQUE INDEX order_line_items_pkey ON public.order_line_items USING btree (id);
CREATE INDEX idx_order_line_items_order_id ON public.order_line_items USING btree (order_id);
CREATE INDEX idx_order_line_items_variant_id ON public.order_line_items USING btree (variant_id);
alter table "public"."order_line_items" add constraint "order_line_items_pkey" PRIMARY KEY using index "order_line_items_pkey";
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE SET NULL;


-- Table to store integration settings.
create table "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" integration_platform not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean not null default false,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."integrations" enable row level security;
CREATE UNIQUE INDEX integrations_pkey ON public.integrations USING btree (id);
CREATE UNIQUE INDEX integrations_company_id_platform_key ON public.integrations USING btree (company_id, platform);
alter table "public"."integrations" add constraint "integrations_pkey" PRIMARY KEY using index "integrations_pkey";
alter table "public"."integrations" add constraint "integrations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Table to store inventory ledger entries for stock movement tracking.
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
CREATE UNIQUE INDEX inventory_ledger_pkey ON public.inventory_ledger USING btree (id);
CREATE INDEX idx_inventory_ledger_variant_id ON public.inventory_ledger USING btree (variant_id);
alter table "public"."inventory_ledger" add constraint "inventory_ledger_pkey" PRIMARY KEY using index "inventory_ledger_pkey";
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- Table for audit logging.
create table "public"."audit_log" (
  id bigint generated by default as identity primary key,
  user_id uuid references auth.users(id),
  company_id uuid references public.companies(id),
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);
alter table "public"."audit_log" enable row level security;


-- Table for AI chat conversations.
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
CREATE UNIQUE INDEX conversations_pkey ON public.conversations USING btree (id);
alter table "public"."conversations" add constraint "conversations_pkey" PRIMARY KEY using index "conversations_pkey";
alter table "public"."conversations" add constraint "conversations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."conversations" add constraint "conversations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Table for AI chat messages.
create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" message_role not null,
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
CREATE UNIQUE INDEX messages_pkey ON public.messages USING btree (id);
alter table "public"."messages" add constraint "messages_pkey" PRIMARY KEY using index "messages_pkey";
alter table "public"."messages" add constraint "messages_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."messages" add constraint "messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


-- Table for user feedback on AI responses.
create table "public"."feedback" (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  company_id uuid not null references public.companies(id),
  subject_id text not null,
  subject_type text not null, -- e.g., 'message', 'alert', 'reorder_suggestion'
  feedback feedback_type not null,
  created_at timestamptz default now()
);
alter table "public"."feedback" enable row level security;


-- Table for company-specific settings.
create table "public"."company_settings" (
    "company_id" uuid not null,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "overstock_multiplier" real not null default 2.5,
    "high_value_threshold" integer not null default 100000, -- in cents
    "predictive_stock_days" integer not null default 7,
    "currency" text not null default 'USD'::text,
    "timezone" text not null default 'UTC'::text,
    "tax_rate" numeric not null default 0.0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."company_settings" enable row level security;
CREATE UNIQUE INDEX company_settings_pkey ON public.company_settings USING btree (company_id);
alter table "public"."company_settings" add constraint "company_settings_pkey" PRIMARY KEY using index "company_settings_pkey";
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

-- Table for tracking channel-specific fees.
create table "public"."channel_fees" (
  "id" uuid not null default uuid_generate_v4(),
  "company_id" uuid not null,
  "channel_name" text not null,
  "percentage_fee" numeric,
  "fixed_fee" integer, -- in cents
  "created_at" timestamp with time zone default now(),
  "updated_at" timestamp with time zone
);
alter table "public"."channel_fees" enable row level security;
CREATE UNIQUE INDEX channel_fees_pkey ON public.channel_fees USING btree (id);
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_key ON public.channel_fees USING btree (company_id, channel_name);
alter table "public"."channel_fees" add constraint "channel_fees_pkey" PRIMARY KEY using index "channel_fees_pkey";
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


-- Table for tracking data export jobs.
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
CREATE UNIQUE INDEX export_jobs_pkey ON public.export_jobs USING btree (id);
alter table "public"."export_jobs" add constraint "export_jobs_pkey" PRIMARY KEY using index "export_jobs_pkey";
alter table "public"."export_jobs" add constraint "export_jobs_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."export_jobs" add constraint "export_jobs_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- Table for preventing webhook replay attacks.
create table "public"."webhook_events" (
  "id" uuid not null default gen_random_uuid(),
  "integration_id" uuid not null,
  "webhook_id" text not null,
  "created_at" timestamp with time zone default now()
);
alter table "public"."webhook_events" enable row level security;
CREATE UNIQUE INDEX webhook_events_pkey ON public.webhook_events USING btree (id);
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_key ON public.webhook_events USING btree (integration_id, webhook_id);
alter table "public"."webhook_events" add constraint "webhook_events_pkey" PRIMARY KEY using index "webhook_events_pkey";
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;


-- Table for tracking data import jobs.
create table "public"."imports" (
  "id" uuid not null default gen_random_uuid(),
  "company_id" uuid not null,
  "created_by" uuid not null,
  "import_type" text not null,
  "file_name" text not null,
  "total_rows" integer,
  "processed_rows" integer,
  "failed_rows" integer,
  "status" text not null default 'pending', -- pending, processing, completed, completed_with_errors, failed
  "errors" jsonb,
  "summary" jsonb,
  "created_at" timestamp with time zone default now(),
  "completed_at" timestamp with time zone
);
alter table "public"."imports" enable row level security;
CREATE UNIQUE INDEX imports_pkey ON public.imports USING btree (id);
alter table "public"."imports" add constraint "imports_pkey" PRIMARY KEY using index "imports_pkey";
alter table "public"."imports" add constraint "imports_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
alter table "public"."imports" add constraint "imports_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;



-- === Functions ===

-- Function to get the company_id for a user based on their JWT claims.
create or replace function "public"."get_company_id_for_user"()
returns uuid
language "sql"
security definer
as $$
  select auth.jwt()->'app_metadata'->>'company_id' as company_id;
$$;


-- Function to handle new user sign-ups.
create or replace function "public"."handle_new_user"()
returns trigger
language "plpgsql"
security definer
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Check if the user is being invited (company_id is pre-set)
  if new.raw_app_meta_data->>'company_id' is not null then
    company_id := (new.raw_app_meta_data->>'company_id')::uuid;
    -- Set user role to Member by default for invites
    insert into public.company_users (user_id, company_id, role)
    values (new.id, company_id, 'Member');
  else
    -- This is a new signup, not an invite. Create a new company.
    company_name := new.raw_app_meta_data->>'company_name';
    if company_name is null or company_name = '' then
      company_name := new.email || '''s Company';
    end if;

    insert into public.companies (name, owner_id)
    values (company_name, new.id)
    returning id into company_id;

    -- Link the new user to the new company as Owner
    insert into public.company_users (user_id, company_id, role)
    values (new.id, company_id, 'Owner');

    -- Update the user's app_metadata with the new company_id
    update auth.users set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
    where id = new.id;
  end if;
  return new;
end;
$$;
-- Create a trigger to call the handle_new_user function after a new user is inserted.
create trigger "on_auth_user_created"
after insert on "auth"."users"
for each row execute procedure "public"."handle_new_user"();


-- Function to check if a user has the required permission level.
create or replace function public.check_user_permission(
    p_user_id uuid,
    p_required_role company_role
)
returns boolean
language plpgsql
security definer
as $$
declare
    user_role public.company_role;
begin
    select role into user_role
    from public.company_users
    where user_id = p_user_id
    and company_id = (select company_id from public.company_users where user_id = p_user_id limit 1);

    if user_role is null then
        return false;
    end if;

    if p_required_role = 'Owner' then
        return user_role = 'Owner';
    elsif p_required_role = 'Admin' then
        return user_role in ('Owner', 'Admin');
    end if;
    
    return true; -- 'Member' requirement passes for any valid role
end;
$$;


-- Function to temporarily lock a user account.
create or replace function public.lock_user_account(
    p_user_id uuid,
    p_lockout_duration interval
)
returns void
language plpgsql
security definer
as $$
begin
    update auth.users
    set banned_until = now() + p_lockout_duration
    where id = p_user_id;
end;
$$;


-- Function for batch inserting/updating product costs and reorder info.
create or replace function public.batch_upsert_costs(
    p_records jsonb,
    p_company_id uuid,
    p_user_id uuid
)
returns void
language plpgsql
as $$
declare
    v_rec record;
begin
    for v_rec in select * from jsonb_to_recordset(p_records) as x(
        sku text,
        cost integer,
        supplier_name text,
        reorder_point integer,
        reorder_quantity integer,
        lead_time_days integer
    ) loop
        -- Find supplier_id from supplier_name if provided
        declare
            v_supplier_id uuid;
        begin
            if v_rec.supplier_name is not null then
                select id into v_supplier_id from public.suppliers
                where name = v_rec.supplier_name and company_id = p_company_id
                limit 1;
            end if;

            update public.product_variants
            set
                cost = coalesce(v_rec.cost, cost),
                reorder_point = coalesce(v_rec.reorder_point, reorder_point),
                reorder_quantity = coalesce(v_rec.reorder_quantity, reorder_quantity),
                supplier_id = coalesce(v_supplier_id, supplier_id),
                updated_at = now()
            where sku = v_rec.sku and company_id = p_company_id;
        end;
    end loop;
end;
$$;

-- Function for batch inserting/updating suppliers.
create or replace function public.batch_upsert_suppliers(
    p_records jsonb,
    p_company_id uuid,
    p_user_id uuid -- For future auditing
)
returns void
language plpgsql
as $$
declare
    v_rec record;
begin
    for v_rec in select * from jsonb_to_recordset(p_records) as x(
        name text,
        email text,
        phone text,
        default_lead_time_days integer,
        notes text
    ) loop
        insert into public.suppliers (company_id, name, email, phone, default_lead_time_days, notes)
        values (p_company_id, v_rec.name, v_rec.email, v_rec.phone, v_rec.default_lead_time_days, v_rec.notes)
        on conflict (company_id, name) do update
        set
            email = excluded.email,
            phone = excluded.phone,
            default_lead_time_days = excluded.default_lead_time_days,
            notes = excluded.notes,
            updated_at = now();
    end loop;
end;
$$;

-- Function for batch importing historical sales data.
create or replace function public.batch_import_sales(
    p_records jsonb,
    p_company_id uuid,
    p_user_id uuid
)
returns void
language plpgsql
as $$
declare
    v_rec record;
    v_variant_id uuid;
    v_order_id uuid;
begin
    for v_rec in select * from jsonb_to_recordset(p_records) as x(
        order_date timestamptz,
        sku text,
        quantity integer,
        unit_price integer,
        cost_at_time integer,
        customer_email text,
        order_id text
    ) loop
        -- Find variant_id from SKU
        select id into v_variant_id from public.product_variants
        where sku = v_rec.sku and company_id = p_company_id
        limit 1;
        
        -- If variant does not exist, we cannot proceed with this record
        if v_variant_id is null then
            continue;
        end if;
        
        -- Create a simplified order record for this historical sale
        insert into public.orders (company_id, order_number, total_amount, created_at, source_platform)
        values (p_company_id, 'HISTORICAL-' || v_rec.order_id, v_rec.unit_price * v_rec.quantity, v_rec.order_date, 'historical_import')
        returning id into v_order_id;
        
        -- Create the order line item
        insert into public.order_line_items (order_id, variant_id, company_id, sku, quantity, price, cost_at_time)
        values (v_order_id, v_variant_id, p_company_id, v_rec.sku, v_rec.quantity, v_rec.unit_price, v_rec.cost_at_time);
        
    end loop;
end;
$$;


-- === Row-Level Security Policies ===

-- Companies
create policy "Users can view their own company" on "public"."companies" for select using (id = (select public.get_company_id_for_user()));
create policy "Owners can update their own company" on "public"."companies" for update using (id = (select public.get_company_id_for_user()) and auth.uid() = owner_id);

-- Company Users
create policy "Users can view members of their own company" on "public"."company_users" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Owners/Admins can manage company users" on "public"."company_users" for all using (
  company_id = (select public.get_company_id_for_user()) and
  (select public.check_user_permission(auth.uid(), 'Admin'))
);

-- Products & Variants
create policy "Users can view products in their company" on "public"."products" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage products in their company" on "public"."products" for all using (company_id = (select public.get_company_id_for_user()));
create policy "Users can view variants in their company" on "public"."product_variants" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage variants in their company" on "public"."product_variants" for all using (company_id = (select public.get_company_id_for_user()));

-- Suppliers
create policy "Users can view suppliers in their company" on "public"."suppliers" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage suppliers in their company" on "public"."suppliers" for all using (company_id = (select public.get_company_id_for_user()));

-- Purchase Orders
create policy "Users can view POs in their company" on "public"."purchase_orders" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage POs in their company" on "public"."purchase_orders" for all using (company_id = (select public.get_company_id_for_user()));
create policy "Users can view PO line items in their company" on "public"."purchase_order_line_items" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage PO line items in their company" on "public"."purchase_order_line_items" for all using (company_id = (select public.get_company_id_for_user()));

-- Customers
create policy "Users can view customers in their company" on "public"."customers" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage customers in their company" on "public"."customers" for all using (company_id = (select public.get_company_id_for_user()));

-- Orders
create policy "Users can view orders in their company" on "public"."orders" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage orders in their company" on "public"."orders" for all using (company_id = (select public.get_company_id_for_user()));
create policy "Users can view order line items in their company" on "public"."order_line_items" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage order line items in their company" on "public"."order_line_items" for all using (company_id = (select public.get_company_id_for_user()));

-- Integrations
create policy "Users can view integrations in their company" on "public"."integrations" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can manage integrations in their company" on "public"."integrations" for all using (company_id = (select public.get_company_id_for_user()));

-- Inventory Ledger
create policy "Users can view ledger entries in their company" on "public"."inventory_ledger" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Users can insert ledger entries in their company" on "public"."inventory_ledger" for insert with check (company_id = (select public.get_company_id_for_user()));

-- Chat
create policy "Users can view their own conversations" on "public"."conversations" for select using (user_id = auth.uid());
create policy "Users can manage their own conversations" on "public"."conversations" for all using (user_id = auth.uid());
create policy "Users can view messages in their conversations" on "public"."messages" for select using (company_id = (select public.get_company_id_for_user()) and conversation_id in (select id from public.conversations where user_id = auth.uid()));
create policy "Users can manage messages in their conversations" on "public"."messages" for all using (company_id = (select public.get_company_id_for_user()) and conversation_id in (select id from public.conversations where user_id = auth.uid()));

-- Feedback
create policy "Users can manage their own feedback" on "public"."feedback" for all using (user_id = auth.uid());

-- Settings
create policy "Users can view their own company settings" on "public"."company_settings" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Admins can update company settings" on "public"."company_settings" for update using (company_id = (select public.get_company_id_for_user()) and (select public.check_user_permission(auth.uid(), 'Admin')));
create policy "Users can view their own channel fees" on "public"."channel_fees" for select using (company_id = (select public.get_company_id_for_user()));
create policy "Admins can update channel fees" on "public"."channel_fees" for all using (company_id = (select public.get_company_id_for_user()) and (select public.check_user_permission(auth.uid(), 'Admin')));

-- Data Export
create policy "Users can view their own export jobs" on "public"."export_jobs" for select using (requested_by_user_id = auth.uid());
create policy "Users can create export jobs for their company" on "public"."export_jobs" for insert with check (company_id = (select public.get_company_id_for_user()) and requested_by_user_id = auth.uid());

-- Webhooks & Imports (service-level access)
create policy "Allow all access for service roles" on public.webhook_events for all using (true);
create policy "Allow all access for service roles" on public.imports for all using (true);
create policy "Allow all access for service roles" on public.audit_log for all using (true);
