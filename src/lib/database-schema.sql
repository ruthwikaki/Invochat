
-- #region Setup

-- Create the required extensions
create extension if not exists "uuid-ossp" with schema "extensions";
create extension if not exists "pgcrypto" with schema "extensions";
create extension if not exists "pgaudit" with schema "public";
create extension if not exists "pg_net" with schema "extensions";
create extension if not exists "supabase_vault" with schema "vault";

-- #endregion

-- #region Enums

-- Define the user roles for company access
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
-- Define the types of integrations supported
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');
-- Define feedback types for AI responses
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');
-- Define message roles for conversations
create type "public"."message_role" as enum ('user', 'assistant', 'tool');

-- #endregion

-- #region Tables

-- Stores company information
create table "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "created_at" timestamp with time zone not null default now(),
    "name" text not null,
    "owner_id" uuid not null
);
alter table "public"."companies" enable row level security;
alter table "public"."companies" add constraint "companies_pkey" primary key using index on ("id");
alter table "public"."companies" add constraint "companies_owner_id_fkey" foreign key ("owner_id") references "auth"."users"("id");

-- Manages the relationship between users and companies
create table "public"."company_users" (
    "user_id" uuid not null,
    "company_id" uuid not null,
    "role" company_role not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
alter table "public"."company_users" add constraint "company_users_pkey" primary key using index on ("user_id", "company_id");
alter table "public"."company_users" add constraint "company_users_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."company_users" add constraint "company_users_user_id_fkey" foreign key ("user_id") references "auth"."users"("id") on delete cascade;

-- Stores company-specific settings for business logic
create table "public"."company_settings" (
    "company_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now(),
    "currency" text not null default 'USD'::text,
    "timezone" text not null default 'UTC'::text,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "overstock_multiplier" real not null default 3,
    "high_value_threshold" integer not null default 100000,
    "tax_rate" real not null default 0.0,
    "predictive_stock_days" integer not null default 7
);
alter table "public"."company_settings" enable row level security;
alter table "public"."company_settings" add constraint "company_settings_pkey" primary key using index on ("company_id");
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;


-- Stores information about suppliers
create table "public"."suppliers" (
    "id" uuid not null default uuid_generate_v4(),
    "name" text not null,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now(),
    "company_id" uuid not null
);
alter table "public"."suppliers" enable row level security;
alter table "public"."suppliers" add constraint "suppliers_pkey" primary key using index on ("id");
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;


-- Stores base product information
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
    "updated_at" timestamp with time zone default now()
);
alter table "public"."products" enable row level security;
alter table "public"."products" add constraint "products_pkey" primary key using index on ("id");
alter table "public"."products" add constraint "products_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
create index "products_company_id_external_id_idx" on "public"."products" using btree ("company_id", "external_product_id");


-- Stores product variant details (SKUs)
create table "public"."product_variants" (
    "id" uuid not null default uuid_generate_v4(),
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
    "location" text,
    "supplier_id" uuid,
    "external_variant_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."product_variants" enable row level security;
alter table "public"."product_variants" add constraint "product_variants_pkey" primary key using index on ("id");
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" foreign key ("product_id") references "public"."products"("id") on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" foreign key ("supplier_id") references "public"."suppliers"("id") on delete set null;
create index "variants_company_id_external_id_idx" on "public"."product_variants" using btree ("company_id", "external_variant_id");
create index "variants_company_id_sku_idx" on "public"."product_variants" using btree ("company_id", "sku");


-- Stores customer information
create table "public"."customers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now(),
    "deleted_at" timestamp with time zone
);
alter table "public"."customers" enable row level security;
alter table "public"."customers" add constraint "customers_pkey" primary key using index on ("id");
alter table "public"."customers" add constraint "customers_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
create index "customers_company_id_email_idx" on "public"."customers" using btree ("company_id", "email");
create index "customers_company_id_external_id_idx" on "public"."customers" using btree ("company_id", "external_customer_id");


