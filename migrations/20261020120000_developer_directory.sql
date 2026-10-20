-- Members who choose to appear on maavadao.com/developers. Joining is opt-in: a
-- row exists only while the member wants to be listed, and deleting it removes
-- them. Everything here is public, so profiles itself stays private.
--
-- The member writes only what they choose to share (display name, bio, website,
-- whether to show their country). Username, role, country and GitHub login are
-- copied in by a trigger from their profile and their GitHub sign-in, so nobody
-- can list themselves under someone else's GitHub account.

create table public.developer_directory (
  id uuid primary key references public.profiles (id) on delete cascade,
  username text not null,
  role text not null,
  -- Null unless show_country is true.
  country char(2),
  -- From the member's GitHub sign-in identity; null if they signed in with Google only.
  github_login text unique,
  display_name text check (display_name is null or char_length(display_name) between 1 and 80),
  bio text check (bio is null or char_length(bio) <= 280),
  website text check (website is null or (website ~ '^https?://\S+$' and char_length(website) <= 200)),
  show_country boolean not null default false,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.developer_directory is 'Opt-in public developer profiles shown on maavadao.com/developers.';

create function public.fill_developer_directory() returns trigger
  language plpgsql security definer set search_path = '' as $$
declare
  p public.profiles;
begin
  select * into p from public.profiles where id = new.id;
  if not found then
    raise exception 'Create your profile before joining the developer directory';
  end if;
  new.username := p.username;
  new.role := p.role;
  new.country := case when new.show_country then p.country end;
  new.github_login := (
    select i.identity_data ->> 'user_name'
    from auth.identities i
    where i.user_id = new.id and i.provider = 'github'
    order by i.created_at
    limit 1
  );
  return new;
end;
$$;

create trigger developer_directory_fill
  before insert or update on public.developer_directory
  for each row execute function public.fill_developer_directory();

create trigger developer_directory_touch_updated_at
  before update on public.developer_directory
  for each row execute function public.touch_updated_at();

-- Keep listed members' username and role current when they edit their profile.
create function public.sync_developer_directory() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  update public.developer_directory set username = new.username where id = new.id;
  return new;
end;
$$;

create trigger profiles_sync_developer_directory
  after update of username, role, country on public.profiles
  for each row execute function public.sync_developer_directory();

alter table public.developer_directory enable row level security;

create policy "Anyone can read the developer directory"
  on public.developer_directory for select
  using (true);

create policy "Members join the directory themselves"
  on public.developer_directory for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "Members edit their own directory entry"
  on public.developer_directory for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "Members leave the directory themselves"
  on public.developer_directory for delete to authenticated
  using ((select auth.uid()) = id);
