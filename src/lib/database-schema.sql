
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema "extensions";

-- Enable cryptographic functions
create extension if not exists "pgcrypto" with schema "extensions";

-- Custom Types
do $$
begin
    if not exists (select 1 from pg_type where typname = 'company_role') then
        create type company_role as enum ('Owner', 'Admin', 'Member');
    end if;
    if not exists (select 1 from pg_type where typname = 'integration_platform') then
        create type integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
    end if;
    if not exists (select 1 from pg_type where typname = 'message_role') then
        create type message_role as enum ('user', 'assistant', 'tool');
    end if;
    if not exists (select 1 from pg_type where typname = 'feedback_type') then
        create type feedback_type as enum ('helpful', 'unhelpful');
    end if;
end$$;

-- Companies Table: Stores company information
create table if not exists "public"."companies" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "name" text not null,
    "owner_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."companies" enable row level security;
alter table "public"."companies" add constraint "companies_pkey" primary key using index on ("id");
alter table "public"."companies" add constraint "companies_owner_id_fkey" foreign key (owner_id) references auth.users(id) on delete cascade;


-- Company Users Junction Table: Links users to companies with roles
create table if not exists "public"."company_users" (
    "user_id" uuid not null,
    "company_id" uuid not null,
    "role" company_role not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
alter table "public"."company_users" add constraint "company_users_pkey" primary key(user_id, company_id);
alter table "public"."company_users" add constraint "company_users_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;
alter table "public"."company_users" add constraint "company_users_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- Company Settings Table
create table if not exists "public"."company_settings" (
    "company_id" uuid not null,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "predictive_stock_days" integer not null default 7,
    "currency" text default 'USD'::text,
    "timezone" text default 'UTC'::text,
    "tax_rate" numeric default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "overstock_multiplier" real not null default 3.0,
    "high_value_threshold" integer not null default 100000 -- in cents
);
alter table "public"."company_settings" enable row level security;
alter table "public"."company_settings" add constraint "company_settings_pkey" primary key(company_id);
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- Suppliers Table
create table if not exists "public"."suppliers" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."suppliers" add constraint "suppliers_pkey" primary key(id);
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- Products Table
create table if not exists "public"."products" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
    "updated_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
alter table "public"."products" add constraint "products_pkey" primary key(id);
alter table "public"."products" add constraint "products_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
create index if not exists "products_company_id_external_id_idx" on "public"."products" using btree (company_id, external_product_id);

-- Product Variants Table
create table if not exists "public"."product_variants" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."product_variants" enable row level security;
alter table "public"."product_variants" add constraint "product_variants_pkey" primary key(id);
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" foreign key (product_id) references products(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" foreign key (supplier_id) references suppliers(id) on delete set null;
create unique index if not exists "product_variants_company_id_sku_idx" on "public"."product_variants" using btree (company_id, sku);
create index if not exists "product_variants_company_id_external_id_idx" on "public"."product_variants" using btree (company_id, external_variant_id);


-- Customers Table
create table if not exists "public"."customers" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
alter table "public"."customers" enable row level security;
alter table "public"."customers" add constraint "customers_pkey" primary key(id);
alter table "public"."customers" add constraint "customers_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
create unique index if not exists "customers_company_id_email_idx" on "public"."customers" (company_id, email) where (deleted_at is null);

-- Orders Table
create table if not exists "public"."orders" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."orders" enable row level security;
alter table "public"."orders" add constraint "orders_pkey" primary key(id);
alter table "public"."orders" add constraint "orders_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."orders" add constraint "orders_customer_id_fkey" foreign key (customer_id) references customers(id) on delete set null;
create unique index if not exists "orders_company_id_external_id_idx" on "public"."orders" using btree (company_id, external_order_id);


-- Order Line Items Table
create table if not exists "public"."order_line_items" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."order_line_items" add constraint "order_line_items_pkey" primary key(id);
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" foreign key (order_id) references orders(id) on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" foreign key (variant_id) references product_variants(id) on delete set null;
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- Purchase Orders Table
create table if not exists "public"."purchase_orders" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" primary key(id);
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" foreign key (supplier_id) references suppliers(id) on delete set null;
create unique index if not exists "purchase_orders_company_id_po_number_idx" on "public"."purchase_orders" using btree (company_id, po_number);
create index if not exists "purchase_orders_idempotency_key_idx" on "public"."purchase_orders" using btree (idempotency_key);

-- Purchase Order Line Items Table
create table if not exists "public"."purchase_order_line_items" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "purchase_order_id" uuid not null,
    "variant_id" uuid not null,
    "company_id" uuid not null,
    "quantity" integer not null,
    "cost" integer not null
);
alter table "public"."purchase_order_line_items" enable row level security;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_pkey" primary key(id);
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" foreign key (purchase_order_id) references purchase_orders(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" foreign key (variant_id) references product_variants(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- Inventory Ledger Table
create table if not exists "public"."inventory_ledger" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."inventory_ledger" add constraint "inventory_ledger_pkey" primary key(id);
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" foreign key (variant_id) references product_variants(id) on delete cascade;

-- Integrations Table
create table if not exists "public"."integrations" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."integrations" add constraint "integrations_pkey" primary key(id);
alter table "public"."integrations" add constraint "integrations_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
create unique index if not exists "integrations_company_id_platform_idx" on "public"."integrations" using btree (company_id, platform);

-- Channel Fees Table
create table if not exists "public"."channel_fees" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "company_id" uuid not null,
    "channel_name" text not null,
    "percentage_fee" numeric,
    "fixed_fee" numeric,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."channel_fees" enable row level security;
alter table "public"."channel_fees" add constraint "channel_fees_pkey" primary key(id);
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
create unique index if not exists "channel_fees_company_id_channel_name_idx" on "public"."channel_fees" (company_id, channel_name);

-- AI Conversation & Message Tables
create table if not exists "public"."conversations" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone default now(),
    "last_accessed_at" timestamp with time zone default now(),
    "is_starred" boolean default false
);
alter table "public"."conversations" enable row level security;
alter table "public"."conversations" add constraint "conversations_pkey" primary key(id);
alter table "public"."conversations" add constraint "conversations_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;
alter table "public"."conversations" add constraint "conversations_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

