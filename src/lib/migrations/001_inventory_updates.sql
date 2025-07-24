-- Migration to add advanced inventory management features.
-- This script is designed to be idempotent and can be run safely on an existing database.

-- Add columns to product_variants for better reordering and stock tracking
ALTER TABLE public.product_variants
    ADD COLUMN IF NOT EXISTS reorder_point INTEGER,
    ADD COLUMN IF NOT EXISTS reorder_quantity INTEGER,
    ADD COLUMN IF NOT EXISTS reserved_quantity INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS in_transit_quantity INTEGER NOT NULL DEFAULT 0;

-- Add a constraint to prevent negative inventory quantities, a critical data integrity rule.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'check_non_negative_inventory' AND conrelid = 'public.product_variants'::regclass
    ) THEN
        ALTER TABLE public.product_variants
        ADD CONSTRAINT check_non_negative_inventory CHECK (inventory_quantity >= 0);
    END IF;
END;
$$;

-- Add a column to track supplier-specific lead times for more accurate reordering.
ALTER TABLE public.suppliers
    ADD COLUMN IF NOT EXISTS lead_time_days INTEGER;

-- Add a column for better purchase order management
ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS notes TEXT;
