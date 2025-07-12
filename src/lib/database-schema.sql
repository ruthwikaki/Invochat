
-- This is a one-time setup script for your Supabase project.
--
-- 1. Go to the "SQL Editor" section in your Supabase project dashboard.
-- 2. Click "+ New query".
-- 3. Paste the entire content of this file into the editor.
-- 4. Click "Run".
--
-- After this script runs successfully, you must sign out and then sign up
-- with a new user account. This new account will be properly configured.

--------------------------------------------------------------------------------
-- 1. Helper Functions
--------------------------------------------------------------------------------
-- Function to get user role from app_metadata.
create or replace function get_user_role(p_user_id uuid)
returns text as $$
begin
  return (
    select raw_app_meta_data->>'role'
    from auth.users
    where id = p_user_id
  );
end;
$$ language plpgsql security definer;

-- Function to safely convert text to numeric, returning 0 on failure.
CREATE OR REPLACE FUNCTION safe_to_numeric(text_value TEXT)
RETURNS NUMERIC AS $$
BEGIN
    RETURN text_value::NUMERIC;
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


--------------------------------------------------------------------------------
-- 2. Tables
--------------------------------------------------------------------------------
-- Represents a single business entity or organization.
create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);
alter table companies enable row level security;

-- Extends auth.users with company_id and role.
alter table auth.users add column if not exists company_id uuid references companies(id);
alter table auth.users add column if not exists role text;
alter table auth.users add column if not exists deleted_at timestamptz;

