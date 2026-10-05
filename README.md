# mawaDao — Supabase

The database and auth setup for [mawaDao](https://mawadao.com): **a non-profit, community-owned marketplace for responsible AI agents, built to bring quality education to underserved children and orphans.**

The website lives in [mawadao/frontend](https://github.com/mawadao/frontend). This repo holds what Supabase needs: the schema as migrations, row-level security policies, and the config for the local development stack.

## What's here

| Path | What it is |
| --- | --- |
| `migrations/` | Every schema change, in order. The only way the database changes. |
| `config.toml` | The local stack: Google and GitHub sign-in on, email sign-up off, redirects to `localhost:3000`. |
| `.env.example` | Names of the OAuth secrets for the local stack. Copy to `.env`, which is ignored. |

### Tables

- **`profiles`**: one row per member, created at onboarding after their first Google or GitHub sign-in.
  - Columns: `username`, `country` (ISO 3166-1 alpha-2) and `role`.
  - Roles: student, developer, contributor, educator, organisation or funder. They must match `roles` in the frontend's `src/lib/profile.ts`.
  - Members can read and edit only their own row.

## Local development

You need Docker running. Run these from the folder that contains `supabase/`, so the CLI finds it.

```bash
npx supabase start      # starts Postgres, Auth and Studio, and applies migrations
npx supabase db reset   # wipe and rebuild from migrations (clean slate for testing)
npx supabase stop
```

`supabase start` prints the API URL and publishable key. Put them in the frontend's `.env.local`. Studio runs at http://127.0.0.1:54323.

**Sign-in locally** needs dev-only OAuth apps, separate from production ones:

1. Create a Google OAuth client (Web application) and a GitHub OAuth App ("mawaDao (dev)").
2. Set the callback URL of both to `http://127.0.0.1:54321/auth/v1/callback`.
3. Copy `.env.example` to `.env`, fill in the four values, and restart with `npx supabase stop && npx supabase start`.

## Production

Production is a separate hosted Supabase project. It only changes through migrations:

1. Write a new migration (`npx supabase migration new <name>`).
2. Test it locally with `npx supabase db reset`.
3. Push it:

   ```bash
   npx supabase link --project-ref <prod-ref>
   npx supabase db push
   ```

Don't edit tables by hand in the production dashboard.

The production project's auth settings are set in its dashboard, not from `config.toml`:

- **Site URL:** `https://mawadao.com`.
- **Redirect URL:** `https://mawadao.com/auth/callback`.
- **Providers:** Google and GitHub, using the production OAuth apps. Their callback is `https://<prod-ref>.supabase.co/auth/v1/callback`.
- **Email sign-up:** off.

## Licence

[Apache 2.0](LICENSE).
