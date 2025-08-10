
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema "extensions";

-- #################################################################
--                         CORE TABLES
-- #################################################################

-- Table to store company information
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    owner_id uuid references auth.users(id),
    created_at timestamptz not null default now()
);
comment on table public.companies is 'Stores company-level information.';

-- Table for user roles within a company
create table if not exists public.company_users (
    company_id uuid references public.companies(id) on delete cascade not null,
    user_id uuid references auth.users(id) on delete cascade not null,
    role company_role not null default 'Member',
    primary key (company_id, user_id)
);
comment on table public.company_users is 'Maps users to companies with specific roles.';

-- Table for company-specific settings
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    currency text default 'USD',
    timezone text default 'UTC',
    tax_rate numeric default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    overstock_multiplier integer not null default 3,
    high_value_threshold integer not null default 100000
);
comment on table public.company_settings is 'Stores settings and thresholds for business logic.';

-- #################################################################
--                       PRODUCT & INVENTORY TABLES
-- #################################################################

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
comment on table public.products is 'Stores product master data.';

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
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    reorder_point int,
    reorder_quantity int,
    supplier_id uuid references public.suppliers(id) on delete set null,
    constraint unique_sku_per_company unique (company_id, sku),
    constraint unique_external_variant_per_company unique (company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs).';

create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
comment on table public.inventory_ledger is 'Tracks every stock movement for auditing.';

-- #################################################################
--                         SALES & CUSTOMER TABLES
-- #################################################################

create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    unique(company_id, external_customer_id)
);
comment on table public.customers is 'Stores customer information.';


create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_number text not null,
    external_order_id text,
    customer_id uuid references public.customers(id) on delete set null,
    financial_status text default 'pending',
    fulfillment_status text default 'unfulfilled',
    currency text default 'USD',
    subtotal int not null default 0,
    total_tax int default 0,
    total_shipping int default 0,
    total_discounts int default 0,
    total_amount int not null,
    source_platform text,
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order data.';

create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int default 0, -- in cents
    tax_amount int default 0, -- in cents
    cost_at_time int, -- in cents
    external_line_item_id text
);
comment on table public.order_line_items is 'Stores individual items within an order.';

create table if not exists public.refunds (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    order_id uuid not null references public.orders(id) on delete cascade,
    refund_number text not null,
    status text not null default 'pending',
    reason text,
    note text,
    total_amount integer not null,
    created_by_user_id uuid references auth.users(id),
    external_refund_id text,
    created_at timestamptz default now()
);

-- #################################################################
--                     SUPPLIER & PURCHASING TABLES
-- #################################################################

create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

create table if not exists public.purchase_orders (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    status text not null default 'Draft',
    po_number text not null,
    total_cost int not null,
    expected_arrival_date date,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    idempotency_key uuid unique
);
comment on table public.purchase_orders is 'Stores purchase order information.';

create table if not exists public.purchase_order_line_items (
    id uuid primary key default uuid_generate_v4(),
    purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    quantity int not null,
    cost int not null -- in cents
);
comment on table public.purchase_order_line_items is 'Stores individual items within a purchase order.';

-- #################################################################
--                          INTEGRATIONS
-- #################################################################

create table if not exists public.integrations (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    platform integration_platform not null,
    shop_domain text,
    shop_name text,
    is_active boolean default false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, platform)
);
comment on table public.integrations is 'Stores details for connected third-party platforms.';

create table if not exists public.channel_fees (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    channel_name text not null,
    percentage_fee numeric,
    fixed_fee numeric, -- in cents
    created_at timestamptz default now(),
    updated_at timestamptz,
    unique(company_id, channel_name)
);
comment on table public.channel_fees is 'Stores fees associated with different sales channels for accurate profit calculation.';

-- #################################################################
--                     AI & CONVERSATION TABLES
-- #################################################################

create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now(),
    is_starred boolean default false
);
comment on table public.conversations is 'Stores metadata for AI chat conversations.';

