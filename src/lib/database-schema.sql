-- Add a "location" text column to the product_variants table if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'product_variants'
        AND column_name = 'location'
    ) THEN
        ALTER TABLE public.product_variants ADD COLUMN location TEXT NULL;
    END IF;
END $$;

-- Drop the view if it exists. This is necessary to avoid column order/name conflicts.
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Recreate the view with the new location column
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
    pv.location,
    pv.external_variant_id,
    pv.created_at,
    pv.updated_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
LEFT JOIN
    public.products p ON pv.product_id = p.id;

-- Ensure the authenticated user can select from the view
GRANT SELECT ON public.product_variants_with_details TO authenticated;
