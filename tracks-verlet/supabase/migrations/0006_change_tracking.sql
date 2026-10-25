-- Requests stay editable by their engineer and by managers at every stage.
-- Once approved, each line keeps the confirmed version in `approved`, and the request keeps its confirmed header
-- in `approved_snapshot`. Edits after that are pending changes until a manager approves them (approve_request)
-- or someone discards them (discard_changes). Deleting a confirmed line marks it `removed` until then.

alter table public.line_items
  add column approved jsonb,
  add column removed boolean not null default false;
alter table public.requests
  add column approved_snapshot jsonb,
  add column approved_at timestamptz;

-- The fields that make up a confirmed line / header.
create or replace function public.line_fields(li public.line_items) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object(
    'item_name', li.item_name, 'qty', li.qty, 'unit', li.unit, 'specification', li.specification,
    'datasheet_url', li.datasheet_url, 'air_freight', li.air_freight, 'est_unit_price_usd', li.est_unit_price_usd,
    'suggested_vendor', li.suggested_vendor, 'notes', li.notes);
$$;
create or replace function public.header_fields(r public.requests) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_object('title', r.title, 'project', r.project, 'needed_by', r.needed_by,
                            'urgency', r.urgency, 'justification', r.justification);
$$;

-- Template checks ignore lines that are marked for removal.
create or replace function public.line_issues(li public.line_items) returns text[]
language sql stable set search_path = public as $$
  select case when li.removed then '{}'::text[] else array_remove(array[
    case when nullif(trim(li.item_name),'') is not null and li.qty is null then 'Qty missing' end,
    case when nullif(trim(li.item_name),'') is not null and li.qty <= 0 then 'Qty must be above zero' end,
    case when nullif(trim(li.item_name),'') is not null and li.unit is null then 'Unit missing' end,
    case when nullif(trim(li.item_name),'') is not null and length(trim(coalesce(li.specification,''))) < 25 then 'Spec too thin' end,
    case when nullif(trim(li.item_name),'') is not null and li.air_freight is null then 'Air-freight answer missing' end,
    case when nullif(trim(li.item_name),'') is not null and (select count(*) from public.line_items d
          where d.request_id = li.request_id and not d.removed and lower(trim(d.item_name)) = lower(trim(li.item_name))) > 1
         then 'Duplicate item in this request' end,
    case when nullif(trim(li.item_name),'') is null and (li.qty is not null or nullif(trim(li.specification),'') is not null)
         then 'Item name missing' end
  ], null) end;
$$;

create or replace function public.request_issues(rid uuid) returns text[]
language sql stable set search_path = public as $$
  select array_remove(array[
    case when nullif(trim(p.full_name),'') is null then 'your name' end,
    case when nullif(trim(p.email),'') is null then 'your email' end,
    case when r.project is null then 'project' end,
    case when r.needed_by is null then 'needed-by date' end,
    case when length(trim(coalesce(r.justification,''))) < 15 then 'why this is needed' end,
    case when not exists (select 1 from public.line_items li where li.request_id = r.id and not li.removed
                          and nullif(trim(li.item_name),'') is not null) then 'no line items' end,
    case when exists (select 1 from public.line_items li where li.request_id = r.id and not li.removed
                      and cardinality(public.line_issues(li)) > 0) then 'line items need attention' end
  ], null)
  from public.requests r join public.profiles p on p.id = r.owner_id
  where r.id = rid;
$$;

create or replace function public.unpriced_count(rid uuid) returns int
language sql stable set search_path = public as $$
  select count(*)::int from public.line_items li
  where li.request_id = rid and not li.removed and nullif(trim(li.item_name),'') is not null and li.est_unit_price_usd is null;
$$;

-- Lines added, changed or marked removed since the last approval, plus 1 if the header changed.
create or replace function public.pending_changes(rid uuid) returns int
language sql stable set search_path = public as $$
  select case when r.approved_at is null then 0 else
    (select count(*)::int from public.line_items li where li.request_id = rid and (
       li.removed or li.approved is null or li.approved <> public.line_fields(li)))
    + case when r.approved_snapshot is distinct from public.header_fields(r) then 1 else 0 end
  end
  from public.requests r where r.id = rid;
$$;

