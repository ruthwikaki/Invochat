
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Create custom types for roles
create type public.user_role as enum ('Owner', 'Admin', 'Member');

-- #################################################################
-- 1. Tables
-- #################################################################

-- Public Tables
create table public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  role public.user_role not null default 'Member',
  email text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
comment on table public.users is 'User profiles, linked to a company and auth user.';

create table public.products (
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
  updated_at timestamptz,
  constraint uq_product_external_id unique (company_id, external_product_id)
);
comment on table public.products is 'Stores product master data.';

create table public.product_variants (
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
  price integer,
  compare_at_price integer,
  cost integer,
  inventory_quantity integer not null default 0,
  location text,
  deleted_at timestamptz,
  external_variant_id text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint uq_variant_sku unique (company_id, sku)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid,
  financial_status text default 'pending',
  fulfillment_status text default 'unfulfilled',
  currency text default 'USD',
  subtotal integer not null default 0,
  total_tax integer default 0,
  total_shipping integer default 0,
  total_discounts integer default 0,
  total_amount integer not null,
  source_platform text,
  source_name text,
  tags text[],
  notes text,
  cancelled_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null,
    variant_id uuid not null,
    product_name text not null,
    variant_title text,
    sku text not null,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    fulfillment_status text default 'unfulfilled',
    requires_shipping boolean default true,
    external_line_item_id text
);

create table public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);

create table public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null, -- 'shopify', 'woocommerce', etc.
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- 'sale', 'purchase', 'reconciliation', etc.
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

create table public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);

create table public.messages (
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

create table public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000, -- Stored as integer (e.g., $1000)
    predictive_stock_days integer not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    promo_sales_lift_multiplier real not null default 2.5,
    custom_rules jsonb,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

create table public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id),
    status text not null default 'Draft',
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz not null default now()
);

create table public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id),
    quantity integer not null,
    cost integer not null
);

create table public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    unique (integration_id, webhook_id)
);

create table public.audit_log (
  id bigserial primary key,
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);

-- #################################################################
-- 2. Helper Functions
-- #################################################################

-- Helper function to get the company ID from the JWT claims.
create or replace function get_company_id()
returns uuid
language sql stable
as $$
  select (current_setting('request.jwt.claims', true)::jsonb ->> 'company_id')::uuid;
$$;

-- Helper function to get the user ID from the JWT claims.
create or replace function get_user_id()
returns uuid
language sql stable
as $$
  select (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')::uuid;
$$;

-- Helper function to check if the current user has a specific role.
create or replace function check_user_role(p_role text)
returns boolean
language plpgsql stable
as $$
declare
  current_role text;
begin
  select role into current_role from public.users where id = get_user_id();
  return current_role = p_role;
end;
$$;


-- #################################################################
-- 3. Row Level Security (RLS) Policies
-- #################################################################

-- Generic function to check if a user belongs to the company of a given record.
create or replace function is_company_member(p_company_id uuid)
returns boolean
language sql stable
as $$
  select exists (
    select 1
    from public.users u
    where u.id = get_user_id() and u.company_id = p_company_id
  );
$$;

-- Enable RLS for all tables in the public schema
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.company_settings enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.webhook_events enable row level security;
alter table public.audit_log enable row level security;


-- Policies
create policy "Allow read access to own company" on public.companies
  for select using (id = get_company_id());

create policy "Allow access to own company data" on public.users
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.products
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.product_variants
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.orders
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.order_line_items
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.suppliers
  for all using (company_id = get_company_id());
  
create policy "Allow access to own company data" on public.integrations
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.inventory_ledger
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.customers
  for all using (company_id = get_company_id());

create policy "Allow access to user's own conversations" on public.conversations
  for all using (user_id = get_user_id());

create policy "Allow access to own company data" on public.messages
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.company_settings
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.purchase_orders
  for all using (company_id = get_company_id());

create policy "Allow access to own company data" on public.purchase_order_line_items
  for all using (company_id = get_company_id());
  
create policy "Allow access to own company data" on public.webhook_events
  for select using (is_company_member((select company_id from public.integrations where id = integration_id)));

create policy "Allow access to own company data" on public.audit_log
  for all using (company_id = get_company_id());


-- #################################################################
-- 4. Triggers and Functions
-- #################################################################

-- Function to handle new user sign-ups
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  company_name text := new.raw_app_meta_data ->> 'company_name';
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (coalesce(company_name, 'My Company'))
  returning id into new_company_id;

  -- Create a profile for the new user, linking them to their new company as Owner
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in the auth schema with the company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Trigger to update product's updated_at timestamp
create or replace function set_updated_at_timestamp()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_products_updated_at
before update on public.products
for each row
execute procedure set_updated_at_timestamp();

create trigger set_variants_updated_at
before update on public.product_variants
for each row
execute procedure set_updated_at_timestamp();

-- #################################################################
-- 5. Views
-- #################################################################

-- View to combine product and variant data for easy querying
create or replace view public.product_variants_with_details as
select
    v.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
from public.product_variants v
join public.products p on v.product_id = p.id;

-- View for sales orders with customer info
create or replace view public.orders_view as
select
    o.*,
    c.customer_name,
    c.email as customer_email
from public.orders o
left join public.customers c on o.customer_id = c.id;

-- View for customers with their analytics
create or replace view public.customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    coalesce(count(o.id), 0) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_spent
from public.customers c
left join public.orders o on c.id = o.customer_id
group by c.id, c.company_id;


-- #################################################################
-- 6. Indexes
-- #################################################################

create index idx_products_company_id on public.products(company_id);
create index idx_variants_product_id on public.product_variants(product_id);
create index idx_variants_sku on public.product_variants(sku);
create index idx_orders_company_id on public.orders(company_id);
create index idx_orders_customer_id on public.orders(customer_id);
create index idx_line_items_order_id on public.order_line_items(order_id);
create index idx_ledger_variant_id on public.inventory_ledger(variant_id, created_at desc);

-- #################################################################
-- 7. Full-Text Search (FTS)
-- #################################################################

-- Trigger function to update the FTS document
CREATE OR REPLACE FUNCTION update_product_fts_document()
RETURNS TRIGGER AS $$
BEGIN
  NEW.fts_document :=
    setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(array_to_string(NEW.tags, ' '), '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to execute the function on insert or update
CREATE TRIGGER products_fts_update
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_product_fts_document();

-- Create GIN index for FTS
CREATE INDEX idx_products_fts ON public.products USING GIN (fts_document);
