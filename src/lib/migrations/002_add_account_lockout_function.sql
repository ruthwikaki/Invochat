
-- Function to lock a user account by setting `banned_until`.
-- This is a security function and should only be callable by the service_role.
create or replace function lock_user_account(p_user_id uuid, p_lockout_duration interval)
returns void as $$
begin
    if auth.uid() is not null then
        raise exception 'This function can only be called by the service_role';
    end if;

    update auth.users
    set banned_until = now() + p_lockout_duration
    where id = p_user_id;
end;
$$ language plpgsql security definer;

-- Grant execute permission to the service_role.
-- The authenticator role (anon, authenticated) should NOT be able to run this.
grant execute on function public.lock_user_account(uuid, interval) to service_role;

revoke execute on function public.lock_user_account(uuid, interval) from authenticated;
revoke execute on function public.lock_user_account(uuid, interval) from anon;
