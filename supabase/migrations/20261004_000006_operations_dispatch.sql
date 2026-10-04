-- Live collector dispatch. This is additive and leaves citizen reporting untouched.

create or replace function public.dispatch_nearby_collectors()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- No location means the report remains visible to the municipal dashboard,
  -- but cannot be offered automatically.
  if new.latitude is null or new.longitude is null then return new; end if;

  insert into public.dispatch_offers (complaint_id, collector_id, distance_meters)
  select new.id, l.collector_id,
    round(6371000 * acos(least(1.0, greatest(-1.0,
      cos(radians(new.latitude)) * cos(radians(l.latitude)) *
      cos(radians(l.longitude) - radians(new.longitude)) +
      sin(radians(new.latitude)) * sin(radians(l.latitude))
    ))))::integer
  from public.collector_locations l
  join public.profiles p on p.id = l.collector_id and p.role = 'collector'
  where l.is_available and l.updated_at > now() - interval '15 minutes'
  order by l.latitude <-> new.latitude, l.longitude <-> new.longitude
  limit 3
  on conflict (complaint_id, collector_id) do nothing;
  return new;
end;
$$;

drop trigger if exists complaints_dispatch_nearby_collectors on public.complaints;
create trigger complaints_dispatch_nearby_collectors
after insert on public.complaints
for each row execute function public.dispatch_nearby_collectors();

create or replace function public.respond_to_dispatch_offer(p_offer_id uuid, p_accept boolean)
returns public.collection_tasks
language plpgsql
security definer
set search_path = public
as $$
declare offer_row public.dispatch_offers; task_row public.collection_tasks;
begin
  select * into offer_row from public.dispatch_offers
  where id = p_offer_id and collector_id = auth.uid() and status = 'offered' and expires_at > now()
  for update;
  if offer_row.id is null then raise exception 'This offer is no longer available'; end if;
  if not p_accept then
    update public.dispatch_offers set status = 'rejected', responded_at = now() where id = offer_row.id;
    insert into public.collector_point_events (collector_id, complaint_id, points_delta, reason, created_by)
    values (auth.uid(), offer_row.complaint_id, -3, 'Rejected a nearby collection offer', auth.uid());
    return null;
  end if;
  insert into public.collection_tasks (complaint_id, collector_id, assigned_by)
  values (offer_row.complaint_id, auth.uid(), auth.uid())
  on conflict (complaint_id) do nothing
  returning * into task_row;
  if task_row.id is null then raise exception 'Another collector accepted this report first'; end if;
  update public.dispatch_offers set status = case when id = offer_row.id then 'accepted' else 'expired' end,
    responded_at = now() where complaint_id = offer_row.complaint_id and status = 'offered';
  update public.complaints set status = 'assigned', collected_by = auth.uid() where id = offer_row.complaint_id;
  return task_row;
end;
$$;

create or replace function public.submit_collection_proof(p_task_id uuid, p_photo_path text, p_latitude numeric default null, p_longitude numeric default null)
returns public.collection_tasks
language plpgsql
security definer
set search_path = public
as $$
declare task_row public.collection_tasks;
begin
  select * into task_row from public.collection_tasks where id = p_task_id and collector_id = auth.uid() for update;
  if task_row.id is null then raise exception 'Task not found'; end if;
  insert into public.collection_proofs (task_id, submitted_by, photo_path, latitude, longitude)
  values (p_task_id, auth.uid(), p_photo_path, p_latitude, p_longitude)
  on conflict (task_id) do update set photo_path = excluded.photo_path, latitude = excluded.latitude, longitude = excluded.longitude, submitted_at = now();
  update public.collection_tasks set status = 'proof_submitted' where id = p_task_id returning * into task_row;
  return task_row;
end;
$$;

create or replace function public.verify_collection_proof(p_task_id uuid, p_approved boolean)
returns public.collection_tasks
language plpgsql
security definer
set search_path = public
as $$
declare task_row public.collection_tasks;
begin
  if not public.is_municipal_operator() then raise exception 'Admin access required'; end if;
  select * into task_row from public.collection_tasks where id = p_task_id and status = 'proof_submitted' for update;
  if task_row.id is null then raise exception 'Proof is not ready for review'; end if;
  if p_approved then
    update public.collection_proofs set verified_by = auth.uid(), verified_at = now() where task_id = p_task_id;
    update public.collection_tasks set status = 'verified' where id = p_task_id returning * into task_row;
    update public.complaints set status = 'collected', collected_at = now() where id = task_row.complaint_id;
    insert into public.collector_point_events (collector_id, complaint_id, points_delta, reason, created_by)
    values (task_row.collector_id, task_row.complaint_id, 10, 'Verified cleanup proof', auth.uid());
  else
    update public.collection_tasks set status = 'reached' where id = p_task_id returning * into task_row;
  end if;
  return task_row;
end;
$$;

insert into storage.buckets (id, name, public) values ('collection-proofs', 'collection-proofs', false)
on conflict (id) do nothing;
create policy "collectors upload their proof photos" on storage.objects for insert to authenticated
with check (bucket_id = 'collection-proofs' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "collectors read their proof photos" on storage.objects for select to authenticated
using (bucket_id = 'collection-proofs' and (storage.foldername(name))[1] = (select auth.uid()::text));
create policy "operators read all proof photos" on storage.objects for select to authenticated
using (bucket_id = 'collection-proofs' and (select public.is_municipal_operator()));

revoke all on function public.respond_to_dispatch_offer(uuid, boolean) from public;
revoke all on function public.submit_collection_proof(uuid, text, numeric, numeric) from public;
revoke all on function public.verify_collection_proof(uuid, boolean) from public;
grant execute on function public.respond_to_dispatch_offer(uuid, boolean) to authenticated;
grant execute on function public.submit_collection_proof(uuid, text, numeric, numeric) to authenticated;
grant execute on function public.verify_collection_proof(uuid, boolean) to authenticated;
