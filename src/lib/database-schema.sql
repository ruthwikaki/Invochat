-- This is a minimal ALTER script to fix the existing database state.
-- It adds the missing 'location' column and recreates the view that depends on it.

-- Add the 'location' column to the product_variants table if it doesn't exist.
DO $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'product_variants' AND column_name = 'location') THEN
    ALTER TABLE public.product_variants ADD COLUMN location TEXT;
  END IF;
END $$;


-- Recreate the view to include the new location column and remove the incorrect join.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title as product_title,
    p.status as product_status,
    p.product_type,
    p.image_url,
    pv.location -- This is the newly added column
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;
