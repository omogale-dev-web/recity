-- Operations access controls. The initial code hash is inserted separately in
-- Supabase SQL Editor so no access code is ever committed to this repository.

create table public.operations_admin_codes (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,
  code_hash text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.operations_admin_codes enable row level security;

create or replace function public.claim_operations_admin(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  if not exists (
    select 1 from public.operations_admin_codes
    where is_active and code_hash = crypt(p_code, code_hash)
  ) then
    raise exception 'Invalid access code';
  end if;
  update public.profiles set role = 'admin' where id = auth.uid();
  return true;
end;
$$;

create or replace function public.review_collector_request(p_request_id uuid, p_approved boolean)
returns public.collector_requests
language plpgsql
security definer
set search_path = public
as $$
declare result public.collector_requests;
begin
  if not public.is_municipal_operator() then raise exception 'Admin access required'; end if;
  update public.collector_requests
  set status = (case when p_approved then 'approved' else 'rejected' end)::public.collector_request_status,
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_request_id and status = 'pending'
  returning * into result;
  if result.id is null then raise exception 'Request is no longer pending'; end if;
  if p_approved then
    update public.profiles set role = 'collector' where id = result.applicant_id;
  end if;
  return result;
end;
$$;

revoke all on function public.claim_operations_admin(text) from public;
revoke all on function public.review_collector_request(uuid, boolean) from public;
grant execute on function public.claim_operations_admin(text) to authenticated;
grant execute on function public.review_collector_request(uuid, boolean) to authenticated;
