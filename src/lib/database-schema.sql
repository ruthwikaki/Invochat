-- Enable the UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create a custom type for user roles in a company
CREATE TYPE public.company_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- Create a custom type for integration platforms
CREATE TYPE public.integration_platform AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);

-- Create a custom type for message roles
CREATE TYPE public.message_role AS ENUM (
    'user',
    'assistant',
    'tool'
);

CREATE TYPE public.feedback_type AS ENUM (
    'helpful',
    'unhelpful'
);


-- Companies Table
CREATE TABLE public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company Users Join Table (for roles)
CREATE TABLE public.company_users (
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Company Settings Table
CREATE TABLE public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    alert_settings JSONB DEFAULT '{"low_stock_threshold": 10, "critical_stock_threshold": 5, "email_notifications": true, "morning_briefing_enabled": true, "morning_briefing_time": "09:00", "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "dismissal_hours": 24}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Integrations Table
CREATE TABLE public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);

-- Products Table
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    fts_document TSVECTOR,
    deleted_at TIMESTAMPTZ
);

-- Product Variants Table
CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT,
    cost INT,
    inventory_quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    in_transit_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    reorder_point INT,
    reorder_quantity INT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 1
);

-- Suppliers Table
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    lead_time_days INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Purchase Orders Table
CREATE TABLE public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id),
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    notes TEXT,
    idempotency_key UUID
);

-- Purchase Order Line Items Table
CREATE TABLE public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);

-- Customers Table
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Orders Table
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT DEFAULT 'pending',
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    currency TEXT DEFAULT 'USD',
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    source_name TEXT,
    tags TEXT[],
    notes TEXT,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Order Line Items Table
CREATE TABLE public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    variant_title TEXT,
    sku TEXT NOT NULL,
    quantity INT NOT NULL,
    price INT NOT NULL, -- in cents
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    fulfillment_status TEXT DEFAULT 'unfulfilled',
    requires_shipping BOOLEAN DEFAULT true,
    external_line_item_id TEXT,
    cost_at_time INT
);

-- Refunds Table
CREATE TABLE public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id),
    refund_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    reason TEXT,
    note TEXT,
    total_amount INT NOT NULL,
    created_by_user_id UUID REFERENCES auth.users(id),
    external_refund_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Inventory Ledger Table
CREATE TABLE public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Conversations Table
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);

-- Messages Table
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    created_at TIMESTAMPTZ DEFAULT now(),
    is_error BOOLEAN DEFAULT false
);

-- Audit Log Table
CREATE TABLE public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Feedback Table
CREATE TABLE public.feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL,
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);


-- Function to create a company and link the owner
CREATE OR REPLACE FUNCTION public.create_company_for_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
BEGIN
    -- Create a new company
    INSERT INTO public.companies (name, owner_id)
    VALUES (NEW.raw_user_meta_data->>'company_name', NEW.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as Owner
    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (new_company_id, NEW.id, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = NEW.id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function on new user signup
CREATE TRIGGER on_new_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.create_company_for_new_user();

-- Create the auth.company_id() function that RLS policies need
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    -- Get company_id from JWT token
    -- First try app_metadata
    company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'app_metadata' ->> 'company_id', '')::UUID;
    
    -- If not found, try user_metadata  
    IF company_id_val IS NULL THEN
        company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'user_metadata' ->> 'company_id', '')::UUID;
    END IF;
    
    -- If still not found, get from users table
    IF company_id_val IS NULL THEN
        SELECT (raw_app_meta_data ->> 'company_id')::UUID
        INTO company_id_val
        FROM auth.users
        WHERE id = auth.uid();
    END IF;
    
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = auth.company_id());

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON products FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON product_variants FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON orders FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON order_line_items FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON customers FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON suppliers FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON purchase_orders FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON purchase_order_line_items FOR ALL USING (company_id = auth.company_id());


