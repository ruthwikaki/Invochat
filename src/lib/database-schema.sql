
-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema extensions;

-- Enable the "plpgsql" language
create extension if not exists plpgsql with schema extensions;

-- #################################################################
-- #############           CORE TABLES             #################
-- #################################################################

-- Table to store companies
create table if not exists public.companies (
    id uuid not null primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamp with time zone not null default now()
);

-- Table to map users to companies with specific roles
create table if not exists public.users (
    id uuid not null primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role text not null default 'member'::text check (role in ('owner', 'admin', 'member')),
    deleted_at timestamp with time zone,
    created_at timestamp with time zone default now()
);

-- Table for company-specific settings
create table if not exists public.company_settings (
    company_id uuid not null primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 1000,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    currency text default 'USD'::text,
    timezone text default 'UTC'::text,
    tax_rate numeric default 0,
    custom_rules jsonb,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone,
    subscription_status text default 'trial'::text,
    subscription_plan text default 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5
);

-- Table for suppliers/vendors
create table if not exists public.suppliers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone not null default now(),
    unique(company_id, name)
);

-- Table for products (parent of variants)
create table if not exists public.products (
    id uuid not null primary key default uuid_generate_v4(),
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
    updated_at timestamp with time zone
);
alter table public.products add constraint products_company_id_external_product_id_key unique (company_id, external_product_id);


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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer not null default 0,
    external_variant_id text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone,
    weight numeric,
    weight_unit text
);
alter table public.product_variants add constraint product_variants_company_id_external_variant_id_key unique (company_id, external_variant_id);
alter table public.product_variants add constraint product_variants_company_id_sku_key unique (company_id, sku);


-- Table for customers
create table if not exists public.customers (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text,
    email text,
    total_orders integer default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone default now()
);

-- Table for customer addresses
create table if not exists public.customer_addresses (
    id uuid not null primary key default gen_random_uuid(),
    customer_id uuid not null references public.customers(id) on delete cascade,
    address_type text not null default 'shipping'::text,
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

-- Table for orders
create table if not exists public.orders (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id),
    status text not null default 'pending'::text,
    financial_status text default 'pending'::text,
    fulfillment_status text default 'unfulfilled'::text,
    currency text default 'USD'::text,
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone
);
alter table public.orders add constraint orders_company_id_external_order_id_key unique (company_id, external_order_id);


-- Table for order line items
create table if not exists public.order_line_items (
    id uuid not null primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    product_id uuid references public.products(id) on delete set null,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    fulfillment_status text default 'unfulfilled'::text,
    requires_shipping boolean default true,
    external_line_item_id text
);

-- Table for chat conversations
create table if not exists public.conversations (
    id uuid not null primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamp with time zone default now(),
    last_accessed_at timestamp with time zone default now(),
    is_starred boolean default false
);

-- Table for chat messages
create table if not exists public.messages (
    id uuid not null primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamp with time zone default now(),
    is_error boolean default false
);

-- Table for integrations
create table if not exists public.integrations (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone
);

-- Table for audit logs
create table if not exists public.audit_log (
    id bigserial primary key,
    user_id uuid references auth.users(id) on delete set null,
    company_id uuid references public.companies(id) on delete cascade,
    action text not null,
    details jsonb,
    created_at timestamp with time zone default now()
);

-- Table for inventory ledger
create table if not exists public.inventory_ledger (
    id uuid not null primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamp with time zone not null default now()
);

-- Table for export jobs
create table if not exists public.export_jobs (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending',
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone not null default now()
);

-- Table for sales channel fees
create table if not exists public.channel_fees (
    id uuid not null primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone,
    unique(company_id, channel_name)
);

-- Drop the incorrect table if it exists
drop table if exists public.webhook_events;

-- Corrected webhook_events table
create table if not exists public.webhook_events (
    id uuid not null primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamp with time zone default now()
);
create index if not exists webhook_events_integration_id_webhook_id_idx on public.webhook_events(integration_id, webhook_id);


-- #################################################################
-- #############        FUNCTIONS & TRIGGERS       #################
-- #################################################################

-- Function to get the current user's company_id
create or replace function public.get_current_company_id()
returns uuid
language plpgsql
security definer
as $$
declare
    _company_id uuid;
begin
    select raw_app_meta_data->>'company_id' into _company_id from auth.users where id = auth.uid();
    return _company_id;
end;
$$;

-- Function to handle new user signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
    _company_id uuid;
begin
    -- Create a new company for the user
    insert into public.companies (name)
    values (new.raw_user_meta_data->>'company_name')
    returning id into _company_id;

    -- Insert into our public users table
    insert into public.users (id, company_id, email, role)
    values (new.id, _company_id, new.email, 'owner');

    -- Update the user's app_metadata with the new company_id
    update auth.users
    set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', _company_id, 'role', 'owner')
    where id = new.id;
    
    return new;
end;
$$;

-- Trigger for new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();


