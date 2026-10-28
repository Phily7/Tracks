-- Engineers may submit without prices; procurement prices the lines.
-- A request can't be approved (or ordered) until every named line has an estimated price.

create or replace function public.line_issues(li public.line_items) returns text[]
language sql stable set search_path = public as $$
  select array_remove(array[
    case when nullif(trim(li.item_name),'') is not null and li.qty is null then 'Qty missing' end,
    case when nullif(trim(li.item_name),'') is not null and li.qty <= 0 then 'Qty must be above zero' end,
    case when nullif(trim(li.item_name),'') is not null and li.unit is null then 'Unit missing' end,
    case when nullif(trim(li.item_name),'') is not null and length(trim(coalesce(li.specification,''))) < 25 then 'Spec too thin' end,
    case when nullif(trim(li.item_name),'') is not null and li.air_freight is null then 'Air-freight answer missing' end,
    case when nullif(trim(li.item_name),'') is not null and (select count(*) from public.line_items d
          where d.request_id = li.request_id and lower(trim(d.item_name)) = lower(trim(li.item_name))) > 1
         then 'Duplicate item in this request' end,
    case when nullif(trim(li.item_name),'') is null and (li.qty is not null or nullif(trim(li.specification),'') is not null)
         then 'Item name missing' end
  ], null);
$$;

create or replace function public.unpriced_count(rid uuid) returns int
language sql stable set search_path = public as $$
  select count(*)::int from public.line_items li
  where li.request_id = rid and nullif(trim(li.item_name),'') is not null and li.est_unit_price_usd is null;
$$;

create or replace function public.guard_request_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare problems text[]; unpriced int;
begin
  if new.status is distinct from old.status then
    if not public.is_manager() and not (old.status = 'draft' and new.status = 'submitted') then
      raise exception 'Only a manager can move a request from % to %', old.status, new.status;
    end if;
    if new.status = 'submitted' then
      problems := public.request_issues(new.id);
      if cardinality(problems) > 0 then
        raise exception 'NOT READY - %', array_to_string(problems, ', ');
      end if;
      new.date_submitted := coalesce(new.date_submitted, current_date);
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

create or replace view public.request_summaries with (security_invoker = true) as
select r.*, p.full_name as owner_name, p.email as owner_email,
  (select count(*) from public.line_items li where li.request_id = r.id and nullif(trim(li.item_name),'') is not null) as line_count,
  (select coalesce(sum(li.qty * li.est_unit_price_usd), 0) from public.line_items li where li.request_id = r.id) as est_total_usd,
  (select bool_or(li.air_freight <> 'No') from public.line_items li where li.request_id = r.id) as has_air_restricted,
  public.request_issues(r.id) as issues,
  public.unpriced_count(r.id) as unpriced_count
from public.requests r join public.profiles p on p.id = r.owner_id;

revoke execute on function public.unpriced_count(uuid) from public, anon;
grant execute on function public.unpriced_count(uuid) to authenticated;
