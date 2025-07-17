-- Migration: Enforce SKU on Order Line Items
-- Date: 2024-07-26
-- Description: This script ensures data integrity by making the 'sku' column on the 'order_line_items' table non-nullable.

-- Step 1: Backfill any existing order line items where SKU is NULL.
-- This prevents the ALTER TABLE command from failing on existing data.
-- It attempts to look up the SKU from the related product variant. If not found,
-- it uses a placeholder to satisfy the constraint.
UPDATE public.order_line_items oli
SET sku = COALESCE(pv.sku, 'UNKNOWN_SKU_' || oli.id::text)
FROM public.product_variants pv
WHERE oli.variant_id = pv.id AND oli.sku IS NULL;

-- Step 2: Alter the table to make the SKU column required.
-- This is the core fix to enforce data integrity for all future sales.
ALTER TABLE public.order_line_items
ALTER COLUMN sku SET NOT NULL;

-- --- End of Migration ---