-- Function to record an order from a platform
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_platform text,
    p_order_payload jsonb
)
returns void
language plpgsql
as $$
declare
    _customer_id uuid;
    _order_id uuid;
    line_item jsonb;
    _variant_id uuid;
    _product_id uuid;
begin
    -- Find or create customer
    select id into _customer_id
    from public.customers
    where company_id = p_company_id and email = (p_order_payload->'customer'->>'email');

    if _customer_id is null then
        insert into public.customers (company_id, email, customer_name)
        values (p_company_id, p_order_payload->'customer'->>'email', coalesce(p_order_payload->'customer'->>'first_name', '') || ' ' || coalesce(p_order_payload->'customer'->>'last_name', ''))
        returning id into _customer_id;
    end if;

    -- Insert or update order
    insert into public.orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, total_amount, source_platform, created_at, updated_at)
    values (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'id',
        _customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz,
        (p_order_payload->>'updated_at')::timestamptz
    )
    on conflict (company_id, external_order_id) do update set
        financial_status = excluded.financial_status,
        fulfillment_status = excluded.fulfillment_status,
        updated_at = excluded.updated_at
    returning id into _order_id;

    -- Process line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find variant and product by SKU
        select pv.id, pv.product_id into _variant_id, _product_id
        from public.product_variants pv
        where pv.company_id = p_company_id and pv.sku = (line_item->>'sku');
        
        insert into public.order_line_items (order_id, company_id, variant_id, product_id, sku, product_name, variant_title, quantity, price, external_line_item_id)
        values (
            _order_id,
            p_company_id,
            _variant_id,
            _product_id,
            line_item->>'sku',
            line_item->>'name',
            line_item->>'variant_title',
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100,
            line_item->>'id'
        )
        on conflict do nothing;

    end loop;
end;
$$;


-- #################################################################
-- #############        ROW LEVEL SECURITY         #################
-- #################################################################

-- Enable RLS for all tables
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.audit_log enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.webhook_events enable row level security;

-- Drop existing policies to prevent errors on re-run
drop policy if exists "allow_all_for_service_role" on public.companies;
drop policy if exists "allow_read_for_user_company" on public.companies;
drop policy if exists "allow_all_for_service_role" on public.users;
drop policy if exists "allow_read_for_user_company" on public.users;
drop policy if exists "allow_all_for_user_company" on public.company_settings;
drop policy if exists "allow_all_for_user_company" on public.suppliers;
drop policy if exists "allow_all_for_user_company" on public.products;
drop policy if exists "allow_all_for_user_company" on public.product_variants;
drop policy if exists "allow_all_for_user_company" on public.customers;
drop policy if exists "allow_read_based_on_customer" on public.customer_addresses;
drop policy if exists "allow_all_for_user_company" on public.orders;
drop policy if exists "allow_all_for_user_company" on public.order_line_items;
drop policy if exists "allow_all_for_owner" on public.conversations;
drop policy if exists "allow_all_for_owner" on public.messages;
drop policy if exists "allow_all_for_user_company" on public.integrations;
drop policy if exists "allow_all_for_user_company" on public.audit_log;
drop policy if exists "allow_all_for_user_company" on public.inventory_ledger;
drop policy if exists "allow_all_for_owner" on public.export_jobs;
drop policy if exists "allow_all_for_user_company" on public.channel_fees;
drop policy if exists "allow_all_for_user_company" on public.webhook_events;

-- Policies for companies
create policy "allow_all_for_service_role" on public.companies for all using (true);
create policy "allow_read_for_user_company" on public.companies for select using (id = get_current_company_id());

-- Policies for users (company mapping)
create policy "allow_all_for_service_role" on public.users for all using (true);
create policy "allow_read_for_user_company" on public.users for select using (company_id = get_current_company_id());

-- Generic "allow all for user's company" policy for most tables
create policy "allow_all_for_user_company" on public.company_settings for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.suppliers for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.products for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.product_variants for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.customers for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.orders for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.order_line_items for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.integrations for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.audit_log for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.inventory_ledger for all using (company_id = get_current_company_id());
create policy "allow_all_for_user_company" on public.channel_fees for all using (company_id = get_current_company_id());

-- Policies for conversations and messages (user-specific)
create policy "allow_all_for_owner" on public.conversations for all using (user_id = auth.uid());
create policy "allow_all_for_owner" on public.messages for all using (company_id = get_current_company_id() and conversation_id in (select id from public.conversations where user_id = auth.uid()));

-- Policies for export jobs (user-specific)
create policy "allow_all_for_owner" on public.export_jobs for all using (requested_by_user_id = auth.uid());

-- Policy for customer_addresses (join to customers)
create policy "allow_read_based_on_customer" on public.customer_addresses for select
    using ((select company_id from public.customers c where c.id = customer_id) = get_current_company_id());
    
-- Policy for webhook_events (join to integrations)
create policy "allow_all_for_user_company" on public.webhook_events for all
    using ((select company_id from public.integrations i where i.id = integration_id) = get_current_company_id());

-- Final command to make functions callable by authenticated users
grant execute on function public.get_current_company_id to authenticated;
grant execute on function public.record_order_from_platform to authenticated;

