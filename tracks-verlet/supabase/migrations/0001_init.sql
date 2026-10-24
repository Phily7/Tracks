-- Tracks Verlet: initial schema
-- Mirrors Verlet_Procurement_Request_TemplateV1.xlsx (Request tab + Lists tab).
-- Manager = Supabase Auth email+password. Engineers = Supabase Auth email OTP (passwordless),
-- limited to emails/domains on public.allowlist.

-- Lists tab -------------------------------------------------------------
create table public.projects (
  name text primary key,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.projects (name) values
  ('AMR'),('EGO'),('Facilities / workshop'),('IT & software'),
  ('General overhead'),('UMI'),('Gello'),('NIST');

create type public.unit as enum ('pcs','m','kg','set','pair','roll','box','litre','sheet','service');
create type public.urgency as enum ('Normal','Blocking within 2 weeks','Blocking work right now');
create type public.air_freight as enum ('No','Yes','Not sure - please check');
create type public.user_role as enum ('manager','engineer');
create type public.request_status as enum ('draft','submitted','approved','rejected','ordered');

-- People ----------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text,
  phone text,
  role public.user_role not null default 'engineer',
  created_at timestamptz not null default now()
);

-- Who may sign in passwordlessly: a full address ('ana@verlet.co') or a domain ('@verlet.co').
create table public.allowlist (
  entry text primary key check (entry = lower(entry) and entry like '%@%'),
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Request header (Request tab C4:C11) ------------------------------------
create sequence public.req_number_seq;

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  req_number text unique,                         -- assigned by procurement
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text,                                     -- C4
  project text references public.projects(name) on update cascade, -- C7
  date_submitted date,                            -- C8
  needed_by date,                                 -- C9
  urgency public.urgency,                         -- C10
  justification text,                             -- C11 "Why this is needed"
  status public.request_status not null default 'draft',
  manager_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Uploaded BOM files (KiCad / Fusion 360 CSV) ----------------------------
create table public.bom_uploads (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  filename text not null,
  source text not null,                           -- 'kicad' | 'fusion360' | 'generic'
  headers text[] not null default '{}',
  raw_row_count int not null default 0,
  item_count int not null default 0,
  created_at timestamptz not null default now()
);

-- Line items (Request tab rows 19-58) ------------------------------------
create table public.line_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  bom_upload_id uuid references public.bom_uploads(id) on delete set null,
  position int not null default 0,
  item_name text,                                 -- B
  qty numeric,                                    -- C
  unit public.unit,                               -- D
  specification text,                             -- E
  datasheet_url text,                             -- F
  air_freight public.air_freight,                 -- G
  est_unit_price_usd numeric,                     -- H
  suggested_vendor text,                          -- J
  notes text,                                     -- K
  source_row jsonb,                               -- original BOM row, for traceability
  auto_fields text[] not null default '{}',       -- fields the system filled itself
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.line_items (request_id, position);
create index on public.requests (owner_id);

-- Template rules in SQL (same as Request!L19 / N2 / C13) -----------------
create function public.line_issues(li public.line_items) returns text[]
language sql stable as $$
  select array_remove(array[
    case when nullif(trim(li.item_name),'') is not null and li.qty is null then 'Qty missing' end,
    case when nullif(trim(li.item_name),'') is not null and li.qty <= 0 then 'Qty must be above zero' end,
    case when nullif(trim(li.item_name),'') is not null and li.unit is null then 'Unit missing' end,
    case when nullif(trim(li.item_name),'') is not null and length(trim(coalesce(li.specification,''))) < 25 then 'Spec too thin' end,
    case when nullif(trim(li.item_name),'') is not null and li.air_freight is null then 'Air-freight answer missing' end,
    case when nullif(trim(li.item_name),'') is not null and li.est_unit_price_usd is null then 'Est. price missing' end,
    case when nullif(trim(li.item_name),'') is not null and (select count(*) from public.line_items d
          where d.request_id = li.request_id and lower(trim(d.item_name)) = lower(trim(li.item_name))) > 1
         then 'Duplicate item in this request' end,
    case when nullif(trim(li.item_name),'') is null and (li.qty is not null or nullif(trim(li.specification),'') is not null)
         then 'Item name missing' end
  ], null);
$$;

create function public.request_issues(rid uuid) returns text[]
language sql stable as $$
  select array_remove(array[
    case when nullif(trim(p.full_name),'') is null then 'your name' end,
    case when nullif(trim(p.email),'') is null then 'your email' end,
    case when r.project is null then 'project' end,
    case when r.needed_by is null then 'needed-by date' end,
    case when length(trim(coalesce(r.justification,''))) < 15 then 'why this is needed' end,
    case when not exists (select 1 from public.line_items li where li.request_id = r.id
                          and nullif(trim(li.item_name),'') is not null) then 'no line items' end,
    case when exists (select 1 from public.line_items li where li.request_id = r.id
                      and cardinality(public.line_issues(li)) > 0) then 'line items need attention' end
  ], null)
  from public.requests r join public.profiles p on p.id = r.owner_id
  where r.id = rid;
$$;

create view public.request_summaries with (security_invoker = true) as
select r.*, p.full_name as owner_name, p.email as owner_email,
  (select count(*) from public.line_items li where li.request_id = r.id and nullif(trim(li.item_name),'') is not null) as line_count,
  (select coalesce(sum(li.qty * li.est_unit_price_usd), 0) from public.line_items li where li.request_id = r.id) as est_total_usd,
  (select bool_or(li.air_freight <> 'No') from public.line_items li where li.request_id = r.id) as has_air_restricted,
  public.request_issues(r.id) as issues
from public.requests r join public.profiles p on p.id = r.owner_id;

-- Helpers -----------------------------------------------------------------
create function public.is_manager() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'manager');
$$;

