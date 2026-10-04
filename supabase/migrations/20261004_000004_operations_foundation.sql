-- ReCity Operations foundation
-- Additive only: this migration does not alter citizen reports, their existing
-- submission function, or existing ReCity policies.

alter type public.recity_role add value if not exists 'collector';

create type public.collector_request_status as enum ('pending', 'approved', 'rejected');
create type public.dispatch_offer_status as enum ('offered', 'accepted', 'rejected', 'expired');
create type public.collection_task_status as enum ('assigned', 'on_the_way', 'reached', 'proof_submitted', 'verified', 'closed');

create table public.municipal_teams (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.collector_requests (
  id uuid primary key default gen_random_uuid(),
  applicant_id uuid not null references public.profiles(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 80),
  team_id uuid references public.municipal_teams(id) on delete set null,
  status public.collector_request_status not null default 'pending',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (applicant_id, status)
);

create table public.collector_locations (
  collector_id uuid primary key references public.profiles(id) on delete cascade,
  latitude numeric(9, 6) not null check (latitude between -90 and 90),
  longitude numeric(9, 6) not null check (longitude between -180 and 180),
  is_available boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.dispatch_offers (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints(id) on delete cascade,
  collector_id uuid not null references public.profiles(id) on delete cascade,
  distance_meters integer check (distance_meters >= 0),
  status public.dispatch_offer_status not null default 'offered',
  responded_at timestamptz,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  created_at timestamptz not null default now(),
  unique (complaint_id, collector_id)
);

create table public.collection_tasks (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null unique references public.complaints(id) on delete cascade,
  collector_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid references public.profiles(id) on delete set null,
  status public.collection_task_status not null default 'assigned',
  accepted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.collection_proofs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null unique references public.collection_tasks(id) on delete cascade,
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  photo_path text not null,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  submitted_at timestamptz not null default now(),
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz
);

create table public.collector_point_events (
  id uuid primary key default gen_random_uuid(),
  collector_id uuid not null references public.profiles(id) on delete cascade,
  complaint_id uuid references public.complaints(id) on delete set null,
  points_delta integer not null check (points_delta <> 0),
  reason text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index collector_requests_status_idx on public.collector_requests(status, created_at desc);
create index collector_locations_available_idx on public.collector_locations(is_available, updated_at desc) where is_available;
create index dispatch_offers_collector_idx on public.dispatch_offers(collector_id, status, created_at desc);
create index collection_tasks_collector_idx on public.collection_tasks(collector_id, status, updated_at desc);
create index collector_point_events_collector_idx on public.collector_point_events(collector_id, created_at desc);

create trigger collection_tasks_set_updated_at before update on public.collection_tasks
for each row execute function public.set_updated_at();

alter table public.municipal_teams enable row level security;
alter table public.collector_requests enable row level security;
alter table public.collector_locations enable row level security;
alter table public.dispatch_offers enable row level security;
alter table public.collection_tasks enable row level security;
alter table public.collection_proofs enable row level security;
alter table public.collector_point_events enable row level security;

create policy "operators manage municipal teams" on public.municipal_teams for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "applicants read their collector request" on public.collector_requests for select to authenticated
using ((select auth.uid()) = applicant_id);
create policy "operators manage collector requests" on public.collector_requests for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "collectors read their location" on public.collector_locations for select to authenticated
using ((select auth.uid()) = collector_id);
create policy "operators read collector locations" on public.collector_locations for select to authenticated
using ((select public.is_municipal_operator()));

create policy "collectors read their dispatch offers" on public.dispatch_offers for select to authenticated
using ((select auth.uid()) = collector_id);
create policy "operators manage dispatch offers" on public.dispatch_offers for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "collectors read their tasks" on public.collection_tasks for select to authenticated
using ((select auth.uid()) = collector_id);
create policy "operators manage collection tasks" on public.collection_tasks for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "collectors read their proofs" on public.collection_proofs for select to authenticated
using (exists (select 1 from public.collection_tasks t where t.id = task_id and t.collector_id = (select auth.uid())));
create policy "operators manage collection proofs" on public.collection_proofs for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "collectors read their point events" on public.collector_point_events for select to authenticated
using ((select auth.uid()) = collector_id);
create policy "operators manage collector point events" on public.collector_point_events for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create or replace function public.request_collector_role(p_display_name text)
returns public.collector_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.collector_requests;
begin
  if auth.uid() is null then
    raise exception 'Sign in is required';
  end if;

  insert into public.collector_requests (applicant_id, display_name)
  values (auth.uid(), nullif(trim(p_display_name), ''))
  returning * into request_row;

  return request_row;
end;
$$;

revoke all on function public.request_collector_role(text) from public;
grant execute on function public.request_collector_role(text) to authenticated;

create or replace function public.set_collector_availability(p_latitude numeric, p_longitude numeric, p_is_available boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'collector') then
    raise exception 'Collector approval is required';
  end if;

  insert into public.collector_locations (collector_id, latitude, longitude, is_available)
  values (auth.uid(), p_latitude, p_longitude, p_is_available)
  on conflict (collector_id) do update set
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    is_available = excluded.is_available,
    updated_at = now();
end;
$$;

revoke all on function public.set_collector_availability(numeric, numeric, boolean) from public;
grant execute on function public.set_collector_availability(numeric, numeric, boolean) to authenticated;
