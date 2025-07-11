
-- This script adds the `imports` table for tracking data import jobs.

CREATE TABLE IF NOT EXISTS public.imports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  import_type VARCHAR(50) NOT NULL,
  file_name VARCHAR(255),
  status VARCHAR(20) DEFAULT 'pending',
  total_rows INTEGER,
  processed_rows INTEGER DEFAULT 0,
  failed_rows INTEGER DEFAULT 0,
  errors JSONB,
  summary JSONB,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,
  CONSTRAINT imports_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT imports_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id)
);

-- Enable RLS
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Policies for the imports table
CREATE POLICY "Allow users to view their own company's imports"
ON public.imports FOR SELECT
USING (auth.uid() IS NOT NULL AND company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

CREATE POLICY "Allow admins/owners to create imports for their company"
ON public.imports FOR INSERT
WITH CHECK (
  auth.uid() IS NOT NULL AND
  company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()) AND
  (SELECT role FROM public.users WHERE id = auth.uid()) IN ('Admin', 'Owner')
);

-- Add indexes for faster lookups during import processing
CREATE INDEX IF NOT EXISTS idx_inventory_sku_company ON public.inventory(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_vendors_email_company ON public.vendors(contact_info, company_id);

-- Optional: Add a comment to the new table for clarity in the database schema
COMMENT ON TABLE public.imports IS 'Tracks the status and results of data import jobs.';