create table if not exists "public"."messages" (
    "id" uuid not null default extensions.uuid_generate_v4(),
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
alter table "public"."messages" add constraint "messages_pkey" primary key(id);
alter table "public"."messages" add constraint "messages_conversation_id_fkey" foreign key (conversation_id) references conversations(id) on delete cascade;
alter table "public"."messages" add constraint "messages_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;


-- Audit Log Table
create table if not exists "public"."audit_log" (
    "id" bigserial primary key,
    "company_id" uuid not null,
    "user_id" uuid,
    "action" text not null,
    "details" jsonb,
    "created_at" timestamp with time zone default now()
);
alter table "public"."audit_log" enable row level security;
alter table "public"."audit_log" add constraint "audit_log_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."audit_log" add constraint "audit_log_user_id_fkey" foreign key (user_id) references auth.users(id) on delete set null;

-- Webhook Events Table (for preventing replay attacks)
create table if not exists "public"."webhook_events" (
  "id" uuid not null default extensions.uuid_generate_v4(),
  "integration_id" uuid not null,
  "webhook_id" text not null,
  "created_at" timestamp with time zone default now(),
  constraint "webhook_events_pkey" primary key (id),
  constraint "webhook_events_integration_id_fkey" foreign key (integration_id) references integrations (id) on delete cascade,
  constraint "webhook_events_integration_id_webhook_id_key" unique (integration_id, webhook_id)
);
alter table "public"."webhook_events" enable row level security;

-- Export Jobs Table
create table if not exists "public"."export_jobs" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "company_id" uuid not null,
    "requested_by_user_id" uuid not null,
    "status" text not null default 'pending',
    "download_url" text,
    "expires_at" timestamp with time zone,
    "error_message" text,
    "created_at" timestamp with time zone not null default now(),
    "completed_at" timestamp with time zone,
    constraint "export_jobs_pkey" primary key(id),
    constraint "export_jobs_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade,
    constraint "export_jobs_requested_by_user_id_fkey" foreign key (requested_by_user_id) references auth.users(id) on delete cascade
);
alter table "public"."export_jobs" enable row level security;

-- =================================================================
-- FUNCTIONS
-- =================================================================

