-- Mirrors maavadao/marketplace-registry: every tool and agent listed there, kept in
-- sync by its GitHub Actions publish workflow on every merge to main (and weekly,
-- to refresh GitHub stats). Rows are written by that workflow's service role only;
-- everyone else reads. A listing disappearing from the registry removes its row.

create table public.marketplace_listings (
  kind text not null
    check (kind in ('tool', 'agent')),
  slug text not null
    check (slug ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  name text not null,
  summary text not null,
  description text,
  category text not null,
  tags text[] not null default '{}',
  links jsonb not null default '{}',
  license text,
  skill_level text
    check (skill_level is null or skill_level in ('beginner', 'intermediate', 'advanced')),
  -- {education, individuals, business}, each {price, amount?, currency?, period?, usage?}
  pricing jsonb not null,
  -- {runtime, audience, languages, data_collected?}; null for tools
  agent jsonb,
  maintainer jsonb,
  safety jsonb,
  added date,
  -- {stars, forks, language, pushed_at, archived, stars_gained, since}, refreshed weekly
  stats jsonb,
  updated_at timestamptz not null default now(),
  primary key (kind, slug)
);

comment on table public.marketplace_listings is 'AI agents and tools listed on maavaDao, synced from maavadao/marketplace-registry on every merge.';

alter table public.marketplace_listings enable row level security;

-- Public catalog: anyone can read. Only the registry's CI (service role, which
-- bypasses RLS) writes, so there are no insert/update/delete policies here.
create policy "Anyone can read marketplace listings"
  on public.marketplace_listings for select
  using (true);

create trigger marketplace_listings_touch_updated_at
  before update on public.marketplace_listings
  for each row execute function public.touch_updated_at();
