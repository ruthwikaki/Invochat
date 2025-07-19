-- Create the imports table
CREATE TABLE IF NOT EXISTS public.imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    summary JSONB,
    errors JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_imports_company_id ON public.imports(company_id);
CREATE INDEX IF NOT EXISTS idx_imports_status ON public.imports(status);

-- RLS Policies
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Allow users to see their own company's imports.
CREATE POLICY "Allow users to view their own company's imports"
ON public.imports
FOR SELECT
USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Allow users to create imports for their own company.
CREATE POLICY "Allow users to create imports for their company"
ON public.imports
FOR INSERT
WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- It's generally safer to disallow direct updates/deletes from the client.
-- These should be handled by trusted server-side code.