-- Stores sales orders
create table "public"."orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "order_number" text not null,
    "customer_id" uuid,
    "external_order_id" text,
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
    "updated_at" timestamp with time zone default now()
);
alter table "public"."orders" enable row level security;
alter table "public"."orders" add constraint "orders_pkey" primary key using index on ("id");
alter table "public"."orders" add constraint "orders_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."orders" add constraint "orders_customer_id_fkey" foreign key ("customer_id") references "public"."customers"("id") on delete set null;
create index "orders_company_id_external_id_idx" on "public"."orders" using btree ("company_id", "external_order_id");
create index "orders_created_at_idx" on "public"."orders" using btree ("created_at" desc);


-- Stores line items for each order
create table "public"."order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
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
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" foreign key ("order_id") references "public"."orders"("id") on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" foreign key ("variant_id") references "public"."product_variants"("id") on delete set null;

-- Stores purchase orders
create table "public"."purchase_orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "supplier_id" uuid,
    "status" text not null default 'Draft'::text,
    "po_number" text not null,
    "total_cost" integer not null,
    "expected_arrival_date" date,
    "idempotency_key" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."purchase_orders" enable row level security;
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" primary key using index on ("id");
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" foreign key ("supplier_id") references "public"."suppliers"("id") on delete set null;

-- Stores line items for each purchase order
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
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" foreign key ("purchase_order_id") references "public"."purchase_orders"("id") on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" foreign key ("variant_id") references "public"."product_variants"("id") on delete cascade;

-- Tracks all inventory movements
create table "public"."inventory_ledger" (
    "id" uuid not null default uuid_generate_v4(),
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
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" foreign key ("variant_id") references "public"."product_variants"("id") on delete cascade;

-- Stores external platform integrations
create table "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" integration_platform not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean not null default true,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."integrations" enable row level security;
alter table "public"."integrations" add constraint "integrations_pkey" primary key using index on ("id");
alter table "public"."integrations" add constraint "integrations_company_id_platform_key" unique ("company_id", "platform");
alter table "public"."integrations" add constraint "integrations_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;

-- Tracks webhook events to prevent duplicates
create table "public"."webhook_events" (
  "id" uuid not null default uuid_generate_v4(),
  "integration_id" uuid not null,
  "webhook_id" text not null,
  "created_at" timestamp with time zone not null default now()
);
alter table "public"."webhook_events" enable row level security;
alter table "public"."webhook_events" add constraint "webhook_events_pkey" primary key using index on ("id");
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_webhook_id_key" unique ("integration_id", "webhook_id");
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" foreign key ("integration_id") references "public"."integrations"("id") on delete cascade;

-- Stores chat conversations
create table "public"."conversations" (
    "id" uuid not null default uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone not null default now(),
    "last_accessed_at" timestamp with time zone not null default now(),
    "is_starred" boolean not null default false
);
alter table "public"."conversations" enable row level security;
alter table "public"."conversations" add constraint "conversations_pkey" primary key using index on ("id");
alter table "public"."conversations" add constraint "conversations_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."conversations" add constraint "conversations_user_id_fkey" foreign key ("user_id") references "auth"."users"("id") on delete cascade;


-- Stores messages within conversations
create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" message_role not null,
    "content" text not null,
    "visualization" jsonb,
    "component" text,
    "componentProps" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "confidence" real,
    "assumptions" text[],
    "isError" boolean default false
);
alter table "public"."messages" enable row level security;
alter table "public"."messages" add constraint "messages_pkey" primary key using index on ("id");
alter table "public"."messages" add constraint "messages_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."messages" add constraint "messages_conversation_id_fkey" foreign key ("conversation_id") references "public"."conversations"("id") on delete cascade;

-- Stores refunds
create table "public"."refunds" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "order_id" uuid not null,
    "refund_number" text not null,
    "status" text not null,
    "reason" text,
    "note" text,
    "total_amount" integer not null,
    "created_by_user_id" uuid,
    "external_refund_id" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."refunds" enable row level security;
