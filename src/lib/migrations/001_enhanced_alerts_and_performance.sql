-- Enhanced Alert System & Performance Index Migration
-- Version: 1
-- Description: Adds the alert_history table, alert settings, performance indexes, and updated alert functions.
-- This script is safe to run multiple times; it will only apply changes if they haven't been applied before.

BEGIN;

-- Create migration tracking if it doesn't exist
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Check if this migration was already applied
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.schema_migrations WHERE version = '20250129_alert_system_v2') THEN
        RAISE NOTICE 'Migration 20250129_alert_system_v2 already applied, skipping...';
        RETURN;
    END IF;
END $$;

-- Create the alert history table
CREATE TABLE IF NOT EXISTS public.alert_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    alert_id TEXT NOT NULL,
    status TEXT DEFAULT 'unread',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    read_at TIMESTAMP WITH TIME ZONE,
    dismissed_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}',
    CONSTRAINT alert_history_status_check CHECK (status IN ('unread', 'read', 'dismissed')),
    CONSTRAINT unique_alert_history_entry UNIQUE (company_id, alert_id)
);

-- Add alert settings column with better defaults
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'company_settings' 
        AND column_name = 'alert_settings'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.company_settings 
        ADD COLUMN alert_settings JSONB DEFAULT jsonb_build_object(
            'email_notifications', true,
            'morning_briefing_enabled', true,
            'morning_briefing_time', '09:00',
            'low_stock_threshold', 10,
            'critical_stock_threshold', 5,
            'dismissal_hours', 24,
            'enabled_alert_types', array['low_stock', 'out_of_stock', 'overstock']
        );
    END IF;
END $$;

-- Create indexes safely
DO $$
BEGIN
    -- Orders analytics index
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_orders_analytics') THEN
        CREATE INDEX CONCURRENTLY idx_orders_analytics 
        ON public.orders(company_id, created_at, financial_status);
    END IF;
    
    -- Inventory ledger history index
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_inventory_ledger_history') THEN
        CREATE INDEX CONCURRENTLY idx_inventory_ledger_history 
        ON public.inventory_ledger(variant_id, created_at, change_type);
    END IF;
    
    -- Messages conversation index
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_messages_conversation_timeline') THEN
        CREATE INDEX CONCURRENTLY idx_messages_conversation_timeline 
        ON public.messages(conversation_id, created_at);
    END IF;
    
    -- Alert history lookup index
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_alert_history_lookup') THEN
        CREATE INDEX CONCURRENTLY idx_alert_history_lookup 
        ON public.alert_history(company_id, alert_id, status, dismissed_at);
    END IF;
END $$;

