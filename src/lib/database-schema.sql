-- Full script for setting up the InvoChat database schema.
-- This script is idempotent and can be re-run safely.

-- 1. CLEANUP: Drop old objects if they exist, using CASCADE to handle dependencies.
-- This section ensures that re-running the script doesn't cause errors.
drop function if exists public.get_my_role cascade;
drop function if exists public.get_current_company_id cascade;
drop function if exists public.handle_new_user cascade;
drop function if exists public.update_inventory_from_sale cascade;
drop function if exists public.create_rls_policy cascade;
drop function if exists public.record_sale_transaction cascade;
drop function if exists public.batch_upsert_costs cascade;
drop function if exists public.batch_upsert_suppliers cascade;
drop function if exists public.batch_import_sales cascade;
drop function if exists public.record_order_from_platform cascade;

drop view if exists public.company_dashboard_metrics cascade;

drop table if exists public.inventory cascade;
drop table if exists public.sales cascade;
drop table if exists public.sale_items cascade;

-- Drop new tables in reverse order of creation due to foreign keys
drop table if exists public.refund_line_items cascade;
drop table if exists public.refunds cascade;
drop table if exists public.order_line_items cascade;
drop table if exists public.orders cascade;
drop table if exists public.product_variants cascade;
drop table if exists public.products cascade;
drop table if exists public.customer_addresses cascade;
drop table if exists public.customers cascade;
drop table if exists public.discounts cascade;
drop table if exists public.suppliers cascade;
drop table if exists public.company_settings cascade;
drop table if exists public.users cascade;
drop table if exists public.companies cascade;

-- Drop custom types
drop type if exists public.user_role cascade;

-- 2. SETUP: Create new tables and types for the SaaS architecture.

-- Create a custom type for user roles
create type public.user_role as enum ('Owner', 'Admin', 'Member');

