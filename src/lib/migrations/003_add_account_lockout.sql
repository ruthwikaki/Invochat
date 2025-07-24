-- Migration: Add Account Lockout Functionality
-- This script adds a function to temporarily lock a user account after too many failed login attempts.

-- Do not co-locate this with other migration scripts.

create or replace function "public"."lock_user_account"(p_user_id uuid, p_lockout_duration text)
returns void
language plpgsql
security definer -- Required to perform admin actions
set search_path = auth
as $$
begin
  -- This function MUST be run with the service_role key to have permission to update auth.users
  if not (select session_user = 'postgres') then
    raise exception 'This function must be run by the database superuser';
  end if;

  update auth.users
  set banned_until = now() + p_lockout_duration::interval
  where id = p_user_id;
end;
$$;

grant execute on function "public"."lock_user_account"(uuid, text) to service_role;

comment on function "public"."lock_user_account"(uuid, text) is 'Locks a user account for a specified duration by setting the banned_until field. Can only be executed by the service_role.';
