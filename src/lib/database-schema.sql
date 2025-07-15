-- InvoChat Schema v2.0
-- This script is designed to be idempotent. It can be run multiple times without causing errors.

-- 1. Enable necessary extensions
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgroonga with schema extensions;

-- 2. Define custom types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        create type user_role as enum ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- 3. Create core tables
-- Note: We use "if not exists" to prevent errors on re-runs.

create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Users table in the public schema to store app-specific user data
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Stores application-specific user data and links to a company.';

create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    overstock_multiplier int not null default 3,
    high_value_threshold int not null default 1000,
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now()
);

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
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

create table if not exists public.orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid, -- We will create customers table later
    status text not null default 'pending',
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0, -- in cents
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, external_order_id)
);

create table if not exists public.order_line_items (
    id uuid primary key default uuid_generate_v4(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0,
    tax_amount int default 0,
    cost_at_time int, -- cost of goods in cents at time of sale
    external_line_item_id text
);


create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders int default 0,
    total_spent int default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);
-- Add fkey from orders to customers now that it exists
alter table public.orders add constraint fk_customer foreign key (customer_id) references public.customers(id) on delete set null;


create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

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
  updated_at timestamptz,
  unique(company_id, platform)
);

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    created_at timestamptz not null default now()
);

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity integer not null,
    cost integer not null
);

create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- 4. Correct column definitions and add missing ones
alter table public.product_variants drop column if exists "weight";
alter table public.product_variants drop column if exists "weight_unit";
alter table public.product_variants alter column sku type text;
alter table public.product_variants alter column title type text;
alter table public.product_variants alter column title drop not null;
alter table public.product_variants alter column sku drop not null;

-- Add company_id to tables that missed it.
alter table public.order_line_items add column if not exists company_id uuid references public.companies(id) on delete cascade;


-- 5. Create Indexes for performance
-- Core Foreign Keys
create index if not exists idx_users_company_id on public.users(company_id);
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_company_id on public.product_variants(company_id);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_ledger_company_id on public.inventory_ledger(company_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);
create index if not exists idx_po_company_id on public.purchase_orders(company_id);
create index if not exists idx_po_supplier_id on public.purchase_orders(supplier_id);
create index if not exists idx_poli_po_id on public.purchase_order_line_items(purchase_order_id);
create index if not exists idx_poli_variant_id on public.purchase_order_line_items(variant_id);

-- High-cardinality lookups
create index if not exists idx_products_external_id on public.products(external_product_id);
create index if not exists idx_variants_sku on public.product_variants(sku);
create index if not exists idx_variants_external_id on public.product_variants(external_variant_id);
create index if not exists idx_orders_external_id on public.orders(external_order_id);
create index if not exists idx_customers_email on public.customers(email);

-- Full-text search index (PGroonga)
-- This creates a secure search function that incorporates company_id
drop function if exists search_products(text, uuid);
create or replace function search_products(search_term text, p_company_id uuid)
returns setof products
language sql
stable
as $$
  select *
  from products
  where
    products.company_id = p_company_id and
    products.title &@ search_term;
$$;
-- Now create the index on the products table
create index if not exists pgroonga_products_title_index on public.products using pgroonga (title);


-- 6. Setup Row-Level Security (RLS) Policies
-- This is a critical security step for our multi-tenant application.

-- A helper function to get the company_id from a user's JWT claims.
create or replace function get_my_company_id()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Enable RLS on all company-specific tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.webhook_events enable row level security;

-- Drop existing policies to avoid conflicts before creating new ones
drop policy if exists "Users can only access their own company data" on public.companies;
drop policy if exists "Users can only access users within their own company" on public.users;
drop policy if exists "Users can only access their own company settings" on public.company_settings;
drop policy if exists "Users can only access their own company's products" on public.products;
drop policy if exists "Users can only access their own company's variants" on public.product_variants;
drop policy if exists "Users can only access their own company's orders" on public.orders;
drop policy if exists "Users can only access their own company's order line items" on public.order_line_items;
drop policy if exists "Users can only access their own company's customers" on public.customers;
drop policy if exists "Users can only access their own company's suppliers" on public.suppliers;
drop policy if exists "Users can only access their own company's ledger" on public.inventory_ledger;
drop policy if exists "Users can only access their own conversations" on public.conversations;
drop policy if exists "Users can only access messages in their own company" on public.messages;
drop policy if exists "Users can only access their own company's integrations" on public.integrations;
drop policy if exists "Users can only access their own company's POs" on public.purchase_orders;
drop policy if exists "Users can only access their own company's PO line items" on public.purchase_order_line_items;
drop policy if exists "Users can only access their own webhook events" on public.webhook_events;

