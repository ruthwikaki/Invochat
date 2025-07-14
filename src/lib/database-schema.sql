-- Drop functions and triggers if they exist to ensure idempotency
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user;
drop function if exists public.get_current_company_id;
drop function if exists public.create_company_rls_policy;
drop function if exists public.record_order_from_platform;
drop function if exists public.cleanup_old_data;


-- Enable HTTP extension for webhooks if not already enabled
create extension if not exists http with schema extensions;
-- Enable pg_cron for scheduled jobs if not already enabled
create extension if not exists pg_cron with schema extensions;
-- Enable pgroonga for indexing if not already enabled
create extension if not exists pgroonga with schema extensions;


-- =================================================================
-- Helper Functions
-- =================================================================

-- Function to get the current user's company_id from their JWT claims
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- =================================================================
-- Tables
-- =================================================================

-- Companies Table
create table if not exists public.companies (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.companies is 'Stores company information.';

-- Users Table (references auth.users)
create table if not exists public.users (
  id uuid references auth.users not null primary key,
  company_id uuid references public.companies on delete cascade,
  email text,
  role text default 'Member'::text not null,
  created_at timestamptz default (now() at time zone 'utc'),
  constraint users_company_id_fkey foreign key (company_id) references public.companies(id)
);
comment on table public.users is 'Stores user profile information and their company association.';

-- Company Settings Table
create table if not exists public.company_settings (
  company_id uuid references public.companies on delete cascade not null primary key,
  dead_stock_days integer not null default 90,
  fast_moving_days integer not null default 30,
  overstock_multiplier numeric not null default 3,
  high_value_threshold integer not null default 100000,
  predictive_stock_days integer not null default 7,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz
);
comment on table public.company_settings is 'Stores business logic parameters for a company.';

-- Products Table
create table if not exists public.products (
    id uuid default gen_random_uuid() primary key,
    company_id uuid references public.companies on delete cascade not null,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);
comment on table public.products is 'Stores product master data.';

-- Product Variants Table
create table if not exists public.product_variants (
    id uuid default gen_random_uuid() primary key,
    product_id uuid references public.products on delete cascade not null,
    company_id uuid references public.companies on delete cascade not null,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer,
    cost integer, -- in cents
    inventory_quantity integer not null default 0,
    external_variant_id text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, external_variant_id),
    unique(company_id, sku)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
    id uuid default gen_random_uuid() primary key,
    company_id uuid references public.companies on delete cascade not null,
    variant_id uuid references public.product_variants on delete cascade not null,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.inventory_ledger is 'Records all inventory movements for auditing.';

-- Customers Table
create table if not exists public.customers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid references public.companies on delete cascade not null,
    customer_name text,
    email text,
    total_orders integer default 0 not null,
    total_spent integer default 0 not null, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.customers is 'Stores customer data.';

-- Orders Table
create table if not exists public.orders (
    id uuid default gen_random_uuid() primary key,
    company_id uuid references public.companies on delete cascade not null,
    order_number text,
    external_order_id text,
    customer_id uuid references public.customers,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores order header information.';

-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid references public.orders on delete cascade not null,
    variant_id uuid references public.product_variants,
    company_id uuid references public.companies on delete cascade not null,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null check (price >= 0),
    total_discount integer,
    tax_amount integer,
    cost_at_time integer check (cost_at_time >= 0),
    external_line_item_id text
);
comment on table public.order_line_items is 'Stores individual line items for each order.';

-- Suppliers Table
create table if not exists public.suppliers (
    id uuid default gen_random_uuid() primary key,
    company_id uuid references public.companies on delete cascade not null,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

-- Purchase Orders Table
create table if not exists public.purchase_orders (
  id uuid default gen_random_uuid() primary key,
  company_id uuid references public.companies on delete cascade not null,
  supplier_id uuid references public.suppliers on delete set null,
  status text not null default 'draft',
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date,
  created_by uuid references public.users on delete set null,
  created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.purchase_orders is 'Stores purchase order headers.';

-- Purchase Order Line Items Table
create table if not exists public.purchase_order_line_items (
    id uuid default gen_random_uuid() primary key,
    purchase_order_id uuid references public.purchase_orders on delete cascade not null,
    variant_id uuid references public.product_variants on delete cascade not null,
    quantity integer not null,
    cost integer not null
);
comment on table public.purchase_order_line_items is 'Stores individual line items for each PO.';

-- Refund Line Items (placeholder for future use)
create table if not exists public.refund_line_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid references public.orders not null,
    company_id uuid references public.companies not null,
    variant_id uuid references public.product_variants,
    quantity integer not null,
    reason text,
    created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.refund_line_items is 'Stores refund line items.';

-- Conversations Table
create table if not exists public.conversations (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.users on delete cascade not null,
  company_id uuid references public.companies on delete cascade not null,
  title text not null,
  created_at timestamptz default (now() at time zone 'utc'),
  last_accessed_at timestamptz default (now() at time zone 'utc'),
  is_starred boolean default false
);
comment on table public.conversations is 'Stores chat conversation metadata.';

-- Messages Table
create table if not exists public.messages (
  id uuid default gen_random_uuid() primary key,
  conversation_id uuid references public.conversations on delete cascade not null,
  company_id uuid references public.companies on delete cascade not null,
  role text not null,
  content text not null,
  visualization jsonb,
  confidence float,
  assumptions text[],
  component text,
  component_props jsonb,
  created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.messages is 'Stores individual chat messages.';

-- Integrations Table
create table if not exists public.integrations (
  id uuid default gen_random_uuid() primary key,
  company_id uuid references public.companies on delete cascade not null,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default true,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  unique(company_id, platform)
);
comment on table public.integrations is 'Stores integration settings for a company.';

-- Audit Log Table
create table if not exists public.audit_log (
  id uuid default gen_random_uuid() primary key,
  company_id uuid references public.companies on delete cascade not null,
  user_id uuid, -- can be null for system actions
  action text not null,
  details jsonb,
  created_at timestamptz default (now() at time zone 'utc')
);
comment on table public.audit_log is 'Records significant actions for security and auditing.';

-- Webhook Events Table
create table if not exists public.webhook_events (
    id uuid default gen_random_uuid() primary key,
    integration_id uuid references public.integrations on delete cascade not null,
    webhook_id text not null,
    processed_at timestamptz default (now() at time zone 'utc'),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs processed webhook IDs to prevent replay attacks.';

-- =================================================================
-- Indexes
-- =================================================================
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_products_tags on public.products using gin (tags);

-- =================================================================
-- User Creation Trigger
-- =================================================================
-- This function is called when a new user signs up.
-- It creates a new company for them and links it to their user account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- grants the function elevated privileges
as $$
declare
  v_company_id uuid;
  v_company_name text;
begin
  -- Extract company name from metadata, fallback to a generic name
  v_company_name := new.raw_user_meta_data ->> 'company_name';
  if v_company_name is null or v_company_name = '' then
    v_company_name := new.email || '''s Company';
  end if;

  -- Create a new company
  insert into public.companies (name)
  values (v_company_name)
  returning id into v_company_id;

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set app_metadata = app_metadata || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  where id = new.id;
  
  -- Also insert a corresponding record into our public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, v_company_id, new.email, 'Owner');

  return new;
end;
$$;

-- Create the trigger that calls the function
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- =================================================================
-- Row-Level Security (RLS) Policies
-- =================================================================

-- Function to dynamically create RLS policies for a given table
create or replace function create_company_rls_policy(table_name text)
returns void as $$
begin
  execute format('
    alter table public.%I enable row level security;
    -- Drop existing policies to ensure idempotency
    drop policy if exists "Allow full access based on company_id" on public.%I;
    -- Create the new policy
    create policy "Allow full access based on company_id"
    on public.%I for all
    using (company_id = get_current_company_id())
    with check (company_id = get_current_company_id());
  ', table_name, table_name, table_name);
end;
$$ language plpgsql;

-- Apply the RLS policy to all relevant tables
select create_company_rls_policy(table_name)
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'products', 'product_variants', 'customers', 'orders',
    'order_line_items', 'suppliers', 'conversations', 'messages',
    'integrations', 'inventory_ledger', 'company_settings',
    'purchase_orders', 'purchase_order_line_items', 'refund_line_items',
    'audit_log', 'webhook_events'
  );

-- Special RLS for `companies` table (uses `id` instead of `company_id`)
alter table public.companies enable row level security;
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id"
on public.companies for all
using (id = get_current_company_id())
with check (id = get_current_company_id());

-- Special RLS for `users` table
alter table public.users enable row level security;
drop policy if exists "Allow read access to other users in same company" on public.users;
create policy "Allow read access to other users in same company"
on public.users for select
using (company_id = get_current_company_id());

drop policy if exists "Allow users to update their own record" on public.users;
create policy "Allow users to update their own record"
on public.users for update
using (id = auth.uid());


-- =================================================================
-- Data Processing Functions (RPCs)
-- =================================================================

create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
) returns void as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
    v_quantity int;
    current_inventory_quantity int;
begin
    -- Upsert customer
    insert into public.customers (company_id, email, customer_name)
    values (
        p_company_id,
        p_order_payload -> 'customer' ->> 'email',
        p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name'
    )
    on conflict (company_id, email) do update set
        customer_name = excluded.customer_name
    returning id into v_customer_id;

    -- Upsert order
    insert into public.orders (
        company_id, external_order_id, customer_id, order_number, total_amount, subtotal, total_tax, currency, source_platform
    )
    values (
        p_company_id,
        p_order_payload ->> 'id',
        v_customer_id,
        p_order_payload ->> 'name',
        (p_order_payload ->> 'total_price')::numeric * 100,
        (p_order_payload ->> 'subtotal_price')::numeric * 100,
        (p_order_payload ->> 'total_tax')::numeric * 100,
        p_order_payload ->> 'currency',
        p_platform
    )
    on conflict (company_id, external_order_id) do update set
        total_amount = excluded.total_amount,
        updated_at = (now() at time zone 'utc')
    returning id into v_order_id;

    -- Process line items
    for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
    loop
        v_sku := line_item ->> 'sku';
        v_quantity := (line_item ->> 'quantity')::int;

        -- Find the corresponding variant and lock the row for the transaction
        select id, inventory_quantity into v_variant_id, current_inventory_quantity
        from public.product_variants
        where company_id = p_company_id and sku = v_sku
        for update;

        if v_variant_id is not null then
            -- Upsert order line item
            insert into public.order_line_items (
                order_id, company_id, variant_id, product_name, sku, quantity, price
            )
            values (
                v_order_id,
                p_company_id,
                v_variant_id,
                line_item ->> 'name',
                v_sku,
                v_quantity,
                (line_item ->> 'price')::numeric * 100
            );

            -- Decrement inventory and log the change
            update public.product_variants
            set inventory_quantity = inventory_quantity - v_quantity
            where id = v_variant_id;

            insert into public.inventory_ledger (
                company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes
            )
            values (
                p_company_id,
                v_variant_id,
                'sale',
                -v_quantity,
                current_inventory_quantity - v_quantity,
                v_order_id,
                'Order #' || (p_order_payload ->> 'name')
            );
        else
            -- Log a warning if the SKU wasn't found
            raise warning 'SKU % from order % not found in product_variants for company %', v_sku, p_order_payload ->> 'name', p_company_id;
        end if;
    end loop;
end;
$$ language plpgsql;


-- =================================================================
-- Data Retention & Cleanup Cron Job
-- =================================================================

-- Function to delete old audit logs and chat messages
create or replace function public.cleanup_old_data()
returns void as $$
begin
  -- Delete audit logs older than 90 days
  delete from public.audit_log where created_at < (now() at time zone 'utc') - interval '90 days';
  
  -- Delete messages in non-starred conversations older than 90 days
  delete from public.messages
  where created_at < (now() at time zone 'utc') - interval '90 days'
    and conversation_id in (
      select id from public.conversations where is_starred = false
    );
end;
$$ language plpgsql;

-- Schedule the cleanup job to run daily at 3 AM UTC
-- This uses the pg_cron extension.
select cron.schedule('daily-cleanup', '0 3 * * *', 'select public.cleanup_old_data()');


commit;
```)