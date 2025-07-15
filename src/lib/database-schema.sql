--
-- Universal App Starter
--
-- Copyright (c) 2024, App Prototyper, Firebase. All rights reserved.
--
-- This script is designed to be run in the Supabase SQL Editor.
-- It sets up the necessary tables, functions, and security policies
-- for a multi-tenant SaaS application.
--
-- It is designed to be idempotent and can be run multiple times safely.
--

----------------------------------------
-- 1. Helper Functions
----------------------------------------

-- Helper function to get the company ID for the currently authenticated user.
-- This is used in RLS policies to scope data access.
create or replace function get_my_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select raw_app_meta_data->>'company_id' from auth.users where id = auth.uid();
$$;

-- Helper function to check if a user is an admin of their company.
create or replace function is_my_company_admin(p_company_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from users
    where id = auth.uid()
      and company_id = p_company_id
      and role in ('Admin', 'Owner')
  );
$$;

----------------------------------------
-- 2. Initial Table Setup
----------------------------------------

-- Companies table to store information about each tenant
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Users table with a link to their company
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  email text,
  role text default 'Member' check (role in ('Owner', 'Admin', 'Member')),
  deleted_at timestamptz,
  created_at timestamptz default now()
);

-- Company-specific settings
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Products table
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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

-- Product Variants table (the core of inventory)
create table if not exists public.product_variants (
    id uuid primary key default uuid_generate_v4(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, external_variant_id)
);

-- Customers table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

-- Orders table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    status text not null default 'pending',
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Order Line Items table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text
);

-- Suppliers table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);

-- Purchase Orders table
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    created_at timestamptz not null default now()
);

-- Purchase Order Line Items table
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    quantity integer not null,
    cost integer not null
);

-- Inventory Ledger table for tracking stock movements
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- Integrations table
create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- Audit Log table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

-- Conversations table for AI chat
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

-- Messages table for AI chat
create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);

-- Table for webhook deduplication
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now()
);

----------------------------------------
-- 3. Correct Column Constraints
----------------------------------------

-- Ensure product variants have a non-nullable SKU and title, and remove obsolete columns.
alter table public.product_variants alter column sku set not null;
alter table public.product_variants alter column title set not null;

alter table public.product_variants drop column if exists weight;
alter table public.product_variants drop column if exists weight_unit;

----------------------------------------
-- 4. Create Indexes for Performance
----------------------------------------

-- Indexes on foreign keys and frequently queried columns
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_company_id on public.product_variants(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_sku on public.product_variants(sku);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_customers_email on public.customers(email);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_purchase_orders_company_id on public.purchase_orders(company_id);
create index if not exists idx_purchase_orders_supplier_id on public.purchase_orders(supplier_id);
create index if not exists idx_po_line_items_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_inventory_ledger_company_id on public.inventory_ledger(company_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_messages_conversation_id on public.messages(conversation_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);
create index if not exists idx_audit_log_company_id on public.audit_log(company_id);

-- Unique index for webhook deduplication
create unique index if not exists uix_webhook_events_integration_id_webhook_id on public.webhook_events(integration_id, webhook_id);

----------------------------------------
-- 5. Views for Simplified Data Access
----------------------------------------

-- Drop the view if it exists to allow underlying table changes
drop view if exists public.product_variants_with_details;

-- Create a view to easily get variant details along with parent product info.
create or replace view public.product_variants_with_details as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url
from
  public.product_variants pv
join
  public.products p on pv.product_id = p.id;

----------------------------------------
-- 6. User and Company Management
----------------------------------------

-- This function is called by a trigger when a new user signs up.
-- It creates a new company for the user and links them as the 'Owner'.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company
  insert into public.companies (name)
  values (new.raw_app_meta_data->>'company_name')
  returning id into new_company_id;

  -- Create a corresponding entry in our public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the function on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

----------------------------------------
-- 7. Row-Level Security (RLS)
----------------------------------------

-- First, drop any old policies that might depend on the old function.
drop policy if exists "Allow company members to read" on public.products;
drop policy if exists "Allow company members to read" on public.product_variants;
drop policy if exists "Allow company members to read" on public.orders;
drop policy if exists "Allow company members to read" on public.order_line_items;
drop policy if exists "Allow company members to manage" on public.customers;
drop policy if exists "Allow company members to read" on public.refunds;
drop policy if exists "Allow company members to manage" on public.suppliers;
drop policy if exists "Allow company members to manage" on public.purchase_orders;
drop policy if exists "Allow company members to read" on public.inventory_ledger;
drop policy if exists "Allow company members to manage" on public.integrations;
drop policy if exists "Allow company members to manage" on public.company_settings;
drop policy if exists "Allow admins to read audit logs for their company" on public.audit_log;
drop policy if exists "Allow user to manage messages in their conversations" on public.messages;
drop policy if exists "Allow user to manage their conversations" on public.conversations;

-- Then, drop the insecure function.
drop function if exists get_my_company_id();

-- Now, enable RLS on all tables that store tenant-specific data.
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.company_settings enable row level security;
alter table public.audit_log enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.refunds enable row level security;
alter table public.refund_line_items enable row level security;
alter table public.users enable row level security;
alter table public.companies enable row level security;

-- Define a new, secure helper function that can't be manipulated by JWT claims.
create or replace function get_my_company_id_from_user_id(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id from public.users where id = p_user_id;
  return v_company_id;
end;
$$;

-- Create the new, secure RLS policies.
create policy "Allow company members to read" on public.products for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));

create policy "Allow company members to read" on public.product_variants for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to read" on public.orders for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to read" on public.order_line_items for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));