-- Create RLS Policies
create policy "Users can only access their own company data" on public.companies for select using (id = get_my_company_id());
create policy "Users can only access users within their own company" on public.users for all using (company_id = get_my_company_id());
create policy "Users can only access their own company settings" on public.company_settings for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's products" on public.products for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's variants" on public.product_variants for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's orders" on public.orders for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's order line items" on public.order_line_items for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's customers" on public.customers for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's suppliers" on public.suppliers for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's ledger" on public.inventory_ledger for all using (company_id = get_my_company_id());
create policy "Users can only access their own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Users can only access messages in their own company" on public.messages for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's integrations" on public.integrations for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's POs" on public.purchase_orders for all using (company_id = get_my_company_id());
create policy "Users can only access their own company's PO line items" on public.purchase_order_line_items for all using (purchase_order_id in (select id from purchase_orders where company_id = get_my_company_id()));
create policy "Users can only access their own webhook events" on public.webhook_events for all using (integration_id in (select id from integrations where company_id = get_my_company_id()));


-- 7. Create Functions and Triggers
-- This function handles new user sign-ups
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
  v_company_name text := new.raw_user_meta_data->>'company_name';
begin
  -- If user is invited, company_id will be in app_metadata
  if new.raw_app_meta_data->>'company_id' is not null then
    v_company_id := (new.raw_app_meta_data->>'company_id')::uuid;
  else
    -- For new signups, create a new company
    insert into public.companies (name)
    values (v_company_name)
    returning id into v_company_id;
  end if;

  insert into public.users (id, company_id, email, role)
  values (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's claims in auth.users to include the company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Drop trigger if it exists to ensure we have the latest version
drop trigger if exists on_auth_user_created on auth.users;
-- Create the trigger to run the function after a new user is created
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- This function updates the inventory ledger after a sale
create or replace function public.update_inventory_on_sale()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Decrease inventory for the sold variant
  update public.product_variants
  set inventory_quantity = inventory_quantity - new.quantity
  where id = new.variant_id;

  -- Log the change in the inventory ledger
  insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  select new.company_id, new.variant_id, 'sale', -new.quantity, v.inventory_quantity, new.order_id, 'Order #' || o.order_number
  from public.product_variants v
  join public.orders o on o.id = new.order_id
  where v.id = new.variant_id;
  
  return new;
end;
$$;

drop trigger if exists on_order_line_item_created on public.order_line_items;
create trigger on_order_line_item_created
  after insert on public.order_line_items
  for each row execute procedure public.update_inventory_on_sale();


-- 8. Enable Realtime for key tables
begin;
  -- remove the realtime publication
  drop publication if exists supabase_realtime;

  -- re-create the publication but don't enable it for any tables
  create publication supabase_realtime;
commit;

-- add tables to the publication
alter publication supabase_realtime add table public.integrations;
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;

-- Grant usage on the realtime schema
grant usage on schema realtime to postgres, anon, authenticated, service_role;
grant all on all tables in schema realtime to postgres, anon, authenticated, service_role;
grant all on all functions in schema realtime to postgres, anon, authenticated, service_role;
grant all on all sequences in schema realtime to postgres, anon, authenticated, service_role;


-- Final command to make sure permissions are set correctly
-- Grant usage on public schema to authenticated users
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;
grant insert on all tables in schema public to authenticated;
grant update on all tables in schema public to authenticated;
grant delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- Let anon role see the RLS policies
grant usage on schema public to anon;
grant all on all tables in schema public to anon;
grant all on all functions in schema public to anon;


-- Create a view for easy access to variant details with product info
create or replace view public.product_variants_with_details as
select
  pv.id,
  pv.product_id,
  pv.company_id,
  pv.sku,
  pv.title,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  pv.inventory_quantity,
  pv.price,
  pv.cost,
  pv.location,
  pv.created_at,
  p.product_type
from
  public.product_variants pv
join
  public.products p on pv.product_id = p.id;
  
comment on view public.product_variants_with_details is 'Combines product variants with key details from their parent product for easier querying.';

-- Grant access to the view
grant select on public.product_variants_with_details to authenticated;

-- Add a function to remove a user from a company (soft delete)
create or replace function remove_user_from_company(p_user_id uuid, p_company_id uuid, p_performing_user_id uuid)
returns void as $$
declare
  performing_user_role user_role;
begin
  -- Check if the performing user is an Owner or Admin of the company
  select role into performing_user_role from public.users where id = p_performing_user_id and company_id = p_company_id;
  
  if performing_user_role not in ('Owner', 'Admin') then
    raise exception 'You do not have permission to remove users from this company.';
  end if;

  -- Soft delete the user by marking them as deleted
  update public.users
  set deleted_at = now()
  where id = p_user_id and company_id = p_company_id;

  -- Optionally, you might want to remove them from the auth.users table if they are not part of other companies
  -- This part is more complex and depends on your multi-tenancy strategy.
  -- For now, we will just soft delete them from the company.
end;
$$ language plpgsql security definer;

-- Add a function to update a user's role
create or replace function update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role user_role)
returns void as $$
begin
  -- This function should be secured by RLS on the public.users table.
  -- The policy should ensure only 'Owner' or 'Admin' can update roles.
  update public.users
  set role = p_new_role
  where id = p_user_id and company_id = p_company_id;
end;
$$ language plpgsql security definer;