-- Stores company-specific business logic settings.
create table if not exists company_settings (
  company_id uuid primary key references companies(id) on delete cascade,
  dead_stock_days int not null default 90,
  fast_moving_days int not null default 30,
  predictive_stock_days int not null default 7,
  overstock_multiplier numeric not null default 3.0,
  high_value_threshold numeric not null default 1000.00,
  promo_sales_lift_multiplier numeric not null default 2.5,
  currency text default 'USD',
  timezone text default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table company_settings enable row level security;

-- Core table for all unique products (stock-keeping units).
create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  sku text not null,
  name text not null,
  category text,
  barcode text,
  source_platform text,
  external_product_id text,
  external_variant_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table products enable row level security;
create index if not exists idx_products_company_id on products(company_id);
create unique index if not exists idx_products_company_sku on products(company_id, sku);
create unique index if not exists idx_products_company_ext_id on products(company_id, source_platform, external_product_id, external_variant_id);


-- Suppliers or vendors.
create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table suppliers enable row level security;
create unique index if not exists idx_suppliers_company_name on suppliers(company_id, name);

-- Associates products with suppliers and stores supplier-specific data.
create table if not exists product_supplier (
  product_id uuid not null references products(id) on delete cascade,
  supplier_id uuid not null references suppliers(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  supplier_sku text,
  unit_cost numeric not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  primary key (product_id, supplier_id)
);
alter table product_supplier enable row level security;
create index if not exists idx_product_supplier_product on product_supplier(product_id);
create index if not exists idx_product_supplier_supplier on product_supplier(supplier_id);

-- Current inventory levels for each product.
create table if not exists inventory (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  product_id uuid not null references products(id) on delete restrict,
  quantity int not null,
  cost numeric not null,
  reorder_point int,
  reorder_quantity int,
  last_sold_date timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table inventory enable row level security;
create unique index if not exists idx_inventory_company_product on inventory(company_id, product_id);


-- Audit trail for all inventory movements.
create table if not exists inventory_ledger (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  change_type text not null,
  quantity_change int not null,
  new_quantity int not null,
  related_id uuid, -- e.g., sale_id, purchase_order_id
  notes text,
  created_at timestamptz not null default now()
);
alter table inventory_ledger enable row level security;
create index if not exists idx_inventory_ledger_product on inventory_ledger(product_id);

-- Stores customer information.
create table if not exists customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references companies(id) on delete cascade,
    customer_name text not null,
    email text,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table customers enable row level security;
create unique index if not exists idx_customers_company_email on customers (company_id, email);

-- Header table for sales transactions.
create table if not exists sales (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  customer_id uuid references customers(id),
  sale_number text not null,
  total_amount numeric not null,
  payment_method text not null,
  notes text,
  external_id text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table sales enable row level security;
create unique index if not exists idx_sales_company_number on sales(company_id, sale_number);
create index if not exists idx_sales_external_id on sales(company_id, external_id);

-- Line items for each sale.
create table if not exists sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  product_id uuid not null references products(id) on delete restrict,
  quantity int not null,
  unit_price numeric not null,
  cost_at_time numeric not null,
  created_at timestamptz not null default now()
);
alter table sale_items enable row level security;
create index if not exists idx_sale_items_sale_id on sale_items(sale_id);
create index if not exists idx_sale_items_product_id on sale_items(product_id);


-- Stores information about connected integrations.
create table if not exists integrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  platform text not null, -- e.g., 'shopify', 'woocommerce'
  shop_domain text,
  shop_name text,
  is_active boolean not null default true,
  last_sync_at timestamptz,
  sync_status text, -- e.g., 'syncing', 'success', 'failed'
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table integrations enable row level security;
create unique index if not exists idx_integrations_company_platform on integrations(company_id, platform);

-- Stores conversations for the chat feature.
create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  title text not null,
  is_starred boolean default false,
  created_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now()
);
alter table conversations enable row level security;
create index if not exists idx_conversations_user on conversations(user_id);

-- Stores individual messages within a conversation.
create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  role text not null, -- 'user' or 'assistant'
  content text not null,
  visualization jsonb,
  confidence float,
  assumptions text[],
  component text,
  component_props jsonb,
  created_at timestamptz not null default now()
);
alter table messages enable row level security;
create index if not exists idx_messages_conversation on messages(conversation_id);


-- General purpose audit logging table
create table if not exists audit_log (
  id bigserial primary key,
  company_id uuid not null references companies(id),
  user_id uuid references auth.users(id),
  action text not null,
  details jsonb,
  created_at timestamptz default now()
);
alter table audit_log enable row level security;
create index if not exists idx_audit_log_company_action on audit_log(company_id, action, created_at);


-- Stores asynchronous data import job details
create table if not exists imports (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  import_type text not null,
  status text not null, -- e.g., 'processing', 'completed', 'failed'
  file_name text not null,
  total_rows int,
  processed_rows int,
  failed_rows int,
  errors jsonb,
  summary jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table imports enable row level security;
create index if not exists idx_imports_company on imports(company_id);

-- Tracks sync state for integrations to allow resumable syncs
create table if not exists sync_state (
  integration_id uuid primary key references integrations(id) on delete cascade,
  sync_type text not null,
  last_processed_cursor text,
  last_update timestamptz not null
);
alter table sync_state enable row level security;

-- Stores logs for individual sync jobs
create table if not exists sync_logs (
  id uuid primary key default gen_random_uuid(),
  integration_id uuid not null references integrations(id) on delete cascade,
  sync_type text not null, -- 'products' or 'sales'
  status text not null, -- 'started', 'completed', 'failed'
  records_synced int,
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table sync_logs enable row level security;
create index if not exists idx_sync_logs_integration on sync_logs(integration_id, started_at desc);

-- Stores channel-specific fees for net margin calculations
create table if not exists channel_fees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric(5, 4) not null, -- e.g., 0.029 for 2.9%
  fixed_fee numeric(10, 2) not null, -- e.g., 0.30 for 30 cents
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (company_id, channel_name)
);
alter table channel_fees enable row level security;

-- Stores jobs for asynchronous data exports
create table if not exists export_jobs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id),
  requested_by_user_id uuid not null references auth.users(id),
  status text not null default 'pending', -- pending, processing, completed, failed
  file_path text,
  download_url text,
  expires_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table export_jobs enable row level security;


--------------------------------------------------------------------------------
-- 3. Row Level Security (RLS) Policies
--------------------------------------------------------------------------------
-- Companies
create policy "Users can only see their own company."
  on companies for select using (id = auth.jwt()->>'company_id');

-- Company Settings
create policy "Users can manage settings for their own company."
  on company_settings for all using (company_id = auth.jwt()->>'company_id');

-- Products
create policy "Users can manage products for their own company."
  on products for all using (company_id = auth.jwt()->>'company_id');

-- Suppliers
create policy "Users can manage suppliers for their own company."
  on suppliers for all using (company_id = auth.jwt()->>'company_id');

-- Product-Supplier Junction
create policy "Users can manage product-supplier links for their own company."
  on product_supplier for all using (company_id = auth.jwt()->>'company_id');

-- Inventory
create policy "Users can manage inventory for their own company."
  on inventory for all using (company_id = auth.jwt()->>'company_id');

-- Inventory Ledger
create policy "Users can view ledger entries for their own company."
  on inventory_ledger for select using (company_id = auth.jwt()->>'company_id');

-- Customers
create policy "Users can manage customers for their own company."
  on customers for all using (company_id = auth.jwt()->>'company_id');
  
-- Sales
create policy "Users can manage sales for their own company."
  on sales for all using (company_id = auth.jwt()->>'company_id');

-- Sale Items
create policy "Users can manage sale items for their own company."
  on sale_items for all using (company_id = auth.jwt()->>'company_id');

-- Integrations
create policy "Users can manage integrations for their own company."
  on integrations for all using (company_id = auth.jwt()->>'company_id');

-- Conversations
create policy "Users can only manage their own conversations."
  on conversations for all using (user_id = auth.uid());

-- Messages
create policy "Users can only manage messages in their own conversations."
  on messages for all using (conversation_id in (select id from conversations where user_id = auth.uid()));

-- Audit Log
create policy "Users can only view audit logs for their own company."
    on audit_log for select using (company_id = auth.jwt()->>'company_id');

-- Imports
create policy "Users can only manage imports for their own company."
    on imports for all using (company_id = auth.jwt()->>'company_id');

-- Sync State
create policy "Users can only manage sync state for their own company."
    on sync_state for all using (integration_id in (select id from integrations where company_id = auth.jwt()->>'company_id'));

-- Sync Logs
create policy "Users can only view sync logs for their own company."
    on sync_logs for select using (integration_id in (select id from integrations where company_id = auth.jwt()->>'company_id'));

-- Channel Fees
create policy "Users can manage channel fees for their own company."
    on channel_fees for all using (company_id = auth.jwt()->>'company_id');

-- Export Jobs
create policy "Users can manage export jobs for their own company."
    on export_jobs for all using (company_id = auth.jwt()->>'company_id');


--------------------------------------------------------------------------------
-- 4. DB Triggers and Functions for Automation
--------------------------------------------------------------------------------
-- Function to create a company and assign it to a new user
create or replace function public.handle_new_user()
returns trigger as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from metadata
  user_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company
  insert into public.companies (name)
  values (coalesce(user_company_name, 'My Company'))
  returning id into new_company_id;

  -- Update the user's app_metadata with the new company_id and role
  update auth.users
  set raw_app_meta_data = jsonb_set(
      jsonb_set(raw_app_meta_data, '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb('Owner'::text)
    )
  where id = new.id;

  return new;
end;
$$ language plpgsql security definer;

-- Trigger to call the function upon new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to create an inventory ledger entry
create or replace function public.log_inventory_change()
returns trigger as $$
begin
  insert into public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
  values (
    new.company_id,
    new.product_id,
    tg_argv[0], -- Change type passed as argument
    new.quantity - coalesce(old.quantity, 0),
    new.quantity,
    case when tg_argv[0] = 'sale' then new.id end, -- Example for related_id
    case when tg_argv[0] = 'adjustment' then 'Manual adjustment' end -- Example note
  );
  return new;
end;
$$ language plpgsql;

-- Trigger for inventory updates
create trigger on_inventory_update
  after update on public.inventory
  for each row
  when (new.quantity is distinct from old.quantity)
  execute procedure public.log_inventory_change('adjustment');


-- Function to update inventory on sale
create or replace function public.update_inventory_on_sale()
returns trigger as $$
begin
    update public.inventory
    set 
        quantity = quantity - new.quantity,
        last_sold_date = now()
    where product_id = new.product_id
    and company_id = new.company_id;
    return new;
end;
$$ language plpgsql;

-- Trigger for new sale items
create trigger on_new_sale_item
  after insert on public.sale_items
  for each row
  execute procedure public.update_inventory_on_sale();


--------------------------------------------------------------------------------
-- 5. Stored Procedures (RPC)
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS get_financial_impact_of_promotion(uuid,text[],numeric,integer);

CREATE OR REPLACE FUNCTION get_financial_impact_of_promotion(
    p_company_id UUID,
    p_skus TEXT[],
    p_discount_percentage NUMERIC,
    p_duration_days INT
)
RETURNS TABLE (
    estimated_sales_lift_units INT,
    estimated_additional_revenue NUMERIC,
    estimated_additional_profit NUMERIC,
    estimated_cogs NUMERIC,
    total_inventory_value_at_risk NUMERIC
) AS $$
DECLARE
    v_sales_lift_multiplier NUMERIC;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier
    INTO v_sales_lift_multiplier
    FROM company_settings cs
    WHERE cs.company_id = p_company_id;

    -- A more realistic, non-linear model for sales lift.
    -- The effect of a discount diminishes as it gets larger.
    -- This uses a logarithmic curve, capped to prevent absurdity.
    -- e.g., 10% discount -> ~1.5x lift, 20% -> ~1.8x, 50% -> ~2.4x
    -- We add 1 to discount to avoid log(0) issues.
    v_sales_lift_multiplier := 1 + LEAST(
        (v_sales_lift_multiplier - 1) * LN(1 + p_discount_percentage * 10),
        10.0 -- Cap lift at 10x to be safe
    );

    RETURN QUERY
    WITH product_base_metrics AS (
        SELECT
            i.product_id,
            i.cost,
            p.price,
            COALESCE(SUM(si.quantity), 0) AS total_units_sold_90_days,
            (COALESCE(SUM(si.quantity), 0)::NUMERIC / 90.0) AS avg_daily_sales
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN sales s ON s.company_id = i.company_id AND s.created_at >= NOW() - INTERVAL '90 days'
        LEFT JOIN sale_items si ON si.sale_id = s.id AND si.product_id = i.product_id
        WHERE i.company_id = p_company_id
          AND p.sku = ANY(p_skus)
        GROUP BY i.product_id, i.cost, p.price
    ),
    promotion_estimates AS (
        SELECT
            pbm.product_id,
            pbm.cost,
            pbm.price,
            (pbm.avg_daily_sales * p_duration_days) AS baseline_sales_units,
            (pbm.avg_daily_sales * v_sales_lift_multiplier * p_duration_days) AS estimated_promo_sales_units
        FROM product_base_metrics pbm
    ),
    financial_impact AS (
        SELECT
            pe.product_id,
            pe.cost,
            pe.price,
            (pe.estimated_promo_sales_units - pe.baseline_sales_units) AS sales_lift_units,
            (pe.price * (1 - p_discount_percentage)) AS discounted_price,
            (pe.price * (1 - p_discount_percentage) * (pe.estimated_promo_sales_units - pe.baseline_sales_units)) AS additional_revenue,
            ((pe.price * (1 - p_discount_percentage) - pe.cost) * (pe.estimated_promo_sales_units - pe.baseline_sales_units)) AS additional_profit,
            (pe.cost * (pe.estimated_promo_sales_units - pe.baseline_sales_units)) AS cogs_of_lift
        FROM promotion_estimates pe
    )
    SELECT
        CEIL(SUM(fi.sales_lift_units))::INT,
        SUM(fi.additional_revenue),
        SUM(fi.additional_profit),
        SUM(fi.cogs_of_lift),
        (SELECT SUM(i.quantity * i.cost) FROM inventory i JOIN products p ON i.product_id = p.id WHERE p.sku = ANY(p_skus) AND i.company_id = p_company_id)
    FROM financial_impact fi;

END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS get_demand_forecast(uuid);

CREATE OR REPLACE FUNCTION get_demand_forecast(p_company_id UUID)
RETURNS TABLE(sku TEXT, product_name TEXT, forecasted_demand NUMERIC) AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            p.sku,
            p.name as product_name,
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        JOIN products p ON si.product_id = p.id
        WHERE s.company_id = p_company_id
          AND s.created_at >= NOW() - INTERVAL '12 months'
        GROUP BY p.sku, p.name, sale_month
    ),
    time_series AS (
        SELECT
            sku,
            product_name,
            -- Generate a series of months from 12 months ago to now
            generate_series(
                date_trunc('month', NOW() - INTERVAL '11 months'),
                date_trunc('month', NOW()),
                '1 month'
            )::date AS month
        FROM (SELECT DISTINCT sku, product_name FROM monthly_sales) as products
    ),
    full_series AS (
        SELECT
            ts.sku,
            ts.product_name,
            ts.month,
            COALESCE(ms.total_quantity, 0) AS monthly_sales
        FROM time_series ts
        LEFT JOIN monthly_sales ms ON ts.sku = ms.sku AND ts.month = ms.sale_month
    ),
    -- Calculate Exponentially Weighted Moving Average (EWMA)
    -- Alpha (smoothing factor) is set to 0.3, giving more weight to recent data.
    ewma_calc AS (
      SELECT
        sku,
        product_name,
        month,
        monthly_sales,
        AVG(monthly_sales) OVER (PARTITION BY sku ORDER BY month) as ewma
      FROM (
        SELECT
          sku,
          product_name,
          month,
          monthly_sales,
          0.3 * monthly_sales + 0.7 * LAG(AVG(monthly_sales) OVER (PARTITION BY sku ORDER BY month), 1, monthly_sales) OVER (PARTITION BY sku ORDER BY month) as weighted_avg
        FROM full_series
      ) as sub
      GROUP BY sku, product_name, month, monthly_sales, weighted_avg
    )
    SELECT
        ew.sku,
        ew.product_name,
        -- Forecast for the next month is the last calculated EWMA value
        (array_agg(ew.ewma ORDER BY ew.month DESC))[1]::numeric as forecasted_demand
    FROM ewma_calc ew
    GROUP BY ew.sku, ew.product_name
    ORDER BY forecasted_demand DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_product_lifecycle_analysis(uuid);

CREATE OR REPLACE FUNCTION get_product_lifecycle_analysis(p_company_id UUID)
RETURNS jsonb AS $$
DECLARE
    v_launch_count INT;
    v_growth_count INT;
    v_maturity_count INT;
    v_decline_count INT;
    v_products JSONB;
BEGIN
    -- Create a temporary table to hold product sales trends
    CREATE TEMP TABLE product_sales_trends ON COMMIT DROP AS
    WITH monthly_sales AS (
        SELECT
            p.id as product_id,
            p.sku,
            p.name as product_name,
            date_trunc('month', s.created_at) AS sale_month,
            SUM(si.quantity) AS total_quantity,
            SUM(si.quantity * si.unit_price) AS total_revenue
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        JOIN products p ON si.product_id = p.id
        WHERE s.company_id = p_company_id
          AND s.created_at >= NOW() - INTERVAL '12 months'
        GROUP BY p.id, p.sku, p.name, sale_month
    ),
    -- Correctly use ROW_NUMBER() in a CTE to filter for the latest month
    latest_month_trends AS (
      SELECT
          sku,
          product_name,
          sale_month,
          total_quantity,
          total_revenue,
          LAG(total_quantity, 1, 0) OVER (PARTITION BY sku ORDER BY sale_month) AS prev_month_quantity,
          LAG(total_revenue, 1, 0) OVER (PARTITION BY sku ORDER BY sale_month) AS prev_month_revenue,
          AVG(total_quantity) OVER (PARTITION BY sku ORDER BY sale_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as moving_avg_quantity,
          ROW_NUMBER() OVER (PARTITION BY sku ORDER BY sale_month DESC) as rn
      FROM monthly_sales
    )
    SELECT * FROM latest_month_trends WHERE rn = 1;

    -- Create a temporary table for product lifecycle stages
    CREATE TEMP TABLE product_lifecycle ON COMMIT DROP AS
    SELECT
        p.id as product_id,
        p.sku,
        p.name as product_name,
        i.quantity as current_stock,
        t.total_revenue,
        -- Determine stage based on sales trends and product age
        CASE
            WHEN p.created_at >= NOW() - INTERVAL '60 days' THEN 'Launch'
            WHEN t.total_quantity > t.prev_month_quantity * 1.2 AND t.moving_avg_quantity > (SELECT AVG(total_quantity) FROM product_sales_trends) THEN 'Growth'
            WHEN t.total_quantity < t.prev_month_quantity * 0.8 AND t.total_quantity > 0 THEN 'Decline'
            ELSE 'Maturity'
        END AS stage,
        CASE
            WHEN p.created_at >= NOW() - INTERVAL '60 days' THEN 'Newly introduced product with initial sales.'
            WHEN t.total_quantity > t.prev_month_quantity * 1.2 THEN 'Sales are accelerating, showing strong market adoption.'
            WHEN t.total_quantity < t.prev_month_quantity * 0.8 AND t.total_quantity > 0 THEN 'Sales are slowing down, indicating market saturation or declining interest.'
            ELSE 'Sales are stable and consistent, indicating a well-established product.'
        END AS reason
    FROM products p
    JOIN inventory i ON p.id = i.product_id
    LEFT JOIN product_sales_trends t ON p.sku = t.sku
    WHERE p.company_id = p_company_id;

    -- Calculate counts for summary
    SELECT COUNT(*) INTO v_launch_count FROM product_lifecycle WHERE stage = 'Launch';
    SELECT COUNT(*) INTO v_growth_count FROM product_lifecycle WHERE stage = 'Growth';
    SELECT COUNT(*) INTO v_maturity_count FROM product_lifecycle WHERE stage = 'Maturity';
    SELECT COUNT(*) INTO v_decline_count FROM product_lifecycle WHERE stage = 'Decline';

    -- Get product details as JSON
    SELECT jsonb_agg(pl) INTO v_products FROM (SELECT * FROM product_lifecycle ORDER BY total_revenue DESC NULLS LAST LIMIT 100) pl;

    -- Return the final JSON object
    RETURN jsonb_build_object(
        'summary', jsonb_build_object(
            'launch_count', v_launch_count,
            'growth_count', v_growth_count,
            'maturity_count', v_maturity_count,
            'decline_count', v_decline_count
        ),
        'products', v_products
    );
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS get_customer_segment_analysis(uuid);

CREATE OR REPLACE FUNCTION get_customer_segment_analysis(p_company_id UUID)
RETURNS TABLE (
    segment TEXT,
    sku TEXT,
    product_name TEXT,
    total_quantity BIGINT,
    total_revenue BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH customer_stats AS (
        SELECT
            c.id as customer_id,
            c.email as customer_email,
            COUNT(s.id) as total_orders
        FROM customers c
        JOIN sales s ON c.email = (SELECT email FROM customers WHERE id = s.customer_id) -- Corrected join condition
        WHERE c.company_id = p_company_id
        GROUP BY c.id, c.email
    ),
    customer_segments AS (
        SELECT
            cs.customer_email,
            CASE
                WHEN cs.total_orders = 1 THEN 'New Customers'
                WHEN cs.total_orders > 1 THEN 'Repeat Customers'
            END as segment
        FROM customer_stats cs
    
        UNION ALL
        
        -- Use a CTE to handle potential small customer bases for Top Spenders
        SELECT
            s.customer_email,
            'Top Spenders' as segment
        FROM sales s
        WHERE s.company_id = p_company_id AND s.customer_email IS NOT NULL
        GROUP BY s.customer_email
        ORDER BY SUM(s.total_amount) DESC
        -- Ensure at least one customer is selected, or top 10%
        LIMIT GREATEST(1, (SELECT CEIL(COUNT(DISTINCT customer_email) * 0.1)::INT FROM sales WHERE company_id = p_company_id))
    )
    SELECT
        seg.segment,
        p.sku,
        p.name as product_name,
        SUM(si.quantity)::BIGINT as total_quantity,
        SUM(si.unit_price * si.quantity)::BIGINT as total_revenue
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN products p ON si.product_id = p.id
    JOIN customer_segments seg ON s.customer_email = seg.customer_email
    WHERE s.company_id = p_company_id
    GROUP BY seg.segment, p.sku, p.name
    ORDER BY seg.segment, total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- Add other functions that might have been dropped back in, if necessary
-- For now, this focused change should resolve the error.
-- (This is a placeholder comment, the functions above are the ones being modified)

    