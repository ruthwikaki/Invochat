
-- This function is called by a trigger when a new user signs up in Supabase Auth.
-- It creates a corresponding company and user profile in the public schema.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Generate new company ID
  new_company_id := gen_random_uuid();
  
  -- Create company
  INSERT INTO public.companies (id, name, owner_id, created_at)
  VALUES (
    new_company_id,
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id,
    now()
  );

  -- Create user record
  INSERT INTO public.users (id, company_id, email, role, created_at)
  VALUES (
    NEW.id,
    new_company_id,
    NEW.email,
    'Owner',
    now()
  );

  -- Create company settings with defaults
  INSERT INTO public.company_settings (
    company_id,
    dead_stock_days,
    fast_moving_days,
    predictive_stock_days,
    currency,
    timezone,
    overstock_multiplier,
    high_value_threshold,
    tax_rate
  )
  VALUES (
    new_company_id,
    90,  -- dead_stock_days
    30,  -- fast_moving_days
    7,   -- predictive_stock_days
    'USD',
    'UTC',
    3, -- overstock_multiplier
    100000, -- high_value_threshold
    0
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log the error but don't fail the user creation
  RAISE LOG 'Error in handle_new_user for user %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

-- Drop the old trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger that calls the function
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- RLS for companies table
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company." ON public.companies
  FOR SELECT USING (id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  ));

-- RLS for company_users table
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see other members of their own company." ON public.company_users;
CREATE POLICY "Users can see other members of their own company." ON public.company_users
  FOR SELECT USING (company_id = (
    SELECT company_id FROM public.company_users WHERE user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "Owners or Admins can insert new users into their company." ON public.company_users;
CREATE POLICY "Owners or Admins can insert new users into their company." ON public.company_users
  FOR INSERT WITH CHECK (
    company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid())
    AND (
      SELECT role FROM public.company_users WHERE user_id = auth.uid()
    ) IN ('Owner', 'Admin')
  );
DROP POLICY IF EXISTS "Owners or Admins can update roles in their company." ON public.company_users;
CREATE POLICY "Owners or Admins can update roles in their company." ON public.company_users
  FOR UPDATE USING (
    company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid())
    AND (
      SELECT role FROM public.company_users WHERE user_id = auth.uid()
    ) IN ('Owner', 'Admin')
  );

-- RLS for all other tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's products." ON public.products;
CREATE POLICY "Authenticated users can manage their own company's products." ON public.products
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's product variants." ON public.product_variants;
CREATE POLICY "Authenticated users can manage their own company's product variants." ON public.product_variants
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's orders." ON public.orders;
CREATE POLICY "Authenticated users can manage their own company's orders." ON public.orders
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's order line items." ON public.order_line_items;
CREATE POLICY "Authenticated users can manage their own company's order line items." ON public.order_line_items
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's customers." ON public.customers;
CREATE POLICY "Authenticated users can manage their own company's customers." ON public.customers
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's suppliers." ON public.suppliers;
CREATE POLICY "Authenticated users can manage their own company's suppliers." ON public.suppliers
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's integrations." ON public.integrations;
CREATE POLICY "Authenticated users can manage their own company's integrations." ON public.integrations
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's settings." ON public.company_settings;
CREATE POLICY "Authenticated users can manage their own company's settings." ON public.company_settings
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own conversations." ON public.conversations;
CREATE POLICY "Authenticated users can manage their own conversations." ON public.conversations
  FOR ALL USING (user_id = auth.uid() AND company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (user_id = auth.uid() AND company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
  
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own messages." ON public.messages;
CREATE POLICY "Authenticated users can manage their own messages." ON public.messages
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
  
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's purchase orders." ON public.purchase_orders;
CREATE POLICY "Authenticated users can manage their own company's purchase orders." ON public.purchase_orders
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's PO line items." ON public.purchase_order_line_items;
CREATE POLICY "Authenticated users can manage their own company's PO line items." ON public.purchase_order_line_items
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
  
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's channel fees." ON public.channel_fees;
CREATE POLICY "Authenticated users can manage their own company's channel fees." ON public.channel_fees
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));
  
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins and Owners can view their company's audit log." ON public.audit_log;
CREATE POLICY "Admins and Owners can view their company's audit log." ON public.audit_log
  FOR SELECT USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()) AND (SELECT role FROM public.company_users WHERE user_id = auth.uid()) IN ('Admin', 'Owner'));

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can manage their own company's feedback." ON public.feedback;
CREATE POLICY "Authenticated users can manage their own company's feedback." ON public.feedback
  FOR ALL USING (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.company_users WHERE user_id = auth.uid()));

-- Function to get a user's company ID
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
DECLARE
  company_uuid uuid;
BEGIN
  SELECT company_id INTO company_uuid
  FROM public.company_users
  WHERE user_id = p_user_id;
  
  RETURN company_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Full text search on products