-- Add the new get_dashboard_metrics function
create or replace function public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int default 30
)
returns table (
  total_orders      bigint,
  total_revenue     bigint,
  new_customers   bigint,
  inventory_summary   jsonb,
  sales_over_time      jsonb,
  top_selling_products      jsonb,
  revenue_change    numeric,
  orders_change     numeric,
  customers_change  numeric,
  dead_stock_value  bigint
)
language sql
stable
as $$
with date_series as (
  select generate_series(
    date_trunc('day', now() - (p_days * 2 - 1) * interval '1 day'),
    date_trunc('day', now()),
    '1 day'::interval
  )::date as day
),
current_period as (
  select
    coalesce(count(distinct o.id), 0) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_revenue,
    coalesce(count(distinct o.customer_id), 0) as new_customers
  from orders o
  where o.company_id = p_company_id
    and o.created_at >= date_trunc('day', now() - (p_days - 1) * interval '1 day')
    and o.cancelled_at is null
),
previous_period as (
  select
    coalesce(count(distinct o.id), 0) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_revenue,
    coalesce(count(distinct o.customer_id), 0) as new_customers
  from orders o
  where o.company_id = p_company_id
    and o.created_at between date_trunc('day', now() - (p_days * 2 - 1) * interval '1 day') and date_trunc('day', now() - p_days * interval '1 day')
    and o.cancelled_at is null
),
daily_sales as (
  select
    d.day,
    coalesce(sum(o.total_amount), 0) as revenue
  from date_series d
  left join orders o on date_trunc('day', o.created_at)::date = d.day and o.company_id = p_company_id and o.cancelled_at is null
  where d.day >= date_trunc('day', now() - (p_days - 1) * interval '1 day')
  group by d.day
  order by d.day
),
top_products as (
  select
    p.title as product_name,
    p.image_url,
    sum(li.quantity) as quantity_sold,
    sum(li.price * li.quantity) as total_revenue
  from order_line_items li
  join orders o on o.id = li.order_id
  join products p on p.id = li.product_id
  where o.company_id = p_company_id
    and o.created_at >= date_trunc('day', now() - (p_days - 1) * interval '1 day')
    and o.cancelled_at is null
  group by p.title, p.image_url
  order by total_revenue desc
  limit 5
),
inventory_values as (
  select
    coalesce(sum(pv.inventory_quantity * pv.cost), 0) as total_value,
    coalesce(sum(case when pv.inventory_quantity > s.dead_stock_days then pv.inventory_quantity * pv.cost else 0 end), 0) as in_stock_value,
    coalesce(sum(case when pv.inventory_quantity > 0 and pv.inventory_quantity <= pv.reorder_point then pv.inventory_quantity * pv.cost else 0 end), 0) as low_stock_value
  from product_variants pv
  join company_settings s on s.company_id = pv.company_id
  where pv.company_id = p_company_id
)
select
  cp.total_orders,
  cp.total_revenue,
  cp.new_customers,
  jsonb_build_object(
    'total_value', iv.total_value,
    'in_stock_value', iv.in_stock_value,
    'low_stock_value', iv.low_stock_value,
    'dead_stock_value', (select total_value from get_dead_stock_report(p_company_id))
  ) as inventory_summary,
  (select jsonb_agg(jsonb_build_object('date', to_char(day, 'YYYY-MM-DD'), 'revenue', revenue)) from daily_sales) as sales_over_time,
  (select jsonb_agg(tp) from top_products tp) as top_selling_products,
  case when pp.total_revenue > 0 then round(((cp.total_revenue - pp.total_revenue) / pp.total_revenue::numeric) * 100, 2) else 0 end as revenue_change,
  case when pp.total_orders > 0 then round(((cp.total_orders - pp.total_orders) / pp.total_orders::numeric) * 100, 2) else 0 end as orders_change,
  case when pp.new_customers > 0 then round(((cp.new_customers - pp.new_customers) / pp.new_customers::numeric) * 100, 2) else 0 end as customers_change,
  (select total_value from get_dead_stock_report(p_company_id)) as dead_stock_value
from current_period cp, previous_period pp, inventory_values iv;
$$;


-- Add performance indexes
create index if not exists idx_orders_company_created
  on orders(company_id, created_at);

create index if not exists idx_orders_company_cancelled
  on orders(company_id) where cancelled_at is null;

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
