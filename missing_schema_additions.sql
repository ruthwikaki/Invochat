-- Missing Schema Additions for AI Features
-- This script adds the missing tables and functions required for AI features to work properly

-- 1. Create missing tables

-- Sales table to track sales transactions
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    customer_name text,
    total_amount numeric(10,2) DEFAULT 0.00,
    channel text,
    status text DEFAULT 'completed',
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Sale items table to track individual items in each sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL,
    company_id uuid NOT NULL,
    inventory_id uuid,
    sku text,
    product_name text,
    quantity integer DEFAULT 0,
    unit_price numeric(10,2) DEFAULT 0.00,
    unit_cost numeric(10,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_inventory_id_fkey FOREIGN KEY (inventory_id) REFERENCES public.inventory(id) ON DELETE SET NULL
);

-- Channel fees table for margin analysis
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    fee_percentage numeric(5,2) DEFAULT 0.00,
    fixed_fee numeric(10,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Add RLS to new tables
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_company_id ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sku ON public.sale_items(sku);
CREATE INDEX IF NOT EXISTS idx_sale_items_created_at ON public.sale_items(created_at);
CREATE INDEX IF NOT EXISTS idx_channel_fees_company_id ON public.channel_fees(company_id);

-- 2. Create RLS policies for new tables

-- Policies for sales table
DROP POLICY IF EXISTS "Users can manage their own company's sales" ON public.sales;
CREATE POLICY "Users can manage their own company's sales" ON public.sales FOR ALL
USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Policies for sale_items table
DROP POLICY IF EXISTS "Users can manage their own company's sale items" ON public.sale_items;
CREATE POLICY "Users can manage their own company's sale items" ON public.sale_items FOR ALL
USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Policies for channel_fees table
DROP POLICY IF EXISTS "Users can manage their own company's channel fees" ON public.channel_fees;
CREATE POLICY "Users can manage their own company's channel fees" ON public.channel_fees FOR ALL
USING (company_id IN (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- 3. Create missing RPC functions

-- Function to get sales velocity
CREATE OR REPLACE FUNCTION public.get_sales_velocity(p_company_id uuid, p_days integer DEFAULT 30, p_limit integer DEFAULT 50)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                si.sku,
                si.product_name,
                SUM(si.quantity) as total_sold,
                COUNT(DISTINCT s.id) as num_transactions,
                AVG(si.unit_price) as avg_price,
                SUM(si.quantity * si.unit_price) as total_revenue,
                ROUND(SUM(si.quantity)::numeric / NULLIF(p_days, 0), 2) as velocity_per_day
            FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            WHERE si.company_id = p_company_id
            AND s.created_at >= NOW() - INTERVAL '1 day' * p_days
            AND s.status = 'completed'
            GROUP BY si.sku, si.product_name
            ORDER BY total_sold DESC
            LIMIT p_limit
        ) t
    );
END;
$$;

-- Function to get ABC analysis
CREATE OR REPLACE FUNCTION public.get_abc_analysis(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            WITH revenue_data AS (
                SELECT
                    si.sku,
                    si.product_name,
                    SUM(si.quantity * si.unit_price) as revenue
                FROM sale_items si
                JOIN sales s ON si.sale_id = s.id
                WHERE si.company_id = p_company_id
                AND s.created_at >= NOW() - INTERVAL '90 days'
                AND s.status = 'completed'
                GROUP BY si.sku, si.product_name
            ),
            ranked_data AS (
                SELECT *,
                    SUM(revenue) OVER () as total_revenue,
                    SUM(revenue) OVER (ORDER BY revenue DESC) as cumulative_revenue
                FROM revenue_data
            )
            SELECT
                sku,
                product_name,
                revenue,
                ROUND((revenue / NULLIF(total_revenue, 0) * 100)::numeric, 2) as revenue_percentage,
                ROUND((cumulative_revenue / NULLIF(total_revenue, 0) * 100)::numeric, 2) as cumulative_percentage,
                CASE
                    WHEN cumulative_revenue / NULLIF(total_revenue, 0) <= 0.8 THEN 'A'
                    WHEN cumulative_revenue / NULLIF(total_revenue, 0) <= 0.95 THEN 'B'
                    ELSE 'C'
                END as category
            FROM ranked_data
            ORDER BY revenue DESC
        ) t
    );
