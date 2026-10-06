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
   - Redirect URLs: add `https://<your-domain>/**` — both the magic link and
     Google OAuth send the user back to `window.location.origin`, so the
     deployed origin must be allow-listed or the redirect bounces to Site
     URL / fails. Keep `http://localhost:5175` listed so local dev keeps
     working.

5. Google sign-in — **Authentication → Sign In / Providers → Google**:
   - In Google Cloud Console: create a project → APIs & Services → OAuth
     consent screen (External, fill app name/email) → Credentials → Create
     Credentials → **OAuth client ID** → type "Web application".
   - Authorized redirect URI: `https://<ref>.supabase.co/auth/v1/callback`
     (Supabase shows the exact URL on the provider settings page). For local
     dev also add `http://127.0.0.1:54321/auth/v1/callback`.
   - Paste the Client ID + Client Secret into the Supabase provider form and
     enable it. Done — the "Entrar com Google" button is already in the app.
   - For the local stack, set `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` and
     `SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET` as env vars before
     `pnpm supabase start` (config.toml reads them via `env(...)`); or just
     test Google sign-in on prod — one credential set works for both if you
     list both callback URLs.

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

Prefer "Entrar com Google" — it skips email deliverability entirely. Magic
links still work but go through Supabase's rate-limited free SMTP. Either
way the signup trigger creates `profiles` + `budget_settings` automatically,
then open the current month. If a redirect 404s, check the URL allow-list in
step 1.4 first — it is almost always that.
