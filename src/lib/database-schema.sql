
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Enable the pgcrypto extension for cryptographic functions
create extension if not exists "pgcrypto" with schema extensions;

-- #################################################################
-- #############           CORE TABLES             #################
-- #################################################################

-- Table to store company information
create table if not exists public.companies (
    id uuid not null primary key default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);
alter table public.companies enable row level security;
drop policy if exists "Allow full access based on company_id" on public.companies;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());


-- Table to store application users and their company affiliation
create table if not exists public.users (
    id uuid not null primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null default 'member' check (role in ('owner', 'admin', 'member')),
    email text,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.users enable row level security;
drop policy if exists "Allow users to see themselves" on public.users;
create policy "Allow users to see themselves" on public.users for select using (id = auth.uid());
drop policy if exists "Allow users to see others in their company" on public.users;
create policy "Allow users to see others in their company" on public.users for select using (company_id = get_current_company_id());
drop policy if exists "Allow owners to update roles" on public.users;
create policy "Allow owners to update roles" on public.users for update using (get_current_user_role() = 'owner') with check (get_current_user_role() = 'owner');


-- Table for company-specific settings and business rules
create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    promo_sales_lift_multiplier real not null default 2.5,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric(5,4) default 0.0,
    subscription_status text default 'trial',
    subscription_plan text default 'starter',
    stripe_customer_id text,
    stripe_subscription_id text,
    subscription_expires_at timestamptz,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table public.company_settings enable row level security;
drop policy if exists "Allow access to settings for company members" on public.company_settings;
create policy "Allow access to settings for company members" on public.company_settings for all using (company_id = get_current_company_id());

-- Table for tracking sales channel specific fees for net margin calculations
create table if not exists public.channel_fees (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric(6,4) not null,
    fixed_fee integer not null default 0, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);
alter table public.channel_fees enable row level security;
drop policy if exists "Allow access for company members" on public.channel_fees;
create policy "Allow access for company members" on public.channel_fees for all using (company_id = get_current_company_id());


-- Table for suppliers/vendors
create table if not exists public.suppliers (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    deleted_at timestamptz,
    created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;
drop policy if exists "Allow access for company members" on public.suppliers;
create policy "Allow access for company members" on public.suppliers for all using (company_id = get_current_company_id());


-- Table for products (parent of variants)
create table if not exists public.products (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);
alter table public.products enable row level security;
drop policy if exists "Allow access for company members" on public.products;
create policy "Allow access for company members" on public.products for all using (company_id = get_current_company_id());

-- Table for product variants (SKUs)
create table if not exists public.product_variants (
    id uuid not null primary key default gen_random_uuid(),
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
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);
alter table public.product_variants enable row level security;
drop policy if exists "Allow access for company members" on public.product_variants;
create policy "Allow access for company members" on public.product_variants for all using (company_id = get_current_company_id());

-- Table for inventory lots
create table if not exists public.inventory_lots (
    id uuid not null primary key default gen_random_uuid(),
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    lot_number text,
    quantity integer not null,
    received_date date,
    expiration_date date,
    created_at timestamptz default now()
);
alter table public.inventory_lots enable row level security;
drop policy if exists "Allow access for company members" on public.inventory_lots;
create policy "Allow access for company members" on public.inventory_lots for all using (company_id = get_current_company_id());


-- Table for customers
create table if not exists public.customers (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent integer default 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);
alter table public.customers enable row level security;
drop policy if exists "Allow access for company members" on public.customers;
create policy "Allow access for company members" on public.customers for all using (company_id = get_current_company_id());


-- Table for sales orders
create table if not exists public.orders (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer not null default 0, -- in cents
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    notes text,
    cancelled_at timestamptz,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
alter table public.orders enable row level security;
drop policy if exists "Allow access for company members" on public.orders;
create policy "Allow access for company members" on public.orders for all using (company_id = get_current_company_id());


-- Table for line items within an order
create table if not exists public.order_line_items (
    id uuid not null primary key default gen_random_uuid(),
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
alter table public.order_line_items enable row level security;
drop policy if exists "Allow access for company members" on public.order_line_items;
create policy "Allow access for company members" on public.order_line_items for all using (company_id = get_current_company_id());


-- Audit trail for all inventory movements
create table if not exists public.inventory_ledger (
    id uuid not null primary key default gen_random_uuid(),
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
drop policy if exists "Allow access for company members" on public.inventory_ledger;
create policy "Allow access for company members" on public.inventory_ledger for all using (company_id = get_current_company_id());


-- Table for integrations with other platforms
create table if not exists public.integrations (
    id uuid not null primary key default gen_random_uuid(),
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
alter table public.integrations enable row level security;
drop policy if exists "Allow access for company members" on public.integrations;
create policy "Allow access for company members" on public.integrations for all using (company_id = get_current_company_id());


-- Table to prevent webhook replay attacks
create table if not exists public.webhook_events (
    id uuid not null primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now(),
    unique(webhook_id)
);
alter table public.webhook_events enable row level security;
drop policy if exists "Allow full access based on integration" on public.webhook_events;
create policy "Allow full access based on integration" on public.webhook_events for all using (
    integration_id in (select id from public.integrations where company_id = get_current_company_id())
);


-- Table for Chat Conversations
create table if not exists public.conversations (
    id uuid not null primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
alter table public.conversations enable row level security;
drop policy if exists "Allow access for conversation owner" on public.conversations;
create policy "Allow access for conversation owner" on public.conversations for all using (user_id = auth.uid());


-- Table for Chat Messages
create table if not exists public.messages (
    id uuid not null primary key default gen_random_uuid(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);
alter table public.messages enable row level security;
drop policy if exists "Allow access for message owner" on public.messages;
create policy "Allow access for message owner" on public.messages for all using (
    conversation_id in (select id from public.conversations where user_id = auth.uid())
);


-- Table for background data export jobs
create table if not exists public.export_jobs (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);
alter table public.export_jobs enable row level security;
drop policy if exists "Allow access for company members" on public.export_jobs;
create policy "Allow access for company members" on public.export_jobs for all using (company_id = get_current_company_id());

-- Table for storing user feedback on AI responses
create table if not exists public.user_feedback (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    subject_id text not null,
    subject_type text not null, -- e.g., 'anomaly_explanation', 'product_description'
    feedback text not null, -- 'helpful' or 'unhelpful'
    created_at timestamptz not null default now()
);
alter table public.user_feedback enable row level security;
drop policy if exists "Allow access for company members" on public.user_feedback;
create policy "Allow access for company members" on public.user_feedback for all using (company_id = get_current_company_id());


-- #################################################################
-- #############        INDEXES & VIEWS            #################
-- #################################################################

-- Indexes for performance
create index if not exists idx_orders_company_created on public.orders(company_id, created_at desc);
create index if not exists idx_variants_company_sku on public.product_variants(company_id, sku);
create index if not exists idx_variants_company_product_id on public.product_variants(company_id, product_id);
create index if not exists idx_ledger_company_variant on public.inventory_ledger(company_id, variant_id, created_at desc);

-- View for user-friendly inventory display
drop view if exists public.product_variants_with_details;
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


-- #################################################################
-- #############     FUNCTIONS & TRIGGERS          #################
-- #################################################################

-- Function to get the current user's company_id
create or replace function public.get_current_company_id()
returns uuid as $$
declare
    company_id_val uuid;
begin
    select id into company_id_val from public.companies where id = (select raw_app_meta_data->>'company_id' from auth.users where id = auth.uid())::uuid;
    return company_id_val;
end;
$$ language plpgsql security definer;

-- Function to get the current user's role
create or replace function public.get_current_user_role()
returns text as $$
begin
  return (select role from public.users where id = auth.uid());
end;
$$ language plpgsql security definer;

-- Function to handle new user setup
create or replace function public.handle_new_user()
returns trigger as $$
declare
  company_id_val uuid;
  user_role text;
begin
  -- If company_name is provided, create a new company and make the user its owner
  if new.raw_app_meta_data->>'company_name' is not null then
    insert into public.companies (name)
    values (new.raw_app_meta_data->>'company_name')
    returning id into company_id_val;
    user_role := 'owner';
  -- If company_id is provided (for invites), use it
  elsif new.raw_app_meta_data->>'company_id' is not null then
    company_id_val := (new.raw_app_meta_data->>'company_id')::uuid;
    user_role := 'member';
  end if;

  -- Insert into our public.users table
  insert into public.users (id, company_id, role, email)
  values (new.id, company_id_val, user_role, new.email);

  -- Update the user's app_metadata in auth.users
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_val, 'role', user_role)
  where id = new.id;

  return new;
end;
$$ language plpgsql security definer;

-- Trigger to call handle_new_user on new user creation
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();


-- Trigger function to update variant quantity from ledger
create or replace function public.update_variant_quantity_from_ledger()
returns trigger as $$
begin
  update public.product_variants
  set inventory_quantity = (
    select coalesce(sum(quantity_change), 0)
    from public.inventory_ledger
    where variant_id = new.variant_id
  )
  where id = new.variant_id;

  return new;
end;
$$ language plpgsql security definer;

-- Trigger to execute the function after a change in inventory_ledger
drop trigger if exists on_inventory_ledger_change on public.inventory_ledger;
create trigger on_inventory_ledger_change
  after insert on public.inventory_ledger
  for each row
  execute function public.update_variant_quantity_from_ledger();


-- Advanced function to record an order from any platform
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns void as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_customer_email text;
    v_customer_name text;
begin
    -- Extract customer info and find/create customer
    v_customer_email := p_order_payload->'customer'->>'email';
    v_customer_name := coalesce(
        p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
        v_customer_email
    );

    if v_customer_email is not null then
        select id into v_customer_id from public.customers where email = v_customer_email and company_id = p_company_id;
        if not found then
            insert into public.customers (company_id, customer_name, email)
            values (p_company_id, v_customer_name, v_customer_email)
            returning id into v_customer_id;
        end if;
    end if;

    -- Insert the main order record
    insert into public.orders (
        company_id, order_number, external_order_id, customer_id,
        financial_status, fulfillment_status, total_amount, source_platform, created_at
    )
    values (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    returning id into v_order_id;

    -- Loop through line items and record them
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the variant_id based on SKU
        select id into v_variant_id from public.product_variants
        where sku = line_item->>'sku' and company_id = p_company_id;

        -- If variant exists, record line item and update inventory
        if v_variant_id is not null then
            insert into public.order_line_items (
                order_id, variant_id, company_id, product_name, sku, quantity, price
            )
            values (
                v_order_id,
                v_variant_id,
                p_company_id,
                line_item->>'name',
                line_item->>'sku',
                (line_item->>'quantity')::integer,
                (line_item->>'price')::numeric * 100
            );

            -- Create inventory ledger entry for the sale
            insert into public.inventory_ledger (
                variant_id, company_id, change_type, quantity_change, related_id, notes
            )
            values (
                v_variant_id,
                p_company_id,
                'sale',
                -1 * (line_item->>'quantity')::integer,
                v_order_id,
                'Order #' || (p_order_payload->>'id')
            );
        else
            -- Optional: log a warning if a SKU from an order is not found in your system
            raise warning 'SKU % from order % not found in product_variants', line_item->>'sku', p_order_payload->>'id';
        end if;
    end loop;
end;
$$ language plpgsql security definer;


-- #################################################################
-- #############     RLS (ROW-LEVEL SECURITY)      #################
-- #################################################################

-- Enable RLS for all tables created above. Default-deny.
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.inventory_lots enable row level security;

-- Grant usage on the public schema to the authenticated role
grant usage on schema public to authenticated;

-- Grant select, insert, update, delete permissions to the authenticated role for all tables
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Grant execute permission on all functions to the authenticated role
grant execute on all functions in schema public to authenticated;

-- Note: The service_role bypasses RLS. The anon key has no rights by default.
-- All access is controlled by the policies defined above for the 'authenticated' role.
