-- This migration fixes the column order in the product_variants_with_details view
-- to prevent the "cannot change name of view column" error.

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
    pv.location,
    pv.created_at,
    pv.updated_at,
    pv.deleted_at,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE
    p.deleted_at IS NULL AND pv.deleted_at IS NULL;