END;
$$;

-- Function to get gross margin analysis
CREATE OR REPLACE FUNCTION public.get_gross_margin_analysis(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                si.sku,
                si.product_name,
                SUM(si.quantity) as total_sold,
                SUM(si.quantity * si.unit_price) as total_revenue,
                SUM(si.quantity * si.unit_cost) as total_cost,
                ROUND(((SUM(si.quantity * si.unit_price) - SUM(si.quantity * si.unit_cost)) / NULLIF(SUM(si.quantity * si.unit_price), 0) * 100)::numeric, 2) as margin_percentage,
                SUM(si.quantity * si.unit_price) - SUM(si.quantity * si.unit_cost) as gross_profit
            FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            WHERE si.company_id = p_company_id
            AND s.created_at >= NOW() - INTERVAL '90 days'
            AND s.status = 'completed'
            GROUP BY si.sku, si.product_name
            ORDER BY gross_profit DESC
        ) t
    );
END;
$$;

-- Function to get net margin by channel
CREATE OR REPLACE FUNCTION public.get_net_margin_by_channel(p_company_id uuid, p_channel_name text)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                si.sku,
                si.product_name,
                s.channel,
                SUM(si.quantity) as total_sold,
                SUM(si.quantity * si.unit_price) as total_revenue,
                SUM(si.quantity * si.unit_cost) as total_cost,
                COALESCE(cf.fee_percentage, 0) as channel_fee_percentage,
                COALESCE(cf.fixed_fee, 0) as channel_fixed_fee,
                SUM(si.quantity * si.unit_price) * COALESCE(cf.fee_percentage, 0) / 100 + COALESCE(cf.fixed_fee, 0) as channel_fees,
                SUM(si.quantity * si.unit_price) - SUM(si.quantity * si.unit_cost) - (SUM(si.quantity * si.unit_price) * COALESCE(cf.fee_percentage, 0) / 100 + COALESCE(cf.fixed_fee, 0)) as net_profit
            FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            LEFT JOIN channel_fees cf ON cf.company_id = si.company_id AND cf.channel_name = s.channel
            WHERE si.company_id = p_company_id
            AND s.channel = p_channel_name
            AND s.created_at >= NOW() - INTERVAL '90 days'
            AND s.status = 'completed'
            GROUP BY si.sku, si.product_name, s.channel, cf.fee_percentage, cf.fixed_fee
            ORDER BY net_profit DESC
        ) t
    );
END;
$$;

-- Function to get margin trends
CREATE OR REPLACE FUNCTION public.get_margin_trends(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                DATE_TRUNC('week', s.created_at) as week,
                SUM(si.quantity * si.unit_price) as revenue,
                SUM(si.quantity * si.unit_cost) as cost,
                ROUND(((SUM(si.quantity * si.unit_price) - SUM(si.quantity * si.unit_cost)) / NULLIF(SUM(si.quantity * si.unit_price), 0) * 100)::numeric, 2) as margin_percentage
            FROM sale_items si
            JOIN sales s ON si.sale_id = s.id
            WHERE si.company_id = p_company_id
            AND s.created_at >= NOW() - INTERVAL '12 weeks'
            AND s.status = 'completed'
            GROUP BY DATE_TRUNC('week', s.created_at)
            ORDER BY week
        ) t
    );
END;
$$;

