
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop dependent views first to allow table modifications
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Create companies table
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow individual read access" ON public.companies FOR SELECT USING (auth.uid() IN (SELECT user_id FROM users WHERE company_id = id));

-- Create users table to link auth.users with companies
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role TEXT CHECK (role IN ('owner', 'admin', 'member')) DEFAULT 'member',
    created_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to view their own company users" ON public.users FOR SELECT USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Function to create a company and link the first user (owner)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_var UUID;
  user_role TEXT;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO company_id_var;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id_var, new.email, 'owner');

  -- Update the user's app_metadata with the company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id_var, 'role', 'owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the function on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Create company_settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
    high_value_threshold NUMERIC NOT NULL DEFAULT 1000,
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access settings" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.products ALTER COLUMN title SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.products FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify product_variants table
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;
ALTER TABLE public.product_variants ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN inventory_quantity SET DEFAULT 0;
ALTER TABLE public.product_variants ALTER COLUMN title DROP NOT NULL;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify suppliers table
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.suppliers ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE public.suppliers ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify orders table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify order_line_items table
ALTER TABLE public.order_line_items ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify customers table
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify purchase_orders table
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify purchase_order_line_items table
ALTER TABLE public.purchase_order_line_items ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.purchase_order_line_items FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify inventory_ledger table
ALTER TABLE public.inventory_ledger ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Modify integrations table
ALTER TABLE public.integrations ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow full access to company members" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM users WHERE id = auth.uid()));

-- Recreate the view with all necessary columns
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.product_type AS category,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


-- Secure search function
CREATE OR REPLACE FUNCTION public.search_products(p_company_id UUID, p_query TEXT)
RETURNS TABLE (
    product_id UUID,
    variant_id UUID,
    product_title TEXT,
    variant_title TEXT,
    sku TEXT,
    image_url TEXT,
    rank REAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS product_id,
        pv.id AS variant_id,
        p.title AS product_title,
        pv.title AS variant_title,
        pv.sku,
        p.image_url,
        ts_rank_cd(p.fts, websearch_to_tsquery('english', p_query)) AS rank
    FROM
        public.products p
    JOIN
        public.product_variants pv ON p.id = pv.product_id
    WHERE
        p.company_id = p_company_id
        AND p.fts @@ websearch_to_tsquery('english', p_query)
    ORDER BY
        rank DESC;
END;
$$;


-- Add Full-Text Search Vector
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts tsvector
GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || coalesce(description, '') || ' ' || coalesce(product_type, ''))) STORED;

-- Create index on the FTS vector
CREATE INDEX IF NOT EXISTS products_fts_idx ON public.products USING gin(fts);

-- Add other crucial indexes
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_line_items_variant_id ON public.purchase_order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_variant ON public.inventory_ledger(company_id, variant_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);

-- Ensure all tables are owned by the correct roles
ALTER TABLE public.companies OWNER TO postgres;
ALTER TABLE public.users OWNER TO postgres;
ALTER TABLE public.company_settings OWNER TO postgres;
ALTER TABLE public.products OWNER TO postgres;
ALTER TABLE public.product_variants OWNER TO postgres;
ALTER TABLE public.suppliers OWNER TO postgres;
ALTER TABLE public.orders OWNER TO postgres;
ALTER TABLE public.order_line_items OWNER TO postgres;
ALTER TABLE public.customers OWNER TO postgres;
ALTER TABLE public.purchase_orders OWNER TO postgres;
ALTER TABLE public.purchase_order_line_items OWNER TO postgres;
ALTER TABLE public.inventory_ledger OWNER TO postgres;
ALTER TABLE public.integrations OWNER TO postgres;
ALTER TABLE public.conversations OWNER TO postgres;
ALTER TABLE public.messages OWNER TO postgres;
ALTER TABLE public.webhook_events OWNER TO postgres;
ALTER TABLE public.export_jobs OWNER TO postgres;
ALTER TABLE public.audit_log OWNER TO postgres;

GRANT ALL ON TABLE public.companies TO postgres, service_role;
GRANT ALL ON TABLE public.users TO postgres, service_role;
GRANT ALL ON TABLE public.company_settings TO postgres, service_role;
GRANT ALL ON TABLE public.products TO postgres, service_role;
GRANT ALL ON TABLE public.product_variants TO postgres, service_role;
GRANT ALL ON TABLE public.suppliers TO postgres, service_role;
GRANT ALL ON TABLE public.orders TO postgres, service_role;
GRANT ALL ON TABLE public.order_line_items TO postgres, service_role;
GRANT ALL ON TABLE public.customers TO postgres, service_role;
GRANT ALL ON TABLE public.purchase_orders TO postgres, service_role;
GRANT ALL ON TABLE public.purchase_order_line_items TO postgres, service_role;
GRANT ALL ON TABLE public.inventory_ledger TO postgres, service_role;
GRANT ALL ON TABLE public.integrations TO postgres, service_role;
GRANT ALL ON TABLE public.conversations TO postgres, service_role;
GRANT ALL ON TABLE public.messages TO postgres, service_role;
GRANT ALL ON TABLE public.webhook_events TO postgres, service_role;
GRANT ALL ON TABLE public.export_jobs TO postgres, service_role;
GRANT ALL ON TABLE public.audit_log TO postgres, service_role;

GRANT ALL ON FUNCTION public.handle_new_user() TO postgres, service_role;
GRANT ALL ON FUNCTION public.search_products(UUID, TEXT) TO postgres, service_role, authenticated;

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA realtime TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

-- Grant sequence permissions
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA realtime TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO postgres, service_role;
