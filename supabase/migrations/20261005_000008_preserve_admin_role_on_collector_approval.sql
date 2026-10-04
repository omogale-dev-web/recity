-- An administrator may preview/approve collectors but is never downgraded
-- to collector when a collector request happens to use the same device.
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
    update public.profiles
    set role = case when role = 'admin' then 'admin'::public.recity_role else 'collector'::public.recity_role end
    where id = result.applicant_id;
  end if;
  return result;
end;
$$;
