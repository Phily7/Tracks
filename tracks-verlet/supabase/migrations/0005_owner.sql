-- An owner whose role nobody else can change, and who alone can demote managers.
-- Any manager can still promote an engineer. is_owner is not in the column grants, so it can't be self-set.

alter table public.profiles add column is_owner boolean not null default false;
update public.profiles set is_owner = true where email = 'philemonmail77@gmail.com';

create or replace function public.set_role(target uuid, new_role public.user_role) returns void
language plpgsql security definer set search_path = public as $$
declare me public.profiles; them public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  select * into them from public.profiles where id = target;
  if me.id is null or me.role <> 'manager' then raise exception 'Only managers can change roles'; end if;
  if them.id is null then raise exception 'No such person'; end if;
  if them.role = new_role then return; end if;
  if them.is_owner then raise exception 'The owner''s role can''t be changed'; end if;
  if them.role = 'manager' and not me.is_owner then raise exception 'Only the owner can remove a manager'; end if;
  update public.profiles set role = new_role where id = target;
  update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('role', new_role)
  where id = target;
end $$;

revoke execute on function public.set_role(uuid, public.user_role) from public, anon;
grant execute on function public.set_role(uuid, public.user_role) to authenticated;
