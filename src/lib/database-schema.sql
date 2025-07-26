
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- Create the companies table to support multi-tenancy.
CREATE TABLE
  public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name text NOT NULL,
    owner_id uuid NOT NULL,
    CONSTRAINT companies_pkey PRIMARY KEY (id),
    CONSTRAINT companies_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;

-- Create the company_users table to link users to companies with roles.
CREATE TABLE
  public.company_users (
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.company_role NOT NULL DEFAULT 'Member'::public.company_role,
    CONSTRAINT company_users_pkey PRIMARY KEY (user_id, company_id),
    CONSTRAINT company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;

-- Create the products table to store base product information.
CREATE TABLE
  public.products (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    title text NOT NULL,
    description text NULL,
    handle text NULL,
    product_type text NULL,
    tags text[] NULL,
    status text NULL,
    image_url text NULL,
    external_product_id text NULL,
    updated_at timestamp with time zone NULL,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;
CREATE UNIQUE INDEX products_company_id_external_product_id_idx ON public.products USING btree (company_id, external_product_id) TABLESPACE pg_default;
CREATE INDEX products_company_id_idx ON public.products USING btree (company_id) TABLESPACE pg_default;

-- Create the suppliers table.
CREATE TABLE
  public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text NULL,
    phone text NULL,
    notes text NULL,
    default_lead_time_days integer NULL,
    updated_at timestamp with time zone NULL,
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;

-- Create the product_variants table. This is the core inventory table.
CREATE TABLE
  public.product_variants (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    title text NULL,
    option1_name text NULL,
    option1_value text NULL,
    option2_name text NULL,
    option2_value text NULL,
    option3_name text NULL,
    option3_value text NULL,
    barcode text NULL,
    price integer NULL,
    compare_at_price integer NULL,
    cost integer NULL,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text NULL,
    supplier_id uuid NULL,
    reorder_point integer NULL,
    reorder_quantity integer NULL,
    external_variant_id text NULL,
    updated_at timestamp with time zone NULL,
    CONSTRAINT product_variants_pkey PRIMARY KEY (id),
    CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT product_variants_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers (id) ON UPDATE CASCADE ON DELETE SET NULL
  ) TABLESPACE pg_default;
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_idx ON public.product_variants USING btree (company_id, external_variant_id) TABLESPACE pg_default;
CREATE UNIQUE INDEX product_variants_company_id_sku_idx ON public.product_variants USING btree (company_id, sku) TABLESPACE pg_default;
CREATE INDEX product_variants_company_id_idx ON public.product_variants USING btree (company_id) TABLESPACE pg_default;

-- Create the customers table.
CREATE TABLE
  public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    name text NULL,
    email text NULL,
    phone text NULL,
    external_customer_id text NULL,
    updated_at timestamp with time zone NULL,
    deleted_at timestamp with time zone NULL,
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;
CREATE INDEX customers_company_id_idx ON public.customers USING btree (company_id) TABLESPACE pg_default;


-- Create the orders table.
CREATE TABLE
  public.orders (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text NULL,
    customer_id uuid NULL,
    financial_status text NULL,
    fulfillment_status text NULL,
    currency text NULL,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer NULL,
    total_shipping integer NULL,
    total_discounts integer NULL,
    total_amount integer NOT NULL,
    source_platform text NULL,
    updated_at timestamp with time zone NULL,
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers (id) ON UPDATE CASCADE ON DELETE SET NULL
  ) TABLESPACE pg_default;
CREATE INDEX orders_company_id_created_at_idx ON public.orders USING btree (company_id, created_at DESC) TABLESPACE pg_default;
CREATE INDEX orders_company_id_idx ON public.orders USING btree (company_id) TABLESPACE pg_default;


-- Create the order_line_items table.
CREATE TABLE
  public.order_line_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    order_id uuid NOT NULL,
    variant_id uuid NULL,
    company_id uuid NOT NULL,
    product_name text NULL,
    variant_title text NULL,
    sku text NULL,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer NULL,
    tax_amount integer NULL,
    cost_at_time integer NULL,
    external_line_item_id text NULL,
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants (id) ON UPDATE CASCADE ON DELETE SET NULL
  ) TABLESPACE pg_default;
CREATE INDEX order_line_items_company_id_idx ON public.order_line_items USING btree (company_id) TABLESPACE pg_default;
CREATE INDEX order_line_items_order_id_idx ON public.order_line_items USING btree (order_id) TABLESPACE pg_default;


-- Create the inventory_ledger table to track stock movements.
CREATE TABLE
  public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid NULL,
    notes text NULL,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;


-- Create the purchase_orders table.
CREATE TABLE
  public.purchase_orders (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    supplier_id uuid NULL,
    status text NOT NULL DEFAULT 'Draft'::text,
    po_number text NOT NULL,
    total_cost integer NOT NULL DEFAULT 0,
    expected_arrival_date date NULL,
    notes text NULL,
    updated_at timestamp with time zone NULL,
    idempotency_key uuid NULL,
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers (id) ON UPDATE CASCADE ON DELETE SET NULL
  ) TABLESPACE pg_default;


-- Create the purchase_order_line_items table.
CREATE TABLE
  public.purchase_order_line_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    purchase_order_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    company_id uuid NOT NULL,
    quantity integer NOT NULL,
    cost integer NOT NULL,
    CONSTRAINT purchase_order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT purchase_order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;


-- Create the integrations table to store connection details for third-party platforms.
CREATE TABLE
  public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4 (),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    company_id uuid NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text NULL,
    shop_name text NULL,
    is_active boolean NOT NULL DEFAULT true,
    last_sync_at timestamp with time zone NULL,
    sync_status text NULL,
    updated_at timestamp with time zone NULL,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies (id) ON UPDATE CASCADE ON DELETE CASCADE
  ) TABLESPACE pg_default;


