# Deploying to production

Goal: the app live on the internet so you can run it in parallel with the
Google Sheet. Three pieces: a cloud Supabase project, static hosting, and the
scheduled jobs (already in `.github/workflows/`).

## 1. Supabase cloud project

1. Create a project at https://supabase.com/dashboard (any name; pick the
   closest region, e.g. `sa-east-1`).
2. From the project settings → **Data API** and **API keys**, copy:
   - Project URL: `https://<ref>.supabase.co`
   - Publishable key (`sb_publishable_...`)
   - The database password you set at creation (needed for the backup secret).
3. Link and push the schema:

   ```bash
   pnpm supabase link --project-ref <ref>
   pnpm supabase db push
   ```

   `db push` applies every migration in `supabase/migrations/`. The pgTAP
   files under `supabase/tests/` never run against prod. `seed.sql` does not
   run on `db push` (it only applies to local `db reset`).

4. Auth URL config — in the dashboard: **Authentication → URL Configuration**:
   - Site URL: your prod domain (e.g. `https://finance.example.com`)
   - Redirect URLs: add `https://<your-domain>/**` — the magic link sends
     `emailRedirectTo: window.location.origin`, so the deployed origin must be
     allow-listed or the link bounces to Site URL / fails. Keep
     `http://localhost:5175` listed so local dev keeps working.

## 2. Hosting (pick one)

The app is a static SPA — any static host works. Build command `pnpm build`,
output dir `dist`.

**Cloudflare Pages** (free): Workers & Pages → Create → import the repo.
Framework preset "Vite". Set the env vars below in Settings → Environment
variables.

**Vercel** (free): New Project → import the repo, framework auto-detected.
Set the env vars under Environment Variables.

Environment variables for the build (both hosts):

```
VITE_SUPABASE_URL=https://<ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

No SPA rewrite rules are needed — there is no client-side router.

## 3. GitHub secrets (for the scheduled workflows)

Repo → Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | publishable key |
| `SUPABASE_DB_URL` | `postgresql://postgres.<ref>:<db-password>@aws-0-<region>.pooler.supabase.com:6543/postgres` (Settings → Database → connection string, session/transaction pooler) |

- **Keepalive** pings the REST endpoint every 3 days so the free project does
  not pause. Without it, the project pauses after ~7 idle days and auth/API
  go down until you resume it manually.
- **Backup** runs `supabase db dump --data-only` weekly and stores it as a
  workflow artifact (90-day retention). Test a restore once: load the dump
  into a fresh local DB with `psql`.

## 4. First prod login

Magic links on prod go to your real inbox (no Mailpit). Sign in with your
email — the signup trigger creates `profiles` + `budget_settings`
automatically, then open the current month. If a link 404s, check the
redirect URL allow-list in step 1.4 first — it is almost always that.
