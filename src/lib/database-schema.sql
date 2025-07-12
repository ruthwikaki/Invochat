
-- This script should be run in the Supabase SQL Editor.
-- It sets up the required tables, functions, and permissions for InvoChat.

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- 2. Define user roles
create type user_role as enum ('Owner', 'Admin', 'Member');

-- 3. Companies Table
create table if not exists companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

-- 4. Users Table (public schema)
-- This table mirrors auth.users for easier joins and app-specific data.
create table if not exists users (
    id uuid primary key references auth.users(id),
    company_id uuid not null references companies(id),
    email text,
    role user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);

-- 5. Company Settings Table
create table if not exists company_settings (
    company_id uuid primary key references companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    overstock_multiplier numeric not null default 3,
    high_value_threshold numeric not null default 1000.00,
    promo_sales_lift_multiplier real not null default 2.5,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    custom_rules jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- 6. Suppliers Table
create table if not exists suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz not null default now()
);

-- 7. Inventory Table
create table if not exists inventory (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    sku text not null,
    name text not null,
    category text,
    quantity int not null default 0,
    cost numeric not null default 0,
    price numeric,
    reorder_point int,
    supplier_id uuid references suppliers(id),
    last_sold_date date,
    barcode text,
    version int not null default 1,
    deleted_at timestamptz,
    deleted_by uuid references users(id),
    created_at timestamptz default now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer
);
create index if not exists idx_inventory_company_id on inventory(company_id);
create unique index if not exists idx_inventory_company_sku on inventory(company_id, sku);
create unique index if not exists idx_inventory_company_source_variant on inventory(company_id, source_platform, external_variant_id) where source_platform is not null;

-- 8. Customers Table
create table if not exists customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
create unique index if not exists idx_customers_company_email on customers(company_id, email) where email is not null;

-- 9. Sales Table
create table if not exists sales (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    sale_number text not null,
    customer_id uuid references customers(id),
    total_amount numeric not null,
    payment_method text,
    notes text,
    created_at timestamptz default now(),
    external_id text
);
create unique index if not exists idx_sales_company_external on sales(company_id, external_id) where external_id is not null;

-- 10. Sale Items Table
create table if not exists sale_items (
    id uuid primary key default uuid_generate_v4(),
    sale_id uuid not null references sales(id) on delete cascade,
    company_id uuid not null references companies(id),
    product_id uuid not null references inventory(id),
    sku text not null,
    product_name text,
    quantity int not null,
    unit_price numeric not null,
    cost_at_time numeric
);

-- 11. Inventory Ledger Table
create table if not exists inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id),
    product_id uuid not null references inventory(id),
    change_type text not null, -- e.g., 'sale', 'return', 'adjustment', 'purchase_order_received'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., sale_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
create index if not exists idx_inventory_ledger_product_id on inventory_ledger(product_id);

-- 12. Integrations Table
create table if not exists integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    platform text not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    access_token text, -- NOTE: This is deprecated in favor of Vault
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
create unique index if not exists idx_integrations_company_platform on integrations(company_id, platform);

-- 13. Sync State & Logs Tables
create table if not exists sync_state (
    integration_id uuid primary key references integrations(id) on delete cascade,
    sync_type text not null,
    last_processed_cursor text,
    last_update timestamptz
);
create table if not exists sync_logs (
    id uuid primary key default uuid_generate_v4(),
    integration_id uuid not null references integrations(id) on delete cascade,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz default now(),
    completed_at timestamptz
);

-- 14. Conversations & Messages Tables
create table if not exists conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id),
    company_id uuid not null references companies(id),
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);

create table if not exists messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    company_id uuid not null references companies(id),
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

-- 15. Audit Log Table
create table if not exists audit_log (
    id bigserial primary key,
    company_id uuid,
    user_id uuid references auth.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

-- 16. Export Jobs Table
create table if not exists export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    requested_by_user_id uuid not null references auth.users(id),
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now()
);

-- 17. Channel Fees Table
create table if not exists channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references companies(id),
    channel_name text not null,
    percentage_fee numeric not null,
    fixed_fee numeric not null,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique (company_id, channel_name)
);

-- =============================================
-- FUNCTIONS & TRIGGERS
-- =============================================

-- Ensure postgres role has necessary permissions
grant usage on schema auth to postgres;
grant select on auth.users to postgres;

-- Function to handle new user setup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- This is crucial for accessing auth.users
as $$
declare
    new_company_id uuid;
    new_company_name text;
