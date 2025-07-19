-- This migration adds a table to track data imports.
-- It helps in maintaining a history of all import jobs, their status,
-- and any errors that occurred during the process.

CREATE TABLE IF NOT EXISTS public.imports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id),
    import_type text NOT NULL,
    file_name text NOT NULL,
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    status text NOT NULL DEFAULT 'pending', -- pending, processing, completed, completed_with_errors, failed
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    completed_at timestamp with time zone
);

ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated users to manage their own company imports"
ON public.imports
FOR ALL
TO authenticated
USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()))
WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

COMMENT ON TABLE public.imports IS 'Stores metadata for CSV import jobs.';
COMMENT ON COLUMN public.imports.status IS 'The current status of the import job.';
COMMENT ON COLUMN public.imports.errors IS 'A JSON array of errors that occurred during the import.';