-- Create a table for managing chat conversations
CREATE TABLE public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false
);

-- Create a table for chat messages
CREATE TABLE public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    confidence real CHECK (confidence >= 0 AND confidence <= 1),
    assumptions text[],
    component text,
    componentProps jsonb,
    isError boolean,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Create the company_settings table
CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text NOT NULL DEFAULT 'USD',
    tax_rate real NOT NULL DEFAULT 0.0,
    timezone text NOT NULL DEFAULT 'UTC',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Create the channel_fees table
CREATE TABLE public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    fixed_fee integer,
    percentage_fee real,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- Create the audit_log table
CREATE TABLE public.audit_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Create the feedback table
CREATE TABLE public.feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Create export_jobs table
CREATE TABLE public.export_jobs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued',
  download_url text,
  expires_at timestamptz,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

-- Create imports table
CREATE TABLE public.imports (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  import_type text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  file_name text NOT NULL,
  total_rows integer,
  processed_rows integer,
  failed_rows integer,
  errors jsonb,
  summary jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

-- Create webhook_events table
CREATE TABLE public.webhook_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(integration_id, webhook_id)
);
-- 1. Enable RLS for all tables
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
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
-- 2. Create helper function to get company_id from user_id
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(user_id uuid)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id FROM public.company_users WHERE company_users.user_id = $1 LIMIT 1;
$$;

-- 3. Create policies
-- Companies: Users can only see their own company
CREATE POLICY "Users can see their own company"
ON public.companies
FOR SELECT
USING (id = public.get_company_id_for_user(auth.uid()));

-- company_users: Users can see other members of their company
CREATE POLICY "Users can see other members of their own company"
ON public.company_users
FOR SELECT
USING (company_id = public.get_company_id_for_user(auth.uid()));

-- Generic policy for most tables: Users can access data belonging to their company
CREATE POLICY "Company data is accessible to its members"
ON public.products FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.product_variants FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.suppliers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.customers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.purchase_order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company data is accessible to its members"
ON public.integrations FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Users can access their own conversations"
ON public.conversations FOR ALL USING (user_id = auth.uid());

