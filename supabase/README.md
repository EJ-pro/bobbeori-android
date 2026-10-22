# Supabase local development

## Prerequisites

- Supabase CLI 2.121.0 or newer
- Docker Desktop or another supported container runtime on Windows

## Start and verify

```powershell
npx supabase start
npx supabase db reset
npx supabase test db
npx supabase db lint --level warning
```

`db reset` recreates the local database, applies every migration in order, and then executes `seed.sql`.

The local Postgres port is `55432` and the shadow database port is `55430`. These non-default ports avoid Docker Desktop port-forwarding conflicts on this Windows development machine.

Local analytics log collection is disabled because it is not required for the MVP backend and would require exposing an additional Docker daemon socket on this Windows setup.

## Directory structure

```text
supabase/
├─ config.toml
├─ migrations/
├─ tests/database/
└─ seed.sql
```

## Security rules

- Only the publishable key may be used by the Android app.
- Secret/service role keys belong in server-side environment secrets only.
- Tables in an exposed schema require explicit grants and RLS.
- Server-managed tables do not accept direct client writes.
- Never commit `.env` files or generated files under `supabase/.temp/`.
