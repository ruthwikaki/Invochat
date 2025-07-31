-- This function is triggered when a new user signs up.
-- It creates a new company, links the user to it as the owner,
-- and creates default settings for the new company.
create or replace function public.on_auth_user_created()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the new user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into new_company_id;

  -- Link the new user to the new company with the 'Owner' role
  insert into public.company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');
  
  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  -- Update the user's app_metadata with the new company_id
  -- This is crucial for the middleware and RLS policies
  perform auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
        'app_metadata', jsonb_build_object(
            'company_id', new_company_id
        )
    )
  );

  return new;
end;
$$;

-- Create the trigger on the auth.users table
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.on_auth_user_created();
