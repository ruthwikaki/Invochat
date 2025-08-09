
-- Enable the UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- #############################################
-- ################## Schemas ##################
-- #############################################

-- The `public` schema is owned by the `postgres` role.
-- The `auth` schema is owned by the `supabase_auth_admin` role.
-- The `storage` schema is owned by the `supabase_storage_admin` role.
-- The `vault` schema is owned by the `supabase_admin` role.


-- #############################################
-- #################### RLS ####################
-- #############################################
-- Helper function to get company_id from JWT
-- This function is used by the RLS policies
create or replace function auth.company_id()
returns uuid as $$
declare
  company_id_val uuid;
begin
  select nullif(current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id', '')::uuid into company_id_val;
  return company_id_val;
end;
$$ language plpgsql stable;

-- Grant execute permission to authenticated role
grant execute on function auth.company_id() to authenticated;


-- #############################################
-- ################### Enums ###################
-- #############################################

create type public.company_role as enum ('Owner', 'Admin', 'Member');
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');
create type public.feedback_type as enum ('helpful', 'unhelpful');
create type public.message_role as enum ('user', 'assistant', 'tool');


-- #############################################
-- ################## Tables ###################
-- #############################################

-- Companies table to store company information
create table if not exists public.companies (
    id uuid not null default uuid_generate_v4(),
    name text not null,
    created_at timestamp with time zone not null default now(),
    owner_id uuid references auth.users(id),
    primary key (id)
);
-- Enable RLS for companies
alter table public.companies enable row level security;


-- Company Users table to link users to companies with roles
create table if not exists public.company_users (
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role company_role not null default 'Member',
    primary key (company_id, user_id)
);
-- Enable RLS for company_users
alter table public.company_users enable row level security;


-- Products table to store product information
create table if not exists public.products (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    primary key (id)
);
-- Enable RLS for products
alter table public.products enable row level security;


-- Product Variants table to store variant information
create table if not exists public.product_variants (
    id uuid not null default gen_random_uuid(),
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    reorder_point integer,
    reorder_quantity integer,
    reserved_quantity integer not null default 0,
    in_transit_quantity integer not null default 0,
    supplier_id uuid references public.suppliers(id) on delete set null,
    location text,
    external_variant_id text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),
    deleted_at timestamp with time zone,
    version integer not null default 1,
    primary key (id),
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
-- Enable RLS for product_variants
alter table public.product_variants enable row level security;


-- Customers table to store customer information
create table if not exists public.customers (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone,
    deleted_at timestamp with time zone,
    primary key(id)
);
-- Enable RLS for customers
alter table public.customers enable row level security;


-- Orders table to store order information
create table if not exists public.orders (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone,
    unique(company_id, external_order_id),
    primary key (id)
);
-- Enable RLS for orders
alter table public.orders enable row level security;


-- Order Line Items table to store individual items in an order
create table if not exists public.order_line_items (
    id uuid not null default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text,
    primary key (id)
);
-- Enable RLS for order_line_items
alter table public.order_line_items enable row level security;


-- Suppliers table
create table if not exists public.suppliers (
  id uuid not null default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone,
  primary key (id)
);
-- Enable RLS for suppliers
alter table public.suppliers enable row level security;


-- Purchase Orders table
create table if not exists public.purchase_orders (
  id uuid not null default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'Draft',
  po_number text not null,
  total_cost int not null,
  expected_arrival_date date,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone,
  idempotency_key uuid,
  notes text,
  primary key (id),
  unique (company_id, po_number)
);
-- Enable RLS for purchase_orders
alter table public.purchase_orders enable row level security;


-- Purchase Order Line Items table
create table if not exists public.purchase_order_line_items (
  id uuid not null default uuid_generate_v4(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  variant_id uuid not null references public.product_variants(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  quantity int not null,
  cost int not null,
  primary key (id)
);
-- Enable RLS for purchase_order_line_items
alter table public.purchase_order_line_items enable row level security;


-- Integrations table
create table if not exists public.integrations (
  id uuid not null default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform integration_platform not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  primary key (id),
  unique (company_id, platform)
);
-- Enable RLS for integrations
alter table public.integrations enable row level security;


-- Inventory Ledger table
create table if not exists public.inventory_ledger (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamp with time zone not null default now(),
    primary key (id)
);
-- Enable RLS for inventory_ledger
alter table public.inventory_ledger enable row level security;


-- Conversation table for AI chat history
create table if not exists public.conversations (
    id uuid not null default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamp with time zone default now(),
    last_accessed_at timestamp with time zone default now(),
    is_starred boolean default false,
    primary key(id)
);
-- Enable RLS for conversations
alter table public.conversations enable row level security;


-- Messages table for AI chat history
create table if not exists public.messages (
    id uuid not null default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role message_role not null,
    content text not null,
    component text,
    componentProps jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamp with time zone default now(),
    isError boolean default false,
    primary key(id)
);
-- Enable RLS for messages
alter table public.messages enable row level security;


-- Company Settings table for business logic parameters
create table if not exists public.company_settings (
  company_id uuid not null references public.companies(id) on delete cascade,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier real not null default 3,
  high_value_threshold int not null default 100000,
  predictive_stock_days int not null default 7,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  primary key (company_id)
);
-- Enable RLS for company_settings
alter table public.company_settings enable row level security;


-- Channel Fees table for calculating net margin
create table if not exists public.channel_fees (
  id uuid not null default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric,
  fixed_fee numeric,
  created_at timestamptz default now(),
  updated_at timestamptz,
  primary key (id),
  unique (company_id, channel_name)
);
-- Enable RLS for channel_fees
alter table public.channel_fees enable row level security;


-- Export Jobs table
create table if not exists public.export_jobs (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    error_message text,
    primary key (id)
);
-- Enable RLS for export_jobs
alter table public.export_jobs enable row level security;

-- Audit Log table
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
-- Enable RLS for audit_log
alter table public.audit_log enable row level security;

-- Feedback table
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  company_id uuid not null references public.companies(id),
  subject_id text not null,
  subject_type text not null,
  feedback feedback_type not null,
  created_at timestamptz default now()
);
-- Enable RLS for feedback
alter table public.feedback enable row level security;

-- Webhook Events table to prevent replay attacks
create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references public.integrations(id) on delete cascade,
  webhook_id text not null,
  created_at timestamptz default now(),
  unique(integration_id, webhook_id)
);
-- Enable RLS for webhook_events
alter table public.webhook_events enable row level security;


-- #############################################
-- ############## RLS Policies #################
-- #############################################

-- Drop existing policies to ensure a clean slate
drop policy if exists "Enable all for service roles" on public.companies;
drop policy if exists "Enable read for users based on company" on public.companies;
drop policy if exists "Enable read for users based on company" on public.company_users;
drop policy if exists "Enable insert for authenticated users" on public.products;
drop policy if exists "Users can only access their own company data" on public.products;
drop policy if exists "Users can only access their own company data" on public.product_variants;
drop policy if exists "Users can only access their own company data" on public.customers;
drop policy if exists "Users can only access their own company data" on public.orders;
drop policy if exists "Users can only access their own company data" on public.order_line_items;
drop policy if exists "Users can only access their own company data" on public.suppliers;
drop policy if exists "Users can only access their own company data" on public.purchase_orders;
drop policy if exists "Users can only access their own company data" on public.purchase_order_line_items;
drop policy if exists "Users can only access their own company data" on public.integrations;
drop policy if exists "Users can only access their own company data" on public.inventory_ledger;
drop policy if exists "Users can only access their own company data" on public.company_settings;
drop policy if exists "Users can only access their own company data" on public.channel_fees;
drop policy if exists "Users can only access their own company data" on public.export_jobs;
drop policy if exists "Users can only access their own company data" on public.audit_log;
drop policy if exists "Users can only access their own company data" on public.feedback;
drop policy if exists "Users can only access their own company data" on public.webhook_events;
drop policy if exists "Users can access their own conversations" on public.conversations;
drop policy if exists "Users can access their own messages" on public.messages;

-- RLS Policies
create policy "Enable read for users based on company" on public.companies
    for select using (id = auth.company_id());

create policy "Enable read for users based on company" on public.company_users
    for select using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.products
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.product_variants
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.customers
    for all using (company_id = auth.company_id());
    
create policy "Users can only access their own company data" on public.orders
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.order_line_items
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.suppliers
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.purchase_orders
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.purchase_order_line_items
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.integrations
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.inventory_ledger
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.company_settings
    for all using (company_id = auth.company_id());
    
create policy "Users can only access their own company data" on public.channel_fees
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.export_jobs
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.audit_log
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.feedback
    for all using (company_id = auth.company_id());

create policy "Users can only access their own company data" on public.webhook_events
    for all using (company_id = auth.company_id());
    
create policy "Users can access their own conversations" on public.conversations
    for all using (user_id = auth.uid());
    
create policy "Users can access their own messages" on public.messages
    for all using (company_id = auth.company_id());

-- #############################################
-- ################## Triggers #################
-- #############################################

-- Trigger function to create a new company for a new user
create or replace function public.handle_new_user()
returns trigger as $$
declare
  company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into company_id;

  -- Link the user to the new company as Owner
  insert into public.company_users (company_id, user_id, role)
  values (company_id, new.id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;
  
  return new;
end;
$$ language plpgsql security definer;

-- Drop existing trigger if it exists
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger function to update the 'updated_at' timestamp
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Apply the trigger to relevant tables
do $$
declare
    t text;
begin
    for t in 
        select table_name from information_schema.columns 
        where table_schema = 'public' and column_name = 'updated_at'
    loop
        execute format('
            drop trigger if exists set_updated_at_trigger on public.%I;
            create trigger set_updated_at_trigger
            before update on public.%I
            for each row
            execute procedure public.set_updated_at();
        ', t, t);
    end loop;
end;
$$;


-- #############################################
-- ################### Views ###################
-- #############################################

create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type as product_type
from public.product_variants pv
join public.products p on pv.product_id = p.id;

create or replace view public.orders_view as
select 
    o.*,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

create or replace view public.purchase_orders_view as
select
    po.*,
    s.name as supplier_name,
    (select json_agg(json_build_object(
        'id', poli.id,
        'quantity', poli.quantity,
        'cost', poli.cost,
        'sku', pv.sku,
        'product_name', p.title
    )) from purchase_order_line_items poli
    join product_variants pv on poli.variant_id = pv.id
    join products p on pv.product_id = p.id
    where poli.purchase_order_id = po.id) as line_items
from public.purchase_orders po
left join public.suppliers s on po.supplier_id = s.id;


create or replace view public.customers_view as
select 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date
from public.customers c
left join public.orders o on c.id = o.customer_id
where c.deleted_at is null
group by c.id;

create or replace view public.feedback_view as
select 
    f.id,
    f.created_at,
    f.feedback,
    u.email as user_email,
    m.content as user_message_content,
    am.content as assistant_message_content,
    f.company_id
from public.feedback f
join auth.users u on f.user_id = u.id
left join public.messages m on f.subject_id = m.id and f.subject_type = 'message'
left join public.messages am on am.conversation_id = m.conversation_id and am.created_at > m.created_at and am.role = 'assistant'
order by am.created_at
limit 1;

create or replace view public.audit_log_view as
select 
    al.id,
    al.created_at,
    u.email as user_email,
    al.action,
    al.details,
    al.company_id
from public.audit_log al
left join auth.users u on al.user_id = u.id;

-- #############################################
-- ################# Functions #################
-- #############################################

-- This is a placeholder for your detailed business logic functions.
-- They would be included here in a production schema deployment.
-- Example:
-- create function public.get_advanced_report(p_company_id uuid) ...
-- grant execute on function public.get_advanced_report to authenticated;

-- Grant usage on schemas to authenticated users
grant usage on schema public to authenticated;
grant usage on schema vault to authenticated;

-- Grant all permissions on all tables in public schema to the service_role
grant all on all tables in schema public to service_role;
grant all on all functions in schema public to service_role;
grant all on all sequences in schema public to service_role;