-- Called before sending a code, so strangers don't get accounts.
create function public.can_sign_in(addr text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.allowlist a
                 where a.entry = lower(trim(addr))
                    or a.entry = '@' || split_part(lower(trim(addr)), '@', 2))
      or exists (select 1 from public.profiles p where p.email = lower(trim(addr)));
$$;
grant execute on function public.can_sign_in(text) to anon, authenticated;

create function public.assign_req_number(rid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if not public.is_manager() then raise exception 'Only managers assign REQ numbers'; end if;
  select req_number into n from public.requests where id = rid;
  if n is not null then return n; end if;
  n := 'REQ-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.req_number_seq')::text, 4, '0');
  update public.requests set req_number = n where id = rid;
  return n;
end $$;

-- Triggers ----------------------------------------------------------------
create function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger requests_touch before update on public.requests for each row execute function public.touch_updated_at();
create trigger line_items_touch before update on public.line_items for each row execute function public.touch_updated_at();

-- Engineers move draft -> submitted only, and only when the request is READY TO SEND.
create function public.guard_request_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare problems text[];
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
  end if;
  if not public.is_manager() and (new.req_number is distinct from old.req_number or new.manager_note is distinct from old.manager_note) then
    raise exception 'Only a manager can set the REQ number or manager note';
  end if;
  return new;
end $$;
create trigger requests_guard before update on public.requests for each row execute function public.guard_request_status();

-- New auth user -> profile. Managers are created with app_metadata.role = 'manager'
-- (scripts/create-manager.mjs); everyone else must be on the allowlist.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.user_role := coalesce((new.raw_app_meta_data->>'role')::public.user_role, 'engineer');
begin
  if r = 'engineer' and not exists (
       select 1 from public.allowlist a
       where a.entry = lower(new.email) or a.entry = '@' || split_part(lower(new.email), '@', 2)) then
    raise exception 'This email is not on the Tracks Verlet allowlist';
  end if;
  insert into public.profiles (id, email, full_name, role)
  values (new.id, lower(new.email), new.raw_user_meta_data->>'full_name', r);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS ---------------------------------------------------------------------
alter table public.projects enable row level security;
alter table public.profiles enable row level security;
alter table public.allowlist enable row level security;
alter table public.requests enable row level security;
alter table public.bom_uploads enable row level security;
alter table public.line_items enable row level security;

create policy projects_read on public.projects for select to authenticated using (true);
create policy projects_manage on public.projects for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

create policy profiles_read on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_manager());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_manager()) with check (id = auth.uid() or public.is_manager());
-- Engineers may edit their name/phone but never their role.
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

create policy allowlist_manage on public.allowlist for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

create policy requests_read on public.requests for select to authenticated
  using (owner_id = auth.uid() or public.is_manager());
create policy requests_insert on public.requests for insert to authenticated
  with check (owner_id = auth.uid() and status = 'draft');
create policy requests_update on public.requests for update to authenticated
  using (public.is_manager() or (owner_id = auth.uid() and status = 'draft'))
  with check (public.is_manager() or owner_id = auth.uid());
create policy requests_delete on public.requests for delete to authenticated
  using (public.is_manager() or (owner_id = auth.uid() and status = 'draft'));

-- Children are readable with the parent; writable only while the parent is a draft (managers always).
create function public.can_edit_request(rid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_manager() or exists (
    select 1 from public.requests r where r.id = rid and r.owner_id = auth.uid() and r.status = 'draft');
$$;
create function public.can_read_request(rid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_manager() or exists (select 1 from public.requests r where r.id = rid and r.owner_id = auth.uid());
$$;

create policy bom_uploads_read on public.bom_uploads for select to authenticated using (public.can_read_request(request_id));
create policy bom_uploads_write on public.bom_uploads for insert to authenticated with check (public.can_edit_request(request_id));
create policy bom_uploads_delete on public.bom_uploads for delete to authenticated using (public.can_edit_request(request_id));

create policy line_items_read on public.line_items for select to authenticated using (public.can_read_request(request_id));
create policy line_items_insert on public.line_items for insert to authenticated with check (public.can_edit_request(request_id));
create policy line_items_update on public.line_items for update to authenticated
  using (public.can_edit_request(request_id)) with check (public.can_edit_request(request_id));
create policy line_items_delete on public.line_items for delete to authenticated using (public.can_edit_request(request_id));
