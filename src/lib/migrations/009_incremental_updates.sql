-- This script contains only the necessary changes to update your database schema.
-- It is safe to run on your existing database.

-- Create the new alert history table to track alert status
CREATE TABLE IF NOT EXISTS public.alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    status TEXT DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'dismissed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    read_at TIMESTAMP WITH TIME ZONE,
    dismissed_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_alert_history_entry UNIQUE (company_id, alert_id)
);

-- Add the new JSONB column to company_settings for alert preferences
ALTER TABLE public.company_settings 
ADD COLUMN IF NOT EXISTS alert_settings JSONB DEFAULT '{
    "email_notifications": true,
    "morning_briefing_enabled": true,
    "morning_briefing_time": "09:00",
    "low_stock_threshold": 10,
    "critical_stock_threshold": 5
}'::jsonb;

-- Create performance indexes recommended by the audit
CREATE INDEX CONCURRENTLY IF NOT EXISTS orders_analytics_idx ON public.orders(company_id, created_at, financial_status);
CREATE INDEX CONCURRENTLY IF NOT EXISTS inventory_ledger_history_idx ON public.inventory_ledger(variant_id, created_at);
CREATE INDEX CONCURRENTLY IF NOT EXISTS messages_conversation_created_at_idx ON public.messages(conversation_id, created_at);

-- Create or replace the function to get alerts with their read/dismissed status
CREATE OR REPLACE FUNCTION public.get_alerts_with_status(p_company_id UUID)
RETURNS JSONB[] AS $$
DECLARE
    alerts JSONB[];
    r RECORD;
    settings record;
    alert_history_record record;
BEGIN
    -- Get company-specific settings
    SELECT cs.alert_settings INTO settings FROM public.company_settings cs WHERE cs.company_id = p_company_id;

    -- If no settings are found, use defaults
    IF settings IS NULL THEN
        settings := ('{"low_stock_threshold": 10, "critical_stock_threshold": 5}')::jsonb;
    END IF;

    -- Low Stock Alerts
    FOR r IN (
        SELECT 
            v.id,
            v.sku,
            p.title as product_name,
            v.inventory_quantity,
            v.reorder_point
        FROM public.product_variants v
        JOIN public.products p ON v.product_id = p.id
        WHERE v.company_id = p_company_id
          AND v.inventory_quantity <= COALESCE((settings.alert_settings->>'low_stock_threshold')::int, 10)
          AND v.inventory_quantity > 0
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
            -- Check if already read
            SELECT * INTO alert_history_record 
            FROM public.alert_history 
            WHERE company_id = p_company_id 
              AND alert_id = 'low_stock_' || r.id
              AND status = 'read';
            
            alerts := array_append(alerts, jsonb_build_object(
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
                'read', alert_history_record IS NOT NULL,
                'metadata', jsonb_build_object(
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
$$ LANGUAGE plpgsql;

-- Grant permissions for the new table and function
GRANT EXECUTE ON FUNCTION public.get_alerts_with_status(UUID) TO "authenticated";
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.alert_history TO "authenticated";

COMMENT ON FUNCTION public.get_alerts_with_status IS 'Retrieves active alerts for a company, including read/dismissed status.';
COMMENT ON TABLE public.alert_history IS 'Stores the read/dismissed state of alerts for users.';

RAISE NOTICE 'Database migration for alert system completed successfully.';
