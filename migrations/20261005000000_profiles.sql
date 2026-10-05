-- One profile per member, created during onboarding after their first sign-in
-- with Google or GitHub. Supabase Auth owns identity; this table owns the
-- public handle, the member's country (used for local and country-level
-- governance) and how they are joining.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique
    check (username ~ '^[a-z0-9_]{3,20}$'),
  country char(2) not null
    check (country ~ '^[A-Z]{2}$'),
  -- Keep in sync with `roles` in src/lib/profile.ts.
  role text not null
    check (role in ('student', 'developer', 'contributor', 'educator', 'organisation', 'funder')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Member profile chosen at onboarding: username, ISO 3166-1 alpha-2 country and role.';

alter table public.profiles enable row level security;

-- Members can read and edit only their own profile for now.
create policy "Members read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Members create their own profile"
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "Members update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create function public.touch_updated_at() returns trigger
  language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();