-- Engineers edit their own requests at any stage; managers edit all.
create or replace function public.can_edit_request(rid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_manager() or exists (select 1 from public.requests r where r.id = rid and r.owner_id = auth.uid());
$$;

drop policy requests_update on public.requests;
create policy requests_update on public.requests for update to authenticated
  using (public.is_manager() or owner_id = (select auth.uid()))
  with check (public.is_manager() or owner_id = (select auth.uid()));

-- A confirmed line can only leave through approve_request; clients mark it `removed` instead.
drop policy line_items_delete on public.line_items;
create policy line_items_delete on public.line_items for delete to authenticated
  using (public.can_edit_request(request_id) and approved is null);

-- Clients never write the confirmed snapshots.
revoke insert, update on public.line_items from authenticated;
grant insert (id, request_id, bom_upload_id, position, item_name, qty, unit, specification, datasheet_url, air_freight,
              est_unit_price_usd, suggested_vendor, notes, source_row, auto_fields)
  on public.line_items to authenticated;
grant update (position, item_name, qty, unit, specification, datasheet_url, air_freight, est_unit_price_usd,
              suggested_vendor, notes, auto_fields, removed)
  on public.line_items to authenticated;
revoke insert, update on public.requests from authenticated;
grant insert (id, title, project, needed_by, urgency, justification) on public.requests to authenticated;
grant update (title, project, needed_by, urgency, justification, status, manager_note) on public.requests to authenticated;

create or replace function public.guard_request_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare problems text[]; unpriced int;
begin
  if new.status is distinct from old.status then
    if not public.is_manager()
       and not (old.status in ('draft', 'rejected') and new.status = 'submitted') then
      raise exception 'Only a manager can move a request from % to %', old.status, new.status;
    end if;
    if new.status = 'submitted' then
      problems := public.request_issues(new.id);
      if cardinality(problems) > 0 then
        raise exception 'NOT READY - %', array_to_string(problems, ', ');
      end if;
      new.date_submitted := coalesce(new.date_submitted, current_date);
    end if;
    if new.status = 'approved' and coalesce(current_setting('tracks.approving', true), '') <> 'on' then
      raise exception 'Use Approve to approve a request, so its BOM is confirmed';
    end if;
    if new.status in ('approved', 'ordered') then
      unpriced := public.unpriced_count(new.id);
      if unpriced > 0 then
        raise exception 'Add an estimated price to the % unpriced line(s) before marking this %', unpriced, new.status;
      end if;
    end if;
  end if;
  if not public.is_manager() and (new.req_number is distinct from old.req_number or new.manager_note is distinct from old.manager_note) then
    raise exception 'Only a manager can set the REQ number or manager note';
  end if;
  return new;
end $$;

-- First approval, and every later "approve changes": the working version becomes the confirmed BOM.
create or replace function public.approve_request(rid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests; problems text[]; unpriced int;
begin
  if not public.is_manager() then raise exception 'Only managers can approve'; end if;
  select * into r from public.requests where id = rid for update;
  if r.id is null then raise exception 'No such request'; end if;
  if r.status = 'draft' then raise exception 'This request hasn''t been submitted yet'; end if;
  problems := public.request_issues(rid);
  if cardinality(problems) > 0 then raise exception 'NOT READY - %', array_to_string(problems, ', '); end if;
  unpriced := public.unpriced_count(rid);
  if unpriced > 0 then raise exception 'Add an estimated price to the % unpriced line(s) before approving', unpriced; end if;

  perform set_config('tracks.approving', 'on', true);
  delete from public.line_items where request_id = rid and removed;
  update public.line_items li set approved = public.line_fields(li) where li.request_id = rid;
  update public.requests set
    status = case when r.status = 'ordered' then 'ordered'::public.request_status else 'approved'::public.request_status end,
    approved_at = now(),
    approved_snapshot = public.header_fields(r)
  where id = rid;
  perform set_config('tracks.approving', 'off', true);
end $$;

-- Back to the confirmed BOM: drop added lines, restore changed and removed ones, restore the header.
create or replace function public.discard_changes(rid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  if not public.can_edit_request(rid) then raise exception 'You can''t edit this request'; end if;
  select * into r from public.requests where id = rid;
  if r.approved_at is null then raise exception 'Nothing has been approved yet, so there''s nothing to go back to'; end if;
  delete from public.line_items where request_id = rid and approved is null;
  update public.line_items set
    item_name = approved->>'item_name',
    qty = (approved->>'qty')::numeric,
    unit = (approved->>'unit')::public.unit,
    specification = approved->>'specification',
    datasheet_url = approved->>'datasheet_url',
    air_freight = (approved->>'air_freight')::public.air_freight,
    est_unit_price_usd = (approved->>'est_unit_price_usd')::numeric,
    suggested_vendor = approved->>'suggested_vendor',
    notes = approved->>'notes',
    removed = false
  where request_id = rid;
  update public.requests set
    title = r.approved_snapshot->>'title',
    project = r.approved_snapshot->>'project',
    needed_by = (r.approved_snapshot->>'needed_by')::date,
    urgency = (r.approved_snapshot->>'urgency')::public.urgency,
    justification = r.approved_snapshot->>'justification'
  where id = rid;
end $$;

revoke execute on function public.approve_request(uuid) from public, anon;
revoke execute on function public.discard_changes(uuid) from public, anon;
revoke execute on function public.pending_changes(uuid) from public, anon;
grant execute on function public.approve_request(uuid), public.discard_changes(uuid), public.pending_changes(uuid) to authenticated;

-- Requests approved before this migration get their current version as the confirmed one.
update public.line_items li set approved = public.line_fields(li)
from public.requests r where r.id = li.request_id and r.status in ('approved', 'ordered');
update public.requests r set approved_at = r.updated_at, approved_snapshot = public.header_fields(r)
where r.status in ('approved', 'ordered');

-- Totals and counts follow the working version (removed lines excluded).
-- Dropped and recreated: r.* now has more columns, which moves the view's columns.
drop view public.request_summaries;
create view public.request_summaries with (security_invoker = true) as
select r.*, p.full_name as owner_name, p.email as owner_email,
  (select count(*) from public.line_items li where li.request_id = r.id and not li.removed and nullif(trim(li.item_name),'') is not null) as line_count,
  (select coalesce(sum(li.qty * li.est_unit_price_usd), 0) from public.line_items li where li.request_id = r.id and not li.removed) as est_total_usd,
  (select bool_or(li.air_freight <> 'No') from public.line_items li where li.request_id = r.id and not li.removed) as has_air_restricted,
  public.request_issues(r.id) as issues,
  public.unpriced_count(r.id) as unpriced_count,
  public.pending_changes(r.id) as pending_changes
from public.requests r join public.profiles p on p.id = r.owner_id;
revoke all on public.request_summaries from anon;
grant select on public.request_summaries to authenticated;
