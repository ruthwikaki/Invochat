--
-- PostgreSQL database schema for InvoChat
--
-- This script is designed to be idempotent, meaning it can be run multiple
-- times without causing errors or creating duplicate objects.
--

-- Section 1: Helper Functions
-- -----------------------------------------------------------------------------

-- Function to get the current user's company ID from their session claims.
-- This is a security-critical function used in RLS policies.
create or replace function public.get_current_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
  select company_id from public.profiles where user_id = auth.uid();
$$;

-- Function to automatically set the `updated_at` timestamp on a table.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = (now() at time zone 'utc');
  return new;
end;
$$;


-- Section 2: Table Creation
-- -----------------------------------------------------------------------------

-- Stores core company information.
create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz default (now() at time zone 'utc')
);

-- Stores company-specific business logic settings.
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier numeric not null default 3.0,
  high_value_threshold numeric not null default 1000.00,
  predictive_stock_days int not null default 7,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz
);

-- Profiles table to store user-specific app data, linked to auth.users.
create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  first_name text,
  last_name text,
  role text not null default 'Member',
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  constraint fk_company foreign key (company_id) references public.companies(id)
);

-- Stores locations like warehouses or stores.
create table if not exists public.locations (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    is_default boolean not null default false,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, name)
);

-- Stores core product information.
create table if not exists public.products (
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
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  unique (company_id, external_product_id)
);

-- Stores variants of products, including SKU and stock levels.
create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  location_id uuid references public.locations(id) on delete set null,
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
  external_variant_id text,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  unique (company_id, external_variant_id),
  unique (company_id, sku)
);

-- Ledger for all inventory movements.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    location_id uuid references public.locations(id) on delete set null,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default (now() at time zone 'utc')
);

-- Stores customer information.
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_name text,
  email text,
  total_orders int default 0,
  total_spent int default 0, -- in cents
  first_order_date timestamptz,
  created_at timestamptz default (now() at time zone 'utc'),
  deleted_at timestamptz
);

-- Stores order information.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  order_number text not null,
  external_order_id text,
  customer_id uuid references public.customers(id),
  financial_status text,
  fulfillment_status text,
  currency text,
  subtotal int, -- in cents
  total_tax int,
  total_shipping int,
  total_discounts int,
  total_amount int,
  source_platform text,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  unique (company_id, external_order_id)
);

-- Stores line items for each order.
create table if not exists public.order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  variant_id uuid references public.product_variants(id),
  company_id uuid not null references public.companies(id) on delete cascade,
  product_name text,
  variant_title text,
  sku text,
  quantity int not null,
  price int not null,
  total_discount int,
  tax_amount int,
  cost_at_time int, -- in cents
  external_line_item_id text
);

-- Stores supplier information.
create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz default (now() at time zone 'utc'),
    updated_at timestamptz,
    unique(company_id, name)
);

-- Stores integration settings for platforms like Shopify.
create table if not exists public.integrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default true,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz default (now() at time zone 'utc'),
  updated_at timestamptz,
  unique (company_id, platform)
);

-- Stores chat conversation history.
create table if not exists public.conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text,
    created_at timestamptz default (now() at time zone 'utc'),
    last_accessed_at timestamptz default (now() at time zone 'utc'),
    is_starred boolean default false
);

-- Stores individual chat messages.
create table if not exists public.messages (
    id uuid primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    visualization jsonb,
    confidence real,
    assumptions text[],
    component text,
    component_props jsonb,
    created_at timestamptz default (now() at time zone 'utc')
);

-- Generic audit log for important events.
create table if not exists public.audit_log (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default (now() at time zone 'utc')
);

-- Stores processed webhook IDs to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default (now() at time zone 'utc'),
    unique(integration_id, webhook_id)
);


-- Section 3: Automatic `updated_at` Triggers
-- -----------------------------------------------------------------------------