alter table "public"."refunds" add constraint "refunds_pkey" primary key using index on ("id");
alter table "public"."refunds" add constraint "refunds_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."refunds" add constraint "refunds_created_by_user_id_fkey" foreign key ("created_by_user_id") references "auth"."users"("id") on delete set null;
alter table "public"."refunds" add constraint "refunds_order_id_fkey" foreign key ("order_id") references "public"."orders"("id") on delete cascade;

-- Tracks user feedback
create table "public"."feedback" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "user_id" uuid not null,
    "subject_id" text not null,
    "subject_type" text not null,
    "feedback" feedback_type not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."feedback" enable row level security;
alter table "public"."feedback" add constraint "feedback_pkey" primary key using index on ("id");
alter table "public"."feedback" add constraint "feedback_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."feedback" add constraint "feedback_user_id_fkey" foreign key ("user_id") references "auth"."users"("id") on delete cascade;

-- Stores channel-specific fees
create table "public"."channel_fees" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "channel_name" text not null,
    "fixed_fee" integer,
    "percentage_fee" real,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."channel_fees" enable row level security;
alter table "public"."channel_fees" add constraint "channel_fees_pkey" primary key using index on ("id");
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."channel_fees" add constraint "channel_fees_company_id_channel_name_key" unique ("company_id", "channel_name");


-- Stores data export jobs
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
alter table "public"."export_jobs" add constraint "export_jobs_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."export_jobs" add constraint "export_jobs_requested_by_user_id_fkey" foreign key ("requested_by_user_id") references "auth"."users"("id") on delete cascade;


-- Stores data import jobs
create table "public"."imports" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "created_by" uuid not null,
    "import_type" text not null,
    "file_name" text not null,
    "status" text not null default 'pending',
    "total_rows" integer,
    "processed_rows" integer,
    "failed_rows" integer,
    "errors" jsonb,
    "summary" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "completed_at" timestamp with time zone
);
alter table "public"."imports" enable row level security;
alter table "public"."imports" add constraint "imports_pkey" primary key using index on ("id");
alter table "public"."imports" add constraint "imports_company_id_fkey" foreign key ("company_id") references "public"."companies"("id") on delete cascade;
alter table "public"."imports" add constraint "imports_created_by_fkey" foreign key ("created_by") references "auth"."users"("id") on delete cascade;

-- #endregion

-- #region Row Level Security (RLS) Policies

-- Companies Table
create policy "Users can see their own company." on "public"."companies" for select using ((select auth.uid()) = owner_id);
create policy "Users can only see companies they are a member of" on "public"."companies" for select using (id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Company Users Table
create policy "Users can only see the company users of the company they belong to." on "public"."company_users" for select using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));
create policy "Admins can manage company users." on "public"."company_users" for all using ((company_id in (select "public"."get_company_id_for_user"((select auth.uid())))) and ((select "public"."check_user_permission"((select auth.uid()), 'Admin'))));

-- Company Settings Table
create policy "Users can read their own company settings" on "public"."company_settings" for select using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));
create policy "Admins can update company settings." on "public"."company_settings" for update with check ((company_id in (select "public"."get_company_id_for_user"((select auth.uid())))) and ((select "public"."check_user_permission"((select auth.uid()), 'Admin'))));

-- Suppliers Table
create policy "Users can manage suppliers for their own company" on "public"."suppliers" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Products and Variants Tables
create policy "Users can manage products for their own company" on "public"."products" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));
create policy "Users can manage product variants for their own company" on "public"."product_variants" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Customers Table
create policy "Users can manage customers for their own company" on "public"."customers" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Orders and Line Items Tables
create policy "Users can manage orders for their own company" on "public"."orders" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));
create policy "Users can manage line items for their own company" on "public"."order_line_items" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Purchase Orders and Line Items Tables
create policy "Users can manage POs for their own company" on "public"."purchase_orders" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));
create policy "Users can manage PO line items for their own company" on "public"."purchase_order_line_items" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Inventory Ledger Table
create policy "Users can view inventory ledger for their own company" on "public"."inventory_ledger" for select using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Integrations Table
create policy "Users can manage integrations for their own company" on "public"."integrations" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Webhook Events Table
create policy "Allow webhook service to insert" on "public"."webhook_events" for insert with check (true);

