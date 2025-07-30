-- InvoChat Database Schema
-- Version: 2.1.0
-- Description: Complete schema including tables, roles, RLS, and functions.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Enable vector extension for AI embeddings
CREATE EXTENSION IF NOT EXISTS "vector";


-- Grant usage to necessary roles
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON FUNCTION uuid_generate_v4() TO postgres, anon, authenticated, service_role;


-- ========== ENUMS (Custom Types) ==========
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- ========== TABLES ==========

-- Companies Table: Stores information about each company tenant.
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company tenant information.';

-- Company Users Table: Manages user roles within each company (many-to-many).
CREATE TABLE IF NOT EXISTS public.company_users (
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);
COMMENT ON TABLE public.company_users IS 'Manages user roles within each company.';

-- Products Table: Central repository for all product information.
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT DEFAULT 'active',
    image_url TEXT,
    external_product_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
COMMENT ON TABLE public.products IS 'Stores master product information.';


-- Product Variants Table: Stores individual SKUs for each product.
CREATE TABLE IF NOT EXISTS public.product_variants (
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
    price INT, -- Stored in cents
    compare_at_price INT, -- Stored in cents
    cost INT, -- Stored in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    reorder_point INT,
    reorder_quantity INT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
COMMENT ON TABLE public.product_variants IS 'Stores individual stock-keeping units (SKUs) for each product.';

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    notes TEXT,
    default_lead_time_days INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.suppliers IS 'Stores information about product suppliers and vendors.';

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id TEXT,
    name TEXT,
    email TEXT,
    phone TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);
COMMENT ON TABLE public.customers IS 'Stores customer information.';

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL,
    total_tax INT,
    total_shipping INT,
    total_discounts INT,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.orders IS 'Stores sales order information.';

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
COMMENT ON TABLE public.order_line_items IS 'Stores individual line items for each sales order.';

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., order_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.inventory_ledger IS 'Records all stock movements for auditing purposes.';

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    notes TEXT,
    idempotency_key UUID
);
COMMENT ON TABLE public.purchase_orders IS 'Stores purchase order information for incoming inventory.';

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity INT NOT NULL,
    cost INT NOT NULL -- Stored in cents
);
COMMENT ON TABLE public.purchase_order_line_items IS 'Stores individual line items for each purchase order.';


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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
COMMENT ON TABLE public.integrations IS 'Stores integration settings for third-party platforms.';

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false
);
COMMENT ON TABLE public.conversations IS 'Stores metadata for AI chat conversations.';

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role message_role NOT NULL,
    content TEXT NOT NULL,
    component TEXT,
    "componentProps" JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    "isError" BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.messages IS 'Stores individual messages within an AI chat conversation.';

-- Feedback Table
CREATE TABLE IF NOT EXISTS public.feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id TEXT NOT NULL,
    subject_type TEXT NOT NULL, -- e.g., 'message', 'alert'
    feedback feedback_type NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.feedback IS 'Stores user feedback on AI responses and other features.';

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE public.audit_log IS 'Records significant events and actions within the system for auditing.';

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- Stored in cents
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    alert_settings JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
COMMENT ON TABLE public.company_settings IS 'Stores business logic settings for a company.';

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee INT NOT NULL, -- In cents
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);
COMMENT ON TABLE public.channel_fees IS 'Stores fees associated with different sales channels.';

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
COMMENT ON TABLE public.webhook_events IS 'Stores received webhook IDs to prevent replay attacks.';

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
COMMENT ON TABLE public.export_jobs IS 'Tracks user-requested data export jobs.';


-- Alert History Table
CREATE TABLE IF NOT EXISTS public.alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    status TEXT DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'dismissed')),
    created_at TIMESTAMPTZ DEFAULT now(),
    read_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    UNIQUE(company_id, alert_id)
);
COMMENT ON TABLE public.alert_history IS 'Tracks user interaction with specific alerts.';

