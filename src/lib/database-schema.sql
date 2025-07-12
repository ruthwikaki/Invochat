
-- This script should be run in the Supabase SQL Editor.
-- It sets up the required tables, roles, and functions for the application.

-- 1. Enable the required extensions if they are not already.
create extension if not exists "uuid-ossp";
create extension if not exists "vector";

-- 2. Grant usage on the 'auth' schema to the 'postgres' role
-- This is necessary for the SECURITY DEFINER functions below to work correctly.
grant usage on schema auth to postgres;

-- 3. Create the 'companies' table to store company information.
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz default now()
);

-- 4. Create the 'users' table to store user-specific information.
-- This table references the 'auth.users' table provided by Supabase.
create table if not exists public.users (
  id uuid primary key references auth.users(id),
  company_id uuid references public.companies(id),
  role text default 'Member'::text,
  deleted_at timestamptz
);

-- 5. Create the 'company_settings' table for business-specific rules.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000,
    promo_sales_lift_multiplier numeric not null default 2.5,
    currency text default 'USD',
    timezone text default 'UTC',
    created_at timestamptz default now(),
    updated_at timestamptz
);

-- 6. Create the 'suppliers' table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz default now(),
    updated_at timestamptz
);

-- 7. Create the 'inventory' table
create table if not exists public.inventory (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sku text not null,
    name text not null,
    category text,
    price integer, -- in cents
    cost integer not null default 0, -- in cents
    quantity integer not null default 0,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid references public.suppliers(id) on delete set null,
    barcode text,
    last_sold_date date,
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    created_at timestamptz default now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    unique(company_id, sku)
);
create index if not exists idx_inventory_company_id on public.inventory(company_id);

-- 8. Create the 'customers' table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    phone text,
    deleted_at timestamptz,
    created_at timestamptz default now(),
    unique(company_id, email)
);

-- 9. Create the 'sales' table
create table if not exists public.sales (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sale_number text not null,
    customer_id uuid references public.customers(id),
    total_amount integer not null, -- in cents
    payment_method text not null,
    notes text,
    created_at timestamptz default now(),
    external_id text
);
create index if not exists idx_sales_created_at on public.sales(created_at);

-- 10. Create the 'sale_items' table
create table if not exists public.sale_items (
    id uuid primary key default uuid_generate_v4(),
    sale_id uuid not null references public.sales(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.inventory(id),
    quantity integer not null,
    unit_price integer not null, -- in cents
    cost_at_time integer not null default 0, -- in cents
    created_at timestamptz default now()
);
create index if not exists idx_sale_items_product_id on public.sale_items(product_id);

-- 11. Create the 'inventory_ledger' table for auditing stock movements.
create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.inventory(id),
    change_type text not null, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change integer not null,
    new_quantity integer not null,
    related_id uuid, -- e.g., sale_id, purchase_order_id
    notes text,
    created_by uuid references public.users(id),
    created_at timestamptz default now()
);

-- 12. Create the 'channel_fees' table for net margin calculations.
create table if not exists public.channel_fees (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric(5, 4) not null, -- e.g., 0.029 for 2.9%
  fixed_fee integer not null, -- in cents
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique (company_id, channel_name)
);

-- 13. Create the 'integrations' table to store sync information.
create table if not exists public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean not null default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz default now(),
  updated_at timestamptz,
  unique (company_id, platform)
);

-- 14. Create helper tables for background jobs and logging.
create table if not exists public.imports (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  created_by uuid not null references public.users(id),
  import_type text not null,
  file_name text not null,
  status text not null,
  total_rows integer,
  processed_rows integer,
  failed_rows integer,
  errors jsonb,
  summary jsonb,
  created_at timestamptz default now(),
  completed_at timestamptz
);

create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references public.users(id),
    status text not null default 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz default now()
);

create table if not exists public.audit_log (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id),
    user_id uuid references public.users(id),
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);

create table if not exists public.sync_state (
    integration_id uuid not null references public.integrations(id) on delete cascade,
    sync_type text not null,
    last_processed_cursor text,
    last_update timestamptz not null,
    primary key (integration_id, sync_type)
);

