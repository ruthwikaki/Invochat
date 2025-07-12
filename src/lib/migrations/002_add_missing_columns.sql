-- This migration script adds missing columns required for reordering and customer analytics.
-- It is designed to be idempotent and can be run safely on existing databases.

-- Add reorder_quantity and lead_time_days to the inventory table if they don't exist.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid = 'public.inventory'::regclass AND attname = 'reorder_quantity') THEN
        ALTER TABLE public.inventory ADD COLUMN reorder_quantity integer;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid = 'public.inventory'::regclass AND attname = 'lead_time_days') THEN
        ALTER TABLE public.inventory ADD COLUMN lead_time_days integer;
    END IF;
END
$$;

-- Add customer_id to the sales table if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_attribute WHERE attrelid = 'public.sales'::regclass AND attname = 'customer_id') THEN
        ALTER TABLE public.sales ADD COLUMN customer_id uuid;
    END IF;
END
$$;

-- Add the foreign key constraint for customer_id if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sales_customer_id_fkey' AND conrelid = 'public.sales'::regclass
    ) THEN
        ALTER TABLE public.sales
        ADD CONSTRAINT sales_customer_id_fkey
        FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL;
    END IF;
END
$$;

-- Add the foreign key constraint for inventory_ledger to product_id if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'inventory_ledger_product_id_fkey' AND conrelid = 'public.inventory_ledger'::regclass
    ) THEN
        ALTER TABLE public.inventory_ledger
        ADD CONSTRAINT inventory_ledger_product_id_fkey
        FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;
    END IF;
END
$$;

-- Remove the old, unused 'sku' column from sale_items if it still exists
ALTER TABLE public.sale_items DROP COLUMN IF EXISTS sku;
