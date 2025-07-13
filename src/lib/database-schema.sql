
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;
-- Enable the pgcrypto extension
create extension if not exists "pgcrypto" with schema extensions;
-- Enable the vault extension
create extension if not exists "supabase_vault" with schema extensions;

-- =============================================
-- ===            HELPER FUNCTIONS           ===
-- =============================================

-- Function to get the current user's ID
create or replace function public.get_current_user_id()
returns uuid
language sql stable
as $$
  select auth.uid();
$$;

-- Function to get the company_id from the current user's claims
create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- =============================================
-- ===               TABLES                  ===
-- =============================================

-- Companies table
create table if not exists public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  created_at timestamptz not null default now()
);

-- Users table with company_id
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text default 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz default now()
);

-- Company Settings table
create table if not exists public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dead_stock_days integer not null default 90,
  overstock_multiplier integer not null default 3,
  high_value_threshold integer not null default 1000,
  fast_moving_days integer not null default 30,
  predictive_stock_days integer not null default 7,
  promo_sales_lift_multiplier real not null default 2.5,
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
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

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
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer not null default 0,
    external_variant_id text,
    weight numeric,
    weight_unit text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

-- Inventory Ledger Table
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'restock', 'return', 'adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

-- Customers Table
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
    unique(company_id, email)
);

-- Customer Addresses table
create table if not exists public.customer_addresses (
    id uuid primary key default gen_random_uuid(),
    customer_id uuid not null references public.customers(id) on delete cascade,
    address_type text not null default 'shipping', -- 'shipping' or 'billing'
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean default false
);

-- Orders Table
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
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
    updated_at timestamptz default now(),
    unique(company_id, external_order_id)
);

-- Order Line Items Table
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null, -- in cents
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text,
    unique(order_id, external_line_item_id)
);

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
    unique(company_id, name)
);

-- Integrations Table
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

-- Webhook Events Table
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    processed_at timestamptz default now(),
    unique(integration_id, webhook_id)
);

-- AI Tables (Conversations and Messages)
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

-- Audit & Job Tables
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);

-- =============================================
-- ===     ROW-LEVEL SECURITY (RLS)          ===
-- =============================================

-- Disable RLS for admin-only tables
alter table public.companies disable row level security;
alter table public.company_settings disable row level security;
alter table public.users disable row level security;

-- Enable RLS for all other public tables
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.customers enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;

-- === POLICIES ===

-- Policies for tables with direct company_id
create policy "Allow full access based on company_id" on public.products for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.product_variants for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.customers for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.orders for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.order_line_items for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.audit_log for all using (company_id = get_current_company_id());
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id());

-- Policies for tables with indirect company_id or user_id
create policy "Allow access to own conversations" on public.conversations for all using (user_id = auth.uid());
create policy "Allow access to own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid());
create policy "Allow access to own webhook events" on public.webhook_events for all using ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id());

-- Corrected Policy for customer_addresses
create policy "Allow full access based on customer's company" on public.customer_addresses for all using (
    (select company_id from public.customers where id = customer_addresses.customer_id) = get_current_company_id()
);


-- =============================================
-- ===         DB FUNCTIONS & TRIGGERS       ===
-- =============================================

-- Creates a new company and assigns the user to it on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from metadata
  user_company_name := new.raw_app_meta_data ->> 'company_name';

  -- Create a new company
  insert into public.companies (name)
  values (coalesce(user_company_name, 'My Company'))
  returning id into new_company_id;

  -- Insert into our public users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  -- This makes it available in JWT claims
  update auth.users
  set raw_app_meta_data = jsonb_set(
      raw_app_meta_data,
      '{company_id}',
      to_jsonb(new_company_id)
  ) || jsonb_set(
      raw_app_meta_data,
      '{role}',
      to_jsonb('Owner'::text)
  )
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger for new user signup
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to record a sale and update inventory atomically
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
    v_line_item jsonb;
    v_variant_id uuid;
    v_cost_at_time integer;
    v_product_name text;
    v_variant_title text;
begin
    -- Find or create customer
    insert into public.customers (company_id, email, customer_name)
    values (p_company_id, p_order_payload ->> 'customer_email', p_order_payload ->> 'customer_name')
    on conflict (company_id, email) do update set customer_name = excluded.customer_name
    returning id into v_customer_id;
    
    -- Insert the order
    insert into public.orders (
        company_id, customer_id, order_number, external_order_id,
        financial_status, fulfillment_status, currency, subtotal,
        total_tax, total_shipping, total_discounts, total_amount, source_platform
    )
    values (
        p_company_id, v_customer_id, p_order_payload ->> 'order_number', p_order_payload ->> 'external_order_id',
        p_order_payload ->> 'financial_status', p_order_payload ->> 'fulfillment_status', p_order_payload ->> 'currency',
        (p_order_payload ->> 'subtotal')::integer, (p_order_payload ->> 'total_tax')::integer, 
        (p_order_payload ->> 'total_shipping')::integer, (p_order_payload ->> 'total_discounts')::integer,
        (p_order_payload ->> 'total_amount')::integer, p_platform
    )
    on conflict (company_id, external_order_id) do nothing -- or do update set ...
    returning id into v_order_id;
    
    if v_order_id is null then
      -- Order already exists, so we don't process its line items
      return;
    end if;

    -- Loop through line items and update inventory
    for v_line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
    loop
        -- Find the variant_id based on SKU
        select id, cost, p.title, pv.title into v_variant_id, v_cost_at_time, v_product_name, v_variant_title
        from public.product_variants pv
        join public.products p on p.id = pv.product_id
        where pv.company_id = p_company_id and pv.sku = (v_line_item ->> 'sku');
        
        -- Insert line item
        insert into public.order_line_items (
            order_id, company_id, variant_id, product_name, variant_title, sku, 
            quantity, price, cost_at_time, external_line_item_id
        )
        values (
            v_order_id, p_company_id, v_variant_id, 
            coalesce(v_product_name, v_line_item ->> 'name'), 
            v_variant_title,
            v_line_item ->> 'sku', (v_line_item ->> 'quantity')::integer, 
            (v_line_item ->> 'price')::integer, v_cost_at_time, v_line_item ->> 'external_line_item_id'
        );

        -- Update inventory if variant is found
        if v_variant_id is not null then
            update public.product_variants
            set inventory_quantity = inventory_quantity - (v_line_item ->> 'quantity')::integer
            where id = v_variant_id;
        end if;
    end loop;
