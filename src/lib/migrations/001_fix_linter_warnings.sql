-- This migration script fixes warnings from the Supabase Database Linter.
-- It can be run safely multiple times.

-- Set a secure search_path for all database functions to prevent hijacking.
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';
ALTER FUNCTION public.record_sale_transaction_v2(uuid, uuid, jsonb, text, text, text, text, text) SET search_path = 'public';
ALTER FUNCTION public.get_distinct_categories(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_alerts(uuid, integer, integer, integer) SET search_path = 'public';
ALTER FUNCTION public.get_anomaly_insights(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_reorder_suggestions(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_inventory_ledger_for_sku(uuid, uuid) SET search_path = 'public';
ALTER FUNCTION public.get_sales_velocity(uuid, integer, integer) SET search_path = 'public';
ALTER FUNCTION public.get_demand_forecast(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_abc_analysis(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_gross_margin_analysis(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_net_margin_by_channel(uuid, text) SET search_path = 'public';
ALTER FUNCTION public.get_margin_trends(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_financial_impact_of_promotion(uuid, text[], numeric, integer) SET search_path = 'public';
ALTER FUNCTION public.get_historical_sales(uuid, text[]) SET search_path = 'public';
ALTER FUNCTION public.get_supplier_performance_report(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_inventory_turnover_report(uuid, integer) SET search_path = 'public';
ALTER FUNCTION public.get_dashboard_metrics(uuid, integer) SET search_path = 'public';
ALTER FUNCTION public.get_inventory_analytics(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_sales_analytics(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_customer_analytics(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_customers_with_stats(uuid, text, integer, integer) SET search_path = 'public';
ALTER FUNCTION public.get_unified_inventory(uuid, text, text, uuid, text[], integer, integer) SET search_path = 'public';
ALTER FUNCTION public.health_check_inventory_consistency(uuid) SET search_path = 'public';
ALTER FUNCTION public.health_check_financial_consistency(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_inventory_aging_report(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_product_lifecycle_analysis(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_inventory_risk_report(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_customer_segment_analysis(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_cash_flow_insights(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_dead_stock_alerts_data(uuid, integer) SET search_path = 'public';
ALTER FUNCTION public.get_business_profile(uuid) SET search_path = 'public';
ALTER FUNCTION public.refresh_materialized_views(uuid) SET search_path = 'public';
ALTER FUNCTION public.reconcile_inventory_from_integration(uuid, uuid) SET search_path = 'public';
ALTER FUNCTION public.is_member_of_company(uuid) SET search_path = 'public';
ALTER FUNCTION public.get_my_role(uuid) SET search_path = 'public';

-- Revoke public API access from materialized views for security.
-- These should only be accessed by the backend service role.
REVOKE ALL ON public.company_dashboard_metrics FROM anon, authenticated;
REVOKE ALL ON public.customer_analytics_metrics FROM anon, authenticated;

-- Grant usage back to postgres and service_role to ensure backend functionality
GRANT ALL ON public.company_dashboard_metrics TO postgres, service_role;
GRANT ALL ON public.customer_analytics_metrics TO postgres, service_role;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'Finished applying database linter fixes.';
END;
$$;
