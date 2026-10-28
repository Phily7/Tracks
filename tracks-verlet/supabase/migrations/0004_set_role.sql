-- Managers promote or demote people from the Team panel.
-- Roles stay off-limits to direct updates (0001 revokes UPDATE on profiles.role); this is the only way in.

create or replace function public.set_role(target uuid, new_role public.user_role) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_manager() then raise exception 'Only managers can change roles'; end if;
  if target = auth.uid() and new_role <> 'manager' then
    raise exception 'You can''t remove your own manager role. Ask another manager.';
  end if;
  update public.profiles set role = new_role where id = target;
  if not found then raise exception 'No such person'; end if;
  update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('role', new_role)
  where id = target;
end $$;

revoke execute on function public.set_role(uuid, public.user_role) from public, anon;
grant execute on function public.set_role(uuid, public.user_role) to authenticated;
