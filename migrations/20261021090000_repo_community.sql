-- Community activity on the open-source AI repos at maavadao.com/repos: star
-- ratings, a personal list ("using", "want to try", "used before") and comments.
-- Repos live in maavadao/open-source-ai-repos, not in this database, so rows
-- refer to them by slug. Only members with a profile take part.
--
-- Ratings and lists are private rows; the public sees totals through
-- repo_summary(). Comments are public, copy the author's username and GitHub
-- login at the time of writing, are limited to 10 an hour per member, and are
-- hidden automatically once three members report them.

create table public.repo_ratings (
  repo_slug text not null check (repo_slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  user_id uuid not null references public.profiles (id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (repo_slug, user_id)
);

create table public.repo_lists (
  repo_slug text not null check (repo_slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null check (status in ('using', 'want', 'used')),
  updated_at timestamptz not null default now(),
  primary key (repo_slug, user_id)
);

create table public.repo_comments (
  id bigint generated always as identity primary key,
  repo_slug text not null check (repo_slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  user_id uuid not null references public.profiles (id) on delete cascade,
  username text not null,
  github_login text,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index repo_comments_repo_slug_created_at on public.repo_comments (repo_slug, created_at desc);

create table public.repo_comment_reports (
  comment_id bigint not null references public.repo_comments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reason text check (reason is null or char_length(reason) <= 200),
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

comment on table public.repo_ratings is 'Members'' 1–5 star ratings of open-source AI repos (by slug).';
comment on table public.repo_lists is 'Members'' personal repo lists: using, want to try, used before.';
comment on table public.repo_comments is 'Public comments on open-source AI repos; hidden after three reports.';
comment on table public.repo_comment_reports is 'Members'' reports of comments; three hide a comment.';

create trigger repo_ratings_touch_updated_at
  before update on public.repo_ratings
  for each row execute function public.touch_updated_at();

create trigger repo_lists_touch_updated_at
  before update on public.repo_lists
  for each row execute function public.touch_updated_at();

-- New comments: copy the author's handle, and limit how fast anyone can post.
-- Edits: only the body changes, and the edit time is recorded.
create function public.prepare_repo_comment() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.repo_comments
        where user_id = new.user_id and created_at > now() - interval '1 hour') >= 10 then
      raise exception 'You''ve posted a lot in the last hour. Please wait a little before commenting again.';
    end if;
    select p.username into new.username from public.profiles p where p.id = new.user_id;
    new.github_login := (
      select i.identity_data ->> 'user_name'
      from auth.identities i
      where i.user_id = new.user_id and i.provider = 'github'
      order by i.created_at
      limit 1
    );
    new.hidden := false;
    new.created_at := now();
    new.edited_at := null;
  else
    -- Updates made by another trigger (hiding a reported comment) pass through as they are.
    if pg_trigger_depth() > 1 then
      return new;
    end if;
    new.repo_slug := old.repo_slug;
    new.user_id := old.user_id;
    new.username := old.username;
    new.github_login := old.github_login;
    new.hidden := old.hidden;
    new.created_at := old.created_at;
    new.edited_at := now();
  end if;
  new.body := btrim(new.body);
  return new;
end;
$$;

create trigger repo_comments_prepare
  before insert or update on public.repo_comments
  for each row execute function public.prepare_repo_comment();

create function public.hide_reported_comment() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.repo_comment_reports where comment_id = new.comment_id) >= 3 then
    update public.repo_comments set hidden = true where id = new.comment_id;
  end if;
  return new;
end;
$$;

create trigger repo_comment_reports_hide
  after insert on public.repo_comment_reports
  for each row execute function public.hide_reported_comment();

-- Public totals for one repo.
create function public.repo_summary(slug text)
  returns table (rating numeric, ratings bigint, using_count bigint, want_count bigint, used_count bigint, comments bigint)
  language sql stable security definer set search_path = '' as $$
  select
    (select round(avg(score)::numeric, 1) from public.repo_ratings where repo_slug = slug),
    (select count(*) from public.repo_ratings where repo_slug = slug),
    (select count(*) from public.repo_lists where repo_slug = slug and status = 'using'),
    (select count(*) from public.repo_lists where repo_slug = slug and status = 'want'),
    (select count(*) from public.repo_lists where repo_slug = slug and status = 'used'),
    (select count(*) from public.repo_comments where repo_slug = slug and not hidden);
$$;

grant execute on function public.repo_summary(text) to anon, authenticated;

alter table public.repo_ratings enable row level security;
alter table public.repo_lists enable row level security;
alter table public.repo_comments enable row level security;
alter table public.repo_comment_reports enable row level security;

create policy "Members manage their own ratings"
  on public.repo_ratings for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members manage their own lists"
  on public.repo_lists for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Anyone can read visible comments"
  on public.repo_comments for select
  using (not hidden);

create policy "Members post their own comments"
  on public.repo_comments for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members edit their own comments"
  on public.repo_comments for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members delete their own comments"
  on public.repo_comments for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members report comments"
  on public.repo_comment_reports for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members see their own reports"
  on public.repo_comment_reports for select to authenticated
  using ((select auth.uid()) = user_id);
