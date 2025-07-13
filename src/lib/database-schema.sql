-- This script is designed to be run on an existing database to add missing security features.
-- It is safe to run multiple times.

-- 1. Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Create the webhook_events table for replay attack protection
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT uuid_generate_v4() NOT NULL PRIMARY KEY,
    integration_id uuid NOT NULL,
    platform text NOT NULL,
    webhook_id text NOT NULL,
    processed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fk_integration
        FOREIGN KEY(integration_id)
        REFERENCES integrations(id)
        ON DELETE CASCADE
);

-- Create a unique index to prevent duplicate webhook IDs per integration
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_idx ON public.webhook_events(integration_id, webhook_id);

-- Enable Row-Level Security on the new table
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- 3. Fix the RLS policy on customer_addresses to ensure it checks company_id
-- We drop it first to ensure a clean re-creation
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customer_addresses;
CREATE POLICY "Users can only see their own company's data."
ON public.customer_addresses
FOR SELECT
USING (company_id = get_current_company_id());