-- Function to create a company and link the new user as its owner.
drop function if exists public.handle_new_user();
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name, owner_id)
  values (new.raw_app_meta_data->>'company_name', new.id)
  returning id into company_id;

  -- Link the user to the new company as 'Owner'
  insert into public.company_users (user_id, company_id, role)
  values (new.id, company_id, 'Owner');
  
  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (company_id);

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- Function to get a user's company ID
drop function if exists public.get_company_id_for_user(uuid);
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users where user_id = p_user_id limit 1;
$$;

-- Function to check user permissions
drop function if exists public.check_user_permission(uuid, company_role);
create or replace function public.check_user_permission(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
as $$
declare
  user_role public.company_role;
begin
  select role into user_role from public.company_users where user_id = p_user_id;

  if p_required_role = 'Admin' then
    return user_role in ('Owner', 'Admin');
  elsif p_required_role = 'Owner' then
    return user_role = 'Owner';
  end if;
  return false;
end;
$$;

-- Function to get all users for a company
drop function if exists public.get_users_for_company(uuid);
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
drop function if exists public.remove_user_from_company(uuid, uuid);
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
drop function if exists public.update_user_role_in_company(uuid, uuid, company_role);
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

-- Function to decrement inventory after an order
drop function if exists public.decrement_inventory_for_order(uuid, uuid);
create or replace function public.decrement_inventory_for_order(p_company_id uuid, p_order_id uuid)
returns void as $$
declare
  line_item record;
  current_stock integer;
begin
  for line_item in
    select variant_id, quantity from public.order_line_items where order_id = p_order_id
  loop
    if line_item.variant_id is not null then
      -- Lock the row to prevent race conditions
      select inventory_quantity into current_stock from public.product_variants
      where id = line_item.variant_id for update;

      -- Validate if there is enough stock
      if current_stock < line_item.quantity then
        raise exception 'Insufficient stock for SKU with variant_id %. Cannot fulfill order.', line_item.variant_id;
      end if;

      update public.product_variants
      set inventory_quantity = inventory_quantity - line_item.quantity
      where id = line_item.variant_id;
    end if;
  end loop;
end;
$$ language plpgsql;


-- Function to record an order from a platform
drop function if exists public.record_order_from_platform(uuid, jsonb, text);
create or replace function public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns uuid as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    line_item jsonb;
    v_variant_id uuid;
    v_sku text;
begin
    -- Find or create customer
    if p_order_payload->'customer'->>'email' is not null then
        select id into v_customer_id from public.customers
        where company_id = p_company_id and email = p_order_payload->'customer'->>'email';

        if v_customer_id is null then
            insert into public.customers (company_id, name, email, external_customer_id)
            values (
                p_company_id,
                p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
                p_order_payload->'customer'->>'email',
                p_order_payload->'customer'->>'id'
            ) returning id into v_customer_id;
        end if;
    end if;

    -- Create order
    insert into public.orders (company_id, external_order_id, order_number, customer_id, financial_status, total_amount, subtotal, total_tax, total_shipping, total_discounts, source_platform, created_at)
    values (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'order_number',
        v_customer_id,
        p_order_payload->>'financial_status',
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    ) returning id into v_order_id;

    -- Create order line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := line_item->>'sku';
        select id into v_variant_id from public.product_variants where company_id = p_company_id and sku = v_sku;

        insert into public.order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price)
        values (
            v_order_id,
            v_variant_id,
            p_company_id,
            line_item->>'name',
            v_sku,
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100
        );
    end loop;
    
    -- Decrement inventory
    perform public.decrement_inventory_for_order(p_company_id, v_order_id);

    return v_order_id;
end;
$$ language plpgsql security definer;

-- =================================================================
-- TRIGGERS
-- =================================================================

-- Trigger to handle new user sign-ups
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger to update 'updated_at' timestamps automatically
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists handle_updated_at on public.products;
create trigger handle_updated_at
  before update on public.products
  for each row execute procedure public.set_updated_at();
  
drop trigger if exists handle_updated_at on public.product_variants;
create trigger handle_updated_at
  before update on public.product_variants
  for each row execute procedure public.set_updated_at();

drop trigger if exists handle_updated_at on public.suppliers;
create trigger handle_updated_at
  before update on public.suppliers
  for each row execute procedure public.set_updated_at();