-- ========== INDEXES (for Performance) ==========
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants (company_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger (variant_id);
CREATE INDEX IF NOT EXISTS idx_po_company_supplier ON public.purchase_orders (company_id, supplier_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations (company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations (user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages (conversation_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id ON public.audit_log(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_analytics ON public.orders(company_id, created_at, financial_status) WHERE financial_status IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_history ON public.inventory_ledger(variant_id, created_at, change_type);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_timeline ON public.messages(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_alert_history_lookup ON public.alert_history(company_id, alert_id, status, dismissed_at);
-- Partial index for quickly finding low-stock items
CREATE INDEX IF NOT EXISTS idx_variants_low_stock ON public.product_variants(company_id, inventory_quantity, id) WHERE inventory_quantity <= 50 AND deleted_at IS NULL;

-- ========== ROW-LEVEL SECURITY (RLS) ==========
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;

-- Function to get the company ID for the currently authenticated user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    company_uuid UUID;
BEGIN
    SELECT company_id INTO company_uuid
    FROM public.company_users
    WHERE user_id = p_user_id;
    RETURN company_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- RLS Policies
CREATE POLICY "Allow company members to access their own company records"
    ON public.companies FOR SELECT
    USING (id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow users to see their own user-company link"
    ON public.company_users FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Allow company members to manage their data"
    ON public.products FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.product_variants FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));
    
CREATE POLICY "Allow company members to manage their data"
    ON public.suppliers FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.customers FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.orders FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.order_line_items FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.inventory_ledger FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.purchase_orders FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.purchase_order_line_items FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.integrations FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow users to manage their own conversations"
    ON public.conversations FOR ALL
    USING (user_id = auth.uid());

CREATE POLICY "Allow users to manage their own messages"
    ON public.messages FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow users to manage their own feedback"
    ON public.feedback FOR ALL
    USING (user_id = auth.uid());

CREATE POLICY "Allow admins/owners to view audit logs for their company"
    ON public.audit_log FOR SELECT
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow admins/owners to manage company settings"
    ON public.company_settings FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.channel_fees FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Allow company members to manage their data"
    ON public.webhook_events FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));
    
CREATE POLICY "Allow users to manage their own export jobs"
    ON public.export_jobs FOR ALL
    USING (requested_by_user_id = auth.uid());
    
CREATE POLICY "Allow company members to manage their data"
    ON public.alert_history FOR ALL
    USING (company_id = public.get_company_id_for_user(auth.uid()));
    
-- ========== DATABASE FUNCTIONS ==========

-- Function to handle new user signup
-- This is a critical function that creates a new company for the user
-- and links them together in the company_users table.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id UUID;
  user_company_name TEXT;
BEGIN
  -- Extract company_name from metadata, fall back to a default name
  user_company_name := COALESCE(new.raw_user_meta_data->>'company_name', new.email || '''s Company');

  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (user_company_name, new.id)
  RETURNING id INTO new_company_id;

  -- Link the new user to the new company as an 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ========== TRIGGERS ==========

-- Trigger to call handle_new_user on new user creation in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update 'updated_at' timestamps automatically
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply the updated_at trigger to all relevant tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN (SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at' AND table_schema = 'public')
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I; CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();', t_name, t_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to check user permission level
CREATE OR REPLACE FUNCTION public.check_user_permission(
    p_user_id UUID,
    p_required_role company_role
) RETURNS BOOLEAN AS $$
DECLARE
    user_role company_role;
BEGIN
    SELECT role INTO user_role
    FROM public.company_users
    WHERE user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Admin' THEN
        RETURN user_role IN ('Admin', 'Owner');
    ELSIF p_required_role = 'Owner' THEN
        RETURN user_role = 'Owner';
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Function to get all alerts for a company, including read/dismissed status
CREATE OR REPLACE FUNCTION public.get_alerts_with_status(p_company_id UUID)
RETURNS JSON[] AS $$
DECLARE
    alerts JSON[];
    r RECORD;
    settings RECORD;
    alert_history_record RECORD;
BEGIN
    -- Get company-specific settings
    SELECT * INTO settings FROM public.company_settings WHERE company_id = p_company_id;

    -- Low Stock Alerts
    FOR r IN (
        SELECT 
            v.id,
            v.sku,
            p.title AS product_name,
            v.inventory_quantity,
            v.reorder_point
        FROM public.product_variants v
        JOIN public.products p ON v.product_id = p.id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity <= COALESCE((settings.alert_settings->>'low_stock_threshold')::int, 10)
          AND v.inventory_quantity > 0
          AND v.deleted_at IS NULL
          AND p.deleted_at IS NULL
    ) LOOP
        -- Check if this alert was recently dismissed
        SELECT * INTO alert_history_record 
        FROM public.alert_history 
        WHERE company_id = p_company_id 
          AND alert_id = 'low_stock_' || r.id
          AND status = 'dismissed'
          AND dismissed_at > (now() - interval '24 hours');
        
        -- Only include if not recently dismissed
        IF alert_history_record IS NULL THEN
            -- Check read status
            SELECT * INTO alert_history_record 
            FROM public.alert_history 
            WHERE company_id = p_company_id 
              AND alert_id = 'low_stock_' || r.id;
            
            alerts := array_append(alerts, json_build_object(
                'id', 'low_stock_' || r.id,
                'type', 'low_stock',
                'title', 'Low Stock Warning',
                'message', r.product_name || ' is running low on stock (' || r.inventory_quantity || ' left).',
                'severity', CASE 
                    WHEN r.inventory_quantity <= COALESCE((settings.alert_settings->>'critical_stock_threshold')::int, 5) 
                    THEN 'critical' 
                    ELSE 'warning' 
                END,
                'timestamp', now(),
                'read', COALESCE(alert_history_record.status = 'read', false),
                'metadata', json_build_object(
                    'productId', r.id,
                    'productName', r.product_name,
                    'sku', r.sku,
                    'currentStock', r.inventory_quantity,
                    'reorderPoint', r.reorder_point
                )
            ));
        END IF;
    END LOOP;

    RETURN alerts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_company_id_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres;
GRANT EXECUTE ON FUNCTION public.set_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.check_user_permission(UUID, company_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_alerts_with_status(UUID) to authenticated;