-- Conversations and Messages Tables
create policy "Users can manage their own conversations" on "public"."conversations" for all using (user_id = (select auth.uid()));
create policy "Users can manage messages in their own conversations" on "public"."messages" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Refunds Table
create policy "Users can manage refunds for their own company" on "public"."refunds" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Feedback Table
create policy "Users can manage their own feedback" on "public"."feedback" for all using (user_id = (select auth.uid()));

-- Channel Fees Table
create policy "Users can manage channel fees for their company" on "public"."channel_fees" for all using (company_id in (select "public"."get_company_id_for_user"((select auth.uid()))));

-- Export Jobs Table
create policy "Users can manage their own export jobs" on "public"."export_jobs" for all using (requested_by_user_id = (select auth.uid()));

-- Imports Table
create policy "Users can manage their own import jobs" on "public"."imports" for all using (created_by = (select auth.uid()));


-- #endregion

-- #region Database Functions

-- Gets the company ID for a given user
create or replace function "public"."get_company_id_for_user"(p_user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users where user_id = p_user_id limit 1;
$$;


-- Checks if a user has a specific role in their company
create or replace function "public"."check_user_permission"(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
as $$
begin
  return exists (
    select 1
    from public.company_users
    where user_id = p_user_id
    and (
      (p_required_role = 'Admin' and role in ('Owner', 'Admin'))
      or
      (p_required_role = 'Owner' and role = 'Owner')
    )
  );
end;
$$;


-- A trigger function to automatically create a company for a new user and link them.
create or replace function "public"."handle_new_user"()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_company_name text;
begin
  -- Extract company name from metadata, default if not present
  v_company_name := new.raw_user_meta_data ->> 'company_name';
  if v_company_name is null or v_company_name = '' then
    v_company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (v_company_name, new.id)
  returning id into v_company_id;

  -- Link the user to the new company as 'Owner'
  insert into public.company_users (user_id, company_id, role)
  values (new.id, v_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set app_metadata = app_metadata || jsonb_build_object('company_id', v_company_id)
  where id = new.id;

  return new;
end;
$$;

-- Attaches the trigger to the auth.users table
create trigger "on_auth_user_created"
after insert on auth.users
for each row execute procedure "public"."handle_new_user"();


-- Function to decrement inventory for a given order
create or replace function "public"."decrement_inventory_for_order"(p_order_id uuid, p_company_id uuid)
returns void
language plpgsql
as $$
declare
  item record;
  current_quantity int;
begin
  for item in
    select variant_id, sku, quantity
    from public.order_line_items
    where order_id = p_order_id and company_id = p_company_id and variant_id is not null
  loop
    -- Lock the variant row to prevent race conditions
    select inventory_quantity into current_quantity from public.product_variants where id = item.variant_id and company_id = p_company_id for update;
    
    -- Check for sufficient stock before decrementing
    if current_quantity < item.quantity then
      raise exception 'Insufficient stock for SKU: %. Available: %, Required: %', item.sku, current_quantity, item.quantity;
    end if;
  
    update public.product_variants
    set inventory_quantity = inventory_quantity - item.quantity,
        updated_at = now()
    where id = item.variant_id;
  end loop;
end;
$$;


-- The main function to record a sale from a platform, now calling the inventory decrement function
create or replace function "public"."record_order_from_platform"(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns uuid
language plpgsql
as $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  line_item jsonb;
  v_variant_id uuid;
begin
  -- Upsert customer
  insert into public.customers (company_id, external_customer_id, name, email, phone)
  values (
    p_company_id,
    p_order_payload ->> 'customer' ->> 'id',
    coalesce(p_order_payload ->> 'customer' ->> 'first_name', '') || ' ' || coalesce(p_order_payload ->> 'customer' ->> 'last_name', ''),
    p_order_payload ->> 'customer' ->> 'email',
    p_order_payload ->> 'customer' ->> 'phone'
  )
  on conflict (company_id, external_customer_id) do update
  set
    name = excluded.name,
    email = excluded.email,
    phone = excluded.phone
  returning id into v_customer_id;

  -- Upsert order
  insert into public.orders (
    company_id, external_order_id, order_number, customer_id, financial_status, fulfillment_status,
    currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
  )
  values (
    p_company_id,
    p_order_payload ->> 'id',
    p_order_payload ->> 'order_number',
    v_customer_id,
    p_order_payload ->> 'financial_status',
    p_order_payload ->> 'fulfillment_status',
    p_order_payload ->> 'currency',
    (p_order_payload ->> 'subtotal_price')::numeric * 100,
    (p_order_payload ->> 'total_tax')::numeric * 100,
    (p_order_payload ->> 'total_shipping_price')::numeric * 100,
    (p_order_payload ->> 'total_discounts')::numeric * 100,
    (p_order_payload ->> 'total_price')::numeric * 100,
    p_platform,
    (p_order_payload ->> 'created_at')::timestamptz
  )
  on conflict (company_id, external_order_id) do update
  set
    financial_status = excluded.financial_status,
    fulfillment_status = excluded.fulfillment_status,
    total_amount = excluded.total_amount,
    updated_at = now()
  returning id into v_order_id;
  
  -- Upsert line items
  for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
  loop
    -- Find variant_id based on SKU
    select id into v_variant_id from public.product_variants where sku = line_item ->> 'sku' and company_id = p_company_id;

    insert into public.order_line_items (
      order_id, variant_id, company_id, external_line_item_id, product_name, sku, quantity, price
    )
    values (
      v_order_id,
      v_variant_id,
      p_company_id,
      line_item ->> 'id',
      line_item ->> 'name',
      line_item ->> 'sku',
      (line_item ->> 'quantity')::integer,
      (line_item ->> 'price')::numeric * 100
    )
    on conflict (order_id, external_line_item_id) do nothing;
  end loop;

  -- Decrement inventory
  perform public.decrement_inventory_for_order(v_order_id, p_company_id);

  return v_order_id;
end;
$$;


-- #endregion

-- #region Materialized Views for Performance

-- Combined product and variant view
create materialized view "public"."product_variants_with_details_mat" as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id;
create unique index on "public"."product_variants_with_details_mat" (id);

-- Daily sales summary
create materialized view "public"."daily_sales_mat" as
select
    company_id,
    date_trunc('day', created_at) as sale_date,
    sum(total_amount) as daily_revenue,
    count(id) as daily_orders,
    sum((select sum(quantity) from public.order_line_items where order_id = o.id)) as daily_units_sold
from
    public.orders o
group by
    company_id, date_trunc('day', created_at);
create unique index on "public"."daily_sales_mat" (company_id, sale_date);


-- Combined customers and orders view
create materialized view "public"."customers_view" as
with customer_orders as (
    select
        c.id,
        c.company_id,
        count(o.id) as total_orders,
        sum(o.total_amount) as total_spent,
        min(o.created_at) as first_order_date
    from
        public.customers c
    join
        public.orders o on c.id = o.customer_id
    group by
        c.id, c.company_id
)
select
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    coalesce(co.total_orders, 0) as total_orders,
    coalesce(co.total_spent, 0) as total_spent,
    co.first_order_date
from
    public.customers c
left join
    customer_orders co on c.id = co.id
where c.deleted_at is null;
create unique index on "public"."customers_view" (id);


-- Function to refresh all materialized views for a given company.
-- This is more efficient than a single global refresh.
create or replace function "public"."refresh_all_matviews"(p_company_id uuid)
returns void
language plpgsql
as $$
begin
    -- It's often simpler to refresh all concurrently without filtering by company_id,
    -- as materialized views are typically fast to refresh incrementally.
    -- If performance becomes an issue, these can be broken into company-specific views.
    refresh materialized view concurrently "public"."product_variants_with_details_mat";
    refresh materialized view concurrently "public"."daily_sales_mat";
    refresh materialized view concurrently "public"."customers_view";
end;
$$;


-- #endregion

-- #region Initial Data (Optional)
-- You can add any initial data seeding here if necessary for setup.
-- #endregion
