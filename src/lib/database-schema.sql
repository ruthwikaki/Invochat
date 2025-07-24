-- Add version column for optimistic locking
ALTER TABLE public.product_variants
ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1;


-- Drop the existing function to redefine it
DROP FUNCTION IF EXISTS public.update_inventory_from_ledger();

-- Recreate the function with optimistic locking logic
CREATE OR REPLACE FUNCTION public.update_inventory_from_ledger()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for negative inventory before applying the change
    IF (SELECT inventory_quantity FROM public.product_variants WHERE id = NEW.variant_id) + NEW.quantity_change < 0 THEN
        RAISE EXCEPTION 'Negative inventory violation: Cannot complete operation for SKU %', (SELECT sku FROM public.product_variants WHERE id = NEW.variant_id);
    END IF;

    UPDATE public.product_variants
    SET 
        inventory_quantity = inventory_quantity + NEW.quantity_change,
        version = version + 1, -- Increment the version on each update
        updated_at = now()
    WHERE id = NEW.variant_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The trigger definition remains the same, but the function it calls is now updated.
-- This ensures the trigger exists if it was somehow missed before.
CREATE TRIGGER trg_update_inventory_from_ledger
AFTER INSERT ON public.inventory_ledger
FOR EACH ROW
EXECUTE FUNCTION public.update_inventory_from_ledger();

COMMENT ON FUNCTION public.update_inventory_from_ledger() IS 'Updates the inventory_quantity and version in product_variants whenever a new entry is added to inventory_ledger, preventing negative stock and providing optimistic locking.';
