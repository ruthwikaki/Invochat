
--
-- Types
--
create type public.user_role as enum ('Owner', 'Admin', 'Member');
--
-- Tables
--
create table public.companies (
    id uuid primary key not null default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

create table public.users(
    id uuid primary key references auth.users(id) on delete cascade not null,
    company_id uuid references public.companies(id) on delete cascade not null,
    email text,
    role user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);

create table public.company_settings (
  company_id uuid primary key references public.companies(id) on delete cascade not null,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  overstock_multiplier numeric not null default 3,
  high_value_threshold numeric not null default 1000.00,
  predictive_stock_days int not null default 7,
  currency text default 'USD',
  timezone text default 'UTC',
  tax_rate numeric default 0,
  promo_sales_lift_multiplier real not null default 2.5,
  custom_rules jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
comment on column public.company_settings.high_value_threshold is 'Cost threshold in cents to be considered a high-value item.';


create table public.suppliers (
    id uuid primary key not null default uuid_generate_v4(),
    company_id uuid references public.companies(id) on delete cascade not null,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    constraint unique_supplier_name unique (company_id, name)
);

create table public.inventory (
    id uuid primary key not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sku text not null,
    name text not null,
    category text,
    quantity int not null default 0,
    cost numeric not null default 0,
    price numeric,
    reorder_point int,
    last_sold_date date,
    supplier_id uuid references public.suppliers(id) on delete set null,
    barcode text,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity int,
    version int not null default 1,
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    created_at timestamptz default now(),
    updated_at timestamptz,
    constraint unique_sku_per_company unique(company_id, sku)
);
comment on column public.inventory.cost is 'Cost in cents';
comment on column public.inventory.price is 'Price in cents';

create table public.customers (
    id uuid primary key not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

create table public.sales (
    id uuid primary key not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sale_number text not null,
    customer_name text,
    customer_email text,
    total_amount numeric not null,
    payment_method text,
    notes text,
    external_id text, -- For linking to external platform orders
    created_at timestamptz default now()
);

create table public.sale_items (
    id uuid primary key not null default uuid_generate_v4(),
    sale_id uuid not null references public.sales(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.inventory(id),
    product_name text,
    sku text not null,
    quantity int not null,
    unit_price numeric not null,
    cost_at_time numeric
);

create table public.conversations (
    id uuid primary key not null default uuid_generate_v4(),
    user_id uuid not null references public.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);

create table public.messages (
    id uuid primary key not null default uuid_generate_v4(),
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

create table public.audit_log (
  id bigserial primary key,
  user_id uuid references public.users(id),
  company_id uuid references public.companies(id),
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);

create table public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.inventory(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., sale_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);

create table public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references public.users(id),
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

create table public.integrations (
  id uuid primary key not null default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  access_token text,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create table public.sync_state (
    integration_id uuid not null references public.integrations(id) on delete cascade,
    sync_type text not null,
    last_processed_cursor text,
    last_update timestamptz,
    primary key (integration_id, sync_type)
);

create table public.sync_logs (
    id uuid primary key not null default uuid_generate_v4(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    sync_type text,
    status text,
    records_synced int,
    error_message text,
    started_at timestamptz default now(),
    completed_at timestamptz
);

create table public.channel_fees (
    id uuid primary key not null default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);
comment on column public.channel_fees.fixed_fee is 'Fixed fee in cents';
--
-- Views
--
create or replace view public.company_dashboard_metrics as
select
    c.id as company_id,
    coalesce(sum(i.quantity * i.cost), 0) as inventory_value,
    count(distinct i.id) filter (where i.deleted_at is null) as total_skus,
    count(distinct i.id) filter (where i.deleted_at is null and i.quantity < i.reorder_point) as low_stock_count
from
    public.companies c
left join
    public.inventory i on c.id = i.company_id and i.deleted_at is null
group by
    c.id;

--
-- Functions
--
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  company_id uuid;
  user_role user_role;
begin
  -- Check if a company name is provided in metadata, create company if so
  if new.raw_app_meta_data->>'company_name' is not null then
    insert into public.companies (name)
    values (new.raw_app_meta_data->>'company_name')
    returning id into company_id;
    user_role := 'Owner';
  else
    -- If invited, the company_id should already be in the metadata
    company_id := (new.raw_app_meta_data->>'company_id')::uuid;
    user_role := (new.raw_app_meta_data->>'role')::user_role;
  end if;

  -- Insert into our public users table
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, new.email, user_role);

  -- Update the user's app_metadata in auth.users
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', user_role)
  where id = new.id;

  return new;
end;
$$;

create or replace function public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text
)
returns public.sales
language plpgsql
security definer
set search_path = public
as $$
declare
    v_sale_id uuid;
    v_new_sale_number text;
    v_total_amount numeric := 0;
    v_item record;
    v_inventory_item public.inventory;
    v_customer_id uuid;
begin
    -- Generate a unique sale number
    select 'SALE-' || to_char(now(), 'YYYYMMDD') || '-' || count(*) + 1
    into v_new_sale_number
    from sales
    where created_at >= date_trunc('day', now()) and company_id = p_company_id;

    -- Upsert customer and get ID
    if p_customer_email is not null and p_customer_email != '' then
        insert into public.customers (company_id, customer_name, email, first_order_date, total_orders, total_spent)
        values (p_company_id, p_customer_name, p_customer_email, now(), 1, 0)
        on conflict (company_id, email) do update
        set
            total_orders = customers.total_orders + 1,
            customer_name = coalesce(p_customer_name, customers.customer_name)
        returning id into v_customer_id;
    end if;

    -- Calculate total amount from items
    for v_item in select * from jsonb_to_recordset(p_sale_items) as x(product_id uuid, quantity int, unit_price numeric)
    loop
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    end loop;

    -- Update customer's total spent
    if v_customer_id is not null then
        update public.customers
        set total_spent = customers.total_spent + v_total_amount
        where id = v_customer_id;
    end if;

    -- Create the sale record
    insert into public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    values (p_company_id, v_new_sale_number, p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id)
    returning id into v_sale_id;

    -- Loop through items again to process inventory and create sale_items
    for v_item in select * from jsonb_to_recordset(p_sale_items) as x(product_id uuid, sku text, quantity int, unit_price numeric)
    loop
        -- Fetch current inventory details for the cost
        select * into v_inventory_item from public.inventory where id = v_item.product_id and company_id = p_company_id;

        -- Create sale item record
        insert into public.sale_items (sale_id, company_id, product_id, sku, quantity, unit_price, cost_at_time)
        values (v_sale_id, p_company_id, v_item.product_id, v_inventory_item.sku, v_item.quantity, v_item.unit_price, v_inventory_item.cost);

        -- Update inventory quantity and log the change
        update public.inventory
        set
            quantity = quantity - v_item.quantity,
            last_sold_date = current_date,
            version = version + 1
        where id = v_item.product_id and company_id = p_company_id;

        insert into public.inventory_ledger(company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        select p_company_id, v_item.product_id, 'sale', -v_item.quantity, i.quantity, v_sale_id
        from public.inventory i where i.id = v_item.product_id;
    end loop;

    -- Log the audit record
    insert into public.audit_log(company_id, user_id, action, details)
    values (p_company_id, p_user_id, 'sale_created', jsonb_build_object('sale_id', v_sale_id, 'total', v_total_amount));

    -- Return the newly created sale
    return (select * from public.sales where id = v_sale_id);
end;
$$;

create or replace function public.batch_upsert_costs(p_records jsonb, p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
declare
    rec record;
    v_supplier_id uuid;
begin
    for rec in select * from jsonb_to_recordset(p_records) as x(
        sku text,
        cost numeric,
        supplier_name text,
        reorder_point int,
        reorder_quantity int,
        lead_time_days int
    )
    loop
        if rec.supplier_name is not null then
            insert into public.suppliers (company_id, name)
            values (p_company_id, rec.supplier_name)
            on conflict (company_id, name) do update set name = excluded.name
            returning id into v_supplier_id;
        else
            v_supplier_id := null;
        end if;

        insert into public.inventory (company_id, sku, name, cost, supplier_id, reorder_point)
        values (p_company_id, rec.sku, 'Default Name for ' || rec.sku, rec.cost, v_supplier_id, rec.reorder_point)
        on conflict (company_id, sku) do update set
            cost = excluded.cost,
            supplier_id = coalesce(excluded.supplier_id, inventory.supplier_id),
            reorder_point = coalesce(excluded.reorder_point, inventory.reorder_point),
            updated_at = now();
    end loop;
end;
$$;


create or replace function public.batch_upsert_suppliers(p_records jsonb, p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
declare
    rec record;
begin
    for rec in select * from jsonb_to_recordset(p_records) as x(
        name text,
        email text,
        phone text,
        default_lead_time_days int,
        notes text
    )
    loop
        insert into public.suppliers(company_id, name, email, phone, default_lead_time_days, notes)
        values (p_company_id, rec.name, rec.email, rec.phone, rec.default_lead_time_days, rec.notes)
        on conflict (company_id, name) do update set
            email = excluded.email,
            phone = excluded.phone,
            default_lead_time_days = excluded.default_lead_time_days,
            notes = excluded.notes;
    end loop;
end;
$$;


create or replace function public.batch_import_sales(p_records jsonb, p_company_id uuid, p_user_id uuid)
returns void
language plpgsql
as $$
declare
    rec record;
    v_product_id uuid;
    v_sale_id uuid;
begin
    for rec in select * from jsonb_to_recordset(p_records) as x(
        order_date timestamptz,
        sku text,
        quantity int,
        unit_price numeric,
        cost_at_time numeric,
        customer_email text,
        order_id text
    )
    loop
        select id into v_product_id from public.inventory where sku = rec.sku and company_id = p_company_id;

        if v_product_id is not null then
            -- Create a minimal sale record
            insert into public.sales(company_id, sale_number, customer_email, total_amount, created_at, external_id)
            values (p_company_id, 'IMP-' || rec.order_id, rec.customer_email, rec.quantity * rec.unit_price, rec.order_date, rec.order_id)
            returning id into v_sale_id;

            -- Create sale item
            insert into public.sale_items(sale_id, company_id, product_id, sku, quantity, unit_price, cost_at_time)
            values (v_sale_id, p_company_id, v_product_id, rec.sku, rec.quantity, rec.unit_price, rec.cost_at_time);
        end if;
    end loop;
end;
$$;
--
-- Triggers
--
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

--
-- Stored Procedures for Reports/Analytics
--

-- Helper function to get settings with defaults
create or replace function get_company_settings(p_company_id uuid)
returns public.company_settings as $$
declare
    settings_rec public.company_settings;
begin
    select * into settings_rec from public.company_settings where company_id = p_company_id;
    if not found then
        return (p_company_id, 90, 3, 1000, 30, 7, 'USD', 'UTC', 0, null, now(), null, 2.5)::public.company_settings;
    end if;
    return settings_rec;
end;
$$ language plpgsql stable;


create or replace function public.get_distinct_categories(p_company_id uuid)
returns table(category text) as $$
begin
    return query
    select distinct i.category
    from public.inventory i
    where i.company_id = p_company_id and i.category is not null and i.deleted_at is null;
end;
$$ language plpgsql stable;

create or replace function public.get_alerts(
    p_company_id uuid,
    p_dead_stock_days int,
    p_fast_moving_days int,
    p_predictive_stock_days int
) returns table (
    id text,
    type text,
    title text,
    message text,
    severity text,
    "timestamp" timestamptz,
    metadata jsonb
)
language plpgsql
as $$
begin
    return query
    -- Low Stock Alerts
    select
        'low_stock_' || i.id as id,
        'low_stock' as type,
        'Low Stock Warning' as title,
        i.name || ' is running low on stock.' as message,
        'warning' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'reorderPoint', i.reorder_point
        ) as metadata
    from public.inventory i
    where i.company_id = p_company_id
      and i.quantity < i.reorder_point
      and i.deleted_at is null

    union all

    -- Dead Stock Alerts
    select
        'dead_stock_' || i.id as id,
        'dead_stock' as type,
        'Dead Stock Detected' as title,
        i.name || ' has not been sold in over ' || p_dead_stock_days || ' days.' as message,
        'critical' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'lastSoldDate', i.last_sold_date,
            'currentStock', i.quantity,
            'value', i.quantity * i.cost
        ) as metadata
    from public.inventory i
    where i.company_id = p_company_id
      and i.last_sold_date <= current_date - make_interval(days => p_dead_stock_days)
      and i.quantity > 0
      and i.deleted_at is null;
end;
$$;


create or replace function public.get_anomaly_insights(p_company_id uuid)
returns table (
    date date,
    anomaly_type text,
    daily_revenue numeric,
    avg_revenue numeric,
    daily_customers int,
    avg_customers int,
    deviation_percentage numeric
)
language plpgsql
as $$
begin
    return query
    with daily_stats as (
      select
        s.created_at::date as sale_date,
        sum(s.total_amount) as total_revenue,
        count(distinct s.customer_email) as total_customers
      from public.sales s
      where s.company_id = p_company_id
      group by 1
    ),
    stats_with_avg as (
      select
        *,
        avg(total_revenue) over (order by sale_date rows between 30 preceding and 1 preceding) as avg_30d_revenue,
        avg(total_customers) over (order by sale_date rows between 30 preceding and 1 preceding) as avg_30d_customers
      from daily_stats
    )
    select
      s.sale_date as date,
      'Revenue Anomaly' as anomaly_type,
      s.total_revenue as daily_revenue,
      s.avg_30d_revenue as avg_revenue,
      null::int as daily_customers,
      null::int as avg_customers,
      (s.total_revenue - s.avg_30d_revenue) / s.avg_30d_revenue * 100 as deviation_percentage
    from stats_with_avg s
    where s.avg_30d_revenue > 0 and abs((s.total_revenue - s.avg_30d_revenue) / s.avg_30d_revenue) > 0.5
    order by s.sale_date desc limit 5;
end;
$$;


create or replace function public.reconcile_inventory_from_integration(p_integration_id uuid)
returns void
language plpgsql
security definer
as $$
declare
    v_integration public.integrations;
    v_inventory_item record;
    v_quantity_diff int;
begin
    select * into v_integration from public.integrations where id = p_integration_id;

    if v_integration is null then
        raise exception 'Integration not found';
    end if;

    for v_inventory_item in
        select id, quantity, external_quantity
        from public.inventory
        where company_id = v_integration.company_id and source_platform = v_integration.platform and external_quantity is not null
    loop
        v_quantity_diff := v_inventory_item.external_quantity - v_inventory_item.quantity;
        if v_quantity_diff != 0 then
            update public.inventory
            set quantity = external_quantity
            where id = v_inventory_item.id;

            insert into public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, notes)
            values (v_integration.company_id, v_inventory_item.id, 'reconciliation', v_quantity_diff, v_inventory_item.external_quantity, 'Sync with ' || v_integration.platform);
        end if;
    end loop;
end;
$$;


-- Grant permissions
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all privileges on all tables in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all functions in schema public to postgres, anon, authenticated, service_role;
grant all privileges on all sequences in schema public to postgres, anon, authenticated, service_role;

alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

grant usage on schema auth to postgres, service_role;
grant select on auth.users to postgres, service_role;

-- RLS Policies
alter table public.companies enable row level security;
create policy "Users can only see their own company" on public.companies for select using (id = (select company_id from public.users where id = auth.uid()));

alter table public.users enable row level security;
create policy "Users can see other users in their company" on public.users for select using (company_id = (select company_id from public.users where id = auth.uid()));
create policy "Users can only update their own user record" on public.users for update using (id = auth.uid());

alter table public.company_settings enable row level security;
create policy "Users can manage settings for their own company" on public.company_settings for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.inventory enable row level security;
create policy "Users can manage inventory for their own company" on public.inventory for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.suppliers enable row level security;
create policy "Users can manage suppliers for their own company" on public.suppliers for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.customers enable row level security;
create policy "Users can manage customers for their own company" on public.customers for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.sales enable row level security;
create policy "Users can manage sales for their own company" on public.sales for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.sale_items enable row level security;
create policy "Users can manage sale_items for their own company" on public.sale_items for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.conversations enable row level security;
create policy "Users can only see their own conversations" on public.conversations for select using (user_id = auth.uid());
create policy "Users can only insert into their own conversations" on public.conversations for insert with check (user_id = auth.uid());

alter table public.messages enable row level security;
create policy "Users can see messages in their conversations" on public.messages for select using (conversation_id in (select id from public.conversations where user_id = auth.uid()));
create policy "Users can only insert messages into their own conversations" on public.messages for insert with check (conversation_id in (select id from public.conversations where user_id = auth.uid()));

alter table public.audit_log enable row level security;
create policy "Users can only see audit logs for their own company" on public.audit_log for select using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.inventory_ledger enable row level security;
create policy "Users can see ledger entries for their own company" on public.inventory_ledger for select using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.export_jobs enable row level security;
create policy "Users can manage export jobs for their own company" on public.export_jobs for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.integrations enable row level security;
create policy "Users can manage integrations for their own company" on public.integrations for all using (company_id = (select company_id from public.users where id = auth.uid()));

alter table public.sync_state enable row level security;
create policy "Users can see sync state for their own integrations" on public.sync_state for select using (integration_id in (select id from public.integrations where company_id = (select company_id from public.users where id = auth.uid())));

alter table public.sync_logs enable row level security;
create policy "Users can see sync logs for their own integrations" on public.sync_logs for select using (integration_id in (select id from public.integrations where company_id = (select company_id from public.users where id = auth.uid())));

alter table public.channel_fees enable row level security;
create policy "Users can manage channel fees for their own company" on public.channel_fees for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Logical Updates
alter table company_settings add column if not exists promo_sales_lift_multiplier real not null default 2.5;

drop function if exists get_financial_impact_of_promotion(uuid,text[],numeric,integer);
create or replace function get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
) returns table (
    estimated_sales_lift_units numeric,
    estimated_revenue_gain numeric,
    estimated_profit_impact numeric,
    notes text
)
language plpgsql
security definer
as $$
declare
    v_settings public.company_settings;
    v_base_sales_velocity numeric;
    v_avg_price numeric;
    v_avg_cost numeric;
begin
    select * into v_settings from public.company_settings where company_id = p_company_id limit 1;
    if v_settings is null then
        select 2.5 into v_settings.promo_sales_lift_multiplier;
    end if;

    select
        coalesce(sum(si.quantity) / (90.0), 0) as daily_velocity,
        coalesce(avg(si.unit_price / 100.0), 0) as avg_price,
        coalesce(avg(i.cost / 100.0), 0) as avg_cost
    into
        v_base_sales_velocity, v_avg_price, v_avg_cost
    from public.sale_items si
    join public.sales s on si.sale_id = s.id
    join public.inventory i on si.sku = i.sku and i.company_id = s.company_id
    where s.company_id = p_company_id
      and si.sku = any(p_skus)
      and s.created_at >= now() - interval '90 days';
    
    estimated_sales_lift_units := v_base_sales_velocity * p_duration_days * (power(v_settings.promo_sales_lift_multiplier, p_discount_percentage) - 1);
    
    declare
        original_profit numeric := (v_avg_price - v_avg_cost) * v_base_sales_velocity * p_duration_days;
        promo_price numeric := v_avg_price * (1 - p_discount_percentage);
        promo_profit_per_unit numeric := promo_price - v_avg_cost;
        estimated_promo_sales_units numeric := v_base_sales_velocity * p_duration_days * power(v_settings.promo_sales_lift_multiplier, p_discount_percentage);
        estimated_promo_profit numeric := promo_profit_per_unit * estimated_promo_sales_units;
    begin
        estimated_revenue_gain := (promo_price * estimated_promo_sales_units) - (v_avg_price * v_base_sales_velocity * p_duration_days);
        estimated_profit_impact := estimated_promo_profit - original_profit;
        notes := 'The promotional model now uses an exponential lift factor and considers diminishing returns for higher discounts.';
    end;

    return query select estimated_sales_lift_units, estimated_revenue_gain, estimated_profit_impact, notes;
end;
$$;


drop function if exists get_demand_forecast(uuid);
create or replace function get_demand_forecast(p_company_id uuid)
returns table(sku text, product_name text, forecast_30_days numeric)
language plpgsql
security definer
as $$
declare
    alpha numeric := 0.7; -- EWMA smoothing factor, higher gives more weight to recent data
begin
    return query
    with monthly_sales as (
        select
            si.sku,
            date_trunc('month', s.created_at) as sale_month,
            sum(si.quantity) as total_quantity
        from public.sales s
        join public.sale_items si on s.id = si.sale_id
        where s.company_id = p_company_id
        group by 1, 2
    ),
    ewma as (
        select
            sku,
            sale_month,
            total_quantity,
            avg(total_quantity) over (partition by sku order by sale_month) as ewma_forecast
        from monthly_sales
    ),
    latest_forecast as (
        select
            sku,
            ewma_forecast as forecast
        from (
            select sku, ewma_forecast, row_number() over (partition by sku order by sale_month desc) as rn
            from ewma
        ) as sub
        where sub.rn = 1
    )
    select
        i.sku,
        i.name,
        round(coalesce(lf.forecast, 0), 0)
    from public.inventory i
    left join latest_forecast lf on i.sku = lf.sku
    where i.company_id = p_company_id and i.deleted_at is null
    order by coalesce(lf.forecast, 0) desc
    limit 20;
end;
$$;

drop function if exists get_customer_segment_analysis(uuid);
create or replace function get_customer_segment_analysis(p_company_id uuid)
returns table(segment text, sku text, product_name text, total_quantity bigint, total_revenue numeric)
language plpgsql
security definer
as $$
begin
    return query
    with customer_stats as (
        select
            s.customer_email,
            count(s.id) as order_count
        from public.sales s
        where s.company_id = p_company_id and s.customer_email is not null
        group by 1
    ),
    new_customers as (
        select cs.customer_email
        from customer_stats cs
        where cs.order_count = 1
    ),
    repeat_customers as (
        select cs.customer_email
        from customer_stats cs
        where cs.order_count > 1
    ),
    top_spenders as (
        select s.customer_email
        from public.sales s
        where s.company_id = p_company_id and s.customer_email is not null
        group by 1
        order by sum(s.total_amount) desc
        limit greatest(1, (select count(distinct customer_email) from public.sales where company_id = p_company_id) / 10)
    ),
    segments as (
        select customer_email, 'New Customers' as segment from new_customers
        union all
        select customer_email, 'Repeat Customers' as segment from repeat_customers
        union all
        select customer_email, 'Top Spenders' as segment from top_spenders
    )
    select
        seg.segment,
        si.sku,
        max(si.product_name) as product_name,
        sum(si.quantity) as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    from public.sales s
    join segments seg on s.customer_email = seg.customer_email
    join public.sale_items si on s.id = si.sale_id
    where s.company_id = p_company_id
    group by 1, 2
    order by 1, 5 desc;
end;
$$;