CREATE OR REPLACE FUNCTION public.products_fts_trigger()
RETURNS TRIGGER AS $$
BEGIN
  NEW.fts_document :=
    to_tsvector('english', coalesce(NEW.title, '')) ||
    to_tsvector('english', coalesce(NEW.description, '')) ||
    to_tsvector('english', coalesce(NEW.product_type, '')) ||
    to_tsvector('english', array_to_string(NEW.tags, ' '));
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_products_fts ON public.products;
CREATE TRIGGER update_products_fts
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.products_fts_trigger();


-- Set up Storage policies
INSERT into storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
values ('product_images', 'product_images', true, false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Product images are viewable by everyone." ON storage.objects;
CREATE POLICY "Product images are viewable by everyone." ON storage.objects
  FOR SELECT USING (bucket_id = 'product_images');

DROP POLICY IF EXISTS "Authenticated users can upload product images." ON storage.objects;
CREATE POLICY "Authenticated users can upload product images." ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'product_images' AND
    auth.uid() IS NOT NULL
  );

DROP POLICY IF EXISTS "Authenticated users can update their own product images." ON storage.objects;
CREATE POLICY "Authenticated users can update their own product images." ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'product_images' AND
    auth.uid() IS NOT NULL
  );

-- Create a view for product variants with essential product details for easy querying.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;
    

-- A view to simplify fetching POs with their line items and supplier info
CREATE OR REPLACE VIEW public.purchase_orders_view AS
SELECT
    po.*,
    s.name as supplier_name,
    (
        SELECT json_agg(json_build_object(
            'id', pli.id,
            'sku', pv.sku,
            'product_name', p.title,
            'quantity', pli.quantity,
            'cost', pli.cost
        ))
        FROM purchase_order_line_items pli
        JOIN product_variants pv ON pli.variant_id = pv.id
        JOIN products p ON pv.product_id = p.id
        WHERE pli.purchase_order_id = po.id
    ) as line_items
FROM
    purchase_orders po
LEFT JOIN
    suppliers s ON po.supplier_id = s.id;


-- A view to simplify fetching customer details with analytics
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    c.created_at
FROM
    customers c
LEFT JOIN
    orders o ON c.id = o.customer_id
GROUP BY
    c.id;


-- A view to simplify fetching order details with customer email
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    orders o
LEFT JOIN
    customers c ON o.customer_id = c.id;

-- A helper function to check user permissions inside other functions
CREATE OR REPLACE FUNCTION public.check_user_permission(
  p_user_id uuid,
  p_required_role company_role
)
RETURNS boolean AS $$
DECLARE
  user_role company_role;
BEGIN
  SELECT role INTO user_role FROM public.company_users WHERE user_id = p_user_id;

  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;

  IF p_required_role = 'Owner' THEN
    RETURN user_role = 'Owner';
  ELSIF p_required_role = 'Admin' THEN
    RETURN user_role IN ('Owner', 'Admin');
  END IF;
  
  RETURN TRUE; -- If no specific role is required, any role is fine
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to get historical sales for a set of SKUs, aggregated by month.
CREATE OR REPLACE FUNCTION public.get_historical_sales_for_skus(p_company_id uuid, p_skus text[])
RETURNS TABLE(sku text, monthly_sales jsonb) AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales_data AS (
        SELECT
            pv.sku,
            date_trunc('month', o.created_at)::date AS month,
            SUM(oli.quantity) AS total_quantity
        FROM
            order_line_items oli
        JOIN
            orders o ON oli.order_id = o.id
        JOIN
            product_variants pv ON oli.variant_id = pv.id
        WHERE
            o.company_id = p_company_id
            AND pv.sku = ANY(p_skus)
            AND o.created_at >= now() - interval '24 months'
        GROUP BY
            pv.sku, month
    )
    SELECT
        msd.sku,
        jsonb_agg(jsonb_build_object(
            'month', msd.month,
            'total_quantity', msd.total_quantity
        ) ORDER BY msd.month) AS monthly_sales
    FROM
        monthly_sales_data msd
    GROUP BY
        msd.sku;
END;
$$ LANGUAGE plpgsql;

-- A more comprehensive materialized view for daily sales summaries
CREATE MATERIALIZED VIEW public.daily_sales_summary AS
SELECT
    company_id,
    date_trunc('day', created_at)::date as sale_date,
    SUM(total_amount) as total_revenue,
    COUNT(id) as total_orders,
    COUNT(DISTINCT customer_id) as unique_customers
FROM
    public.orders
GROUP BY
    company_id, sale_date;

CREATE UNIQUE INDEX ON public.daily_sales_summary(company_id, sale_date);

-- Function to refresh all materialized views for a specific company
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW public.daily_sales_summary;
END;
$$ LANGUAGE plpgsql;

-- Final setup: Create the required pg_cron extension for scheduled jobs if it doesn't exist
CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Ensure the pg_stat_statements extension is available for performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
