-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types
CREATE TYPE company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE message_role AS ENUM ('user', 'assistant', 'tool');
CREATE TYPE feedback_type AS ENUM ('helpful', 'unhelpful');


-- Companies Table: Stores company information
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    owner_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Company Users Table: Manages user roles within companies
CREATE TABLE IF NOT EXISTS company_users (
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

-- Function to get company_id from JWT
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


-- Set up Row Level Security (RLS) for all company-scoped tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company" ON companies FOR SELECT USING (id = auth.company_id());

-- Automatically create a company for a new user and assign them as owner
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  company_name TEXT;
BEGIN
  -- Extract company name from metadata, default if not present
  company_name := COALESCE(new.raw_app_meta_data->>'company_name', 'My Company');
  
  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, new.id)
  RETURNING id INTO new_company_id;

  -- Link the new user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the function on new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Suppliers Table: Stores supplier information
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, name)
);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON suppliers FOR ALL USING (company_id = auth.company_id());

-- Products Table: Main product information
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
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
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON products FOR ALL USING (company_id = auth.company_id());


-- Product Variants Table: Specific versions of a product (e.g., by size or color)
CREATE TABLE IF NOT EXISTS product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT,
    compare_at_price INT,
    cost INT,
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    reorder_point INT,
    reorder_quantity INT,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    UNIQUE(company_id, sku)
);
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON product_variants FOR ALL USING (company_id = auth.company_id());


-- Customers Table: Stores customer information
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    external_customer_id TEXT,
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON customers FOR ALL USING (company_id = auth.company_id());


-- Orders Table: Stores order information
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON orders FOR ALL USING (company_id = auth.company_id());

-- Order Line Items Table: Products within an order
CREATE TABLE IF NOT EXISTS order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT,
    tax_amount INT,
    cost_at_time INT,
    external_line_item_id TEXT
);
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON order_line_items FOR ALL USING (company_id = auth.company_id());


-- Purchase Orders Table: Records for orders placed with suppliers
CREATE TABLE IF NOT EXISTS purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    notes TEXT,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON purchase_orders FOR ALL USING (company_id = auth.company_id());

-- Purchase Order Line Items Table: Products within a purchase order
CREATE TABLE IF NOT EXISTS purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL
);
ALTER TABLE purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company data" ON purchase_order_line_items FOR ALL USING (company_id = auth.company_id());

-- Integrations Table
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform integration_platform NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, platform)
);
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can access their company's integrations" ON integrations FOR ALL USING (company_id = auth.company_id());

-- Final, corrected get_dashboard_metrics function
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer);

CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(
  p_company_id uuid,
  p_days int DEFAULT 30
)
RETURNS TABLE (
  total_orders bigint,
  total_revenue bigint,
  total_customers bigint,
  inventory_count bigint,
  sales_series jsonb,
  top_products jsonb,
  inventory_summary jsonb,
  revenue_change double precision,
  orders_change double precision,
  customers_change double precision,
  dead_stock_value bigint
)
LANGUAGE sql
STABLE
AS $$
WITH time_window AS (
  SELECT
    now() - make_interval(days => p_days)            AS start_at,
    now() - make_interval(days => p_days * 2)        AS prev_start_at,
    now() - make_interval(days => p_days)            AS prev_end_at
),
filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at >= w.start_at
    AND o.cancelled_at IS NULL
),
prev_filtered_orders AS (
  SELECT o.*
  FROM public.orders o
  JOIN time_window w ON true
  WHERE o.company_id = p_company_id
    AND o.created_at >= w.prev_start_at AND o.created_at < w.prev_end_at
    AND o.cancelled_at IS NULL
),
day_series AS (
  SELECT date_trunc('day', o.created_at) AS day,
         SUM(o.total_amount)::bigint     AS revenue,
         COUNT(*)::int                   AS orders
  FROM filtered_orders o
  GROUP BY 1
  ORDER BY 1
),
top_products AS (
  SELECT
    p.id                                  AS product_id,
    p.title                               AS product_name,
    p.image_url,
    SUM(li.quantity)::int                 AS quantity_sold,
    SUM((li.price::bigint) * (li.quantity::bigint))::bigint AS total_revenue
  FROM public.order_line_items li
  JOIN public.orders o   ON o.id = li.order_id
  LEFT JOIN public.products p ON p.id = li.product_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
    AND o.created_at >= (SELECT start_at FROM time_window)
  GROUP BY 1,2,3
  ORDER BY total_revenue DESC
  LIMIT 5
),
inventory_values AS (
  SELECT
    SUM((v.inventory_quantity::bigint) * (v.cost::bigint))::bigint AS total_value,
    SUM(CASE WHEN v.reorder_point IS NULL OR v.inventory_quantity > v.reorder_point
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END)::bigint AS in_stock_value,
    SUM(CASE WHEN v.reorder_point IS NOT NULL
               AND v.inventory_quantity <= v.reorder_point
               AND v.inventory_quantity > 0
             THEN (v.inventory_quantity::bigint) * (v.cost::bigint) ELSE 0 END)::bigint AS low_stock_value
  FROM public.product_variants v
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL
    AND v.deleted_at IS NULL
),
variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.cancelled_at IS NULL
  GROUP BY li.variant_id
),
dead_stock AS (
  SELECT
    COALESCE(SUM((v.inventory_quantity::bigint) * (v.cost::bigint)), 0)::bigint AS value
  FROM public.product_variants v
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  LEFT JOIN public.company_settings cs ON cs.company_id = v.company_id
  WHERE v.company_id = p_company_id
    AND v.cost IS NOT NULL
    AND v.deleted_at IS NULL
    AND v.inventory_quantity > 0
    AND (
      ls.last_sale_at IS NULL
      OR ls.last_sale_at < (now() - make_interval(days => COALESCE(cs.dead_stock_days, 90)))
    )
),
current_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM filtered_orders
),
previous_period AS (
  SELECT
    COALESCE(COUNT(*), 0)::bigint                      AS orders,
    COALESCE(SUM(total_amount), 0)::bigint             AS revenue,
    COALESCE(COUNT(DISTINCT customer_id), 0)::bigint   AS customers
  FROM prev_filtered_orders
)
SELECT
  (SELECT orders    FROM current_period) AS total_orders,
  (SELECT revenue   FROM current_period) AS total_revenue,
  (SELECT customers FROM current_period) AS total_customers,

  COALESCE((
    SELECT SUM(pv.inventory_quantity)
    FROM public.product_variants pv
    WHERE pv.company_id = p_company_id AND pv.deleted_at IS NULL
  ), 0)::bigint AS inventory_count,

  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object('date', to_char(day, 'YYYY-MM-DD'), 'revenue', revenue, 'orders', orders)
      ORDER BY day
    )
    FROM day_series
  ), '[]'::jsonb) AS sales_series,

  COALESCE((SELECT jsonb_agg(to_jsonb(tp)) FROM top_products tp), '[]'::jsonb) AS top_products,

  jsonb_build_object(
    'total_value',     COALESCE((SELECT total_value     FROM inventory_values), 0),
    'in_stock_value',  COALESCE((SELECT in_stock_value  FROM inventory_values), 0),
    'low_stock_value', COALESCE((SELECT low_stock_value FROM inventory_values), 0),
    'dead_stock_value',COALESCE((SELECT value           FROM dead_stock), 0)
  ) AS inventory_summary,

  CASE WHEN (SELECT revenue FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT revenue FROM current_period)::float
             - (SELECT revenue FROM previous_period)::float)
             / (SELECT revenue FROM previous_period)::float) * 100
  END AS revenue_change,
  CASE WHEN (SELECT orders FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT orders FROM current_period)::float
             - (SELECT orders FROM previous_period)::float)
             / (SELECT orders FROM previous_period)::float) * 100
  END AS orders_change,
  CASE WHEN (SELECT customers FROM previous_period) = 0
       THEN 0.0
       ELSE (((SELECT customers FROM current_period)::float
             - (SELECT customers FROM previous_period)::float)
             / (SELECT customers FROM previous_period)::float) * 100
  END AS customers_change,

  COALESCE((SELECT value FROM dead_stock), 0)::bigint AS dead_stock_value;
$$;


-- Add performance indexes
CREATE INDEX IF NOT EXISTS idx_orders_company_created ON public.orders(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_orders_company_not_cancelled ON public.orders(company_id) WHERE cancelled_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_olis_order ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_olis_company_variant ON public.order_line_items(company_id, variant_id);
CREATE INDEX IF NOT EXISTS idx_products_company ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_not_deleted ON public.product_variants(company_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_customers_company ON public.customers(company_id);
