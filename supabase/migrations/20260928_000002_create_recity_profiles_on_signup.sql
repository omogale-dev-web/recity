-- Recity Phase 2 — create a safe public profile for every Auth user.
-- This function runs inside the database; do not create profiles from the browser.

create or replace function public.handle_new_recity_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_recity_id text;
  requested_character text;
  requested_locale text;
  attempt integer := 0;
begin
  requested_character := lower(coalesce(new.raw_user_meta_data ->> 'eco_character', 'reuse_ranger'));
  requested_locale := lower(coalesce(new.raw_user_meta_data ->> 'locale', 'en'));

  loop
    attempt := attempt + 1;
    generated_recity_id := 'REC-' || upper(substr(md5(new.id::text || clock_timestamp()::text || attempt::text), 1, 6));

    begin
      insert into public.profiles (
        id,
        recity_id,
        display_name,
        eco_character,
        locale,
        role
      ) values (
        new.id,
        generated_recity_id,
        nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 80), ''),
        case requested_character
          when 'green_guardian' then 'green_guardian'
          when 'eco_explorer' then 'eco_explorer'
          when 'nature_keeper' then 'nature_keeper'
          when 'planet_protector' then 'planet_protector'
          when 'green_pioneer' then 'green_pioneer'
          else 'reuse_ranger'
        end,
        case requested_locale when 'mr' then 'mr' else 'en' end,
        'citizen'::public.recity_role
      );
      exit;
    exception when unique_violation then
      if attempt >= 5 then
        raise exception 'Could not generate a unique Recity ID';
      end if;
    end;
  end loop;

  return new;
end;
$$;

revoke all on function public.handle_new_recity_user() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_recity_user();

-- TODO: Create municipal_operator profiles only through a protected server-side
-- admin flow; never accept a role from browser user metadata.
