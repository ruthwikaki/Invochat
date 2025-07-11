-- This file contains the full database schema for the application.
-- It's intended to be run once in the Supabase SQL editor to set up your database.

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- 2. Create the 'companies' table
drop table if exists "public"."companies" cascade;
create table "public"."companies" (
    "id" uuid not null default extensions.uuid_generate_v4(),
    "name" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."companies" enable row level security;
create unique index companies_pkey on public.companies using btree (id);
alter table "public"."companies" add constraint "companies_pkey" primary key using index "companies_pkey";
grant delete on table "public"."companies" to "anon";
grant insert on table "public"."companies" to "anon";
grant references on table "public"."companies" to "anon";
grant select on table "public"."companies" to "anon";
grant trigger on table "public"."companies" to "anon";
grant truncate on table "public"."companies" to "anon";
grant update on table "public"."companies" to "anon";
grant delete on table "public"."companies" to "authenticated";
grant insert on table "public"."companies" to "authenticated";
grant references on table "public"."companies" to "authenticated";
grant select on table "public"."companies" to "authenticated";
grant trigger on table "public"."companies" to "authenticated";
grant truncate on table "public"."companies" to "authenticated";
grant update on table "public"."companies" to "authenticated";
grant delete on table "public"."companies" to "service_role";
grant insert on table "public"."companies" to "service_role";
grant references on table "public"."companies" to "service_role";
grant select on table "public"."companies" to "service_role";
grant trigger on table "public"."companies" to "service_role";
grant truncate on table "public"."companies" to "service_role";
grant update on table "public"."companies" to "service_role";


-- 3. Set up user profiles and link to companies
drop table if exists "public"."users" cascade;
create table "public"."users" (
    "id" uuid not null,
    "company_id" uuid,
    "role" text default 'Member'::text,
    "email" text,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone default now()
);
alter table "public"."users" enable row level security;
alter table "public"."users" add constraint "users_id_fkey" foreign key (id) references auth.users(id) on delete cascade;
alter table "public"."users" add constraint "users_company_id_fkey" foreign key (company_id) references companies(id) on delete set null;
create unique index users_pkey on public.users using btree (id);
alter table "public"."users" add constraint "users_pkey" primary key using index "users_pkey";
grant delete on table "public"."users" to "anon";
grant insert on table "public"."users" to "anon";
grant references on table "public"."users" to "anon";
grant select on table "public"."users" to "anon";
grant trigger on table "public"."users" to "anon";
grant truncate on table "public"."users" to "anon";
grant update on table "public"."users" to "anon";
grant delete on table "public"."users" to "authenticated";
grant insert on table "public"."users" to "authenticated";
grant references on table "public"."users" to "authenticated";
grant select on table "public"."users" to "authenticated";
grant trigger on table "public"."users" to "authenticated";
grant truncate on table "public"."users" to "authenticated";
grant update on table "public"."users" to "authenticated";
grant delete on table "public"."users" to "service_role";
grant insert on table "public"."users" to "service_role";
grant references on table "public"."users" to "service_role";
grant select on table "public"."users" to "service_role";
grant trigger on table "public"."users" to "service_role";
grant truncate on table "public"."users" to "service_role";
grant update on table "public"."users" to "service_role";


-- 4. Function to create a company for a new user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Insert a profile for the new user and set their role to 'Owner'
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in the auth schema
  update auth.users
  set app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  where id = new.id;

  return new;
end;
$$;

-- 5. Trigger to call the function on new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 6. Create RLS policies for companies
drop policy if exists "Allow owners to do everything" on "public"."companies";
create policy "Allow owners to do everything" on "public"."companies" as permissive
for all
to authenticated
using ((auth.uid() IN ( SELECT users.id
   FROM users
  WHERE (users.company_id = companies.id) AND users.role = 'Owner'::text)));

-- 7. Create RLS policies for users table
drop policy if exists "Allow admins to see their own company users" on "public"."users";
create policy "Allow admins to see their own company users" ON "public"."users"
as permissive for select
to authenticated
using (
  (get_my_claim('role') = '"Owner"'::jsonb OR get_my_claim('role') = '"Admin"'::jsonb) AND
  company_id = (get_my_claim('company_id'))::uuid
);

-- 8. Enable real-time updates on tables
alter table "public"."integrations" replica identity full;
begin;
  drop publication if exists supabase_realtime;
  create publication supabase_realtime;
commit;
alter publication supabase_realtime add table "public"."integrations";


-- #############################################################################
-- #                        APPLICATION-SPECIFIC SCHEMA                        #
-- #############################################################################


-- Function to get a custom claim from the JWT
create or replace function get_my_claim(claim_name text)
returns jsonb
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' -> claim_name
$$;


-- PRODUCTS & INVENTORY
----------------------------------------------------------------------------------------------------
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT,
    price INT, -- in cents
    cost INT NOT NULL DEFAULT 0, -- in cents
    barcode TEXT,
    supplier_id UUID, -- To be linked later
    reorder_point INT,
    reorder_quantity INT,
    lead_time_days INT,
    source_platform TEXT,
    external_product_id TEXT,
    external_variant_id TEXT,
    deleted_at TIMESTAMPTZ,
    deleted_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_products_company_sku ON products(company_id, sku);
CREATE INDEX idx_products_company_id ON products(company_id);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access products" ON products FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


CREATE TABLE inventory (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity INT NOT NULL DEFAULT 0,
    external_quantity INT, -- To store the quantity from the external platform
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_inventory_product_id ON inventory(product_id);
ALTER TABLE inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access inventory" ON inventory FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


CREATE TABLE inventory_ledger (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    related_id UUID, -- e.g., sale_id, purchase_order_id
    notes TEXT
);
CREATE INDEX idx_inventory_ledger_product ON inventory_ledger(product_id);
ALTER TABLE inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access ledger" ON inventory_ledger FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


-- SUPPLIERS
----------------------------------------------------------------------------------------------------
CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access suppliers" ON suppliers FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);
ALTER TABLE products ADD CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;


-- SALES & CUSTOMERS
----------------------------------------------------------------------------------------------------
CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    email TEXT,
    customer_name TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_customers_company_email ON customers(company_id, email) WHERE email IS NOT NULL;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access customers" ON customers FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


CREATE TABLE sales (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    sale_number TEXT NOT NULL,
    customer_id UUID REFERENCES customers(id),
    customer_name TEXT,
    customer_email TEXT,
    total_amount INT NOT NULL, -- in cents
    payment_method TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    external_id TEXT
);
CREATE UNIQUE INDEX idx_sales_company_external_id ON sales(company_id, external_id) WHERE external_id IS NOT NULL;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access sales" ON sales FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


CREATE TABLE sale_items (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity INT NOT NULL,
    unit_price INT NOT NULL, -- in cents
    cost_at_time INT -- in cents
);
CREATE INDEX idx_sale_items_sale_id ON sale_items(sale_id);
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to access sale items" ON sale_items FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


-- OTHER TABLES (Settings, Integrations, etc.)
----------------------------------------------------------------------------------------------------
CREATE TABLE company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    dead_stock_days INT DEFAULT 90 NOT NULL,
    fast_moving_days INT DEFAULT 30 NOT NULL,
    predictive_stock_days INT DEFAULT 7 NOT NULL,
    overstock_multiplier NUMERIC(5,2) DEFAULT 3.0 NOT NULL,
    high_value_threshold INT DEFAULT 100000 NOT NULL, -- in cents
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow members to read settings" ON company_settings FOR SELECT USING (company_id = (get_my_claim('company_id'))::uuid);
CREATE POLICY "Allow owners/admins to update settings" ON company_settings FOR UPDATE
USING (
  company_id = (get_my_claim('company_id'))::uuid AND
  (get_my_claim('role') = '"Owner"'::jsonb OR get_my_claim('role') = '"Admin"'::jsonb)
);


CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX idx_integrations_company_platform ON integrations(company_id, platform);
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow members to see integrations" ON integrations FOR SELECT
USING (company_id = (get_my_claim('company_id'))::uuid);


CREATE TABLE sync_state (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    last_processed_cursor TEXT,
    last_update TIMESTAMPTZ
);
ALTER TABLE sync_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow members to access sync state" ON sync_state FOR ALL
USING (company_id = (SELECT i.company_id FROM integrations i WHERE i.id = integration_id));


CREATE TABLE audit_log (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    user_id UUID REFERENCES auth.users,
    company_id UUID REFERENCES companies,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow admins/owners to view audit logs" ON audit_log FOR SELECT
USING (
  company_id = (get_my_claim('company_id'))::uuid AND
  (get_my_claim('role') = '"Owner"'::jsonb OR get_my_claim('role') = '"Admin"'::jsonb)
);


CREATE TABLE channel_fees (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC(5, 4) NOT NULL, -- e.g., 0.029 for 2.9%
    fixed_fee INT NOT NULL, -- in cents, e.g., 30 for $0.30
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT unique_channel_fee UNIQUE (company_id, channel_name)
);
ALTER TABLE channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow company members to manage channel fees" ON channel_fees FOR ALL
USING (company_id = (get_my_claim('company_id'))::uuid);


-- VIEWS & MATERIALIZED VIEWS
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.inventory_view AS
 SELECT
    p.id AS product_id,
    p.company_id,
    p.sku,
    p.name AS product_name,
    p.category,
    p.cost,
    p.price,
    i.quantity,
    (p.cost * i.quantity) AS total_value,
    p.reorder_point,
    s.name AS supplier_name,
    s.id AS supplier_id,
    p.barcode
   FROM products p
   LEFT JOIN inventory i ON p.id = i.product_id
   LEFT JOIN suppliers s ON p.supplier_id = s.id
  WHERE p.deleted_at IS NULL;


CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    c.id as company_id,
    SUM(i.quantity * p.cost) AS inventory_value,
    COUNT(p.id) AS total_skus,
    SUM(CASE WHEN i.quantity <= p.reorder_point THEN 1 ELSE 0 END) as low_stock_count
FROM
    companies c
LEFT JOIN
    products p ON c.id = p.company_id
LEFT JOIN
    inventory i ON p.id = i.product_id
WHERE p.deleted_at IS NULL
GROUP BY c.id;

CREATE UNIQUE INDEX on company_dashboard_metrics(company_id);


CREATE MATERIALIZED VIEW public.customer_analytics_metrics AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.created_at,
    COUNT(s.id) as total_orders,
    SUM(s.total_amount) as total_spent
FROM
    customers c
JOIN
    sales s ON c.id = s.customer_id
WHERE c.deleted_at IS NULL
GROUP BY c.id, c.company_id, c.customer_name, c.email, c.created_at;

CREATE UNIQUE INDEX on customer_analytics_metrics(id);


-- FUNCTIONS & STORED PROCEDURES
----------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_sale_items JSONB,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_external_id TEXT
) RETURNS sales LANGUAGE plpgsql AS $$
DECLARE
    v_sale_id UUID;
    v_customer_id UUID;
    v_total_amount INT := 0;
    item JSONB;
    v_product_id UUID;
    v_quantity INT;
    v_unit_price INT;
    v_cost_at_time INT;
    v_new_quantity INT;
BEGIN
    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE
        SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total amount
    FOR item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        v_total_amount := v_total_amount + ((item->>'unit_price')::INT * (item->>'quantity')::INT);
    END LOOP;

    -- Insert sale
    INSERT INTO sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'SALE-' || nextval('sales_sale_number_seq'), v_customer_id, p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO v_sale_id;

    -- Insert sale items and update inventory
    FOR item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        v_product_id := (SELECT id FROM products WHERE sku = item->>'sku' AND company_id = p_company_id);
        v_quantity := (item->>'quantity')::INT;
        v_unit_price := (item->>'unit_price')::INT;
        v_cost_at_time := (SELECT cost FROM products WHERE id = v_product_id);

        INSERT INTO sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (v_sale_id, p_company_id, v_product_id, v_quantity, v_unit_price, v_cost_at_time);

        UPDATE inventory SET quantity = quantity - v_quantity, updated_at = NOW() WHERE product_id = v_product_id
        RETURNING quantity INTO v_new_quantity;
        
        -- Create ledger entry
        INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, v_product_id, 'sale', -v_quantity, v_new_quantity, v_sale_id);

    END LOOP;
    
    RETURN (SELECT * FROM sales WHERE id = v_sale_id);
END;
$$;


CREATE OR REPLACE FUNCTION get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSONB;
BEGIN
    WITH metrics AS (
        SELECT
            SUM(s.total_amount) AS totalSalesValue,
            SUM(si.quantity * si.cost_at_time) AS totalCostOfGoods,
            COUNT(DISTINCT s.id) AS totalOrders
        FROM sales s
        JOIN sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id AND s.created_at >= NOW() - (p_days || ' days')::INTERVAL
    ),
    dead_stock AS (
        SELECT COUNT(*) as dead_stock_count
        FROM products p
        JOIN inventory i ON p.id = i.product_id
        WHERE p.company_id = p_company_id
        AND (SELECT MAX(si.created_at) FROM sale_items si JOIN sales s ON si.sale_id = s.id WHERE si.product_id = p.id) < NOW() - '90 days'::INTERVAL
    )
    SELECT jsonb_build_object(
        'totalSalesValue', m.totalSalesValue,
        'totalProfit', m.totalSalesValue - m.totalCostOfGoods,
        'totalOrders', m.totalOrders,
        'averageOrderValue', CASE WHEN m.totalOrders > 0 THEN m.totalSalesValue / m.totalOrders ELSE 0 END,
        'deadStockItemsCount', ds.dead_stock_count
    )
    INTO v_result
    FROM metrics m, dead_stock ds;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
 RETURNS TABLE(segment text, sku text, product_name text, total_quantity bigint, total_revenue bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Top 5 products for new customers (first purchase)
    RETURN QUERY
    WITH first_sales AS (
        SELECT
            s.customer_id,
            MIN(s.created_at) as first_sale_date
        FROM sales s
        WHERE s.company_id = p_company_id AND s.customer_id IS NOT NULL
        GROUP BY s.customer_id
    )
    SELECT
        'New Customers' as segment,
        p.sku,
        p.name as product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price)::bigint as total_revenue
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN products p ON si.product_id = p.id
    JOIN first_sales fs ON s.customer_id = fs.customer_id AND s.created_at = fs.first_sale_date
    WHERE s.company_id = p_company_id
    GROUP BY p.sku, p.name
    ORDER BY total_revenue DESC
    LIMIT 5;

    -- Top 5 products for repeat customers
    RETURN QUERY
    WITH customer_order_counts AS (
        SELECT
            customer_id,
            COUNT(id) as order_count
        FROM sales
        WHERE company_id = p_company_id AND customer_id IS NOT NULL
        GROUP BY customer_id
        HAVING COUNT(id) > 1
    )
    SELECT
        'Repeat Customers' as segment,
        p.sku,
        p.name as product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price)::bigint as total_revenue
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN products p ON si.product_id = p.id
    WHERE s.company_id = p_company_id AND s.customer_id IN (SELECT customer_id FROM customer_order_counts)
    GROUP BY p.sku, p.name
    ORDER BY total_revenue DESC
    LIMIT 5;

    -- Top 5 products for top spenders (top 10%)
    RETURN QUERY
    WITH customer_spend AS (
        SELECT
            customer_id,
            SUM(total_amount) as total_spent,
            NTILE(10) OVER (ORDER BY SUM(total_amount) DESC) as spend_percentile
        FROM sales
        WHERE company_id = p_company_id AND customer_id IS NOT NULL
        GROUP BY customer_id
    ),
    top_spenders AS (
        SELECT customer_id FROM customer_spend WHERE spend_percentile = 1
    )
    SELECT
        'Top Spenders' as segment,
        p.sku,
        p.name as product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price)::bigint as total_revenue
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN products p ON si.product_id = p.id
    WHERE s.company_id = p_company_id AND s.customer_id IN (SELECT customer_id FROM top_spenders)
    GROUP BY p.sku, p.name
    ORDER BY total_revenue DESC
    LIMIT 5;

END;
$function$;


-- Final setup: Create sequences and refresh views
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq
    INCREMENT 1
    START 1001
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 1;

REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
REFRESH MATERIALIZED VIEW public.customer_analytics_metrics;
