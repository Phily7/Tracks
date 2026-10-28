-- Fixes from the Supabase advisors after 0001.

-- Pin search_path on the remaining functions.
alter function public.line_issues(public.line_items) set search_path = public;
alter function public.request_issues(uuid) set search_path = public;
alter function public.touch_updated_at() set search_path = public;

-- Supabase grants EXECUTE to anon/authenticated by default. Only can_sign_in is needed before login.
revoke execute on function public.is_manager() from public, anon;
revoke execute on function public.can_edit_request(uuid) from public, anon;
revoke execute on function public.can_read_request(uuid) from public, anon;
revoke execute on function public.assign_req_number(uuid) from public, anon;

-- Trigger functions are never called over RPC.
revoke execute on function public.guard_request_status() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

-- Cover foreign keys.
create index if not exists allowlist_added_by_idx on public.allowlist (added_by);
create index if not exists bom_uploads_request_id_idx on public.bom_uploads (request_id);
create index if not exists line_items_bom_upload_id_idx on public.line_items (bom_upload_id);
create index if not exists requests_project_idx on public.requests (project);
