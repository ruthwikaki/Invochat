
-- =================================================================
--  ARVO: Advanced Inventory Management System
--  Schema Version: 1.3.0
-- =================================================================

-- =================================================================
--  1. Extensions
-- =================================================================
create extension if not exists "uuid-ossp" with schema "extensions";
create extension if not exists "pg_net" with schema "extensions";

-- =================================================================
--  2. Custom Types
-- =================================================================
do $$
begin
    if not exists (select 1 from pg_type where typname = 'company_role') then
        create type public.company_role as enum ('Owner', 'Admin', 'Member');
    end if;
    if not exists (select 1 from pg_type where typname = 'integration_platform') then
        create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
    end if;
    if not exists (select 1 from pg_type where typname = 'message_role') then
        create type public.message_role as enum ('user', 'assistant', 'tool');
    end if;
    if not exists (select 1 from pg_type where typname = 'feedback_type') then
        create type public.feedback_type as enum ('helpful', 'unhelpful');
    end if;
end$$;

-- =================================================================
--  3. Tables
-- =================================================================

-- Companies Table: Stores basic information about each company tenant.
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Company Users Table: Manages user roles within a company.
create table if not exists public.company_users (
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role public.company_role not null default 'Member',
    primary key (company_id, user_id)
);

-- Company Settings Table: Configurable business logic parameters per company.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 100000, -- Stored in cents
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Products Table
create table if not exists public.products (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    fts_document tsvector,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create index if not exists products_company_id_idx on public.products(company_id);
create index if not exists products_fts_document_idx on public.products using gin (fts_document);
create unique index if not exists products_company_id_external_product_id_idx on public.products(company_id, external_product_id);

-- Suppliers Table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create index if not exists suppliers_company_id_idx on public.suppliers(company_id);

-- Product Variants Table
create table if not exists public.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    sku text not null,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    supplier_id uuid references public.suppliers(id) on delete set null,
    reorder_point int,
    reorder_quantity int,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);
create index if not exists product_variants_product_id_idx on public.product_variants(product_id);
create index if not exists product_variants_company_id_idx on public.product_variants(company_id);
create unique index if not exists product_variants_company_sku_unique on public.product_variants (company_id, sku);
create unique index if not exists product_variants_company_id_external_variant_id_idx on public.product_variants(company_id, external_variant_id);

-- Customers Table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz
);
create index if not exists customers_company_id_idx on public.customers(company_id);

-- Orders Table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int not null,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz
);
create index if not exists orders_company_id_idx on public.orders(company_id);
create index if not exists orders_created_at_idx on public.orders(created_at);
create unique index if not exists orders_company_id_external_order_id_idx on public.orders(company_id, external_order_id);


-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int,
    tax_amount int,
    cost_at_time int,
    external_line_item_id text
);
create index if not exists order_line_items_order_id_idx on public.order_line_items(order_id);
create index if not exists order_line_items_variant_id_idx on public.order_line_items(variant_id);

-- Purchase Orders Table
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null,
    expected_arrival_date date,
    idempotency_key uuid,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create index if not exists purchase_orders_company_id_idx on public.purchase_orders(company_id);
create unique index if not exists po_idempotency_key_idx on public.purchase_orders (idempotency_key) where idempotency_key is not null;

-- Purchase Order Line Items Table
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity int not null,
    cost int not null -- in cents
);
create index if not exists po_line_items_po_id_idx on public.purchase_order_line_items(purchase_order_id);
create index if not exists po_line_items_variant_id_idx on public.purchase_order_line_items(variant_id);

-- Integrations Table
create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform public.integration_platform not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create unique index if not exists integrations_company_platform_unique on public.integrations(company_id, platform);

-- Webhook Events Table: Prevents replay attacks for webhooks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now()
);
create unique index if not exists webhook_events_unique_idx on public.webhook_events(integration_id, webhook_id);

-- Inventory Ledger Table: Tracks all stock movements for auditability.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);
create index if not exists inventory_ledger_company_id_variant_id_idx on public.inventory_ledger(company_id, variant_id);
create index if not exists inventory_ledger_created_at_idx on public.inventory_ledger(created_at);