-- 15. Set up Row-Level Security (RLS) policies
alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.channel_fees enable row level security;
alter table public.integrations enable row level security;
alter table public.imports enable row level security;
alter table public.export_jobs enable row level security;
alter table public.audit_log enable row level security;
alter table public.sync_state enable row level security;

-- Policies for tables are based on company_id matching the user's company_id
create policy "Users can only see data from their own company."
on public.companies for select using (id = (select company_id from public.users where id = auth.uid()));

create policy "Users can only see users from their own company."
on public.users for select using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own company settings."
on public.company_settings for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own suppliers."
on public.suppliers for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own inventory."
on public.inventory for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own customers."
on public.customers for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own sales."
on public.sales for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own sale items."
on public.sale_items for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own ledger."
on public.inventory_ledger for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own channel fees."
on public.channel_fees for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own integrations."
on public.integrations for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own imports."
on public.imports for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own export jobs."
on public.export_jobs for all using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can view their own audit logs."
on public.audit_log for select using (company_id = (select company_id from public.users where id = auth.uid()));

create policy "Users can manage their own sync state."
on public.sync_state for all using (
    integration_id in (select id from public.integrations where company_id = (select company_id from public.users where id = auth.uid()))
);


-- 16. Function to create a company and assign user role on new user signup.
create or replace function public.create_user_company_and_role()
returns trigger
language plpgsql
security definer
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Extract company name from metadata
  company_name := new.raw_user_meta_data->>'company_name';
  
  -- Create a new company for the new user
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;
  
  -- Create a corresponding user entry in the public.users table
  insert into public.users (id, company_id, role)
  values (new.id, company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- 17. Trigger to call the function on new user creation
drop trigger if exists on_new_user_created on auth.users;
create trigger on_new_user_created
  after insert on auth.users
  for each row execute procedure public.create_user_company_and_role();


-- 18. Function to invite a user to a company
create or replace function public.invite_user_to_company(
    p_company_id uuid,
    p_company_name text,
    p_email text
)
returns void
language plpgsql
security definer
as $$
begin
  -- Invite the user using Supabase's built-in invite function
  perform auth.admin.invite_user_by_email(
    p_email,
    json_build_object(
        'company_id', p_company_id,
        'company_name', p_company_name,
        'role', 'Member'
    )
  );
end;
$$;

-- 19. Function to handle a new sale transactionally
drop function if exists public.record_sale_transaction(uuid, uuid, jsonb[], text, text, text, text, text);
create or replace function public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb[],
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text
)
returns public.sales
language plpgsql
as $$
declare
    new_sale public.sales;
    customer_id uuid;
    item_record jsonb;
    item_product_id uuid;
    item_quantity int;
    item_price int;
    item_cost int;
    item_product_name text;
    current_stock int;
begin
    -- Check if customer exists, otherwise create one
    if p_customer_email is not null then
        select id into customer_id from public.customers where email = p_customer_email and company_id = p_company_id;
        if customer_id is null then
            insert into public.customers (company_id, customer_name, email)
            values (p_company_id, coalesce(p_customer_name, 'New Customer'), p_customer_email)
            returning id into customer_id;
        end if;
    end if;

    -- Create the sale record
    insert into public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    values (
        p_company_id,
        'SALE-' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
        customer_id,
        (select sum((it->>'unit_price')::int * (it->>'quantity')::int) from unnest(p_sale_items) as it),
        p_payment_method,
        p_notes,
        p_external_id
    ) returning * into new_sale;

    -- Loop through sale items
    foreach item_record in array p_sale_items loop
        item_product_id := (item_record->>'product_id')::uuid;
        item_quantity := (item_record->>'quantity')::int;
        item_price := (item_record->>'unit_price')::int;
        item_product_name := item_record->>'product_name';

        -- Get current stock and cost
        select quantity, cost into current_stock, item_cost from public.inventory where id = item_product_id and company_id = p_company_id;
        
        if current_stock is null then
            raise exception 'Product not found: %', item_product_name;
        end if;

        -- Insert sale item
        insert into public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        values (new_sale.id, p_company_id, item_product_id, item_quantity, item_price, item_cost);

        -- Update inventory quantity
        update public.inventory set
            quantity = quantity - item_quantity,
            last_sold_date = current_date
        where id = item_product_id;

        -- Record in inventory ledger
        insert into public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, created_by)
        values (p_company_id, item_product_id, 'sale', -item_quantity, current_stock - item_quantity, new_sale.id, p_user_id);

    end loop;

    return new_sale;
