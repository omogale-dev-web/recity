-- Recity Phase 2 — initial database schema
-- Run this migration in the Supabase SQL Editor or through the Supabase CLI.
-- Never place service_role credentials in the web app.

create extension if not exists pgcrypto;

create type public.recity_role as enum ('citizen', 'municipal_operator', 'admin');
create type public.complaint_status as enum ('pending', 'under_review', 'assigned', 'collected');
create type public.hazard_level as enum ('none', 'low', 'medium', 'high');
create type public.eco_event_type as enum ('report_submitted', 'collection_completed', 'item_reused', 'manual_adjustment');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  recity_id text not null unique check (recity_id ~ '^REC-[A-Z0-9]{6}$'),
  display_name text,
  eco_character text not null default 'reuse_ranger'
    check (eco_character in ('reuse_ranger', 'green_guardian', 'eco_explorer', 'nature_keeper', 'planet_protector', 'green_pioneer')),
  role public.recity_role not null default 'citizen',
  level integer not null default 1 check (level >= 1),
  eco_points integer not null default 0 check (eco_points >= 0),
  items_reused integer not null default 0 check (items_reused >= 0),
  reports_submitted integer not null default 0 check (reports_submitted >= 0),
  collections_completed integer not null default 0 check (collections_completed >= 0),
  estimated_waste_diverted_kg numeric(10, 2) not null default 0 check (estimated_waste_diverted_kg >= 0),
  locale text not null default 'en' check (locale in ('en', 'mr')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.complaints (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique default ('RC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5))),
  citizen_id uuid not null references public.profiles(id) on delete restrict,
  status public.complaint_status not null default 'pending',
  hazard public.hazard_level not null default 'low',
  waste_summary text not null,
  ai_summary text,
  waste_type text,
  photo_path text,
  address text,
  latitude numeric(9, 6),
  longitude numeric(9, 6),
  reported_at timestamptz not null default now(),
  collected_at timestamptz,
  collected_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_coordinates check (
    (latitude is null and longitude is null) or
    (latitude between -90 and 90 and longitude between -180 and 180)
  )
);

create table public.complaint_items (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null references public.complaints(id) on delete cascade,
  item_name text not null,
  material text,
  item_condition text,
  reusable boolean not null default false,
  recyclable boolean not null default false,
  hazard public.hazard_level not null default 'none',
  confidence numeric(5, 2) check (confidence between 0 and 100),
  suggested_action text,
  created_at timestamptz not null default now()
);

create table public.municipal_assignments (
  id uuid primary key default gen_random_uuid(),
  complaint_id uuid not null unique references public.complaints(id) on delete cascade,
  operator_id uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  notes text
);

create table public.eco_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  complaint_id uuid references public.complaints(id) on delete set null,
  event_type public.eco_event_type not null,
  points_delta integer not null,
  note text,
  created_at timestamptz not null default now()
);

create index complaints_citizen_id_idx on public.complaints(citizen_id);
create index complaints_status_reported_at_idx on public.complaints(status, reported_at desc);
create index complaints_hazard_idx on public.complaints(hazard) where hazard in ('medium', 'high');
create index complaint_items_complaint_id_idx on public.complaint_items(complaint_id);
create index eco_events_profile_id_created_at_idx on public.eco_events(profile_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

create trigger complaints_set_updated_at before update on public.complaints
for each row execute function public.set_updated_at();

-- This helper is intentionally SECURITY DEFINER: operator membership must be
-- checked without exposing the entire profiles table through an RLS subquery.
create or replace function public.is_municipal_operator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('municipal_operator', 'admin')
  );
$$;

revoke all on function public.is_municipal_operator() from public;
grant execute on function public.is_municipal_operator() to authenticated;

alter table public.profiles enable row level security;
alter table public.complaints enable row level security;
alter table public.complaint_items enable row level security;
alter table public.municipal_assignments enable row level security;
alter table public.eco_events enable row level security;

-- Citizens see and edit only their own basic profile. Role and reward changes
-- remain server-side in a later secure function.
create policy "citizens read their profile"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "citizens update their profile"
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id and role = 'citizen');

create policy "operators read profiles"
on public.profiles for select to authenticated
using ((select public.is_municipal_operator()));

create policy "citizens read their complaints"
on public.complaints for select to authenticated
using ((select auth.uid()) = citizen_id);

create policy "citizens create their complaints"
on public.complaints for insert to authenticated
with check ((select auth.uid()) = citizen_id);

create policy "operators manage complaints"
on public.complaints for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "citizens read items for their complaints"
on public.complaint_items for select to authenticated
using (exists (
  select 1 from public.complaints c
  where c.id = complaint_id and c.citizen_id = (select auth.uid())
));

create policy "citizens add items to their complaints"
on public.complaint_items for insert to authenticated
with check (exists (
  select 1 from public.complaints c
  where c.id = complaint_id and c.citizen_id = (select auth.uid())
));

create policy "operators manage complaint items"
on public.complaint_items for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "operators manage assignments"
on public.municipal_assignments for all to authenticated
using ((select public.is_municipal_operator()))
with check ((select public.is_municipal_operator()));

create policy "citizens read their own eco events"
on public.eco_events for select to authenticated
using ((select auth.uid()) = profile_id);

create policy "operators read eco events"
on public.eco_events for select to authenticated
using ((select public.is_municipal_operator()));

grant select on public.profiles to authenticated;
grant update (display_name, eco_character, locale) on public.profiles to authenticated;
grant select, insert on public.complaints to authenticated;
grant select, insert on public.complaint_items to authenticated;
grant select on public.eco_events to authenticated;
grant select, insert, update, delete on public.municipal_assignments to authenticated;

-- TODO: Add an auth.users trigger in Step 3 to generate a Recity ID and profile.
-- TODO: Add an Edge Function / server endpoint for municipal status changes and points.
