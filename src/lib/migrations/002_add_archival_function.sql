-- This script creates archival tables and a function to move old data.
-- It's designed to be run once.

BEGIN;

-- Create archive table for sales
CREATE TABLE IF NOT EXISTS public.sales_archive (
    LIKE public.sales INCLUDING ALL
);
ALTER TABLE public.sales_archive ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.sales_archive IS 'Archive for old sales records.';

-- Create archive table for sale_items
CREATE TABLE IF NOT EXISTS public.sale_items_archive (
    LIKE public.sale_items INCLUDING ALL
);
ALTER TABLE public.sale_items_archive ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.sale_items_archive IS 'Archive for old sale items, linked to sales_archive.';

-- Create archive table for audit_log
CREATE TABLE IF NOT EXISTS public.audit_log_archive (
    LIKE public.audit_log INCLUDING ALL
);
ALTER TABLE public.audit_log_archive ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.audit_log_archive IS 'Archive for old audit log entries.';

-- Create the archival function
CREATE OR REPLACE FUNCTION public.archive_old_data(
    p_company_id uuid,
    p_cutoff_date date
) RETURNS TABLE(archived_table text, record_count int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_archived_sales_count int;
    v_archived_sale_items_count int;
    v_archived_audit_logs_count int;
BEGIN
    -- Archive Sales and associated Sale Items
    WITH archived_sales AS (
        DELETE FROM public.sales s
        WHERE s.company_id = p_company_id
          AND s.created_at < p_cutoff_date
        RETURNING s.*
    ),
    inserted_sales AS (
        INSERT INTO public.sales_archive SELECT * FROM archived_sales
        RETURNING id
    ),
    archived_items AS (
        DELETE FROM public.sale_items si
        WHERE si.sale_id IN (SELECT id FROM inserted_sales)
        RETURNING si.*
    )
    INSERT INTO public.sale_items_archive SELECT * FROM archived_items;

    GET DIAGNOSTICS v_archived_sales_count = ROW_COUNT;
    -- The above will not work as expected for CTEs, so we count from the CTE result.
    SELECT count(*) INTO v_archived_sales_count FROM (SELECT 1 FROM archived_sales) a;
    SELECT count(*) INTO v_archived_sale_items_count FROM (SELECT 1 FROM archived_items) a;


    -- Archive Audit Logs
    WITH archived_logs AS (
        DELETE FROM public.audit_log al
        WHERE al.company_id = p_company_id
          AND al.created_at < p_cutoff_date
        RETURNING al.*
    )
    INSERT INTO public.audit_log_archive SELECT * FROM archived_logs;

    GET DIAGNOSTICS v_archived_audit_logs_count = ROW_COUNT;
    -- Correct count for the audit logs
    SELECT count(*) INTO v_archived_audit_logs_count FROM (SELECT 1 FROM archived_logs) a;


    -- Return summary of actions
    RETURN QUERY SELECT 'sales' as archived_table, v_archived_sales_count as record_count;
    RETURN QUERY SELECT 'sale_items' as archived_table, v_archived_sale_items_count as record_count;
    RETURN QUERY SELECT 'audit_log' as archived_table, v_archived_audit_logs_count as record_count;
END;
$$;

-- Grant execute permissions on the new function
GRANT EXECUTE ON FUNCTION public.archive_old_data(uuid, date) TO authenticated;

-- Set up RLS policies for the archive tables
CREATE POLICY "Allow company members to read sales archive" ON public.sales_archive FOR SELECT USING (is_member_of_company(company_id));
CREATE POLICY "Allow company members to read sale_items archive" ON public.sale_items_archive FOR SELECT USING (is_member_of_company(company_id));
CREATE POLICY "Allow company members to read audit_log archive" ON public.audit_log_archive FOR SELECT USING (is_member_of_company(company_id));


COMMIT;

-- Example Usage (run manually in SQL Editor):
/*
SELECT * FROM public.archive_old_data(
    'your-company-id-here', -- Replace with a valid company_id
    '2024-01-01'::date       -- Replace with your desired cutoff date
);
*/
