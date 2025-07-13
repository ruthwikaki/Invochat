
-- This script is targeted to fix specific issues in the existing database.
-- It is safe to run on your current schema.

-- 1. Create a table to prevent webhook replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    platform text NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT webhook_events_pkey PRIMARY KEY (id),
    CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE,
    CONSTRAINT webhook_events_unique_webhook UNIQUE (platform, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company's data." ON public.webhook_events
    FOR SELECT
    USING (company_id_from_integration(integration_id) = get_current_company_id());

-- 2. Fix the incorrect RLS policy on customer_addresses
-- This was causing the error: column "company_id" does not exist

-- Drop the old, incorrect policy if it exists from a failed run
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customer_addresses;

-- Create the new, correct policy that checks the company_id from the parent customer
CREATE POLICY "Users can only see their own company's data." ON public.customer_addresses
    FOR ALL
    USING (
        (
            SELECT company_id
            FROM public.customers
            WHERE id = customer_addresses.customer_id
        ) = get_current_company_id()
    );

-- The rest of the schema is assumed to be correct based on previous updates.
-- This script only applies the necessary fixes.
