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

Android에서 영상 검증과 분석 작업 생성을 시험할 때는 Supabase를 시작한 뒤 별도 터미널에서 Edge Functions를 실행합니다.

```powershell
npx supabase functions serve
```

현재 `validate-video`는 YouTube URL을 검증·정규화하고, `create-extraction`은 인증 사용자의 중복되지 않는 `QUEUED` 작업을 생성합니다. 실제 영상 메타데이터 수집과 AI 추출 worker는 다음 구현 단계입니다.

`db reset` recreates the local database, applies every migration in order, and then executes `seed.sql`.

The local Postgres port is `55432` and the shadow database port is `55430`. These non-default ports avoid Docker Desktop port-forwarding conflicts on this Windows development machine.

Local analytics log collection is disabled because it is not required for the MVP backend and would require exposing an additional Docker daemon socket on this Windows setup.

## Directory structure

```text
supabase/
├─ config.toml
├─ functions/
│  ├─ _shared/
│  ├─ validate-video/
│  └─ create-extraction/
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