-- Function to forecast demand (simplified version)
CREATE OR REPLACE FUNCTION public.forecast_demand(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                si.sku,
                si.product_name,
                AVG(weekly_qty) as avg_weekly_demand,
                ROUND(AVG(weekly_qty) * 4, 0) as forecasted_monthly_demand,
                CASE
                    WHEN AVG(weekly_qty) * 4 > i.quantity THEN 'REORDER_SOON'
                    WHEN AVG(weekly_qty) * 2 > i.quantity THEN 'MONITOR'
                    ELSE 'ADEQUATE'
                END as stock_status
            FROM (
                SELECT
                    si.sku,
                    si.product_name,
                    DATE_TRUNC('week', s.created_at) as week,
                    SUM(si.quantity) as weekly_qty
                FROM sale_items si
                JOIN sales s ON si.sale_id = s.id
                WHERE si.company_id = p_company_id
                AND s.created_at >= NOW() - INTERVAL '12 weeks'
                AND s.status = 'completed'
                GROUP BY si.sku, si.product_name, DATE_TRUNC('week', s.created_at)
            ) weekly_data
            LEFT JOIN inventory i ON i.sku = weekly_data.sku AND i.company_id = p_company_id
            GROUP BY weekly_data.sku, weekly_data.product_name, i.quantity
            ORDER BY avg_weekly_demand DESC
        ) t
    );
END;
$$;

-- Function to get financial impact of promotion
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(t), '[]'::json)
        FROM (
            SELECT
                si.sku,
                si.product_name,
                AVG(si.unit_price) as current_price,
                AVG(si.unit_price) * (1 - p_discount_percentage / 100) as discounted_price,
                AVG(daily_qty) as avg_daily_sales,
                ROUND(AVG(daily_qty) * p_duration_days, 0) as estimated_units_sold,
                ROUND(AVG(daily_qty) * p_duration_days * AVG(si.unit_price) * (1 - p_discount_percentage / 100), 2) as estimated_revenue,
                ROUND(AVG(daily_qty) * p_duration_days * (AVG(si.unit_price) * (1 - p_discount_percentage / 100) - AVG(si.unit_cost)), 2) as estimated_profit
            FROM (
                SELECT
                    si.sku,
                    si.product_name,
                    si.unit_price,
                    si.unit_cost,
                    DATE_TRUNC('day', s.created_at) as day,
                    SUM(si.quantity) as daily_qty
                FROM sale_items si
                JOIN sales s ON si.sale_id = s.id
                WHERE si.company_id = p_company_id
                AND si.sku = ANY(p_skus)
                AND s.created_at >= NOW() - INTERVAL '30 days'
                AND s.status = 'completed'
                GROUP BY si.sku, si.product_name, si.unit_price, si.unit_cost, DATE_TRUNC('day', s.created_at)
            ) daily_data
            GROUP BY daily_data.sku, daily_data.product_name
        ) t
    );
END;
$$;

-- Insert some sample data for testing (optional - remove in production)
-- Note: This requires a company_id to exist. In a real setup, this would be populated by the application.

-- Sample channel fees
INSERT INTO public.channel_fees (company_id, channel_name, fee_percentage, fixed_fee)
SELECT 
    c.id as company_id,
    'Shopify' as channel_name,
    2.9 as fee_percentage,
    0.30 as fixed_fee
FROM public.companies c
WHERE NOT EXISTS (
    SELECT 1 FROM public.channel_fees cf 
    WHERE cf.company_id = c.id AND cf.channel_name = 'Shopify'
)
LIMIT 1;

INSERT INTO public.channel_fees (company_id, channel_name, fee_percentage, fixed_fee)
SELECT 
    c.id as company_id,
    'Amazon' as channel_name,
    15.0 as fee_percentage,
    0.00 as fixed_fee
FROM public.companies c
WHERE NOT EXISTS (
    SELECT 1 FROM public.channel_fees cf 
    WHERE cf.company_id = c.id AND cf.channel_name = 'Amazon'
)
LIMIT 1;
