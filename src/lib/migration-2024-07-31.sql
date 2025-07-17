-- MIGRATION SCRIPT: 2024-07-31
-- Corrects the column order for the `product_variants_with_details` view to prevent errors on `CREATE OR REPLACE`.
-- This script is safe to run on databases that have the previous migrations applied.

-- Step 1: Recreate the product_variants_with_details view with the correct column order
-- This ensures that the view is updated without causing a column rename error.

CREATE OR REPLACE VIEW public.product_variants_with_details
AS
 SELECT pv.id,
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
    pv.location,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
   FROM (public.product_variants pv
     JOIN public.products p ON ((pv.product_id = p.id)))
  WHERE ((p.deleted_at IS NULL) AND (pv.deleted_at IS NULL));


-- Step 2: Ensure RLS policies are correct for the view owner.
-- This reaffirms the security posture.
ALTER VIEW public.product_variants_with_details OWNER TO postgres;
GRANT ALL ON TABLE public.product_variants_with_details TO postgres;
GRANT ALL ON TABLE public.product_variants_with_details TO service_role;
GRANT SELECT ON TABLE public.product_variants_with_details TO authenticated;

COMMENT ON VIEW public.product_variants_with_details IS 'A unified view of product variants with essential details from their parent product, excluding soft-deleted records.';

-- End of migration script
