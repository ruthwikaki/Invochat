-- src/lib/database-schema.sql

-- Drop existing tables and types if they exist, for a clean slate
DROP VIEW IF EXISTS public.orders_view, public.customers_view, public.product_variants_with_details, public.purchase_orders_view, public.audit_log_view, public.feedback_view CASCADE;
DROP TABLE IF EXISTS public.order_line_items, public.orders, public.customers, public.inventory_ledger, public.purchase_order_line_items, public.purchase_orders, public.product_variants, public.suppliers, public.products, public.company_users, public.companies, public.integrations, public.webhook_events, public.messages, public.conversations, public.feedback, public.channel_fees, public.export_jobs, public.audit_log, public.company_settings CASCADE;
DROP TYPE IF EXISTS public.company_role, public.integration_platform, public.message_role, public.feedback_type CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user, public.get_company_id_for_user, public.check_user_permission, public.record_order_from_platform, public.get_sales_analytics, public.get_customer_analytics, public.get_inventory_analytics, public.get_dashboard_metrics, public.get_dead_stock_report, public.get_reorder_suggestions, public.get_supplier_performance_report, public.get_inventory_turnover, public.get_users_for_company, public.remove_user_from_company, public.update_user_role_in_company, public.adjust_inventory_quantity, public.create_full_purchase_order, public.update_full_purchase_order, public.refresh_all_matviews, public.get_historical_sales_for_sku, public.get_historical_sales_for_skus, public.get_abc_analysis, public.get_gross_margin_analysis, public.get_margin_trends, public.get_net_margin_by_channel, public.forecast_demand, public.get_sales_velocity, public.get_financial_impact_of_promotion, public.reconcile_inventory_from_integration CASCADE;

-- Create ENUM types
CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE public.message_role AS ENUM ('user', 'assistant');
CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');

-- Create Tables
CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid NOT NULL REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.company_users (
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (company_id, user_id)
);

CREATE TABLE public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text NOT NULL DEFAULT 'USD',
    timezone text NOT NULL DEFAULT 'UTC',
    tax_rate numeric(5,4) NOT NULL DEFAULT 0.0,
    overstock_multiplier numeric(4,2) NOT NULL DEFAULT 3.0,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- in cents
    alert_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, external_product_id)
);

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, external_order_id)
);

CREATE TABLE public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text,
    UNIQUE(order_id, external_line_item_id)
);

CREATE TABLE public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    notes text,
    idempotency_key uuid UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE public.purchase_order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);

CREATE TABLE public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.integrations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform public.integration_platform NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean NOT NULL DEFAULT TRUE,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(webhook_id)
);

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false
);

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    visualization jsonb,
    component text,
    confidence real CHECK (confidence >= 0 AND confidence <= 1),
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT now(),
    isError boolean DEFAULT false
);
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS component_props jsonb;

CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback public.feedback_type NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric,
    fixed_fee integer, -- in cents
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'queued',
    download_url text,
    expires_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE public.audit_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);


-- DB Functions
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    company_id_var uuid;
    company_name_var text;
BEGIN
    company_name_var := new.raw_user_meta_data->>'company_name';

    INSERT INTO public.companies (name, owner_id)
    VALUES (company_name_var, new.id)
    RETURNING id INTO company_id_var;

    INSERT INTO public.company_users (company_id, user_id, role)
    VALUES (company_id_var, new.id, 'Owner');
    
    UPDATE auth.users
    SET raw_user_meta_data = new.raw_user_meta_data || jsonb_build_object('company_id', company_id_var)
    WHERE id = new.id;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user creation
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create dead stock report function
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(
  p_company_id uuid,
  p_days int DEFAULT 90
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
WITH variant_last_sale AS (
  SELECT li.variant_id, MAX(o.created_at) AS last_sale_at
  FROM public.order_line_items li
  JOIN public.orders o ON o.id = li.order_id
  WHERE o.company_id = p_company_id
    AND o.fulfillment_status != 'cancelled'
  GROUP BY li.variant_id
),
params AS (
  SELECT COALESCE(cs.dead_stock_days, p_days) AS ds_days
  FROM public.company_settings cs
  WHERE cs.company_id = p_company_id
  LIMIT 1
),
dead AS (
  SELECT
    v.id                             AS variant_id,
    v.product_id,
    v.title                          AS variant_name,
    p.title                          AS product_name,
    v.sku,
    v.inventory_quantity as quantity,
    v.cost::bigint                   AS total_value,
    ls.last_sale_at
  FROM public.product_variants v
  LEFT JOIN variant_last_sale ls ON ls.variant_id = v.id
  JOIN public.products p on p.id = v.product_id
  CROSS JOIN params
  WHERE v.company_id = p_company_id
    AND v.inventory_quantity > 0
    AND v.cost IS NOT NULL
    AND (ls.last_sale_at IS NULL OR ls.last_sale_at < (now() - make_interval(days => params.ds_days)))
)
SELECT jsonb_build_object(
  'deadStockItems', COALESCE(jsonb_agg(to_jsonb(dead)), '[]'::jsonb),
  'totalValue',     COALESCE(SUM(dead.total_value), 0)
)
FROM dead;
$$;
