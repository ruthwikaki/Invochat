

-- Create the imports table
-- This table tracks the history and status of all data import jobs.
CREATE TABLE public.imports (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    import_type text NOT NULL,
    file_name text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    total_rows integer,
    processed_rows integer,
    failed_rows integer,
    errors jsonb,
    summary jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    completed_at timestamp with time zone,
    PRIMARY KEY (id)
);
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own company's import jobs.
CREATE POLICY "Users can view their own company's import jobs" ON public.imports
    FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Allow users to create import jobs for their own company.
CREATE POLICY "Users can create import jobs for their own company" ON public.imports
    FOR INSERT WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Note: The service_role key will be used to update the status of jobs from the server.
