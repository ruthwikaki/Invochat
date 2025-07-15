
-- This script migrates an existing database to the final schema state.
-- It is designed to be run once.

BEGIN;

-- 1. Clean up obsolete columns from tables based on the final schema.
ALTER TABLE public.product_variants
    DROP COLUMN IF EXISTS weight,
    DROP COLUMN IF EXISTS weight_unit;

ALTER TABLE public.company_settings
    DROP COLUMN IF EXISTS timezone,
    DROP COLUMN IF EXISTS custom_rules,
    DROP COLUMN IF EXISTS subscription_status,
    DROP COLUMN IF EXISTS subscription_plan,
    DROP COLUMN IF EXISTS subscription_expires_at,
    DROP COLUMN IF EXISTS stripe_customer_id,
    DROP COLUMN IF EXISTS stripe_subscription_id,
    DROP COLUMN IF EXISTS promo_sales_lift_multiplier;

ALTER TABLE public.orders
    DROP COLUMN IF EXISTS source_name,
    DROP COLUMN IF EXISTS tags,
    DROP COLUMN IF EXISTS status;

-- 2. Add crucial missing indexes for performance and security.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(company_id, email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);

-- 3. Enable Row-Level Security (RLS) on all user data tables.
-- This is a CRITICAL security step.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS Policies to enforce data isolation between companies.
-- Drop policies if they exist to ensure they are created correctly.
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
    ON public.companies FOR SELECT
    USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own company settings." ON public.company_settings;
CREATE POLICY "Users can manage their own company settings."
    ON public.company_settings FOR ALL
    USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
    WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Repeat for all other tables...
DROP POLICY IF EXISTS "Users can manage their own products." ON public.products;
CREATE POLICY "Users can manage their own products." ON public.products FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own product variants." ON public.product_variants;
CREATE POLICY "Users can manage their own product variants." ON public.product_variants FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own orders." ON public.orders;
CREATE POLICY "Users can manage their own orders." ON public.orders FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own order line items." ON public.order_line_items;
CREATE POLICY "Users can manage their own order line items." ON public.order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own customers." ON public.customers;
CREATE POLICY "Users can manage their own customers." ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own suppliers." ON public.suppliers;
CREATE POLICY "Users can manage their own suppliers." ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own purchase orders." ON public.purchase_orders;
CREATE POLICY "Users can manage their own purchase orders." ON public.purchase_orders FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own PO line items." ON public.purchase_order_line_items;
CREATE POLICY "Users can manage their own PO line items." ON public.purchase_order_line_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own inventory ledger." ON public.inventory_ledger;
CREATE POLICY "Users can manage their own inventory ledger." ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own integrations." ON public.integrations;
CREATE POLICY "Users can manage their own integrations." ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own conversations." ON public.conversations;
CREATE POLICY "Users can manage their own conversations." ON public.conversations FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage their own messages." ON public.messages;
CREATE POLICY "Users can manage their own messages." ON public.messages FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can read their own company's audit logs." ON public.audit_log;
CREATE POLICY "Users can read their own company's audit logs." ON public.audit_log FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Ensure users can see their own user record
DROP POLICY IF EXISTS "Users can see their own user record." ON public.users;
CREATE POLICY "Users can see their own user record." ON public.users FOR SELECT USING (id = auth.uid());


-- 5. Final check on function security
-- Change any SECURITY DEFINER functions to SECURITY INVOKER for safety
-- (The main schema creation already does this, but this is a safeguard)
ALTER FUNCTION public.create_company_for_new_user() SECURITY INVOKER;
ALTER FUNCTION public.get_user_company_id() SECURITY INVOKER;
ALTER FUNCTION public.record_inventory_change(uuid, text, integer, uuid, text) SECURITY INVOKER;


COMMIT;

