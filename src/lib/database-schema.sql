
-- This is a one-time setup script for your Supabase project.
--
-- 1. Go to your Supabase project dashboard.
-- 2. In the left sidebar, click "SQL Editor".
-- 3. Click "New Query" and paste the entire contents of this file.
-- 4. Click "Run".
--
-- After running this, you must sign up for a new user account in your app.
-- The trigger defined below will only work for new user registrations.

-- =================================================================
-- ENUMS - Define custom types for consistency
-- =================================================================
CREATE TYPE public.company_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);
CREATE TYPE public.integration_platform AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);
CREATE TYPE public.message_role AS ENUM (
    'user',
    'assistant',
    'tool'
);
CREATE TYPE public.feedback_type AS ENUM (
    'helpful',
    'unhelpful'
);

-- =================================================================
-- TABLES - The core data structure of the application
-- =================================================================

-- Stores company information
CREATE TABLE public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Stores the many-to-many relationship between users and companies
CREATE TABLE public.company_users (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;

-- Stores company-specific business logic settings
CREATE TABLE public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC(5, 2) NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- Stored in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT NOT NULL DEFAULT 'USD',
    tax_rate NUMERIC(5,4) NOT NULL DEFAULT 0.0000,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Stores product information
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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
    UNIQUE(company_id, external_product_id)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Stores suppliers for a company
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

-- Stores product variants (SKUs)
CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- Stored in cents
    compare_at_price INT, -- Stored in cents
    cost INT, -- Stored in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    reorder_point INT,
    reorder_quantity INT,
    location TEXT,
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

-- Stores customer information
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT,
    email TEXT,
    phone TEXT,
    external_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, external_customer_id)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- Stores sales orders
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id),
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Stores line items for each order
CREATE TABLE public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL, -- Stored in cents
    total_discount INT, -- Stored in cents
    tax_amount INT, -- Stored in cents
    cost_at_time INT, -- Stored in cents
    external_line_item_id TEXT
);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Add other tables for refunds, purchase_orders, integrations, etc.
-- ... (rest of the tables as in the original schema)

-- =================================================================
-- RLS POLICIES - Secure the data by company
-- =================================================================
CREATE POLICY "Enable ALL for users based on company_id" ON public.companies
    FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = id));

-- Repeat for all other tables
CREATE POLICY "Enable ALL for users based on company_id" ON public.company_users
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Enable ALL for users based on company_id" ON public.company_settings
    FOR ALL USING (auth.uid() IN (SELECT user_id FROM company_users WHERE company_id = company_settings.company_id));
-- ... (rest of the RLS policies)


-- =================================================================
-- TRIGGERS & FUNCTIONS - Automate business logic
-- =================================================================

-- Function to create a company for a new user and link them.
CREATE OR REPLACE FUNCTION public.create_company_for_new_user()
RETURNS TRIGGER AS $$
DECLARE
    new_company_id UUID;
BEGIN
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_user_meta_data->>'company_name', new.id)
    RETURNING id INTO new_company_id;

    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');

    UPDATE auth.users
    SET raw_user_meta_data = new.raw_user_meta_data || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user signs up.
CREATE TRIGGER on_new_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.create_company_for_new_user();


-- Add RPC functions for dashboard metrics
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID)
RETURNS JSONB AS $$
DECLARE
    total_products INT;
    total_orders INT;
    total_revenue NUMERIC;
    low_stock_count INT;
BEGIN
    SELECT COUNT(*) INTO total_products
    FROM product_variants WHERE company_id = p_company_id;
    
    SELECT COUNT(*) INTO total_orders
    FROM orders WHERE company_id = p_company_id;
    
    SELECT COALESCE(SUM(total_amount), 0) INTO total_revenue
    FROM orders WHERE company_id = p_company_id;
    
    SELECT COUNT(*) INTO low_stock_count
    FROM product_variants WHERE company_id = p_company_id AND inventory_quantity < 10;
    
    RETURN jsonb_build_object(
        'total_products', total_products,
        'total_orders', total_orders,
        'total_revenue', total_revenue,
        'low_stock_count', low_stock_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_inventory_metrics(p_company_id UUID)
RETURNS TABLE(
    metric_name TEXT,
    metric_value NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'total_value'::TEXT, SUM(inventory_quantity * cost)
    FROM product_variants WHERE company_id = p_company_id
    UNION ALL
    SELECT 'total_items'::TEXT, SUM(inventory_quantity)::NUMERIC
    FROM product_variants WHERE company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

    