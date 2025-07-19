SET QUOTED_IDENTIFIER ON;
-- Create the imports table
CREATE TABLE public.imports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    import_type TEXT NOT NULL,
    file_name TEXT,
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX idx_imports_company_id ON public.imports(company_id);

-- RLS Policies
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own company's imports"
    ON public.imports FOR SELECT
    USING (company_id IN (SELECT company_id FROM public.user_profiles WHERE user_id = auth.uid()));

CREATE POLICY "Users can insert imports for their own company"
    ON public.imports FOR INSERT
    WITH CHECK (company_id IN (SELECT company_id FROM public.user_profiles WHERE user_id = auth.uid()));

-- Grant usage permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.imports TO authenticated;