-- Create the companies table
create table public.companies (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company-level information.';

-- Create the users table to link auth.users to companies
create table public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
comment on table public.users is 'Maps auth users to companies and assigns roles.';

-- Create the products table
create table public.products (
    id uuid primary key default gen_random_uuid(),
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
    updated_at timestamptz
);
create index on public.products(company_id);
create unique index on public.products(company_id, external_product_id);
comment on table public.products is 'Stores parent product information.';

-- Create the product_variants table
create table public.product_variants (
    id uuid primary key default gen_random_uuid(),
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
    external_variant_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create index on public.product_variants(product_id);
create index on public.product_variants(company_id);
create unique index on public.product_variants(company_id, sku);
create unique index on public.product_variants(company_id, external_variant_id);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

-- Create the orders table
create table public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid, -- references public.customers (added below)
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create index on public.orders(company_id);
create index on public.orders(customer_id);
create unique index on public.orders(company_id, external_order_id);
comment on table public.orders is 'Stores sales order information.';

-- Create the order_line_items table
create table public.order_line_items (
    id uuid primary key default gen_random_uuid(),
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
    external_line_item_id text
);
create index on public.order_line_items(order_id);
create index on public.order_line_items(variant_id);
comment on table public.order_line_items is 'Stores individual items within an order.';

-- Create the customers table
create table public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    created_at timestamptz default now()
);
create index on public.customers(company_id);
create unique index on public.customers(company_id, email);
comment on table public.customers is 'Stores customer information.';

-- Add the foreign key from orders to customers now that customers table exists
alter table public.orders add constraint fk_customer foreign key (customer_id) references public.customers(id) on delete set null;

-- 3. HELPER FUNCTIONS & TRIGGERS

-- Function to get the current user's company_id from their JWT claims
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select
    case
      when (auth.jwt() ->> 'app_metadata')::jsonb ->> 'company_id' is not null
      then ((auth.jwt() ->> 'app_metadata')::jsonb ->> 'company_id')::uuid
      else null
    end;
$$;
comment on function public.get_current_company_id is 'Returns the company_id from the current user''s JWT.';

-- Function to handle new user creation
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _company_id uuid;
  _company_name text;
begin
  -- Get company name from user metadata
  _company_name := new.raw_app_meta_data->>'company_name';

  -- Create a new company for the user
  insert into public.companies (name)
  values (_company_name)
  returning id into _company_id;

  -- Insert into our public users table
  insert into public.users (id, company_id, email, role)
  values (new.id, _company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', _company_id)
  where id = new.id;

  return new;
end;
$$;
comment on function public.handle_new_user is 'Trigger function to create a company and user profile upon new user signup.';

-- Trigger to call handle_new_user on new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute procedure public.handle_new_user();
comment on trigger on_auth_user_created on auth.users is 'When a new user signs up, this trigger creates their company and profile.';


-- Auto-update `updated_at` columns
create or replace function public.set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger update_products_updated_at
before update on public.products
for each row execute procedure public.set_updated_at();

create trigger update_product_variants_updated_at
before update on public.product_variants
for each row execute procedure public.set_updated_at();

create trigger update_orders_updated_at
before update on public.orders
for each row execute procedure public.set_updated_at();


-- 4. ROW-LEVEL SECURITY (RLS)
-- This section ensures that users can only access data belonging to their own company.

-- Function to create RLS policies on a table
create or replace function public.create_rls_policy(table_name text)
returns void as $$
begin
  execute format('
    -- Drop policy if it already exists to avoid errors on re-run
    DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;
    -- Create the policy
    CREATE POLICY "Users can only see their own company''s data."
    ON public.%I FOR ALL
    USING (company_id = public.get_current_company_id());
  ', table_name, table_name);
end;
$$ language plpgsql;
comment on function public.create_rls_policy is 'A helper function to apply a standard multi-tenant RLS policy to a table.';

-- Enable RLS on all company-specific tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;

-- Apply policies using the helper function
select public.create_rls_policy('companies');
select public.create_rls_policy('users');
select public.create_rls_policy('products');
select public.create_rls_policy('product_variants');
select public.create_rls_policy('orders');
select public.create_rls_policy('order_line_items');
select public.create_rls_policy('customers');

-- Special policy for the users table to allow access based on company
drop policy if exists "Users can see other users in their company." on public.users;
create policy "Users can see other users in their company." on public.users
for select using (company_id = public.get_current_company_id());
comment on policy "Users can see other users in their company." on public.users is 'Allows users to view the profiles of other users within the same company.';


-- 5. DATABASE RPCs (Remote Procedure Calls)
-- These functions can be called from the application to perform complex database operations securely and efficiently.

-- Function to get the current user's role
create or replace function public.get_my_role()
returns public.user_role
language sql
security definer
set search_path = public
as $$
  select role from public.users where id = auth.uid();
$$;
comment on function public.get_my_role is 'Returns the role of the currently authenticated user.';

-- Function to record an order from a platform
create or replace function public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns void as $$
declare
    _order_id uuid;
    _customer_id uuid;
    _variant_id uuid;
    line_item jsonb;
begin
    -- Find or create customer
    insert into public.customers (company_id, customer_name, email)
    values (
        p_company_id,
        p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
        p_order_payload->'customer'->>'email'
    )
    on conflict (company_id, email) do update set customer_name = excluded.customer_name
    returning id into _customer_id;

    -- Upsert order
    insert into public.orders (
        company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    ) values (
        p_company_id,
        p_order_payload->>'order_number',
        p_order_payload->>'id',
        _customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    on conflict (company_id, external_order_id) do update set
        financial_status = excluded.financial_status,
        fulfillment_status = excluded.fulfillment_status,
        total_amount = excluded.total_amount,
        updated_at = now()
    returning id into _order_id;

    -- Upsert line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the corresponding variant
        select id into _variant_id from public.product_variants
        where external_variant_id = line_item->>'variant_id' and company_id = p_company_id;

        insert into public.order_line_items (
            order_id, company_id, variant_id, product_name, variant_title, sku, quantity, price, total_discount
        ) values (
            _order_id,
            p_company_id,
            _variant_id,
            line_item->>'title',
            line_item->>'variant_title',
            line_item->>'sku',
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100,
            (line_item->>'total_discount')::numeric * 100
        )
        on conflict do nothing; -- Or define a conflict target if you want to update
    end loop;
end;
$$ language plpgsql;
comment on function public.record_order_from_platform is 'Processes a JSON payload from an e-commerce platform to create/update orders, customers, and line items.';


-- Grant usage on the public schema to authenticated users
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- Grant permissions for service_role to call all functions
grant all privileges on all functions in schema public to service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
