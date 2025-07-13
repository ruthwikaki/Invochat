--
-- Final Corrective Script for ARVO Database
-- Fixes the webhook_events table to use integration_id.
-- This script is safe to run on the current database state.
--

-- Drop the incorrect webhook_events table if it exists
DROP TABLE IF EXISTS public.webhook_events;

-- Re-create the webhook_events table with the correct schema
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    webhook_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_webhook_per_integration UNIQUE (integration_id, webhook_id)
);

-- Ensure the table is owned by the authenticated role
ALTER TABLE public.webhook_events OWNER TO authenticated;
GRANT ALL ON TABLE public.webhook_events TO authenticated;
GRANT ALL ON TABLE public.webhook_events TO service_role;

-- Add a security policy to the new table
DROP POLICY IF EXISTS "Enable all access for users based on company" ON "public"."webhook_events";
CREATE POLICY "Enable all access for users based on company"
ON "public"."webhook_events"
AS PERMISSIVE
FOR ALL
TO authenticated
USING ((
    (SELECT company_id FROM public.integrations WHERE id = webhook_events.integration_id) = get_current_company_id()
));

COMMENT ON TABLE public.webhook_events IS 'Stores unique webhook IDs to prevent replay attacks.';
COMMENT ON CONSTRAINT unique_webhook_per_integration ON public.webhook_events IS 'Ensures that a specific webhook ID can only be processed once per integration.';

--
-- End of Script
--
