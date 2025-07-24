
-- Drop the dependent trigger first to allow the function to be replaced.
DROP TRIGGER IF EXISTS on_inventory_ledger_insert ON public.inventory_ledger;

-- Drop the function
DROP FUNCTION IF EXISTS public.update_inventory_from_ledger();

-- Add a version column for optimistic locking to the product_variants table.
-- This helps prevent race conditions when multiple users edit the same product.
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;

-- Function to be called by a trigger on the inventory_ledger table
CREATE OR REPLACE FUNCTION public.update_inventory_from_ledger()
RETURNS TRIGGER AS $$
DECLARE
    current_version int;
BEGIN
    -- Get the current version of the variant
    SELECT version INTO current_version FROM public.product_variants WHERE id = NEW.variant_id;

    -- Update the product_variants table
    UPDATE public.product_variants
    SET
        inventory_quantity = NEW.new_quantity,
        updated_at = NOW(),
        version = version + 1
    WHERE
        id = NEW.variant_id AND version = current_version;

    -- If no rows were updated, it means the version was stale (race condition)
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conflict: This record was updated by another process. Please try again.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger to call the updated function
CREATE TRIGGER on_inventory_ledger_insert
AFTER INSERT ON public.inventory_ledger
FOR EACH ROW
EXECUTE FUNCTION public.update_inventory_from_ledger();

