-- Fix missing FTS column for inventory search
ALTER TABLE product_variants_with_details ADD COLUMN IF NOT EXISTS fts tsvector;

-- Create FTS index for search functionality
CREATE INDEX IF NOT EXISTS idx_product_variants_fts ON product_variants_with_details USING gin(fts);

-- Update FTS column with searchable content
UPDATE product_variants_with_details 
SET fts = to_tsvector('english', COALESCE(name, '') || ' ' || COALESCE(sku, '') || ' ' || COALESCE(description, ''))
WHERE fts IS NULL;

-- Create trigger to maintain FTS column
CREATE OR REPLACE FUNCTION update_product_fts()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fts = to_tsvector('english', COALESCE(NEW.name, '') || ' ' || COALESCE(NEW.sku, '') || ' ' || COALESCE(NEW.description, ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_product_fts ON product_variants_with_details;
CREATE TRIGGER trigger_update_product_fts
    BEFORE INSERT OR UPDATE ON product_variants_with_details
    FOR EACH ROW EXECUTE FUNCTION update_product_fts();