end;
$$;


-- Function to update inventory and create a ledger entry
create or replace function public.update_inventory_and_log(
    p_company_id uuid,
    p_variant_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid default null,
    p_notes text default null
)
returns integer
language plpgsql
security definer
as $$
declare
    v_new_quantity integer;
begin
    -- Update the inventory quantity
    update public.product_variants
    set inventory_quantity = inventory_quantity + p_quantity_change
    where id = p_variant_id and company_id = p_company_id
    returning inventory_quantity into v_new_quantity;
    
    -- Insert into the ledger
    insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    values (p_company_id, p_variant_id, p_change_type, p_quantity_change, v_new_quantity, p_related_id, p_notes);
    
    return v_new_quantity;
end;
$$;

-- Trigger to log inventory changes on order line item insertion
create or replace function public.log_sale_inventory_change()
returns trigger
language plpgsql
as $$
begin
    if new.variant_id is not null then
        perform public.update_inventory_and_log(
            new.company_id,
            new.variant_id,
            -new.quantity,
            'sale',
            new.order_id
        );
    end if;
    return new;
end;
$$;

-- Since the record_order_from_platform function now handles inventory updates manually
-- we drop the trigger to prevent double-counting.
drop trigger if exists on_order_line_item_insert on public.order_line_items;

-- Trigger to update product variant timestamp
create or replace function public.update_variant_timestamp()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger on_variant_update
  before update on public.product_variants
  for each row execute procedure public.update_variant_timestamp();

-- Trigger to update product timestamp
create or replace function public.update_product_timestamp()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger on_product_update
  before update on public.products
  for each row execute procedure public.update_product_timestamp();

-- Function for a user to remove another user from their company
create or replace function public.remove_user_from_company(
    p_user_id uuid,
    p_company_id uuid,
    p_performing_user_id uuid
)
returns void
language plpgsql
security definer
as $$
declare
    v_performing_user_role text;
begin
    -- Check if the performing user is the owner
    select role into v_performing_user_role
    from public.users
    where id = p_performing_user_id and company_id = p_company_id;
    
    if v_performing_user_role <> 'Owner' then
        raise exception 'Only the company owner can remove users.';
    end if;
    
    -- Prevent owner from removing themselves
    if p_user_id = p_performing_user_id then
        raise exception 'Owner cannot remove themselves from the company.';
    end if;

    -- Soft delete the user from the public.users table
    update public.users
    set deleted_at = now()
    where id = p_user_id and company_id = p_company_id;
    
    -- Remove the user from the company in auth.users metadata
    update auth.users
    set raw_app_meta_data = raw_app_meta_data - 'company_id' - 'role'
    where id = p_user_id;
end;
$$;

-- Function for the owner to update another user's role
create or replace function public.update_user_role_in_company(
    p_user_id uuid,
    p_company_id uuid,
    p_new_role text
)
returns void
language plpgsql
security definer
as $$
begin
    -- This function should be callable only by the company owner.
    -- The RLS policy on this function (or the table it modifies) would enforce this.
    -- For simplicity, we assume the caller is authorized.

    -- Update the role in public.users
    update public.users
    set role = p_new_role
    where id = p_user_id and company_id = p_company_id;
    
    -- Update the role in auth.users metadata for JWT claims
    update auth.users
    set raw_app_meta_data = jsonb_set(
        raw_app_meta_data,
        '{role}',
        to_jsonb(p_new_role)
    )
    where id = p_user_id;
end;
$$;


-- =============================================
-- === VIEWS FOR PERFORMANCE & REPORTING     ===
-- =============================================

-- A view to unify product and variant data for easy display
drop view if exists public.product_variants_with_details;
create or replace view public.product_variants_with_details as
select
  pv.id,
  pv.product_id,
  pv.company_id,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  pv.sku,
  pv.title,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.created_at,
  pv.updated_at
from public.product_variants pv
join public.products p on pv.product_id = p.id
where pv.company_id = p.company_id;

-- Seed initial data for a new user
-- This is a sample function and might need adjustment based on final demo data strategy.
create or replace function public.seed_initial_data(p_company_id uuid)
returns void
language plpgsql
as $$
begin
  -- Seeding logic can be added here if needed for new signups.
  -- For now, it's empty as data comes from imports/integrations.
end;
$$;

commit;