CREATE POLICY "Users can access messages in their own conversations"
ON public.messages FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Company settings are accessible to its members"
ON public.company_settings FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Channel fees are accessible to company members"
ON public.channel_fees FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Audit logs are accessible to company members"
ON public.audit_log FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Feedback is accessible to company members"
ON public.feedback FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Export jobs are accessible to company members"
ON public.export_jobs FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Imports are accessible to company members"
ON public.imports FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));

CREATE POLICY "Webhook events are accessible to company members"
ON public.webhook_events FOR ALL USING (EXISTS (
    SELECT 1 FROM public.integrations i
    WHERE i.id = webhook_events.integration_id
    AND i.company_id = public.get_company_id_for_user(auth.uid())
));

-- 4. Create trigger function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_name text;
BEGIN
  -- Extract company name from metadata, default to 'My Company'
  company_name := NEW.raw_user_meta_data ->> 'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    company_name := 'My Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, NEW.id);

  RETURN NEW;
END;
$$;

-- 5. Create the trigger on the auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- 6. Create trigger function to associate user with company
CREATE OR REPLACE FUNCTION public.add_user_to_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id_to_add uuid;
BEGIN
  -- Find the company associated with the new user's owner
  SELECT id INTO company_id_to_add FROM public.companies WHERE owner_id = NEW.owner_id;

  -- If a company is found, add the user to it
  IF company_id_to_add IS NOT NULL THEN
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (NEW.id, company_id_to_add, 'Owner');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_user_to_company_on_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (NEW.id, (SELECT id FROM public.companies WHERE owner_id = NEW.id), 'Owner');
  RETURN NEW;
END;
$$;


-- Create the trigger that fires after a new company is created
CREATE TRIGGER on_company_created_add_owner_as_user
  AFTER INSERT ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.add_user_to_company_on_signup();
-- This is a view that unnests variants from products for easier querying.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.supplier_id,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;
-- Create the orders view to join orders with customer emails
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email AS customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- Create the customers view to pre-calculate total spent and orders
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name AS customer_name,
    c.email,
    c.created_at,
    COUNT(o.id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    MIN(o.created_at) AS first_order_date
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id AND c.company_id = o.company_id
WHERE c.deleted_at IS NULL
GROUP BY
    c.id, c.company_id, c.name, c.email, c.created_at;

-- Create Materialized View for faster dashboard queries
CREATE MATERIALIZED VIEW public.product_variants_with_details_mat AS
SELECT
    pv.id,
    pv.product_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.supplier_id,
    pv.reorder_point,
    pv.reorder_quantity,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Add indexes for performance
CREATE UNIQUE INDEX ON public.product_variants_with_details_mat (id);
CREATE INDEX ON public.product_variants_with_details_mat (company_id, sku);
CREATE INDEX ON public.product_variants_with_details_mat (company_id, product_title);


-- Function to refresh the materialized view
CREATE OR REPLACE FUNCTION public.refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only allow the service_role to run this
    IF NOT is_service_role() THEN
        RAISE EXCEPTION 'Only service_role can refresh materialized views.';
    END IF;

    REFRESH MATERIALIZED VIEW CONCURRENTLY public.product_variants_with_details_mat;
END;
$$;
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days int)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result json;
    start_date timestamptz := now() - (p_days || ' days')::interval;
    previous_start_date timestamptz := start_date - (p_days || ' days')::interval;
