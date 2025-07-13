-- This script is designed to finalize the database schema.
-- It performs only the necessary cleanup of deprecated columns.

-- Step 1: Alter the integrations table to remove the unused access_token column.
-- Secrets are now stored securely in Supabase Vault.
ALTER TABLE IF EXISTS public.integrations
DROP COLUMN IF EXISTS access_token;

-- Finalization complete. Your schema is now fully aligned with the application code.