-- This procedure dynamically applies the `set_updated_at` trigger to a list of tables.
create or replace procedure public.apply_updated_at_trigger(table_names text[])
language plpgsql
as $$
declare
  tbl_name text;
begin
  foreach tbl_name in array table_names
  loop
    execute format('
        drop trigger if exists handle_updated_at on public.%I;
        create trigger handle_updated_at
        before update on public.%I
        for each row
        execute function public.set_updated_at();
    ', tbl_name, tbl_name);
  end loop;
end;
$$;

-- Apply the trigger to all tables that have an `updated_at` column.
call public.apply_updated_at_trigger(array[
    'companies', 'company_settings', 'products', 'product_variants', 'orders', 'suppliers', 'integrations', 'profiles'
]);


-- Section 4: Row-Level Security (RLS) Policies
-- -----------------------------------------------------------------------------
-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_events enable row level security;
alter table public.profiles enable row level security;
alter table public.locations enable row level security;

-- Policies for `companies` table
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id"
on public.companies for all
using (id = get_current_company_id())
with check (id = get_current_company_id());

-- Policies for `profiles` table
drop policy if exists "Users can only see their own profile" on public.profiles;
create policy "Users can only see their own profile"
on public.profiles for select
using (user_id = auth.uid());

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles for update
using (user_id = auth.uid());

-- Generic policies for most tables based on company_id
create or replace procedure public.create_company_rls_policy(table_name text)
language plpgsql
as $$
begin
    execute format('
        drop policy if exists "Allow full access based on company_id" on public.%I;
        create policy "Allow full access based on company_id"
        on public.%I for all
        using (company_id = get_current_company_id())
        with check (company_id = get_current_company_id());
    ', table_name, table_name);
end;
$$;

-- Apply the generic RLS policy to all tables with a `company_id` column
call public.create_company_rls_policy('company_settings');
call public.create_company_rls_policy('products');
call public.create_company_rls_policy('product_variants');
call public.create_company_rls_policy('inventory_ledger');
call public.create_company_rls_policy('customers');
call public.create_company_rls_policy('orders');
call public.create_company_rls_policy('order_line_items');
call public.create_company_rls_policy('suppliers');
call public.create_company_rls_policy('integrations');
call public.create_company_rls_policy('conversations');
call public.create_company_rls_policy('messages');
call public.create_company_rls_policy('audit_log');
call public.create_company_rls_policy('locations');


-- Section 5: Authentication Triggers and Functions
-- -----------------------------------------------------------------------------

-- Trigger function to handle new user sign-ups.
create or replace function public.on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Extract company name from metadata, defaulting if not provided.
  company_name := new.raw_user_meta_data ->> 'company_name';
  if company_name is null or company_name = '' then
    company_name := new.email || '''s Company';
  end if;

  -- Create a new company for the user.
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Create a profile for the new user, linking them to the new company.
  insert into public.profiles (user_id, company_id, role)
  values (new.id, company_id, 'Owner');

  return new;
end;
$$;

-- Apply the trigger to the auth.users table.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.on_auth_user_created();

-- Section 6: Database Views
-- -----------------------------------------------------------------------------
create or replace view public.product_variants_with_details as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    l.name as location_name
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id
left join
    public.locations l on pv.location_id = l.id;


-- Section 7: Indexes
-- -----------------------------------------------------------------------------
create index if not exists idx_products_company_id on public.products(company_id);
create index if not exists idx_product_variants_product_id on public.product_variants(product_id);
create index if not exists idx_product_variants_company_id on public.product_variants(company_id);
create index if not exists idx_orders_company_id on public.orders(company_id);
create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_order_line_items_order_id on public.order_line_items(order_id);
create index if not exists idx_order_line_items_variant_id on public.order_line_items(variant_id);
create index if not exists idx_suppliers_company_id on public.suppliers(company_id);
create index if not exists idx_customers_company_id on public.customers(company_id);
create index if not exists idx_inventory_ledger_variant_id on public.inventory_ledger(variant_id);
create index if not exists idx_inventory_ledger_company_id on public.inventory_ledger(company_id);


-- Section 8: Stored Procedures for Business Logic
-- -----------------------------------------------------------------------------

create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
returns void
language plpgsql
security definer
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_customer_name text;
    v_customer_email text;
    line_item jsonb;
    v_variant_id uuid;
    v_quantity int;
begin
    -- Extract customer info
    if p_platform = 'shopify' then
        v_customer_name := coalesce(p_order_payload -> 'customer' ->> 'first_name', '') || ' ' || coalesce(p_order_payload -> 'customer' ->> 'last_name', '');
        v_customer_email := p_order_payload -> 'customer' ->> 'email';
    elsif p_platform = 'woocommerce' then
        v_customer_name := coalesce(p_order_payload -> 'billing' ->> 'first_name', '') || ' ' || coalesce(p_order_payload -> 'billing' ->> 'last_name', '');
        v_customer_email := p_order_payload -> 'billing' ->> 'email';
    else
        -- Default for other platforms or direct sales
        v_customer_name := p_order_payload ->> 'customer_name';
        v_customer_email := p_order_payload ->> 'customer_email';
    end if;

    -- Upsert customer
    if v_customer_email is not null then
        insert into public.customers (company_id, email, customer_name)
        values (p_company_id, v_customer_email, v_customer_name)
        on conflict (company_id, email) do update
        set customer_name = excluded.customer_name
        returning id into v_customer_id;
    end if;

    -- Upsert order
    insert into public.orders (
        company_id, external_order_id, order_number, customer_id, total_amount, created_at, source_platform
    )
    values (
        p_company_id,
        p_order_payload ->> 'id',
        coalesce(p_order_payload ->> 'name', p_order_payload ->> 'number', p_order_payload ->> 'id'),
        v_customer_id,
        ( (p_order_payload ->> 'total_price')::numeric * 100 )::int,
        (p_order_payload ->> 'created_at')::timestamptz,
        p_platform
    )
    on conflict (company_id, external_order_id) do update
    set total_amount = excluded.total_amount, updated_at = (now() at time zone 'utc')
    returning id into v_order_id;

    -- Loop through line items and update inventory
    for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
    loop
        -- Find variant by SKU
        select id into v_variant_id
        from public.product_variants
        where sku = line_item ->> 'sku' and company_id = p_company_id;

        if v_variant_id is not null then
            v_quantity := (line_item ->> 'quantity')::int;

            -- Atomically update inventory and check for stock
            update public.product_variants
            set inventory_quantity = inventory_quantity - v_quantity
            where id = v_variant_id and inventory_quantity >= v_quantity;

            if not found then
                raise notice 'Insufficient stock for SKU %. Skipping inventory update.', line_item ->> 'sku';
            end if;
            
            -- Record line item
            insert into public.order_line_items (order_id, variant_id, company_id, quantity, price)
            values (v_order_id, v_variant_id, p_company_id, v_quantity, ((line_item ->> 'price')::numeric * 100)::int);

        else
            raise notice 'Variant with SKU % not found. Skipping line item.', line_item ->> 'sku';
        end if;
    end loop;
end;
$$;


create or replace function public.cleanup_old_data()
returns void language plpgsql as $$
begin
  -- Delete audit logs older than 90 days
  delete from public.audit_log where created_at < now() - interval '90 days';
  
  -- Delete messages older than 90 days
  delete from public.messages where created_at < now() - interval '90 days';
end;
$$;


select cron.schedule(
  'daily-cleanup',
  '0 0 * * *', -- every day at midnight
  $$ select public.cleanup_old_data(); $$
);

-- Final grant of usage on the cron schema to the postgres user
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Grant permissions on public schema to supabase_admin.
-- This is important for allowing the admin user to manage the schema.
grant all privileges on all tables in schema public to supabase_admin;
grant all privileges on all sequences in schema public to supabase_admin;
grant all privileges on all functions in schema public to supabase_admin;
