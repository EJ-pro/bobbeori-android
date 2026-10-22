-- Bobbeori user foundation and shared database helpers.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgtap with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  locale text not null default 'ko-KR',
  timezone text not null default 'Asia/Seoul',
  is_anonymous_snapshot boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(display_name) between 1 and 50
  ),
  constraint profiles_locale_not_blank check (btrim(locale) <> ''),
  constraint profiles_timezone_not_blank check (btrim(timezone) <> '')
);

create table public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tts_enabled boolean not null default true,
  confirm_voice_before_send boolean not null default false,
  analytics_consent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger user_preferences_set_updated_at
before update on public.user_preferences
for each row execute function private.set_updated_at();

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (
    id,
    display_name,
    is_anonymous_snapshot
  )
  values (
    new.id,
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    coalesce(new.is_anonymous, false)
  );

  insert into public.user_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

alter table public.profiles enable row level security;
alter table public.user_preferences enable row level security;

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.user_preferences from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (display_name, locale, timezone) on table public.profiles to authenticated;
grant select on table public.user_preferences to authenticated;
grant update (
  tts_enabled,
  confirm_voice_before_send,
  analytics_consent
) on table public.user_preferences to authenticated;
grant all on table public.profiles to service_role;
grant all on table public.user_preferences to service_role;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

create policy profiles_update_own
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy user_preferences_select_own
on public.user_preferences
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy user_preferences_update_own
on public.user_preferences
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

comment on table public.profiles is
  'Application profile keyed by Supabase Auth user ID.';
comment on table public.user_preferences is
  'Account-level preferences; device-only preferences remain in Android DataStore.';