drop trigger if exists handle_updated_at on public.company_settings;
create trigger handle_updated_at
    before update on public.company_settings
    for each row execute procedure public.set_updated_at();

-- =================================================================
-- RLS (ROW LEVEL SECURITY)
-- =================================================================

-- Helper function to get the company_id from a user's JWT
create or replace function auth.get_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb->>'company_id', '')::uuid;
$$;

-- Generic policy for tables with a 'company_id' column
create or replace function public.create_company_rls_policy(table_name text)
returns void as $$
begin
  execute format('
    alter table public.%I enable row level security;
    drop policy if exists "Users can manage their own company''s data" on public.%I;
    create policy "Users can manage their own company''s data"
    on public.%I
    for all
    using (company_id = auth.get_company_id());
  ', table_name, table_name, table_name);
end;
$$ language plpgsql;

-- Apply RLS to all relevant tables
select public.create_company_rls_policy('products');
select public.create_company_rls_policy('product_variants');
select public.create_company_rls_policy('suppliers');
select public.create_company_rls_policy('orders');
select public.create_company_rls_policy('order_line_items');
select public.create_company_rls_policy('purchase_orders');
select public.create_company_rls_policy('purchase_order_line_items');
select public.create_company_rls_policy('customers');
select public.create_company_rls_policy('integrations');
select public.create_company_rls_policy('company_settings');
select public.create_company_rls_policy('inventory_ledger');
select public.create_company_rls_policy('channel_fees');
select public.create_company_rls_policy('conversations');
select public.create_company_rls_policy('messages');
select public.create_company_rls_policy('audit_log');
select public.create_company_rls_policy('webhook_events');
select public.create_company_rls_policy('export_jobs');

-- RLS for company_users table
drop policy if exists "Users can view their own company membership" on public.company_users;
create policy "Users can view their own company membership"
on public.company_users for select
using (company_id = auth.get_company_id());

-- RLS for companies table
drop policy if exists "Users can view their own company" on public.companies;
create policy "Users can view their own company"
on public.companies for select
using (id = auth.get_company_id());

-- =================================================================
-- MATERIALIZED VIEWS for Analytics Performance
-- =================================================================

-- A flattened view of variants with key product details
create materialized view if not exists public.product_variants_with_details_mat as
select
  pv.id,
  pv.product_id,
  pv.company_id,
  p.title as product_title,
  pv.title as variant_title,
  pv.sku,
  p.status as product_status,
  p.product_type,
  pv.inventory_quantity,
  pv.price,
  pv.cost,
  pv.location,
  pv.supplier_id,
  p.image_url,
  pv.created_at as variant_created_at,
  pv.updated_at as variant_updated_at
from public.product_variants pv
join public.products p on pv.product_id = p.id;

create unique index if not exists product_variants_with_details_mat_id_idx on public.product_variants_with_details_mat (id);
create index if not exists product_variants_with_details_mat_company_id_idx on public.product_variants_with_details_mat (company_id);


-- A view for sales aggregated by day
create materialized view if not exists public.daily_sales_mat as
select
    o.company_id,
    date_trunc('day', o.created_at) as sale_date,
    sum(o.total_amount) as total_revenue,
    count(distinct o.id) as total_orders,
    sum(oli.quantity) as total_items_sold
from public.orders o
join public.order_line_items oli on o.id = oli.order_id
group by o.company_id, date_trunc('day', o.created_at);

create unique index if not exists daily_sales_mat_company_date_idx on public.daily_sales_mat (company_id, sale_date);

-- Function to refresh all materialized views for a company
drop function if exists public.refresh_all_matviews(uuid);
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void
language plpgsql
as $$
begin
    -- It's more efficient to refresh concurrently for the whole view
    -- than to try and filter by company_id inside a REFRESH statement.
    -- RLS policies will handle data visibility.
    refresh materialized view concurrently public.product_variants_with_details_mat;
    refresh materialized view concurrently public.daily_sales_mat;
end;
$$;


-- Grant usage on the public schema to the authenticated role
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Grant usage for anon role on specific functions
grant execute on function public.get_company_id_for_user(uuid) to anon;

-- Ensure service_role can bypass RLS
alter table public.companies alter column owner_id set default auth.uid();
alter user supabase_admin with bypassrls;
