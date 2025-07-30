-- supabase/migrations/20240725120000_initial_schema.sql

-- Drop the old, problematic function if it exists to avoid conflicts.
DROP FUNCTION IF EXISTS public.create_company_and_user(text, text, text);

--
-- Create the new, correct function for handling user signup.
-- This function runs with the privileges of the definer (the admin role),
-- which is necessary to create users in the 'auth' schema.
--
create or replace function public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  new_user_id uuid;
begin
  -- 1. Create a new company.
  insert into public.companies (name)
  values (p_company_name)
  returning id into new_company_id;

  -- 2. Create the new user in the auth.users table, embedding the company_id
  --    and a default role in the user's metadata.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, email_change_token_current, email_change_confirm_status)
  values
    (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      p_user_email,
      crypt(p_user_password, gen_salt('bf')),
      now(),
      '',
      now(),
      now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', new_company_id, 'role', 'Owner'),
      now(),
      now(),
      '',
      '',
      '',
      '',
      0
    )
  returning id into new_user_id;

  -- 3. Update the company with the new user's ID as the owner.
  update public.companies
  set owner_id = new_user_id
  where id = new_company_id;

  -- 4. Link the user to the company in the company_users table.
  insert into public.company_users (company_id, user_id, role)
  values (new_company_id, new_user_id, 'Owner');

  return new_user_id;
end;
$$;
