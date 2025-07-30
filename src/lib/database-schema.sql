
-- This function replaces the previous trigger-based approach.
-- It safely creates a company and a new user in a single transaction.
create or replace function public.create_company_and_user(
    p_company_name text,
    p_user_email text,
    p_user_password text
)
returns void as $$
declare
  v_company_id uuid;
  v_user_id uuid;
begin
  -- 1. Create the company first.
  insert into public.companies (name)
  values (p_company_name)
  returning id into v_company_id;

  -- 2. Create the user in auth.users, embedding the company_id in their metadata.
  --    This is the key step to ensure the company_id is available when the public.users record is created.
  v_user_id := auth.uid() from auth.users where email = p_user_email;
  if v_user_id is null then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_token, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, phone, phone_confirmed_at, email_change, email_change_token_new, email_change_sent_at)
    values (gen_random_uuid(), gen_random_uuid(), 'authenticated', 'authenticated', p_user_email, crypt(p_user_password, gen_salt('bf')), now(), 'token', now(), now(), jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'company_id', v_company_id), jsonb_build_object('company_name', p_company_name), now(), now(), null, null, '', '', null)
    returning id into v_user_id;

    -- Also insert into identities
    insert into auth.identities (id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_user_id, jsonb_build_object('sub', v_user_id, 'email', p_user_email), 'email', now(), now(), now());
  else
    raise exception 'A user with this email already exists.';
  end if;


  -- 3. Update the company with the owner's ID.
  update public.companies
  set owner_id = v_user_id
  where id = v_company_id;

  -- 4. Link the user to the company in the company_users junction table.
  insert into public.company_users (user_id, company_id, role)
  values (v_user_id, v_company_id, 'Owner');
end;
$$ language plpgsql security definer;
