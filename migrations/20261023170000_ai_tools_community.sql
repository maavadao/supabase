-- Community activity on the AI tools directory at maavadao.com/ai-tools: star ratings (the
-- trust score) and suggestions for tools to add. Tools live in maavadao/ai-tools-directory,
-- not in this database, so rows refer to them by slug. Only members with a profile take part.
--
-- Ratings are private rows; the public sees the average and count through tool_summary() and
-- tool_ratings_all(). Suggestions are private to the member who sent them, 5 a day, and the
-- team reads them in SQL.

create table public.tool_ratings (
  tool_slug text not null check (tool_slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  user_id uuid not null references public.profiles (id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tool_slug, user_id)
);

create table public.tool_suggestions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  website text not null check (website ~ '^https://\S+$' and char_length(website) <= 300),
  note text check (note is null or char_length(note) <= 500),
  status text not null default 'new' check (status in ('new', 'listed', 'declined')),
  created_at timestamptz not null default now()
);

create index tool_suggestions_user_created on public.tool_suggestions (user_id, created_at desc);

comment on table public.tool_ratings is 'Members'' 1–5 star ratings of AI tools (by slug): the directory''s trust score.';
comment on table public.tool_suggestions is 'Tools members suggest adding. Private to the member; the team sets status in SQL.';

create trigger tool_ratings_touch_updated_at
  before update on public.tool_ratings
  for each row execute function public.touch_updated_at();

-- Five suggestions a day per member; members can't set the status.
create function public.prepare_tool_suggestion() returns trigger
  language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.tool_suggestions
      where user_id = new.user_id and created_at > now() - interval '1 day') >= 5 then
    raise exception 'You''ve suggested a lot of tools today. Please try again tomorrow.';
  end if;
  new.status := 'new';
  new.created_at := now();
  return new;
end;
$$;

create trigger tool_suggestions_prepare
  before insert on public.tool_suggestions
  for each row execute function public.prepare_tool_suggestion();

-- Public totals for one tool.
create function public.tool_summary(slug text)
  returns table (rating numeric, ratings bigint)
  language sql stable security definer set search_path = '' as $$
  select round(avg(score)::numeric, 1), count(*) from public.tool_ratings where tool_slug = slug;
$$;

-- Public totals for every rated tool, for sorting and showing stars on the list.
create function public.tool_ratings_all()
  returns table (tool_slug text, rating numeric, ratings bigint)
  language sql stable security definer set search_path = '' as $$
  select r.tool_slug, round(avg(r.score)::numeric, 1), count(*)
  from public.tool_ratings r
  group by r.tool_slug;
$$;

grant execute on function public.tool_summary(text) to anon, authenticated;
grant execute on function public.tool_ratings_all() to anon, authenticated;

alter table public.tool_ratings enable row level security;
alter table public.tool_suggestions enable row level security;

create policy "Members manage their own tool ratings"
  on public.tool_ratings for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Members send their own tool suggestions"
  on public.tool_suggestions for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members see their own tool suggestions"
  on public.tool_suggestions for select to authenticated
  using ((select auth.uid()) = user_id);