-- AI Conversation History Tables
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);
create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role public.message_role not null,
    content text,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    "isError" boolean,
    created_at timestamptz default now()
);

-- Channel Fees Table: Stores sales channel fees for accurate profit calculation.
create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    fixed_fee int, -- in cents
    percentage_fee numeric,
    created_at timestamptz default now(),
    updated_at timestamptz
);
create unique index if not exists channel_fees_company_channel_unique_idx on public.channel_fees(company_id, channel_name);

-- Audit Log Table: Tracks important system and user actions.
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
create index if not exists audit_log_company_id_action_idx on public.audit_log(company_id, action, created_at);

-- Data Export Jobs Table
create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);

-- Data Import Jobs Table
create table if not exists public.imports (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    created_by uuid not null references auth.users(id) on delete cascade,
    import_type text not null,
    file_name text not null,
    total_rows int,
    processed_rows int,
    failed_rows int,
    status text not null default 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamptz default now(),
    completed_at timestamptz
);

-- Feedback Table: Stores user feedback on AI responses and other features.
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  subject_id text not null,
  subject_type text not null,
  feedback public.feedback_type not null,
  created_at timestamptz default now()
);

-- =================================================================
--  4. Functions & Triggers
-- =================================================================

-- Function to handle new user signup and company creation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
  v_company_name text;