create policy "Allow company members to manage" on public.customers for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to read" on public.refunds for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to manage" on public.suppliers for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to manage" on public.purchase_orders for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to read" on public.inventory_ledger for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to manage" on public.integrations for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()));
  
create policy "Allow company members to manage" on public.company_settings for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()));

create policy "Allow admins to read audit logs for their company" on public.audit_log for select
  using (company_id = get_my_company_id_from_user_id(auth.uid()) and is_my_company_admin(company_id));

create policy "Allow user to manage messages in their conversations" on public.messages for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()) and user_id = auth.uid());

create policy "Allow user to manage their conversations" on public.conversations for all
  using (company_id = get_my_company_id_from_user_id(auth.uid()) and user_id = auth.uid());
  
-- Allow users to see other members of their own company
create policy "Allow users to see their own company members" on public.users for select
    using (company_id = get_my_company_id_from_user_id(auth.uid()));

-- Allow users to see their own company details
create policy "Allow users to see their own company" on public.companies for select
    using (id = get_my_company_id_from_user_id(auth.uid()));


----------------------------------------
-- 8. Stored Procedures for Business Logic
----------------------------------------

-- Procedure to record a sale and update inventory atomically
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
) returns void as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_line_item jsonb;
    v_variant_id uuid;
    v_cost_at_time integer;
begin
    -- Find or create the customer
    select id into v_customer_id
    from public.customers
    where email = (p_order_payload->'billing_address'->>'email')
      and company_id = p_company_id;

    if v_customer_id is null then
        insert into public.customers (company_id, customer_name, email)
        values (
            p_company_id,
            coalesce(p_order_payload->'billing_address'->>'name', 'Unknown'),
            p_order_payload->'billing_address'->>'email'
        ) returning id into v_customer_id;
    end if;

    -- Insert the order
    insert into public.orders (
        company_id, customer_id, order_number, external_order_id, status,
        financial_status, fulfillment_status, currency, subtotal, total_tax,
        total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    values (
        p_company_id, v_customer_id, p_order_payload->>'name', p_order_payload->>'id', 'completed',
        p_order_payload->>'financial_status', p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    ) returning id into v_order_id;

    -- Insert line items and update inventory
    for v_line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the corresponding variant
        select id, cost into v_variant_id, v_cost_at_time
        from public.product_variants
        where external_variant_id = (v_line_item->>'variant_id')
          and company_id = p_company_id;
          
        if v_variant_id is not null then
            insert into public.order_line_items (
                order_id, variant_id, company_id, product_name, sku, quantity, price,
                cost_at_time, external_line_item_id
            )
            values (
                v_order_id, v_variant_id, p_company_id, v_line_item->>'title', v_line_item->>'sku',
                (v_line_item->>'quantity')::integer,
                (v_line_item->>'price')::numeric * 100,
                v_cost_at_time,
                v_line_item->>'id'
            );

            -- Update inventory and create ledger entry
            update public.product_variants
            set inventory_quantity = inventory_quantity - (v_line_item->>'quantity')::integer
            where id = v_variant_id;
            
            insert into public.inventory_ledger (
                company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes
            )
            select
                p_company_id,
                v_variant_id,
                'sale',
                -(v_line_item->>'quantity')::integer,
                pv.inventory_quantity,
                v_order_id,
                'Order #' || (p_order_payload->>'name')
            from public.product_variants pv where pv.id = v_variant_id;
        end if;
    end loop;
end;
$$ language plpgsql;

-- Procedure to create purchase orders from a list of suggestions.
create or replace function public.create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid
)
returns integer as $$
declare
    suggestion jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_number text;
    v_total_cost integer := 0;
    created_po_count integer := 0;
begin
    -- Group suggestions by supplier
    for v_supplier_id in select distinct (s->>'supplier_id')::uuid from jsonb_array_elements(p_suggestions) s
    loop
        -- Create one PO per supplier
        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (
            select coalesce(max(substring(po_number from '\d+$')::int), 0) + 1
            from purchase_orders where company_id = p_company_id and po_number like 'PO-' || to_char(now(), 'YYYYMMDD') || '-%'
        );

        -- Insert the main PO record
        insert into public.purchase_orders (company_id, supplier_id, status, po_number, total_cost)
        values (p_company_id, v_supplier_id, 'Ordered', v_po_number, 0) -- initial cost is 0
        returning id into v_po_id;
        
        v_total_cost := 0;

        -- Add line items for this supplier
        for suggestion in select * from jsonb_array_elements(p_suggestions) s where (s->>'supplier_id')::uuid = v_supplier_id
        loop
            insert into public.purchase_order_line_items (purchase_order_id, variant_id, quantity, cost)
            values (
                v_po_id,
                (suggestion->>'variant_id')::uuid,
                (suggestion->>'suggested_reorder_quantity')::integer,
                (suggestion->>'unit_cost')::integer
            );
            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer);
        end loop;

        -- Update the total cost on the PO
        update public.purchase_orders set total_cost = v_total_cost where id = v_po_id;
        
        created_po_count := created_po_count + 1;
        
        -- Audit log
        insert into public.audit_log (company_id, user_id, action, details)
        values (p_company_id, p_user_id, 'Create Purchase Order', jsonb_build_object('po_id', v_po_id, 'po_number', v_po_number));
    end loop;
    
    return created_po_count;
end;
$$ language plpgsql;
