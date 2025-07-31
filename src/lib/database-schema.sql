-- This function is called by a trigger when a new user signs up in Supabase Auth.
-- It creates a corresponding company and links the user to it.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Generate new company ID
  new_company_id := gen_random_uuid();
  
  -- Create company
  INSERT INTO public.companies (id, name, owner_id)
  VALUES (
    new_company_id,
    COALESCE(NEW.raw_user_meta_data->>'company_name', NEW.email || '''s Company'),
    NEW.id
  );

  -- Create company user link
  INSERT INTO public.company_users (company_id, user_id, role)
  VALUES (
    new_company_id,
    NEW.id,
    'Owner'
  );

  -- Update the user's app_metadata with the new company_id
  -- This is crucial for RLS and application logic
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Trigger to call the function when a new user is created
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- This is a one-time setup to enable Row-Level Security on the 'companies' table.
-- It ensures that users can only see and interact with their own company's data.
-- 1. Enable RLS on the table
alter table public.companies enable row level security;
-- 2. Create a policy that allows users to see their own company
create policy "Users can view their own company" on public.companies
  for select using (id = (select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id')::uuid);


-- This function gets the company_id from the currently authenticated user's JWT claims.
-- It's used in RLS policies to enforce data isolation.
create or replace function auth.company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id'
$$;


-- Generic RLS policy function to be applied to all company-specific tables.
-- It ensures that users can only access rows that match their company_id.
create policy "Company-level access" on public.products
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.product_variants
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.orders
  for all using (company_id = auth.company_id());
  
create policy "Company-level access" on public.order_line_items
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.customers
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.suppliers
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.purchase_orders
  for all using (company_id = auth.company_id());

create policy "Company-level access" on public.purchase_order_line_items
  for all using (company_id = auth.company_id());

-- Enable RLS on all company-specific tables
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku_company ON public.product_variants(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);


-- Materialized View for Product Variant Details
-- This view denormalizes product data to speed up common queries.
CREATE MATERIALIZED VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type,
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
    pv.external_variant_id,
    pv.company_id,
    pv.created_at,
    pv.updated_at
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Indexes on the materialized view
CREATE UNIQUE INDEX ON public.product_variants_with_details (id);
CREATE INDEX ON public.product_variants_with_details (company_id);
CREATE INDEX ON public.product_variants_with_details (sku, company_id);


-- RPC function to get dashboard metrics
-- This function encapsulates a complex query for better performance and reusability.
CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    -- Function body goes here
    result JSON;
BEGIN
    -- This is a placeholder. The full implementation would involve complex SQL queries.
    SELECT json_build_object(
        'total_revenue', (SELECT COALESCE(SUM(total_amount), 0) FROM public.orders WHERE company_id = p_company_id),
        'revenue_change', 0, -- Placeholder
        'total_sales', (SELECT COALESCE(COUNT(*), 0) FROM public.orders WHERE company_id = p_company_id),
        'sales_change', 0, -- Placeholder
        'new_customers', 0, -- Placeholder
        'customers_change', 0, -- Placeholder
        'dead_stock_value', 0, -- Placeholder
        'sales_over_time', '[]'::json,
        'top_selling_products', '[]'::json,
        'inventory_summary', '{"total_value":0, "in_stock_value":0, "low_stock_value":0, "dead_stock_value":0}'::json
    ) INTO result;
    RETURN result;
END;
$$;