BEGIN
    SELECT json_build_object(
        'total_revenue', (SELECT COALESCE(SUM(total_amount), 0) FROM public.orders_view WHERE company_id = p_company_id AND created_at >= start_date),
        'revenue_change', (
            SELECT 
                CASE
                    WHEN prev_revenue = 0 THEN 100.0
                    ELSE ((curr_revenue - prev_revenue) / prev_revenue) * 100.0
                END
            FROM
            (
                SELECT
                    COALESCE(SUM(CASE WHEN created_at >= start_date THEN total_amount ELSE 0 END), 0) as curr_revenue,
                    COALESCE(SUM(CASE WHEN created_at >= previous_start_date AND created_at < start_date THEN total_amount ELSE 0 END), 1) as prev_revenue
                FROM public.orders_view
                WHERE company_id = p_company_id AND created_at >= previous_start_date
            ) as revenue_data
        ),
        'total_sales', (SELECT COUNT(*) FROM public.orders_view WHERE company_id = p_company_id AND created_at >= start_date),
        'sales_change', (
             SELECT 
                CASE
                    WHEN prev_sales = 0 THEN 100.0
                    ELSE ((curr_sales - prev_sales) / prev_sales) * 100.0
                END
            FROM
            (
                SELECT
                    CAST(COUNT(CASE WHEN created_at >= start_date THEN 1 END) AS real) as curr_sales,
                    CAST(COUNT(CASE WHEN created_at >= previous_start_date AND created_at < start_date THEN 1 END) AS real) as prev_sales
                FROM public.orders_view
                WHERE company_id = p_company_id AND created_at >= previous_start_date
            ) as sales_data
        ),
        'new_customers', (SELECT COUNT(*) FROM public.customers_view WHERE company_id = p_company_id AND first_order_date >= start_date),
        'customers_change', (
             SELECT 
                CASE
                    WHEN prev_customers = 0 THEN 100.0
                    ELSE ((curr_customers - prev_customers) / prev_customers) * 100.0
                END
            FROM
            (
                SELECT
                    CAST(COUNT(CASE WHEN first_order_date >= start_date THEN 1 END) AS real) as curr_customers,
                    CAST(COUNT(CASE WHEN first_order_date >= previous_start_date AND first_order_date < start_date THEN 1 END) AS real) as prev_customers
                FROM public.customers_view
                WHERE company_id = p_company_id AND first_order_date >= previous_start_date
            ) as customer_data
        ),
        'dead_stock_value', (SELECT COALESCE(SUM(v.total_value), 0) FROM get_dead_stock_report(p_company_id) v),
        'sales_over_time', (
            SELECT json_agg(s) FROM (
                SELECT
                    date_trunc('day', d.day)::date AS date,
                    COALESCE(SUM(o.total_amount), 0) AS total_sales
                FROM generate_series(start_date, now(), '1 day') AS d(day)
                LEFT JOIN public.orders_view o ON date_trunc('day', o.created_at) = d.day AND o.company_id = p_company_id
                GROUP BY d.day
                ORDER BY d.day
            ) s
        ),
        'top_selling_products', (
            SELECT json_agg(p) FROM (
                SELECT
                    pv.product_title,
                    SUM(oli.quantity * oli.price) as total_revenue,
                    pv.image_url
                FROM public.order_line_items oli
                JOIN public.product_variants_with_details_mat pv ON oli.variant_id = pv.id
                WHERE oli.company_id = p_company_id AND oli.created_at >= start_date
                GROUP BY pv.product_title, pv.image_url
                ORDER BY total_revenue DESC
                LIMIT 5
            ) p
        ),
        'inventory_summary', (
            SELECT json_build_object(
                'total_value', COALESCE(SUM(cost * inventory_quantity), 0),
                'in_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity > reorder_point THEN cost * inventory_quantity ELSE 0 END), 0),
                'low_stock_value', COALESCE(SUM(CASE WHEN inventory_quantity <= reorder_point AND inventory_quantity > 0 THEN cost * inventory_quantity ELSE 0 END), 0),
                'dead_stock_value', (SELECT COALESCE(SUM(v.total_value), 0) FROM get_dead_stock_report(p_company_id) v)
            )
            FROM public.product_variants_with_details_mat
            WHERE company_id = p_company_id AND cost IS NOT NULL AND inventory_quantity IS NOT NULL AND reorder_point IS NOT NULL
        )
    ) INTO result;

    RETURN result;
END;
$$;