begin
    -- 1. Create a new company for the user.
    new_company_name := new.raw_app_meta_data->>'company_name';
    if new_company_name is null then
        new_company_name := new.email || '''s Company';
    end if;

    insert into public.companies (name)
    values (new_company_name)
    returning id into new_company_id;

    -- 2. Create a corresponding entry in the public.users table.
    insert into public.users (id, company_id, email, role)
    values (new.id, new_company_id, new.email, 'Owner');
    
    -- 3. Create default settings for the new company.
    insert into public.company_settings (company_id)
    values (new_company_id);
    
    -- 4. Update the user's app_metadata in the auth.users table.
    -- This links the auth user to their company and sets their role.
    update auth.users
    set raw_app_meta_data = new.raw_app_meta_data || 
                            jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    where id = new.id;
    
    return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row
    execute function public.handle_new_user();

-- Drop the old record_sale_transaction function
drop function if exists public.record_sale_transaction(uuid,uuid,jsonb,text,text,text,text,text);

-- Recreate the record_sale_transaction function
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
as $$
declare
    v_sale_id uuid;
    v_customer_id uuid;
    v_total_amount numeric := 0;
    v_sale_item record;
    v_inventory_item record;
    v_new_sale_number text;
begin
    -- Check for existing external_id to prevent duplicates
    if p_external_id is not null then
        select id into v_sale_id from public.sales where company_id = p_company_id and external_id = p_external_id;
        if v_sale_id is not null then
            -- Sale already exists, return it
            return (select s from public.sales s where id = v_sale_id);
        end if;
    end if;

    -- Upsert customer
    if p_customer_email is not null then
        insert into public.customers (company_id, customer_name, email, first_order_date)
        values (p_company_id, coalesce(p_customer_name, p_customer_email), p_customer_email, current_date)
        on conflict (company_id, email) do update set
            customer_name = coalesce(excluded.customer_name, customers.customer_name)
        returning id into v_customer_id;
    end if;

    -- Calculate total sale amount
    for v_sale_item in select * from jsonb_to_recordset(p_sale_items) as x(product_id uuid, quantity int, unit_price numeric)
    loop
        v_total_amount := v_total_amount + (v_sale_item.quantity * v_sale_item.unit_price);
    end loop;

    -- Create sale record
    select 'SALE-' || to_char(now(), 'YYMMDD') || '-' || lpad(nextval('sales_seq')::text, 4, '0') into v_new_sale_number;
    
    insert into public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id, created_at)
    values (p_company_id, v_new_sale_number, v_customer_id, v_total_amount, p_payment_method, p_notes, p_external_id, now())
    returning id into v_sale_id;

    -- Create sale items and update inventory
    for v_sale_item in select * from jsonb_to_recordset(p_sale_items) as x(product_id uuid, product_name text, quantity int, unit_price numeric)
    loop
        select * into v_inventory_item from public.inventory where id = v_sale_item.product_id and company_id = p_company_id;

        insert into public.sale_items (sale_id, company_id, product_id, sku, product_name, quantity, unit_price, cost_at_time)
        values (v_sale_id, p_company_id, v_inventory_item.id, v_inventory_item.sku, v_inventory_item.name, v_sale_item.quantity, v_sale_item.unit_price, v_inventory_item.cost);

        update public.inventory
        set
            quantity = quantity - v_sale_item.quantity,
            last_sold_date = current_date,
            version = version + 1
        where id = v_inventory_item.id;

        insert into public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        values (p_company_id, v_inventory_item.id, 'sale', -v_sale_item.quantity, v_inventory_item.quantity - v_sale_item.quantity, v_sale_id, 'Sale #' || v_new_sale_number);
    end loop;
    
    if v_customer_id is not null then
        update public.customers
        set
            total_orders = total_orders + 1,
            total_spent = total_spent + v_total_amount
        where id = v_customer_id;
    end if;

    return (select s from public.sales s where id = v_sale_id);
end;
$$;


-- Grant permissions
grant execute on function public.handle_new_user() to supabase_auth_admin;
grant execute on function public.record_sale_transaction(uuid,uuid,jsonb,text,text,text,text,text) to authenticated;
grant all on table public.companies to service_role;
grant all on table public.users to service_role;
grant all on table public.company_settings to service_role;
grant all on table public.inventory to service_role;
grant all on table public.suppliers to service_role;
grant all on table public.customers to service_role;
grant all on table public.sales to service_role;
grant all on table public.sale_items to service_role;
grant all on table public.inventory_ledger to service_role;
grant all on table public.integrations to service_role;
grant all on table public.sync_logs to service_role;
grant all on table public.sync_state to service_role;
grant all on table public.conversations to service_role;
grant all on table public.messages to service_role;
grant all on table public.audit_log to service_role;
grant all on table public.export_jobs to service_role;
grant all on table public.channel_fees to service_role;


-- Sequences for unique numbering
create sequence if not exists sales_seq;
grant usage, select on sequence sales_seq to service_role;
grant usage, select on sequence sales_seq to authenticated;

-- Row Level Security Policies
alter table public.companies enable row level security;
create policy "Users can view their own company" on public.companies for select using (id = (select company_id from users where id = auth.uid()));

alter table public.users enable row level security;
create policy "Users can view users in their own company" on public.users for select using (company_id = (select company_id from users where id = auth.uid()));
create policy "Users can update their own info" on public.users for update using (id = auth.uid());

alter table public.company_settings enable row level security;
create policy "Users can manage settings for their own company" on public.company_settings for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.inventory enable row level security;
create policy "Users can manage inventory for their own company" on public.inventory for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.suppliers enable row level security;
create policy "Users can manage suppliers for their own company" on public.suppliers for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.customers enable row level security;
create policy "Users can manage customers for their own company" on public.customers for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.sales enable row level security;
create policy "Users can manage sales for their own company" on public.sales for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.sale_items enable row level security;
create policy "Users can manage sale items for their own company" on public.sale_items for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.inventory_ledger enable row level security;
create policy "Users can view ledger for their own company" on public.inventory_ledger for select using (company_id = (select company_id from users where id = auth.uid()));

alter table public.integrations enable row level security;
create policy "Users can manage integrations for their own company" on public.integrations for all using (company_id = (select company_id from users where id = auth.uid()));

alter table public.sync_logs enable row level security;
create policy "Users can view sync logs for their own company" on public.sync_logs for select using (integration_id in (select id from integrations where company_id = (select company_id from users where id = auth.uid())));

alter table public.sync_state enable row level security;
create policy "Users can view sync state for their own company" on public.sync_state for select using (integration_id in (select id from integrations where company_id = (select company_id from users where id = auth.uid())));

alter table public.conversations enable row level security;
create policy "Users can manage their own conversations" on public.conversations for all using (user_id = auth.uid());

alter table public.messages enable row level security;
create policy "Users can manage messages in their own conversations" on public.messages for all using (conversation_id in (select id from conversations where user_id = auth.uid()));

alter table public.audit_log enable row level security;
create policy "Admins can view audit logs for their company" on public.audit_log for select using ((select role from users where id = auth.uid()) in ('Admin', 'Owner') and company_id = (select company_id from users where id = auth.uid()));

alter table public.export_jobs enable row level security;
create policy "Users can manage their own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid());

alter table public.channel_fees enable row level security;
create policy "Users can manage channel fees for their own company" on public.channel_fees for all using (company_id = (select company_id from users where id = auth.uid()));

-- Add promo_sales_lift_multiplier if it doesn't exist
do $$
begin
  if not exists(select * from information_schema.columns where table_name='company_settings' and column_name='promo_sales_lift_multiplier') then
    alter table "public"."company_settings" add column "promo_sales_lift_multiplier" real not null default 2.5;
  end if;
end $$;

-- Update sale_items to include product_id foreign key if it doesn't exist
do $$
begin
  if not exists(select * from information_schema.columns where table_name='sale_items' and column_name='product_id') then
    alter table "public"."sale_items" add column "product_id" uuid references public.inventory(id);
    -- You might want to run a backfill script here if you have existing data
    -- update public.sale_items si set product_id = (select id from public.inventory i where i.sku = si.sku and i.company_id = si.company_id limit 1);
    alter table "public"."sale_items" alter column "product_id" set not null;
  end if;
end $$;


-- Define or replace analytical functions
create or replace function get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage real,
    p_duration_days integer
)
returns table(
    total_baseline_revenue numeric,
    total_estimated_revenue numeric,
    total_baseline_profit numeric,
    total_estimated_profit numeric,
    estimated_revenue_change numeric,
    estimated_profit_change numeric,
    estimated_sales_lift numeric
)
language sql
security definer
as $$
    select
        coalesce(sum(baseline_revenue), 0) as total_baseline_revenue,
        coalesce(sum(estimated_revenue), 0) as total_estimated_revenue,
        coalesce(sum(baseline_profit), 0) as total_baseline_profit,
        coalesce(sum(estimated_profit), 0) as total_estimated_profit,
        coalesce(sum(estimated_revenue) - sum(baseline_revenue), 0) as estimated_revenue_change,
        coalesce(sum(estimated_profit) - sum(baseline_profit), 0) as estimated_profit_change,
        coalesce(sum(estimated_units) / sum(baseline_units), 0) as estimated_sales_lift
    from (
        select
            p.sku,
            p.name,
            p.daily_sales_velocity * p_duration_days as baseline_units,
            p.daily_sales_velocity * p_duration_days * (1 + (cs.promo_sales_lift_multiplier - 1) * p_discount_percentage * 2) as estimated_units,
            p.price,
            p.cost,
            p.daily_sales_velocity * p_duration_days * p.price as baseline_revenue,
            p.daily_sales_velocity * p_duration_days * (1 + (cs.promo_sales_lift_multiplier - 1) * p_discount_percentage * 2) * p.price * (1 - p_discount_percentage) as estimated_revenue,
            p.daily_sales_velocity * p_duration_days * (p.price - p.cost) as baseline_profit,
            p.daily_sales_velocity * p_duration_days * (1 + (cs.promo_sales_lift_multiplier - 1) * p_discount_percentage * 2) * (p.price * (1 - p_discount_percentage) - p.cost) as estimated_profit
        from get_product_velocity(p_company_id) p
        join company_settings cs on cs.company_id = p.company_id
        where p.sku = any(p_skus)
    ) as promo_calc;
$$;

create or replace function get_demand_forecast(p_company_id uuid)
returns table(sku text, product_name text, forecasted_demand numeric)
language sql
security definer
as $$
    with monthly_sales as (
        select
            si.sku,
            date_trunc('month', s.created_at) as month,
            sum(si.quantity) as total_quantity
        from sale_items si
        join sales s on si.sale_id = s.id
        where s.company_id = p_company_id
        group by si.sku, date_trunc('month', s.created_at)
    ),
    recent_sales as (
        select
            sku,
            month,
            total_quantity,
            row_number() over (partition by sku order by month desc) as rn
        from monthly_sales
    ),
    weighted_sales as (
        select
            sku,
            sum(total_quantity * (4 - rn)) / sum(4 - rn) as ewma_sales
        from recent_sales
        where rn <= 3
        group by sku
    )
    select
        i.sku,
        i.name as product_name,
        round(coalesce(ws.ewma_sales, 0)) as forecasted_demand
    from inventory i
    left join weighted_sales ws on i.sku = ws.sku
    where i.company_id = p_company_id
    order by forecasted_demand desc
    limit 20;
$$;


create or replace function get_customer_segment_analysis(p_company_id uuid)
returns table (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
language sql
security definer
as $$
    with customer_order_stats as (
      select
        c.id as customer_id,
        c.email,
        count(s.id) as order_count
      from customers c
      join sales s on c.id = s.customer_id
      where c.company_id = p_company_id
      group by c.id, c.email
    ),
    new_customers as (
      select customer_id from customer_order_stats where order_count = 1
    ),
    repeat_customers as (
      select customer_id from customer_order_stats where order_count > 1
    ),
    top_spenders as (
        select customer_id
        from sales
        where company_id = p_company_id and customer_id is not null
        group by customer_id
        order by sum(total_amount) desc
        limit greatest(1, (select count(distinct customer_id) from sales where company_id = p_company_id) / 10)
    ),
    segmented_sales as (
      select
        case
          when s.customer_id in (select customer_id from new_customers) then 'New Customers'
          when s.customer_id in (select customer_id from repeat_customers) then 'Repeat Customers'
          else null
        end as segment,
        si.sku,
        si.product_name,
        si.quantity,
        si.quantity * si.unit_price as revenue
      from sales s
      join sale_items si on s.id = si.sale_id
      where s.company_id = p_company_id and s.customer_id is not null
    ),
    top_spender_sales as (
        select
            'Top Spenders' as segment,
            si.sku,
            si.product_name,
            si.quantity,
            si.quantity * si.unit_price as revenue
        from sales s
        join sale_items si on s.id = si.sale_id
        where s.company_id = p_company_id and s.customer_id in (select customer_id from top_spenders)
    )
    select
        coalesce(t.segment, 'Unknown') as segment,
        t.sku,
        t.product_name,
        sum(t.quantity)::bigint as total_quantity,
        sum(t.revenue) as total_revenue
    from (
        select * from segmented_sales
        UNION ALL
        select * from top_spender_sales
    ) t
    where t.segment is not null
    group by t.segment, t.sku, t.product_name
    order by t.segment, total_revenue desc;
$$;


-- Final grants for functions
grant execute on function get_financial_impact_of_promotion(uuid,text[],real,integer) to authenticated;
grant execute on function get_demand_forecast(uuid) to authenticated;
grant execute on function get_customer_segment_analysis(uuid) to authenticated;
