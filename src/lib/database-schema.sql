
-- Enable the UUID extension if it doesn't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pg_stat_statements extension for performance monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Enable the pgcrypto extension for hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Function to safely cast a value to integer, returning NULL if it fails
CREATE OR REPLACE FUNCTION safe_cast_to_int(text_value TEXT)
RETURNS INT AS $$
BEGIN
    RETURN text_value::INT;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Set up Row-Level Security (RLS) for all tables
-- This is a placeholder and should be implemented for each table.

--
-- Companies Table: Stores information about each company using the app.
--
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

--
-- Users Table: Stores user information, linked to a company.
--
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    company_id UUID REFERENCES companies(id),
    email TEXT UNIQUE NOT NULL,
    role TEXT NOT NULL DEFAULT 'Member', -- e.g., 'Owner', 'Admin', 'Member'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to see their own company's users" ON users
FOR SELECT USING (
    auth.uid() IN (
        SELECT id FROM users WHERE company_id = users.company_id
    )
);

CREATE POLICY "Allow owners to manage their company's users" ON users
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM users u
        WHERE u.id = auth.uid()
        AND u.company_id = users.company_id
        AND u.role = 'Owner'
    )
);

--
-- Company Settings Table
--
CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier NUMERIC(5, 2) NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    currency VARCHAR(3) DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own company's settings" ON company_settings
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = company_settings.company_id));

--
-- Suppliers Table: Stores supplier/vendor information.
--
CREATE TABLE IF NOT EXISTS suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own company's suppliers" ON suppliers
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = suppliers.company_id));

--
-- Inventory Table: The core table for products and their metadata.
--
CREATE TABLE IF NOT EXISTS inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT,
    price INT, -- in cents
    cost INT NOT NULL, -- in cents
    quantity INT NOT NULL DEFAULT 0,
    reorder_point INT,
    reorder_quantity INT,
    lead_time_days INT,
    supplier_id UUID REFERENCES suppliers(id),
    barcode TEXT,
    source_platform TEXT, -- e.g., 'shopify', 'woocommerce', 'manual'
    external_product_id TEXT,
    external_variant_id TEXT,
    external_quantity INT, -- To track quantity from external system for reconciliation
    last_sync_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, source_platform, external_product_id, external_variant_id)
);
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's inventory" ON inventory
FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = inventory.company_id));
CREATE POLICY "Allow admins to manage their own company's inventory" ON inventory
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = inventory.company_id AND role IN ('Admin', 'Owner')));

--
-- Inventory Ledger Table: Tracks all stock movements for auditing.
--
CREATE TABLE IF NOT EXISTS inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    product_id UUID NOT NULL REFERENCES inventory(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'return', 'restock', 'adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., sale_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's ledger" ON inventory_ledger
FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = inventory_ledger.company_id));

--
-- Customers Table
--
CREATE TABLE IF NOT EXISTS customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    customer_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    external_id TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, email)
);
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own company's customers" ON customers
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = customers.company_id));

--
-- Sales Table: Records each sale transaction.
--
CREATE TABLE IF NOT EXISTS sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id),
    sale_number TEXT NOT NULL,
    customer_id UUID REFERENCES customers(id),
    customer_name TEXT,
    customer_email TEXT,
    total_amount INT NOT NULL, -- in cents
    total_cost INT, -- in cents
    payment_method TEXT NOT NULL,
    external_id TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own company's sales" ON sales
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = sales.company_id));

--
-- Sale Items Table: Links products to a sale.
--
CREATE TABLE IF NOT EXISTS sale_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id),
    product_id UUID NOT NULL REFERENCES inventory(id),
    quantity INT NOT NULL,
    unit_price INT NOT NULL, -- in cents, at time of sale
    cost_at_time INT -- in cents, at time of sale
);
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's sale items" ON sale_items
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = sale_items.company_id));

--
-- Integrations Table
--
CREATE TABLE IF NOT EXISTS integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL, -- e.g., 'shopify', 'woocommerce'
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT, -- e.g., 'syncing_products', 'syncing_sales', 'success', 'failed', 'idle'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, platform)
);
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own company's integrations" ON integrations
FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = integrations.company_id));

--
-- Audit Log Table
--
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    company_id UUID REFERENCES companies(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's audit log" ON audit_log
FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = audit_log.company_id));

--
-- Function to handle new user sign-ups
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_company_name TEXT;
BEGIN
  -- Create a new company for the user
  user_company_name := NEW.raw_user_meta_data->>'company_name';
  IF user_company_name IS NULL OR user_company_name = '' THEN
    user_company_name := NEW.email;
  END IF;

  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Insert the user into our public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');

  -- Update the user's app_metadata in auth.users
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  )
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--
-- Trigger to call the function on new user sign-up
--
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

--
-- Materialized view for faster dashboard queries
--
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) AS inventory_value,
    COUNT(i.id) AS total_skus,
    SUM(CASE WHEN i.quantity <= i.reorder_point THEN 1 ELSE 0 END)::int AS low_stock_count
FROM inventory i
WHERE i.deleted_at IS NULL
GROUP BY i.company_id;

-- Function to refresh materialized views
CREATE OR REPLACE FUNCTION refresh_materialized_views(p_company_id UUID)
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY company_dashboard_metrics;
END;
$$ LANGUAGE plpgsql;

-- Get cash flow insights
CREATE OR REPLACE FUNCTION get_cash_flow_insights(p_company_id UUID)
RETURNS TABLE (
    dead_stock_value BIGINT,
    slow_mover_value BIGINT,
    dead_stock_threshold_days INT
) AS $$
DECLARE
    v_dead_stock_days INT;
BEGIN
    SELECT cs.dead_stock_days INTO v_dead_stock_days
    FROM company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN QUERY
    WITH stock_ages AS (
        SELECT
            i.id,
            i.quantity,
            i.cost,
            COALESCE(
                (SELECT EXTRACT(DAY FROM NOW() - MAX(s.created_at))
                 FROM sales s
                 JOIN sale_items si ON s.id = si.sale_id
                 WHERE si.product_id = i.id),
                9999
            ) as days_since_last_sale
        FROM inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    )
    SELECT
        COALESCE(SUM(CASE WHEN sa.days_since_last_sale > v_dead_stock_days THEN sa.quantity * sa.cost ELSE 0 END), 0)::BIGINT AS dead_stock_value,
        COALESCE(SUM(CASE WHEN sa.days_since_last_sale BETWEEN 31 AND v_dead_stock_days THEN sa.quantity * sa.cost ELSE 0 END), 0)::BIGINT AS slow_mover_value,
        v_dead_stock_days
    FROM stock_ages sa;
END;
$$ LANGUAGE plpgsql;


-- Grant usage on the public schema
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- Grant all privileges on all tables to postgres, anon, authenticated, service_role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