-- Enhanced alert function with better error handling and performance
CREATE OR REPLACE FUNCTION public.get_alerts_with_status(p_company_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB := jsonb_build_object('alerts', '[]'::jsonb, 'summary', jsonb_build_object());
    alerts JSONB[] := '{}';
    r RECORD;
    settings JSONB;
    alert_history_record RECORD;
    dismissal_threshold INTERVAL;
    alert_count INTEGER := 0;
    critical_count INTEGER := 0;
BEGIN
    -- Input validation
    IF p_company_id IS NULL THEN
        RAISE EXCEPTION 'Company ID cannot be null';
    END IF;

    -- Get company settings with fallback defaults
    SELECT COALESCE(cs.alert_settings, jsonb_build_object(
        'low_stock_threshold', 10,
        'critical_stock_threshold', 5,
        'dismissal_hours', 24,
        'enabled_alert_types', array['low_stock', 'out_of_stock']
    )) INTO settings
    FROM public.company_settings cs 
    WHERE cs.company_id = p_company_id;

    -- Set dismissal threshold
    dismissal_threshold := (COALESCE((settings->>'dismissal_hours')::int, 24) || ' hours')::interval;

    -- Low Stock Alerts (only if enabled)
    IF 'low_stock' = ANY(ARRAY(SELECT jsonb_array_elements_text(settings->'enabled_alert_types'))) THEN
        FOR r IN (
            SELECT 
                v.id,
                v.sku,
                p.title as product_name,
                v.inventory_quantity,
                v.reorder_point,
                CASE 
                    WHEN v.inventory_quantity <= COALESCE((settings->>'critical_stock_threshold')::int, 5)
                    THEN 'critical'
                    ELSE 'warning'
                END as severity
            FROM public.product_variants v
            JOIN public.products p ON v.product_id = p.id
            WHERE v.company_id = p_company_id
              AND v.deleted_at IS NULL
              AND p.deleted_at IS NULL
              AND v.inventory_quantity <= COALESCE((settings->>'low_stock_threshold')::int, 10)
              AND v.inventory_quantity > 0
            ORDER BY v.inventory_quantity ASC
            LIMIT 100
        ) LOOP
            -- Check dismissal status
            SELECT ah.* INTO alert_history_record 
            FROM public.alert_history ah
            WHERE ah.company_id = p_company_id 
              AND ah.alert_id = 'low_stock_' || r.id
              AND ah.status = 'dismissed'
              AND ah.dismissed_at > (now() - dismissal_threshold);
            
            IF alert_history_record IS NOT NULL THEN
                CONTINUE;
            END IF;

            -- Check read status
            SELECT ah.* INTO alert_history_record 
            FROM public.alert_history ah
            WHERE ah.company_id = p_company_id 
              AND ah.alert_id = 'low_stock_' || r.id
              AND ah.status IN ('read', 'unread');

            alerts := array_append(alerts, jsonb_build_object(
                'id', 'low_stock_' || r.id,
                'type', 'low_stock',
                'title', 'Low Stock Warning',
                'message', format('%s is running low (%s units remaining)', r.product_name, r.inventory_quantity),
                'severity', r.severity,
                'timestamp', now(),
                'read', COALESCE(alert_history_record.status = 'read', false),
                'metadata', jsonb_build_object(
                    'variant_id', r.id,
                    'product_name', r.product_name,
                    'sku', r.sku,
                    'current_stock', r.inventory_quantity,
                    'reorder_point', r.reorder_point
                )
            ));

            alert_count := alert_count + 1;
            IF r.severity = 'critical' THEN
                critical_count := critical_count + 1;
            END IF;
        END LOOP;
    END IF;

    -- Build final result with summary
    result := jsonb_build_object(
        'alerts', array_to_json(alerts)::jsonb,
        'summary', jsonb_build_object(
            'total_alerts', alert_count,
            'critical_alerts', critical_count,
            'warning_alerts', alert_count - critical_count,
            'last_updated', now()
        )
    );

    RETURN result;

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Error in get_alerts_with_status for company %: %', p_company_id, SQLERRM;
        RETURN jsonb_build_object(
            'alerts', '[]'::jsonb,
            'summary', jsonb_build_object('error', SQLERRM),
            'error', true
        );
END;
$$ LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public;

-- Function to mark alerts as read/dismissed
CREATE OR REPLACE FUNCTION public.update_alert_status(
    p_company_id UUID,
    p_alert_id TEXT,
    p_status TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO public.alert_history (company_id, alert_id, status)
    VALUES (p_company_id, p_alert_id, p_status)
    ON CONFLICT (company_id, alert_id) 
    DO UPDATE SET 
        status = EXCLUDED.status,
        read_at = CASE WHEN EXCLUDED.status = 'read' THEN now() ELSE alert_history.read_at END,
        dismissed_at = CASE WHEN EXCLUDED.status = 'dismissed' THEN now() ELSE alert_history.dismissed_at END;

    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Error updating alert status: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public;

-- Row Level Security policies
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS alert_history_company_isolation ON public.alert_history;
CREATE POLICY alert_history_company_isolation ON public.alert_history
    FOR ALL USING (company_id = get_company_id_for_user(auth.uid()));

-- Grant appropriate permissions
GRANT EXECUTE ON FUNCTION public.get_alerts_with_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_alert_status(UUID, TEXT, TEXT) TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.alert_history TO authenticated;

-- Add helpful comments
COMMENT ON FUNCTION public.get_alerts_with_status IS 'Retrieves active alerts with status and summary for a company';
COMMENT ON FUNCTION public.update_alert_status IS 'Updates the read/dismissed status of an alert';
COMMENT ON TABLE public.alert_history IS 'Tracks alert interaction history (read/dismissed status)';

-- Record successful migration
INSERT INTO public.schema_migrations (version) VALUES ('20250129_alert_system_v2')
ON CONFLICT (version) DO NOTHING;

RAISE NOTICE 'Enhanced alert system migration completed successfully';

COMMIT;