end;
$$;


-- 20. Advanced Analytics Functions (can be dropped and replaced)

drop function if exists public.get_financial_impact_of_promotion(uuid,text[],numeric,integer);
create or replace function public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
) returns table (
    total_items integer,
    estimated_sales_lift_units integer,
    estimated_additional_revenue integer,
    estimated_additional_profit integer
)
language sql stable
as $$
with settings as (
    select promo_sales_lift_multiplier as sales_lift_multiplier 
    from public.company_settings 
    where company_id = p_company_id
),
inventory_info as (
    select 
        id,
        sku,
        cost,
        price,
        (
            select coalesce(sum(si.quantity), 0)
            from public.sale_items si
            join public.sales s on si.sale_id = s.id
            where si.product_id = inv.id 
            and s.created_at >= now() - interval '90 days'
        ) as units_sold_last_90_days
    from public.inventory inv
    where company_id = p_company_id and sku = any(p_skus)
),
select 
    count(*)::integer as total_items,
    (sum(units_sold_last_90_days) / 90.0 * p_duration_days * (1 + (p_discount_percentage * (select sales_lift_multiplier from settings))))::integer as estimated_sales_lift_units,
    (sum(units_sold_last_90_days) / 90.0 * p_duration_days * (1 + (p_discount_percentage * (select sales_lift_multiplier from settings))) * avg(price) * (1 - p_discount_percentage))::integer as estimated_additional_revenue,
    (sum(units_sold_last_90_days) / 90.0 * p_duration_days * (1 + (p_discount_percentage * (select sales_lift_multiplier from settings))) * (avg(price) * (1 - p_discount_percentage) - avg(cost)))::integer as estimated_additional_profit
from inventory_info
cross join settings;
$$;

drop function if exists public.get_demand_forecast(uuid);
create or replace function public.get_demand_forecast(p_company_id uuid)
returns table (
    sku text,
    product_name text,
    forecasted_demand integer
)
language sql stable
as $$
with monthly_sales as (
    select
        i.sku,
        i.name as product_name,
        date_trunc('month', s.created_at) as sale_month,
        sum(si.quantity) as total_quantity
    from public.sale_items si
    join public.sales s on si.sale_id = s.id
    join public.inventory i on si.product_id = i.id
    where s.company_id = p_company_id and s.created_at >= now() - interval '12 months'
    group by 1, 2, 3
),
ewma as (
    select
        sku,
        product_name,
        -- Calculate EWMA for the last 3 months with alpha = 0.7
        (
            (select total_quantity from monthly_sales m2 where m2.sku = m1.sku and m2.sale_month = date_trunc('month', now() - interval '1 month')) * 0.7 +
            (select total_quantity from monthly_sales m2 where m2.sku = m1.sku and m2.sale_month = date_trunc('month', now() - interval '2 months')) * 0.21 +
            (select total_quantity from monthly_sales m2 where m2.sku = m1.sku and m2.sale_month = date_trunc('month', now() - interval '3 months')) * 0.09
        ) as forecasted_demand
    from monthly_sales m1
    group by 1, 2
)
select 
    sku,
    product_name,
    ceil(coalesce(forecasted_demand, 0))::integer as forecasted_demand
from ewma
order by forecasted_demand desc
limit 10;
$$;

