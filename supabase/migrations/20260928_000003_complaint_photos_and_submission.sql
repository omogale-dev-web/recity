-- Private evidence photos and a single, transaction-safe citizen submission RPC.
-- Run after the first two RECITY migrations.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('complaint-photos', 'complaint-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "citizens upload own complaint photos" on storage.objects;
drop policy if exists "citizens view own complaint photos" on storage.objects;
drop policy if exists "citizens delete own unsubmitted complaint photos" on storage.objects;

create policy "citizens upload own complaint photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'complaint-photos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "citizens view own complaint photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'complaint-photos'
  and owner_id = (select auth.uid()::text)
);

create policy "citizens delete own unsubmitted complaint photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'complaint-photos'
  and owner_id = (select auth.uid()::text)
);

create or replace function public.submit_complaint(
  p_waste_summary text,
  p_ai_summary text,
  p_hazard text,
  p_photo_path text,
  p_address text default null,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_items jsonb default '[]'::jsonb
)
returns public.complaints
language plpgsql
security definer
set search_path = public
as $$
declare
  v_complaint public.complaints;
  v_item jsonb;
  v_hazard public.hazard_level;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication is required.';
  end if;
  if coalesce(length(trim(p_waste_summary)), 0) = 0 then
    raise exception 'A waste summary is required.';
  end if;
  if p_hazard not in ('none', 'low', 'medium', 'high') then
    raise exception 'Invalid hazard level.';
  end if;
  if p_photo_path is not null and p_photo_path not like ((select auth.uid())::text || '/%') then
    raise exception 'Photo path does not belong to the signed-in user.';
  end if;

  v_hazard := p_hazard::public.hazard_level;
  insert into public.complaints (
    citizen_id, waste_summary, ai_summary, hazard, photo_path, address, latitude, longitude
  ) values (
    (select auth.uid()), left(trim(p_waste_summary), 500), nullif(left(trim(coalesce(p_ai_summary, '')), 2000), ''),
    v_hazard, p_photo_path, nullif(left(trim(coalesce(p_address, '')), 500), ''), p_latitude, p_longitude
  ) returning * into v_complaint;

  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into public.complaint_items (
      complaint_id, item_name, material, item_condition, reusable, recyclable, hazard, confidence, suggested_action
    ) values (
      v_complaint.id,
      left(coalesce(v_item->>'name', 'Unidentified item'), 200),
      nullif(left(coalesce(v_item->>'material', ''), 200), ''),
      nullif(left(coalesce(v_item->>'condition', ''), 200), ''),
      coalesce((v_item->>'reusable')::boolean, false),
      coalesce((v_item->>'recyclable')::boolean, false),
      (case when lower(coalesce(v_item->>'hazard', 'none')) in ('none', 'low', 'medium', 'high')
        then lower(coalesce(v_item->>'hazard', 'none')) else 'none' end)::public.hazard_level,
      least(100, greatest(0, coalesce((v_item->>'confidence')::numeric, 0))),
      nullif(left(coalesce(v_item->>'suggestedAction', ''), 500), '')
    );
  end loop;

  update public.profiles
  set reports_submitted = reports_submitted + 1,
      eco_points = eco_points + 10
  where id = (select auth.uid());

  insert into public.eco_events (profile_id, complaint_id, event_type, points_delta, note)
  values ((select auth.uid()), v_complaint.id, 'report_submitted', 10, 'Complaint submitted');

  return v_complaint;
end;
$$;

revoke all on function public.submit_complaint(text, text, text, text, text, numeric, numeric, jsonb) from public;
grant execute on function public.submit_complaint(text, text, text, text, text, numeric, numeric, jsonb) to authenticated;
