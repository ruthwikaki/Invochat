-- Enable the pgcrypto extension for UUID generation
create extension if not exists "pgcrypto" with schema "public";
create extension if not exists "uuid-ossp" with schema "public";

-- Create the companies table
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company information.';

-- Create the profiles table
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid references public.companies(id) on delete cascade not null,
    first_name text,
    last_name text,
    role text not null default 'Member' check (role in ('Owner', 'Admin', 'Member')),
    updated_at timestamptz,
    -- constraint to ensure a user can only belong to one company
    unique (id, company_id)
);
comment on table public.profiles is 'Stores public user profile information, linking auth.users to a company.';

-- Create the suppliers table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now(),
    -- Ensure supplier names are unique per company
    unique(company_id, name)
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

-- Create the products table
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
    -- Unique constraint for products from external platforms
    unique(company_id, external_product_id)
);
comment on table public.products is 'Stores base product information.';

-- Create the product_variants table
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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer not null default 0,
    location text null, -- Simple text field for bin/location
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    -- Make SKU unique per company
    unique(company_id, sku)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

-- Create the customers table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    -- Make email unique per company to avoid duplicates
    unique(company_id, email)
);
comment on table public.customers is 'Stores customer information.';

-- Create the orders table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
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
    updated_at timestamptz,
    -- Unique constraint for orders from external platforms
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order information.';

-- Create the order_line_items table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer, -- in cents
    external_line_item_id text
);
comment on table public.order_line_items is 'Stores individual line items for each order.';

-- Create the purchase_orders table
create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null, -- in cents
    expected_arrival_date date,
    created_at timestamptz not null default now(),
    unique(company_id, po_number)
);
comment on table public.purchase_orders is 'Stores purchase orders for restocking inventory.';

-- Create the purchase_order_line_items table
create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity integer not null,
    cost integer not null -- in cents
);
comment on table public.purchase_order_line_items is 'Stores line items for each purchase order.';

-- Create the inventory_ledger table
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Tracks all inventory movements for auditing.';

-- Create the integrations table
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
comment on table public.integrations is 'Stores details for connected e-commerce platforms.';

-- Create webhook_events table for deduplication
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs incoming webhook IDs to prevent replay attacks.';

-- Create company_settings table
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.company_settings is 'Stores business logic settings for a company.';

-- Create conversations and messages tables for the chat feature
create table if not exists public.conversations (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null,
  created_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  is_starred boolean default false
);
comment on table public.conversations is 'Stores chat conversation threads.';

create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null, -- 'user' or 'assistant'
  content text,
  component text,
  component_props jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  is_error boolean default false,
  created_at timestamptz default now()
);
comment on table public.messages is 'Stores individual messages within a conversation.';


-- Create audit_log table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Records significant events for auditing purposes.';


-- Create indexes for performance
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_variants_company_id_sku on public.product_variants(company_id, sku);
create index if not exists idx_variants_product_id on public.product_variants(product_id);
create index if not exists idx_orders_company_id_created_at on public.orders(company_id, created_at desc);
create index if not exists idx_customers_company_id_email on public.customers(company_id, email);
create index if not exists idx_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_integrations_company_id on public.integrations(company_id);
create index if not exists idx_conversations_user_id on public.conversations(user_id);

-- Create a secure full-text search function and index
create or replace function public.search_products(p_company_id uuid, p_search_term text)
returns setof public.products
language sql stable
as $$
  select *
  from public.products
  where company_id = p_company_id and title ilike '%' || p_search_term || '%';
$$;

-- Note: PGroonga might not be available by default. Using standard GIN index for broader compatibility.
create index if not exists products_title_gin_idx on public.products using gin (to_tsvector('english', title));


-- Define a function to get the company_id for the current user
create or replace function public.get_current_company_id()
returns uuid
language sql security definer
as $$
  select company_id from public.profiles where id = auth.uid();
$$;

-- Define the function to handle new user creation
create or replace function public.on_auth_user_created()
returns trigger
language plpgsql
security definer
as $$
declare
  company_name text := new.raw_app_meta_data->>'company_name';
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name) values (company_name) returning id into new_company_id;

  -- Create a profile for the new user, linking them to the new company as 'Owner'
  insert into public.profiles (id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  return new;
end;
$$;

-- Drop trigger if it exists before creating it
drop trigger if exists on_auth_user_created_trigger on auth.users;

-- Create the trigger to fire on new user sign-up
create trigger on_auth_user_created_trigger
  after insert on auth.users
  for each row
  execute function public.on_auth_user_created();

-- RLS Policies
alter table public.companies enable row level security;
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.company_settings enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;


-- Drop old policies before creating new ones to avoid conflicts
drop policy if exists "Allow full access based on company_id" on public.companies;
drop policy if exists "Allow access to own profile and other company members" on public.profiles;
drop policy if exists "Allow full access based on company_id" on public.products;
drop policy if exists "Allow full access based on company_id" on public.product_variants;
drop policy if exists "Allow full access based on company_id" on public.suppliers;
drop policy if exists "Allow full access based on company_id" on public.customers;
drop policy if exists "Allow full access based on company_id" on public.orders;
drop policy if exists "Allow full access based on company_id" on public.order_line_items;
drop policy if exists "Allow full access based on company_id" on public.purchase_orders;
drop policy if exists "Allow full access based on company_id" on public.purchase_order_line_items;
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
drop policy if exists "Allow full access based on company_id" on public.integrations;
drop policy if exists "Allow full access based on company_id" on public.company_settings;
drop policy if exists "Allow access to own conversations" on public.conversations;
drop policy if exists "Allow access to own messages" on public.messages;
drop policy if exists "Allow read access to company audit log" on public.audit_log;
drop policy if exists "Allow read access to webhook_events" on public.webhook_events;


-- Create Policies
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id());
create policy "Allow access to own profile and other company members" on public.profiles for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.purchase_orders for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.purchase_order_line_items for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id());
create policy "Allow access to own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Allow access to own messages" on public.messages for all using (company_id = get_current_company_id());
create policy "Allow read access to company audit log" on public.audit_log for select using (company_id = get_current_company_id());
create policy "Allow read access to webhook_events" on public.webhook_events for select using (company_id = get_current_company_id());


-- Create a view for product variants with essential details
drop view if exists public.product_variants_with_details;
create or replace view public.product_variants_with_details as
select
  pv.id,
  pv.product_id,
  pv.company_id,
  p.title as product_title,
  p.status as product_status,
  p.product_type,
  p.image_url,
  pv.sku,
  pv.title,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.location,
  pv.created_at
from
  public.product_variants pv
join
  public.products p on pv.product_id = p.id;
