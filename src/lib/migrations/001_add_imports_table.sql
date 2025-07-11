-- This script creates the table for tracking data import jobs.

CREATE TABLE IF NOT EXISTS public.imports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
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
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Add indexes for faster lookups during import processing
CREATE INDEX IF NOT EXISTS idx_imports_company_id ON public.imports(company_id);
CREATE INDEX IF NOT EXISTS idx_imports_status ON public.imports(status);

-- Enable RLS for the new table
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Policies for the imports table
-- Users can see their own company's import jobs.
CREATE POLICY "Allow users to see their company's imports"
ON public.imports FOR SELECT
USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())));

-- Users can create import jobs for their own company.
CREATE POLICY "Allow users to create imports for their company"
ON public.imports FOR INSERT
WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- The service_role (backend) can update job status.
-- No UPDATE or DELETE policies are granted to users directly for safety.
