
-- Migration to add subscription, billing, and enhanced sync fields

-- Add new columns to the company_settings table for billing and subscription management
ALTER TABLE public.company_settings
ADD COLUMN IF NOT EXISTS subscription_status TEXT CHECK (subscription_status IN ('trial', 'active', 'past_due', 'canceled')) DEFAULT 'trial',
ADD COLUMN IF NOT EXISTS subscription_plan TEXT CHECK (subscription_plan IN ('starter', 'growth', 'enterprise')) DEFAULT 'starter',
ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT;

-- Add new columns to the inventory table for better synchronization and conflict resolution
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS conflict_status TEXT CHECK (conflict_status IN ('synced', 'conflict', 'override')),
ADD COLUMN IF NOT EXISTS last_external_sync TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS manual_override BOOLEAN DEFAULT FALSE;

-- Add new columns to track payment status on purchase orders
ALTER TABLE public.purchase_orders
ADD COLUMN IF NOT EXISTS payment_terms_days INTEGER,
ADD COLUMN IF NOT EXISTS payment_due_date DATE,
ADD COLUMN IF NOT EXISTS amount_paid BIGINT DEFAULT 0,
ADD CONSTRAINT po_amount_paid_check CHECK (amount_paid >= 0);

-- Add new columns to the inventory table for lot and expiration tracking
ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS expiration_date DATE,
ADD COLUMN IF NOT EXISTS lot_number TEXT;

-- Add an index for efficient querying of soon-to-expire products
CREATE INDEX IF NOT EXISTS idx_inventory_expiration
ON public.inventory (company_id, expiration_date)
WHERE expiration_date IS NOT NULL AND deleted_at IS NULL;

-- Add an index for lot number searches
CREATE INDEX IF NOT EXISTS idx_inventory_lot_number
ON public.inventory (company_id, lot_number)
WHERE lot_number IS NOT NULL AND deleted_at IS NULL;

-- Log successful completion of the migration
-- (This is a comment and won't be executed, but serves as a marker)
-- MIGRATION 001 COMPLETE
