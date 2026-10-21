-- Community ideas at maavadao.com/vote: members post an idea for a project the
-- community could build, and vote for the ideas they want built next.
--
-- Ideas are public, copy the author's username and GitHub login at the time of
-- writing, are limited to 5 a day per member, and are hidden automatically once
-- three members report them. Members can't set an idea's status; an admin
-- changes it in the database (for example, when the DAO picks an idea up):
--   update public.project_ideas set status = 'planned' where id = …;
--
-- Votes are private rows (one per member per idea); the public sees totals
-- through project_ideas_ranked().

create table public.project_ideas (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  username text not null,
  github_login text,
  title text not null check (char_length(btrim(title)) between 5 and 120),
  body text not null check (char_length(btrim(body)) between 20 and 2000),
  status text not null default 'open' check (status in ('open', 'planned', 'building', 'built', 'declined')),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index project_ideas_created_at on public.project_ideas (created_at desc);

create table public.project_idea_votes (
  idea_id bigint not null references public.project_ideas (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (idea_id, user_id)
);

create table public.project_idea_reports (
  idea_id bigint not null references public.project_ideas (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reason text check (reason is null or char_length(reason) <= 200),
  created_at timestamptz not null default now(),
  primary key (idea_id, user_id)
);

comment on table public.project_ideas is 'Public ideas for projects the community could build; hidden after three reports.';
comment on table public.project_idea_votes is 'Members'' votes for project ideas, one per member per idea.';
comment on table public.project_idea_reports is 'Members'' reports of ideas; three hide an idea.';

-- New ideas: copy the author's handle, and limit how fast anyone can post.
-- Edits: only the title and body change, and the edit time is recorded.
create function public.prepare_project_idea() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.project_ideas
        where user_id = new.user_id and created_at > now() - interval '1 day') >= 5 then
      raise exception 'You''ve shared a lot of ideas today. Please wait a little before posting another.';
    end if;
    select p.username into new.username from public.profiles p where p.id = new.user_id;
    new.github_login := (
      select i.identity_data ->> 'user_name'
      from auth.identities i
      where i.user_id = new.user_id and i.provider = 'github'
      order by i.created_at
      limit 1
    );
    new.status := 'open';
    new.hidden := false;
    new.created_at := now();
    new.edited_at := null;
  else
    -- Updates made by another trigger (hiding a reported idea), or by an admin
    -- with no member session (setting the status), pass through as they are.
    if pg_trigger_depth() > 1 or (select auth.uid()) is null then
      return new;
    end if;
    new.user_id := old.user_id;
    new.username := old.username;
    new.github_login := old.github_login;
    new.status := old.status;
    new.hidden := old.hidden;
    new.created_at := old.created_at;
    new.edited_at := now();
  end if;
  new.title := btrim(new.title);
  new.body := btrim(new.body);
  return new;
end;
$$;

create trigger project_ideas_prepare
  before insert or update on public.project_ideas
  for each row execute function public.prepare_project_idea();

create function public.hide_reported_idea() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.project_idea_reports where idea_id = new.idea_id) >= 3 then
    update public.project_ideas set hidden = true where id = new.idea_id;
  end if;
  return new;
end;
$$;

create trigger project_idea_reports_hide
  after insert on public.project_idea_reports
  for each row execute function public.hide_reported_idea();

-- Visible ideas with their vote totals, most votes first (ties: newest first).
create function public.project_ideas_ranked()
  returns table (
    id bigint, user_id uuid, username text, github_login text, title text, body text,
    status text, created_at timestamptz, edited_at timestamptz, votes bigint
  )
  language sql stable security definer set search_path = '' as $$
  select i.id, i.user_id, i.username, i.github_login, i.title, i.body, i.status, i.created_at, i.edited_at,
    (select count(*) from public.project_idea_votes v where v.idea_id = i.id) as votes
  from public.project_ideas i
  where not i.hidden
  order by votes desc, i.created_at desc;
$$;

grant execute on function public.project_ideas_ranked() to anon, authenticated;

alter table public.project_ideas enable row level security;
alter table public.project_idea_votes enable row level security;
alter table public.project_idea_reports enable row level security;

create policy "Anyone can read visible ideas"
  on public.project_ideas for select
  using (not hidden);

create policy "Members post their own ideas"
  on public.project_ideas for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members edit their own ideas"
  on public.project_ideas for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members delete their own ideas"
  on public.project_ideas for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members manage their own votes"
  on public.project_idea_votes for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members report ideas"
  on public.project_idea_reports for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members see their own reports"
  on public.project_idea_reports for select to authenticated
  using ((select auth.uid()) = user_id);
