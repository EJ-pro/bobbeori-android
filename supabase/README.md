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

함수 역할은 다음과 같습니다.

- `validate-video`: YouTube URL 검증·정규화
- `create-extraction`: 인증 사용자의 중복되지 않는 `QUEUED` 작업 생성
- `process-extraction`: 자막 수집, OpenAI 구조화 레시피 추출, 검증 및 원자적 저장

로컬에서는 Git에서 제외된 `supabase/functions/.env`에 `EXTRACTION_FIXTURE_MODE=true`를 설정하면 외부 비용 없이 전체 저장 흐름을 확인할 수 있습니다. 운영에서는 fixture 모드를 반드시 끄고 `.env.example`의 자막 공급자와 OpenAI 비밀값을 Supabase Secrets로 설정해야 합니다. 비밀값은 Android 앱에 넣지 않습니다.

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
│  ├─ create-extraction/
│  └─ process-extraction/
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