drop function if exists public.get_customer_segment_analysis(uuid);
create or replace function public.get_customer_segment_analysis(p_company_id uuid)
returns table(segment text, sku text, product_name text, total_quantity bigint, total_revenue bigint)
language sql stable
as $$
with customer_stats as (
    select 
        c.email,
        count(s.id) as total_orders,
        sum(s.total_amount) as total_spend
    from public.customers c
    join public.sales s on c.email = s.customer_email and c.company_id = s.company_id
    where c.company_id = p_company_id
    group by c.email
),
ranked_customers as (
    select 
        email,
        total_orders,
        total_spend,
        ntile(10) over (order by total_spend desc) as decile
    from customer_stats
),
-- New Customers: First order in the last 60 days
new_customers as (
    select distinct customer_email from public.sales
    where company_id = p_company_id
    and created_at > now() - interval '60 days'
    and customer_email is not null
    and customer_email not in (
        select customer_email from public.sales 
        where company_id = p_company_id and created_at <= now() - interval '60 days'
    )
),
-- Repeat Customers: More than 1 order
repeat_customers as (
    select email from ranked_customers where total_orders > 1
),
-- Top Spenders: Top 10% by spend
top_spenders as (
    select email from ranked_customers where decile = 1
)
-- Combine and get top products for each segment
(
    select 
        'New Customers' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity) as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    from public.sale_items si
    join public.sales s on si.sale_id = s.id
    join public.inventory i on si.product_id = i.id
    where s.company_id = p_company_id and s.customer_email in (select email from new_customers)
    group by 1,2,3
    order by total_revenue desc
    limit 5
)
union all
(
    select 
        'Repeat Customers' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity) as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    from public.sale_items si
    join public.sales s on si.sale_id = s.id
    join public.inventory i on si.product_id = i.id
    where s.company_id = p_company_id and s.customer_email in (select email from repeat_customers)
    group by 1,2,3
    order by total_revenue desc
    limit 5
)
union all
(
    select 
        'Top Spenders' as segment,
        i.sku,
        i.name as product_name,
        sum(si.quantity) as total_quantity,
        sum(si.quantity * si.unit_price) as total_revenue
    from public.sale_items si
    join public.sales s on si.sale_id = s.id
    join public.inventory i on si.product_id = i.id
    where s.company_id = p_company_id and s.customer_email in (select email from top_spenders)
    group by 1,2,3
    order by total_revenue desc
    limit 5
);
$$;

drop function if exists public.get_product_lifecycle_analysis(uuid);
create or replace function public.get_product_lifecycle_analysis(p_company_id uuid)
returns json
language sql stable
as $$
with product_sales_monthly as (
    select
        i.id as product_id,
        i.sku,
        i.name as product_name,
        date_trunc('month', s.created_at) as sale_month,
        sum(si.quantity) as monthly_quantity
    from public.inventory i
    join public.sale_items si on i.id = si.product_id
    join public.sales s on si.sale_id = s.id
    where i.company_id = p_company_id
    group by 1, 2, 3, 4
),
product_sales_trends as (
    select
        product_id,
        sku,
        product_name,
        min(sale_month) as first_sale_month,
        sum(case when sale_month >= date_trunc('month', now()) - interval '3 months' then monthly_quantity else 0 end) as sales_last_3_months,
        sum(case when sale_month < date_trunc('month', now()) - interval '3 months' and sale_month >= date_trunc('month', now()) - interval '6 months' then monthly_quantity else 0 end) as sales_prev_3_months,
        sum(monthly_quantity) as total_sales
    from product_sales_monthly
    group by 1, 2, 3
),
classified_products as (
    select
        ps.sku,
        ps.product_name,
        ps.total_sales,
        ps.sales_last_3_months,
        ps.sales_prev_3_months,
        (ps.sales_last_3_months * ps.total_sales) as revenue_rank,
        case
            when ps.first_sale_month >= date_trunc('month', now()) - interval '2 months' then 'Launch'
            when ps.sales_last_3_months > ps.sales_prev_3_months * 1.2 then 'Growth'
            when ps.sales_last_3_months >= ps.sales_prev_3_months * 0.8 then 'Maturity'
            else 'Decline'
        end as stage
    from product_sales_trends ps
),
summary as (
    select
        sum(case when stage = 'Launch' then 1 else 0 end) as launch_count,
        sum(case when stage = 'Growth' then 1 else 0 end) as growth_count,
        sum(case when stage = 'Maturity' then 1 else 0 end) as maturity_count,
        sum(case when stage = 'Decline' then 1 else 0 end) as decline_count
    from classified_products
),
select json_build_object(
    'summary', (select to_json(summary) from summary),
    'products', (select json_agg(cp) from classified_products cp)
)
$$;

-- End of script
