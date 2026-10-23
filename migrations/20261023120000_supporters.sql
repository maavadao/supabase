-- Everyone is welcome, not only developers. Volunteers, students, teachers and anyone else who
-- wants to help join through maavadao.com/get-involved: they say how they'd like to help, and
-- can refer schools, orphanages and communities that maava could support.
--
-- Both tables are private: a member sees and changes only their own rows. The only public view
-- is community_wall(), on the home page: the username, country, role and ways to help of
-- supporters who chose to appear there (show_on_wall). The maavaDao team reads the rest in the
-- dashboard and moves a referral along by hand, for example:
--   update public.referrals set status = 'contacted' where id = …;

-- A new way to join.
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  -- Keep in sync with `roles` in src/lib/profile.ts.
  check (role in ('student', 'developer', 'contributor', 'educator', 'volunteer', 'organisation', 'funder'));

create table public.supporters (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  -- Keep in sync with `helpWays` in src/lib/supporters.ts.
  ways text[] not null check (
    cardinality(ways) between 1 and 7
    and ways <@ array['volunteer', 'refer', 'teach', 'spread', 'translate', 'fundraise', 'feedback']
  ),
  availability text check (availability is null or availability in ('month', 'week', 'more')),
  skills text check (skills is null or char_length(skills) <= 300),
  message text check (message is null or char_length(message) <= 1000),
  -- Appear on the community wall on maavadao.com (username, country, role and ways only).
  show_on_wall boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.referrals (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('school', 'orphanage', 'community')),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  place text not null check (char_length(btrim(place)) between 2 and 120),
  country char(2) not null check (country ~ '^[A-Z]{2}$'),
  -- How to reach them, shared only with their permission.
  contact text check (contact is null or char_length(contact) <= 200),
  contact_consent boolean not null default false,
  note text check (note is null or char_length(note) <= 1000),
  status text not null default 'new' check (status in ('new', 'contacted', 'supporting', 'closed')),
  created_at timestamptz not null default now(),
  check (contact is null or contact_consent)
);

create index referrals_user_id on public.referrals (user_id);

comment on table public.supporters is 'How a member would like to help, from maavadao.com/get-involved. Private to the member.';
comment on table public.referrals is 'Schools, orphanages and communities members refer to maava. Private to the member; status set by the team.';

create trigger supporters_touch_updated_at
  before update on public.supporters
  for each row execute function public.touch_updated_at();

-- New referrals start as 'new', and no one can send more than 10 a day.
create function public.prepare_referral() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.referrals
      where user_id = new.user_id and created_at > now() - interval '1 day') >= 10 then
    raise exception 'You''ve referred a lot today, thank you! Please add more tomorrow.';
  end if;
  new.status := 'new';
  new.created_at := now();
  new.name := btrim(new.name);
  new.place := btrim(new.place);
  return new;
end;
$$;

create trigger referrals_prepare
  before insert on public.referrals
  for each row execute function public.prepare_referral();

-- The community wall: the newest 48 supporters who chose to appear, and how many there are.
create function public.community_wall()
  returns table (username text, country text, role text, ways text[], joined timestamptz, total bigint)
  language sql stable security definer set search_path = '' as $$
  select p.username, p.country::text, p.role, s.ways, s.created_at, count(*) over ()
  from public.supporters s
  join public.profiles p on p.id = s.user_id
  where s.show_on_wall
  order by s.created_at desc
  limit 48;
$$;

grant execute on function public.community_wall() to anon, authenticated;

alter table public.supporters enable row level security;
alter table public.referrals enable row level security;

create policy "Members manage how they help"
  on public.supporters for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- No update policy: once sent, a referral is changed only by the team (members can delete it).
create policy "Members see their own referrals"
  on public.referrals for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members send referrals"
  on public.referrals for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members withdraw their own referrals"
  on public.referrals for delete to authenticated
  using ((select auth.uid()) = user_id);