create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role message_role not null,
    content text,
    component text,
    "componentProps" jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    "isError" boolean default false,
    created_at timestamptz default now()
);
comment on table public.messages is 'Stores individual messages within a chat conversation.';

-- #################################################################
--                       AUDITING & LOGGING TABLES
-- #################################################################

create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete set null,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
comment on table public.audit_log is 'Records significant events for auditing and security purposes.';

create table if not exists public.feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    subject_id text not null,
    subject_type text not null,
    feedback feedback_type not null,
    created_at timestamptz default now()
);
comment on table public.feedback is 'Stores user feedback on AI responses and other features.';


-- #################################################################
--                          DATA IMPORT
-- #################################################################
create table if not exists public.imports (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    created_by uuid not null references auth.users(id),
    import_type text not null,
    file_name text not null,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text not null default 'pending',
    errors jsonb,
    summary jsonb,
    created_at timestamptz default now(),
    completed_at timestamptz
);
comment on table public.imports is 'Tracks the status and results of data import jobs.';


-- #################################################################
--                          DATA EXPORT
-- #################################################################
create table if not exists public.export_jobs (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    requested_by_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null default 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    error_message text
);
comment on table public.export_jobs is 'Tracks data export requests.';


-- #################################################################
--                       WEBHOOK EVENT LOG
-- #################################################################
create table if not exists public.webhook_events (
    id uuid primary key default gen_random_uuid(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    webhook_id text not null,
    created_at timestamptz default now(),
    unique(integration_id, webhook_id)
);
comment on table public.webhook_events is 'Logs received webhook events to prevent replay attacks.';


-- #################################################################
--                      FUNCTIONS
-- #################################################################

-- Metrics for last N days (default 30). No external dependencies.
create or replace function public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int default 30
)
returns table (
  total_orders       bigint,
  total_revenue      bigint,
  total_customers    bigint,
  inventory_count    bigint,
  sales_series       jsonb,
  top_products       jsonb,
  inventory_summary  jsonb,
  revenue_change     double precision,
  orders_change      double precision,
  customers_change   double precision,
  dead_stock_value   bigint
)
language sql
stable
as $$
with window as (
  select
    now() - make_interval(days => p_days)             as start_at,
    now() - make_interval(days => p_days * 2)         as prev_start_at,
    now() - make_interval(days => p_days)             as prev_end_at
),
filtered_orders as (
  select o.*
  from orders o, window w
  where o.company_id = p_company_id
    and o.created_at >= w.start_at
    and (o.cancelled_at is null)
),
prev_filtered_orders as (
  select o.*
  from orders o, window w
  where o.company_id = p_company_id
    and o.created_at between w.prev_start_at and w.prev_end_at
    and o.cancelled_at is null
),
day_series as (
  select date_trunc('day', o.created_at) as day,
         sum(o.total_amount)::bigint     as revenue
  from filtered_orders o
  group by 1
  order by 1
),
tp as (
  select
    p.id                                    as product_id,
    p.title                                 as product_name,
    p.image_url,
    sum(li.quantity)::int                   as quantity_sold,
    sum(li.price * li.quantity)::bigint     as total_revenue
  from order_line_items li
  join orders o   on o.id = li.order_id
  left join products p on p.id = li.product_id
  where o.company_id = p_company_id
    and o.cancelled_at is null
    and o.created_at >= (select start_at from window)
  group by 1,2,3
  order by total_revenue desc
  limit 5
),
inventory_values as (
  select
    sum(v.inventory_quantity * v.cost)::bigint                                                        as total_value,
    sum(case when v.inventory_quantity > coalesce(v.reorder_point, 0)
             then v.inventory_quantity * v.cost else 0 end)::bigint                                   as in_stock_value,
    sum(case when v.inventory_quantity > 0
               and v.inventory_quantity <= coalesce(v.reorder_point, 0)
             then v.inventory_quantity * v.cost else 0 end)::bigint                                   as low_stock_value
  from product_variants v
  where v.company_id = p_company_id
    and v.cost is not null
),
variant_last_sale as (
  select
    v.id,
    v.inventory_quantity,
    v.cost,
    max(o.created_at)                                           as last_sale,
    coalesce(cs.dead_stock_days, 90)                            as dead_stock_days
  from product_variants v
  left join order_line_items li on li.variant_id = v.id
  left join orders o            on o.id = li.order_id and o.cancelled_at is null
  left join company_settings cs on cs.company_id = v.company_id
  where v.company_id = p_company_id
    and v.cost is not null
  group by v.id, v.inventory_quantity, v.cost, cs.dead_stock_days
),
dead_stock as (
  select coalesce(sum(v.inventory_quantity * v.cost), 0)::bigint as value
  from variant_last_sale v
  where v.inventory_quantity > 0
    and coalesce(v.last_sale, timestamp 'epoch')
        < now() - make_interval(days => v.dead_stock_days)
),
current_period as (
  select
    coalesce(count(*), 0)::bigint                   as orders,
    coalesce(sum(total_amount), 0)::bigint          as revenue,
    coalesce(count(distinct customer_id), 0)::bigint as customers
  from filtered_orders
),
previous_period as (
  select
    coalesce(count(*), 0)::bigint                   as orders,
    coalesce(sum(total_amount), 0)::bigint          as revenue,
    coalesce(count(distinct customer_id), 0)::bigint as customers
  from prev_filtered_orders
)
select
  (select orders    from current_period)                           as total_orders,
  (select revenue   from current_period)                           as total_revenue,
  (select customers from current_period)                           as total_customers,

  coalesce((select sum(pv.inventory_quantity)
            from product_variants pv
            where pv.company_id = p_company_id), 0)::bigint        as inventory_count,

  coalesce((
    select jsonb_agg(
             jsonb_build_object('date', to_char(day, 'YYYY-MM-DD'),
                                 'revenue', revenue)
             order by day)
    from day_series
  ), '[]'::jsonb)                                                  as sales_series,

  coalesce((
    select jsonb_agg(to_jsonb(tp))
    from tp
  ), '[]'::jsonb)                                                  as top_products,

  jsonb_build_object(
    'total_value',     coalesce((select total_value    from inventory_values), 0),
    'in_stock_value',  coalesce((select in_stock_value from inventory_values), 0),
    'low_stock_value', coalesce((select low_stock_value from inventory_values), 0),
    'dead_stock_value',coalesce((select value from dead_stock), 0)
  )                                                                as inventory_summary,

  case when (select revenue from previous_period) = 0 then 0
       else (( (select revenue from current_period)::double precision
             - (select revenue from previous_period)::double precision )
             / nullif((select revenue from previous_period)::double precision, 0)) * 100 end
                                                                 as revenue_change,
  case when (select orders from previous_period) = 0 then 0
       else (( (select orders from current_period)::double precision
             - (select orders from previous_period)::double precision )
             / nullif((select orders from previous_period)::double precision, 0)) * 100 end
                                                                 as orders_change,
  case when (select customers from previous_period) = 0 then 0
       else (( (select customers from current_period)::double precision
             - (select customers from previous_period)::double precision )
             / nullif((select customers from previous_period)::double precision, 0)) * 100 end
                                                                 as customers_change,
  coalesce((select value from dead_stock), 0)::bigint              as dead_stock_value;
$$;


-- #################################################################
--                     PERFORMANCE INDEXES
-- #################################################################

create index if not exists idx_orders_company_created
  on orders(company_id, created_at);

create index if not exists idx_olis_order
  on order_line_items(order_id);

create index if not exists idx_olis_company_variant
  on order_line_items(company_id, variant_id);

create index if not exists idx_products_company
  on products(company_id);

create index if not exists idx_variants_company
  on product_variants(company_id);

create index if not exists idx_customers_company
  on customers(company_id);
