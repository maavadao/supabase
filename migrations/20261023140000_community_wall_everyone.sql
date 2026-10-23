-- The community wall on maavadao.com lists everyone who has joined, not only supporters who
-- filled in the get-involved form: developers and contributors, students, educators, volunteers
-- and partners, however they signed in (Google, GitHub or email).
--
-- The choice to appear moves from supporters to profiles, so it covers every member. It's on by
-- default; members turn it off in onboarding or on the get-involved form. The wall shows only
-- the username, role, country, ways to help, GitHub login (for an avatar, when they signed in
-- with GitHub) and when they joined; never an email address or name.

alter table public.profiles add column show_on_wall boolean not null default true;

comment on column public.profiles.show_on_wall is 'Appear on the community wall on maavadao.com (username, role, country, GitHub avatar).';

update public.profiles p set show_on_wall = s.show_on_wall
from public.supporters s
where s.user_id = p.id;

drop function public.community_wall();
alter table public.supporters drop column show_on_wall;

-- The newest 100 members who chose to appear, and how many there are in all.
create function public.community_wall()
  returns table (
    username text, country text, role text, ways text[], github_login text, joined timestamptz, total bigint
  )
  language sql stable security definer set search_path = '' as $$
  select
    p.username,
    p.country::text,
    p.role,
    coalesce(s.ways, '{}'),
    (
      select i.identity_data ->> 'user_name'
      from auth.identities i
      where i.user_id = p.id and i.provider = 'github'
      order by i.created_at
      limit 1
    ),
    p.created_at,
    count(*) over ()
  from public.profiles p
  left join public.supporters s on s.user_id = p.id
  where p.show_on_wall
  order by p.created_at desc
  limit 100;
$$;

grant execute on function public.community_wall() to anon, authenticated;
