
-- ### Supabase Custom Claims and Security Functions ###
-- These functions are used to get the current user's role and company ID from their JWT claims.
create or replace function public.get_current_user_role()
returns text
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '')::text;
$$;
comment on function public.get_current_user_role() is 'Returns the role of the currently authenticated user from their JWT claims.';

create or replace function public.get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
comment on function public.get_current_company_id() is 'Returns the company_id of the currently authenticated user from their JWT claims.';


-- ### Table: companies ###
-- Stores basic information about each company tenant.
drop policy if exists "Allow full access based on company_id" on public.companies;
drop policy if exists "Enable read access for all users" on public.companies;
drop table if exists public.companies cascade;
create table public.companies (
    id uuid not null default gen_random_uuid(),
    name text not null,
    created_at timestamptz not null default now(),
    deleted_at timestamptz null,
    constraint companies_pkey primary key (id)
);
alter table public.companies enable row level security;
create policy "Allow full access based on company_id" on public.companies for all using (id = get_current_company_id()) with check (id = get_current_company_id());


-- ### Table: users ###
-- Maps Supabase auth users to companies and roles.
drop policy if exists "Allow users to view their own company users" on public.users;
drop table if exists public.users cascade;
create table public.users (
    id uuid not null,
    company_id uuid not null,
    email text,
    role text default 'Member'::text,
    deleted_at timestamptz null,
    created_at timestamptz default now(),
    constraint users_pkey primary key (id),
    constraint users_id_fkey foreign key (id) references auth.users(id) on delete cascade,
    constraint users_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
comment on column public.users.id is 'Matches auth.users.id';
comment on column public.users.role is 'Can be Owner, Admin, or Member';
alter table public.users enable row level security;
create policy "Allow users to view their own company users" on public.users for select using (company_id = get_current_company_id());


-- ### Table: company_settings ###
-- Stores business rules and settings for each company.
drop policy if exists "Allow full access based on company_id" on public.company_settings;
drop table if exists public.company_settings cascade;
create table public.company_settings (
    company_id uuid not null,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000, -- in cents
    predictive_stock_days integer not null default 7,
    promo_sales_lift_multiplier real not null default 2.5,
    timezone text default 'UTC'::text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    constraint company_settings_pkey primary key (company_id),
    constraint company_settings_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.company_settings enable row level security;
create policy "Allow full access based on company_id" on public.company_settings for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: suppliers ###
drop policy if exists "Allow full access based on company_id" on public.suppliers;
drop table if exists public.suppliers cascade;
create table public.suppliers (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    deleted_at timestamptz null,
    created_at timestamptz not null default now(),
    constraint suppliers_pkey primary key (id),
    constraint suppliers_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.suppliers enable row level security;
create policy "Allow full access based on company_id" on public.suppliers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: products & variants ###
drop policy if exists "Allow full access to products based on company_id" on public.products;
drop table if exists public.products cascade;
create table public.products (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    deleted_at timestamptz null,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    constraint products_pkey primary key (id),
    constraint products_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.products enable row level security;
create policy "Allow full access to products based on company_id" on public.products for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create index products_company_id_external_product_id_idx on public.products using btree (company_id, external_product_id);


drop policy if exists "Allow full access to variants based on company_id" on public.product_variants;
drop table if exists public.product_variants cascade;
create table public.product_variants (
    id uuid not null default gen_random_uuid(),
    product_id uuid not null,
    company_id uuid not null,
    supplier_id uuid null,
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
    reorder_point integer,
    reorder_quantity integer,
    lead_time_days integer,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    constraint product_variants_pkey primary key (id),
    constraint product_variants_product_id_fkey foreign key (product_id) references public.products(id) on delete cascade,
    constraint product_variants_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint product_variants_supplier_id_fkey foreign key (supplier_id) references public.suppliers(id) on delete set null
);
alter table public.product_variants enable row level security;
create policy "Allow full access to variants based on company_id" on public.product_variants for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create index product_variants_company_id_sku_idx on public.product_variants using btree (company_id, sku);
create index product_variants_company_id_external_variant_id_idx on public.product_variants using btree (company_id, external_variant_id);


-- ### Table: customers ###
drop policy if exists "Allow full access to customers based on company_id" on public.customers;
drop table if exists public.customers cascade;
create table public.customers (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    customer_name text not null,
    email text,
    total_orders integer default 0,
    total_spent integer default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    constraint customers_pkey primary key (id),
    constraint customers_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.customers enable row level security;
create policy "Allow full access to customers based on company_id" on public.customers for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: orders & line items ###
drop policy if exists "Allow full access to orders based on company_id" on public.orders;
drop table if exists public.orders cascade;
create table public.orders (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    order_number text not null,
    external_order_id text,
    customer_id uuid,
    financial_status text default 'pending'::text,
    fulfillment_status text default 'unfulfilled'::text,
    currency text default 'USD'::text,
    subtotal integer not null default 0,
    total_tax integer default 0,
    total_shipping integer default 0,
    total_discounts integer default 0,
    total_amount integer not null,
    source_platform text,
    tags text[],
    notes text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    constraint orders_pkey primary key (id),
    constraint orders_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint orders_customer_id_fkey foreign key (customer_id) references public.customers(id) on delete set null
);
alter table public.orders enable row level security;
create policy "Allow full access to orders based on company_id" on public.orders for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());
create index orders_company_id_created_at_idx on public.orders using btree (company_id, created_at desc);

drop policy if exists "Allow full access to line items based on company_id" on public.order_line_items;
drop table if exists public.order_line_items cascade;
create table public.order_line_items (
    id uuid not null default gen_random_uuid(),
    order_id uuid not null,
    variant_id uuid,
    company_id uuid not null,
    product_name text not null,
    variant_title text,
    sku text,
    quantity integer not null,
    price integer not null,
    total_discount integer default 0,
    tax_amount integer default 0,
    cost_at_time integer,
    external_line_item_id text,
    constraint order_line_items_pkey primary key (id),
    constraint order_line_items_order_id_fkey foreign key (order_id) references public.orders(id) on delete cascade,
    constraint order_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants(id) on delete set null,
    constraint order_line_items_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.order_line_items enable row level security;
create policy "Allow full access to line items based on company_id" on public.order_line_items for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: inventory_ledger ###
drop policy if exists "Allow full access based on company_id" on public.inventory_ledger;
drop table if exists public.inventory_ledger cascade;
create table public.inventory_ledger (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    variant_id uuid not null,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now(),
    constraint inventory_ledger_pkey primary key (id),
    constraint inventory_ledger_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint inventory_ledger_variant_id_fkey foreign key (variant_id) references public.product_variants(id) on delete cascade
);
alter table public.inventory_ledger enable row level security;
create policy "Allow full access based on company_id" on public.inventory_ledger for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: integrations ###
drop policy if exists "Allow full access based on company_id" on public.integrations;
drop table if exists public.integrations cascade;
create table public.integrations (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    constraint integrations_pkey primary key (id),
    constraint integrations_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint integrations_company_id_platform_key unique (company_id, platform)
);
alter table public.integrations enable row level security;
create policy "Allow full access based on company_id" on public.integrations for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: channel_fees ###
drop policy if exists "Allow full access based on company_id" on public.channel_fees;
drop table if exists public.channel_fees cascade;
create table public.channel_fees (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee integer not null, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    constraint channel_fees_pkey primary key (id),
    constraint channel_fees_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint channel_fees_company_id_channel_name_key unique (company_id, channel_name)
);
alter table public.channel_fees enable row level security;
create policy "Allow full access based on company_id" on public.channel_fees for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: webhook_events (for replay protection) ###
drop policy if exists "Allow insert access to webhooks" on public.webhook_events;
drop table if exists public.webhook_events cascade;
create table public.webhook_events (
    id uuid not null default gen_random_uuid(),
    integration_id uuid not null,
    webhook_id text not null,
    processed_at timestamptz default now(),
    created_at timestamptz default now(),
    constraint webhook_events_pkey primary key (id),
    constraint webhook_events_integration_id_fkey foreign key (integration_id) references public.integrations(id) on delete cascade,
    constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id)
);
alter table public.webhook_events enable row level security;
create policy "Allow insert access to webhooks" on public.webhook_events for insert with check (true);


-- ### Table: conversations and messages ###
drop policy if exists "Allow full access based on user_id" on public.conversations;
drop table if exists public.conversations cascade;
create table public.conversations (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    company_id uuid not null,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false,
    constraint conversations_pkey primary key (id),
    constraint conversations_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade,
    constraint conversations_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.conversations enable row level security;
create policy "Allow full access based on user_id" on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Allow full access based on company_id" on public.messages;
drop table if exists public.messages cascade;
create table public.messages (
    id uuid not null default gen_random_uuid(),
    conversation_id uuid not null,
    company_id uuid not null,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now(),
    constraint messages_pkey primary key (id),
    constraint messages_conversation_id_fkey foreign key (conversation_id) references public.conversations(id) on delete cascade,
    constraint messages_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.messages enable row level security;
create policy "Allow full access based on company_id" on public.messages for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: audit_log ###
drop policy if exists "Allow read access based on company_id" on public.audit_log;
drop table if exists public.audit_log cascade;
create table public.audit_log (
    id bigint generated by default as identity,
    company_id uuid,
    user_id uuid,
    action text not null,
    details jsonb,
    created_at timestamptz default now(),
    constraint audit_log_pkey primary key (id),
    constraint audit_log_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint audit_log_user_id_fkey foreign key (user_id) references auth.users(id) on delete set null
);
alter table public.audit_log enable row level security;
create policy "Allow read access based on company_id" on public.audit_log for select using (company_id = get_current_company_id());


-- ### Table: user_feedback ###
drop policy if exists "Allow full access based on company_id" on public.user_feedback;
drop table if exists public.user_feedback cascade;
create table public.user_feedback (
    id uuid not null default gen_random_uuid(),
    user_id uuid not null,
    company_id uuid not null,
    subject_id text not null,
    subject_type text not null,
    feedback text not null,
    created_at timestamptz default now(),
    constraint user_feedback_pkey primary key (id),
    constraint user_feedback_user_id_fkey foreign key (user_id) references auth.users(id) on delete cascade,
    constraint user_feedback_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade
);
alter table public.user_feedback enable row level security;
create policy "Allow full access based on company_id" on public.user_feedback for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());


-- ### Table: export_jobs ###
drop policy if exists "Allow access based on company" on public.export_jobs;
drop table if exists public.export_jobs cascade;
create table public.export_jobs (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    requested_by_user_id uuid not null,
    status text not null default 'pending'::text,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    constraint export_jobs_pkey primary key (id),
    constraint export_jobs_company_id_fkey foreign key (company_id) references public.companies(id) on delete cascade,
    constraint export_jobs_requested_by_user_id_fkey foreign key (requested_by_user_id) references auth.users(id) on delete cascade
);
alter table public.export_jobs enable row level security;
create policy "Allow access based on company" on public.export_jobs for all using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());



-- ### Triggers and Functions ###

-- Function to create a company and link it to the new user on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Insert a corresponding entry in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'user_role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the function on new user creation in auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to update a variant's quantity when the ledger is updated
create or replace function public.update_variant_quantity_from_ledger()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.product_variants
  set inventory_quantity = new_quantity
  where id = new.variant_id and company_id = new.company_id;
  return new;
end;
$$;

-- Trigger for inventory ledger updates
drop trigger if exists on_inventory_ledger_insert on public.inventory_ledger;
create trigger on_inventory_ledger_insert
  after insert on public.inventory_ledger
  for each row execute procedure public.update_variant_quantity_from_ledger();


-- Function to record an order from a platform
drop function if exists public.record_order_from_platform(uuid, text, jsonb);
create or replace function public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_variant_id uuid;
    v_customer_email text;
    v_customer_name text;
    line_item jsonb;
    v_sku text;
    v_quantity int;
begin
    -- Extract customer details
    if p_platform = 'shopify' then
        v_customer_email := p_order_payload->'customer'->>'email';
        v_customer_name := p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name';
    elsif p_platform = 'woocommerce' then
        v_customer_email := p_order_payload->'billing'->>'email';
        v_customer_name := p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name';
    end if;

    -- Find or create customer
    if v_customer_email is not null then
        select id into v_customer_id from customers where email = v_customer_email and company_id = p_company_id;
        if v_customer_id is null then
            insert into customers (company_id, customer_name, email)
            values (p_company_id, v_customer_name, v_customer_email)
            returning id into v_customer_id;
        end if;
    end if;

    -- Insert order
    insert into orders (company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status, total_amount, source_platform, created_at)
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

    -- Loop through line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := line_item->>'sku';
        v_quantity := (line_item->>'quantity')::int;

        -- Find variant
        select id into v_variant_id from product_variants where sku = v_sku and company_id = p_company_id;

        -- Insert line item
        insert into order_line_items (order_id, variant_id, company_id, product_name, sku, quantity, price)
        values (
            v_order_id,
            v_variant_id,
            p_company_id,
            line_item->>'name',
            v_sku,
            v_quantity,
            (line_item->>'price')::numeric * 100
        );

        -- Update inventory ledger if variant found
        if v_variant_id is not null then
            insert into inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            select
                p_company_id,
                v_variant_id,
                'sale',
                -v_quantity,
                pv.inventory_quantity - v_quantity,
                v_order_id,
                'Sale from ' || p_platform
            from product_variants pv where pv.id = v_variant_id;
        end if;
    end loop;
end;
$$;
comment on function public.record_order_from_platform is 'Standardizes and records an order from a connected e-commerce platform, updating inventory and customer records transactionally.';