begin
  -- Create a new company for the new user
  v_company_name := new.raw_app_meta_data->>'company_name';
  if v_company_name is null or v_company_name = '' then
    v_company_name := new.email || '''s Company';
  end if;
  
  insert into public.companies (name)
  values (v_company_name)
  returning id into v_company_id;

  -- Link the user to the new company as Owner
  insert into public.company_users (user_id, company_id, role)
  values (new.id, v_company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to execute the handle_new_user function on new user creation.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to update the fts_document for products
create or replace function public.update_fts_document()
returns trigger
language plpgsql
as $$
begin
  new.fts_document := to_tsvector('english',
    coalesce(new.title, '') || ' ' ||
    coalesce(new.description, '') || ' ' ||
    coalesce(new.product_type, '')
  );
  return new;
end;
$$;

-- Trigger for products FTS document
drop trigger if exists products_fts_update on public.products;
create trigger products_fts_update
before insert or update on public.products
for each row execute function public.update_fts_document();


-- Function to get the company_id for the current user
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.company_users
  where user_id = p_user_id;
  
  return v_company_id;
end;
$$;

-- Function to prevent negative inventory
create or replace function public.check_inventory_quantity()
returns trigger
language plpgsql
as $$
begin
    if new.inventory_quantity < 0 then
        raise exception 'Inventory quantity cannot be negative. SKU: %', new.sku;
    end if;
    return new;
end;
$$;

-- Trigger for inventory quantity check
drop trigger if exists before_update_inventory_quantity on public.product_variants;
create trigger before_update_inventory_quantity
before update on public.product_variants
for each row
when (new.inventory_quantity is distinct from old.inventory_quantity)
execute function public.check_inventory_quantity();


-- =================================================================
--  5. Row Level Security (RLS)
-- =================================================================
-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.channel_fees enable row level security;
alter table public.export_jobs enable row level security;
alter table public.imports enable row level security;
alter table public.feedback enable row level security;

-- Drop existing policies before creating new ones
drop policy if exists "User can access their own company data" on public.companies;
drop policy if exists "User can access their own company users" on public.company_users;
drop policy if exists "User can access their own company settings" on public.company_settings;
drop policy if exists "User can access their own company data" on public.products;
drop policy if exists "User can access their own company data" on public.product_variants;
drop policy if exists "User can access their own company data" on public.orders;
drop policy if exists "User can access their own company data" on public.order_line_items;
drop policy if exists "User can access their own company data" on public.customers;
drop policy if exists "User can access their own company data" on public.suppliers;
drop policy if exists "User can access their own company data" on public.purchase_orders;
drop policy if exists "User can access their own company data" on public.purchase_order_line_items;
drop policy if exists "User can access their own company data" on public.integrations;
drop policy if exists "User can access their own company data" on public.webhook_events;
drop policy if exists "User can access their own company data" on public.inventory_ledger;
drop policy if exists "User can access their own conversations" on public.conversations;
drop policy if exists "User can access their own company data" on public.messages;
drop policy if exists "User can access their own company data" on public.audit_log;
drop policy if exists "User can access their own company data" on public.channel_fees;
drop policy if exists "User can access their own export jobs" on public.export_jobs;
drop policy if exists "User can access their own company data" on public.imports;
drop policy if exists "User can access their own feedback" on public.feedback;

-- Define RLS Policies
create policy "User can access their own company data" on public.companies for select using (id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company users" on public.company_users for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company settings" on public.company_settings for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.products for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.product_variants for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.orders for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.order_line_items for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.customers for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.suppliers for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.purchase_orders for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.purchase_order_line_items for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.integrations for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.webhook_events for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.inventory_ledger for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "User can access their own company data" on public.messages for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.audit_log for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own company data" on public.channel_fees for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid());
create policy "User can access their own company data" on public.imports for all using (company_id = public.get_company_id_for_user(auth.uid()));
create policy "User can access their own feedback" on public.feedback for all using (user_id = auth.uid());


-- =================================================================
-- 6. New Database Functions for Batch Processing
-- =================================================================
create or replace function public.batch_upsert_costs(p_records jsonb[], p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
begin
    for i in 1..array_length(p_records, 1) loop
        insert into public.product_variants (
            company_id, sku, cost, reorder_point, reorder_quantity, supplier_id, updated_at
        )
        select
            p_company_id,
            r->>'sku',
            (r->>'cost')::int,
            (r->>'reorder_point')::int,
            (r->>'reorder_quantity')::int,
            s.id,
            now()
        from jsonb_to_record(p_records[i]) as r(sku text, cost text, reorder_point text, reorder_quantity text, supplier_name text)
        left join public.suppliers s on s.name = r.supplier_name and s.company_id = p_company_id
        on conflict (company_id, sku) do update set
            cost = excluded.cost,
            reorder_point = excluded.reorder_point,
            reorder_quantity = excluded.reorder_quantity,
            supplier_id = excluded.supplier_id,
            updated_at = now();
    end loop;
end;
$$;

create or replace function public.batch_upsert_suppliers(p_records jsonb[], p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
begin
    for i in 1..array_length(p_records, 1) loop
        insert into public.suppliers (
            company_id, name, email, phone, default_lead_time_days, notes
        )
        select
            p_company_id,
            r->>'name',
            r->>'email',
            r->>'phone',
            (r->>'default_lead_time_days')::int,
            r->>'notes'
        from jsonb_to_record(p_records[i]) as r(name text, email text, phone text, default_lead_time_days text, notes text)
        on conflict (company_id, name) do update set
            email = excluded.email,
            phone = excluded.phone,
            default_lead_time_days = excluded.default_lead_time_days,
            notes = excluded.notes,
            updated_at = now();
    end loop;
end;
$$;

create or replace function public.batch_import_sales(p_records jsonb[], p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
declare
    v_order record;
    v_variant record;
    v_customer_id uuid;
begin
    for i in 1..array_length(p_records, 1) loop
        select * into v_order from jsonb_to_record(p_records[i]) as r(
            order_date timestamptz, sku text, quantity int, unit_price int, 
            customer_email text, order_id text
        );

        select id into v_variant from public.product_variants where sku = v_order.sku and company_id = p_company_id;
        if v_variant is null then
            continue;
        end if;

        if v_order.customer_email is not null then
            select id into v_customer_id from public.customers where email = v_order.customer_email and company_id = p_company_id;
            if v_customer_id is null then
                insert into public.customers (company_id, email) values (p_company_id, v_order.customer_email) returning id into v_customer_id;
            end if;
        end if;
        
        insert into public.orders (
            company_id, order_number, customer_id, total_amount, subtotal, created_at, source_platform
        ) values (
            p_company_id, coalesce(v_order.order_id, 'imported-' || gen_random_uuid()::text), v_customer_id, 
            v_order.quantity * v_order.unit_price, v_order.quantity * v_order.unit_price, v_order.order_date, 'csv_import'
        ) on conflict do nothing;
    end loop;
end;
$$;
