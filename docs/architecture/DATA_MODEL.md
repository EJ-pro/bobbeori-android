# 밥벌이 MVP Supabase 데이터 모델

## 0. 모델링 원칙

1. 공용 영상·추출 원본과 개인 수정·조리 데이터를 분리한다.
2. AI 추출 원본은 version 단위로 불변 보존한다.
3. 사용자 편집은 개인 사본에만 반영한다.
4. 조리 진행은 현재값과 변경 이력을 함께 보존한다.
5. 개인 하위 테이블에도 `user_id`를 둬 RLS를 단순하고 빠르게 만든다.
6. 모든 ID는 UUID, 모든 시각은 `timestamptz`, 순서는 0이 아닌 1부터 시작한다.
7. 유연한 provider 원본은 `jsonb`, 제품의 핵심 조회 필드는 정규화한다.
8. 삭제는 개인 데이터는 cascade를 사용하되 공용 원본은 별도 보존 정책을 따른다.

---

## 1. 관계 개요

```text
auth.users 1─1 profiles
auth.users 1─N extraction_jobs N─1 source_videos
source_videos 1─N recipe_sources
recipe_sources 1─N source_ingredients
recipe_sources 1─N source_steps

auth.users 1─N user_recipes N─1 recipe_sources
user_recipes 1─N recipe_ingredients
user_recipes 1─N recipe_steps
recipe_steps N─M recipe_ingredients (step_ingredients)

user_recipes 1─N cooking_sessions
cooking_sessions 1─N session_step_progress
cooking_sessions 1─N session_changes
cooking_sessions 1─1 conversations
conversations 1─N conversation_messages
conversations 1─N conversation_summaries
```

---

## 2. Enum 초안

| 타입 | 값 |
|---|---|
| `extraction_status` | `QUEUED`, `FETCHING_SOURCE`, `EXTRACTING`, `VALIDATING`, `COMPLETED`, `NEEDS_REVIEW`, `FAILED`, `CANCELLED` |
| `confidence_level` | `CONFIRMED`, `INFERRED`, `UNKNOWN` |
| `recipe_status` | `DRAFT`, `REVIEWING`, `READY`, `ARCHIVED` |
| `cooking_status` | `READY`, `COOKING`, `PAUSED`, `COMPLETED`, `ABANDONED` |
| `step_progress_status` | `PENDING`, `CURRENT`, `COMPLETED`, `SKIPPED` |
| `message_role` | `USER`, `ASSISTANT`, `SYSTEM`, `TOOL` |
| `input_method` | `TEXT`, `VOICE`, `QUICK_ACTION` |
| `action_status` | `NONE`, `PROPOSED`, `CONFIRMED`, `REJECTED`, `APPLIED`, `FAILED` |

DB enum은 값 변경이 번거로울 수 있으므로 구현 시 Postgres enum 또는 text+check 중 migration 운영 방식을 보고 선택한다. MVP 초반에는 text+check가 수정에 유연하다.

---

## 3. 인증 및 사용자

### `profiles`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | `auth.users.id`, on delete cascade |
| `display_name` | text null | 선택 |
| `locale` | text | 기본 `ko-KR` |
| `timezone` | text | 기본 `Asia/Seoul` |
| `is_anonymous_snapshot` | boolean | 운영 조회용, 권한 판단 원본은 JWT |
| `created_at` | timestamptz | default now |
| `updated_at` | timestamptz | trigger 갱신 |

### `user_preferences`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `user_id` | uuid PK/FK | profiles.id |
| `tts_enabled` | boolean | default true |
| `confirm_voice_before_send` | boolean | default false |
| `analytics_consent` | boolean | default false 또는 정책 결정 |
| `updated_at` | timestamptz | default now |

기기 전용 UX 설정은 DataStore가 우선이며 계정 간 동기화할 가치가 있는 설정만 이 테이블에 둔다.

---

## 4. 영상과 분석

### `source_videos`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | 생성 UUID |
| `platform` | text | MVP는 `YOUTUBE` |
| `platform_video_id` | text | unique(platform, id) |
| `canonical_url` | text | 정규화 URL |
| `title` | text null | 외부 메타데이터 |
| `channel_name` | text null | 외부 메타데이터 |
| `thumbnail_url` | text null | 외부 URL |
| `duration_seconds` | integer null | 0 이상 |
| `availability` | text | PUBLIC/PRIVATE/DELETED/RESTRICTED/UNKNOWN |
| `metadata_checked_at` | timestamptz | 캐시 만료 판단 |
| `created_at` | timestamptz | default now |
| `updated_at` | timestamptz | default now |

공용 테이블이지만 클라이언트 임의 insert/update를 허용하지 않는다. Edge Function만 관리한다.

### `extraction_jobs`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | job ID |
| `user_id` | uuid FK | auth.users, 소유자 |
| `source_video_id` | uuid FK | source_videos |
| `status` | text | extraction status check |
| `progress_stage` | text null | 사용자 문구 매핑용 |
| `attempt_count` | integer | default 0 |
| `idempotency_key` | uuid | user 내 unique |
| `cache_hit` | boolean | default false |
| `recipe_source_id` | uuid null FK | 성공 결과 |
| `error_code` | text null | 정해진 코드만 |
| `error_detail_private` | text null | 클라이언트 select 금지 권장 |
| `retryable` | boolean null | 실패 때 설정 |
| `model_provider` | text null | 운영 분석 |
| `model_name` | text null | 운영 분석 |
| `model_version` | text null | 프롬프트/스키마 버전 포함 |
| `queued_at` | timestamptz | default now |
| `started_at` | timestamptz null | worker 시작 |
| `completed_at` | timestamptz null | 종료 |
| `created_at` | timestamptz | default now |

부분 unique index: 사용자·영상별 active 상태 작업은 하나만 허용한다.

### `recipe_sources`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | source version ID |
| `source_video_id` | uuid FK | source_videos |
| `version` | integer | 영상 내 unique, 1 이상 |
| `title` | text | 추출 요리명 |
| `servings_value` | numeric null | 0 초과 |
| `servings_confidence` | text | confidence check |
| `total_time_minutes` | integer null | 0 이상 |
| `total_time_confidence` | text | confidence check |
| `schema_version` | text | 구조화 출력 버전 |
| `prompt_version` | text | extractor prompt 버전 |
| `validation_status` | text | VALID/NEEDS_REVIEW/REJECTED |
| `raw_result_private` | jsonb null | 디버깅 보존 기간 제한 |
| `created_at` | timestamptz | default now |

unique(`source_video_id`, `version`). 외부 provider 원문 전체는 공개 Data API에 노출하지 않는 private schema 분리를 권장한다.

### `source_ingredients`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `recipe_source_id` | uuid FK | on delete cascade |
| `position` | integer | 1 이상 |
| `name` | text | nonblank |
| `quantity` | numeric null | 0 이상 |
| `quantity_text` | text null | “약간” 등 원문 표현 |
| `unit` | text null | |
| `preparation` | text null | |
| `is_optional` | boolean | default false |
| `confidence` | text | confidence check |
| `evidence_text` | text null | 짧고 제한된 근거 |
| `evidence_start_seconds` | integer null | 0 이상 |

### `source_steps`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `recipe_source_id` | uuid FK | on delete cascade |
| `position` | integer | recipe 내 unique, 1 이상 |
| `instruction` | text | nonblank |
| `duration_seconds` | integer null | 0 이상 |
| `heat_level` | text null | |
| `cautions` | text[] | default empty |
| `start_timestamp_seconds` | integer null | 0 이상 |
| `end_timestamp_seconds` | integer null | start 이상 |
| `confidence` | text | confidence check |

`source_step_ingredients` join table로 단계와 원본 재료를 연결한다.

---

## 5. 사용자 레시피

### `user_recipes`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | auth.users |
| `recipe_source_id` | uuid FK | 사용한 원본 version |
| `status` | text | recipe status |
| `title` | text | 사용자 확정값 |
| `servings_value` | numeric null | |
| `total_time_minutes` | integer null | |
| `has_uncertainty` | boolean | 빠른 표시용 |
| `last_cooked_at` | timestamptz null | |
| `created_at` | timestamptz | default now |
| `updated_at` | timestamptz | trigger |
| `deleted_at` | timestamptz null | 복구 기간 정책 시 soft delete |

동일 source를 여러 버전으로 저장할 필요가 없으면 unique(`user_id`, `recipe_source_id`)를 둔다.

### `recipe_ingredients`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | RLS용 소유자 |
| `user_recipe_id` | uuid FK | on delete cascade |
| `source_ingredient_id` | uuid null FK | 원본 추적 |
| `position` | integer | 1 이상 |
| `name` | text | nonblank |
| `quantity` | numeric null | |
| `quantity_text` | text null | |
| `unit` | text null | |
| `preparation` | text null | |
| `is_optional` | boolean | |
| `is_user_modified` | boolean | default false |
| `confidence` | text | 사용자 확인 후 CONFIRMED 가능 |
| `created_at`, `updated_at` | timestamptz | |

### `recipe_steps`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | RLS용 소유자 |
| `user_recipe_id` | uuid FK | on delete cascade |
| `source_step_id` | uuid null FK | 원본 추적 |
| `position` | integer | recipe 내 unique |
| `instruction` | text | nonblank |
| `duration_seconds` | integer null | |
| `heat_level` | text null | |
| `cautions` | text[] | |
| `start_timestamp_seconds` | integer null | |
| `end_timestamp_seconds` | integer null | |
| `is_user_modified` | boolean | default false |
| `confidence` | text | |
| `created_at`, `updated_at` | timestamptz | |

### `step_ingredients`

- `user_id`
- `recipe_step_id`
- `recipe_ingredient_id`
- `quantity_override` / `quantity_text_override` / `unit_override`
- PK(`recipe_step_id`, `recipe_ingredient_id`)

단계에서 사용하는 실제 분량이 전체 재료 분량과 다를 수 있으므로 override를 허용한다.

---

## 6. 조리 세션

### `cooking_sessions`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | 소유자 |
| `user_recipe_id` | uuid FK | 레시피 |
| `status` | text | cooking status |
| `current_step_id` | uuid null FK | 현재 단계 |
| `revision` | bigint | default 0, mutation마다 증가 |
| `device_id` | uuid null | 마지막 작성 기기 |
| `started_at` | timestamptz null | |
| `paused_at` | timestamptz null | |
| `completed_at` | timestamptz null | |
| `abandoned_at` | timestamptz null | |
| `last_activity_at` | timestamptz | |
| `created_at`, `updated_at` | timestamptz | |

사용자당 `READY/COOKING/PAUSED` 세션 수 제한은 제품 정책에 따라 partial unique index 또는 서버 규칙으로 정한다.

### `session_step_progress`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK | RLS용 |
| `cooking_session_id` | uuid FK | on delete cascade |
| `recipe_step_id` | uuid FK | |
| `status` | text | progress status |
| `first_started_at` | timestamptz null | |
| `completed_at` | timestamptz null | |
| `skipped_at` | timestamptz null | |
| `updated_at` | timestamptz | |

unique(`cooking_session_id`, `recipe_step_id`).

### `session_changes`

감사 및 대화 문맥용 append-only 변경 로그다.

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | operation ID로 사용 가능 |
| `user_id` | uuid FK | |
| `cooking_session_id` | uuid FK | |
| `change_type` | text | STEP_COMPLETED 등 allowlist |
| `target_id` | uuid null | step/ingredient ID |
| `before_value` | jsonb null | 필요한 최소값 |
| `after_value` | jsonb null | 필요한 최소값 |
| `source` | text | BUTTON/TEXT/VOICE/SYSTEM |
| `base_revision` | bigint | 클라이언트가 본 revision |
| `applied_revision` | bigint null | 서버 적용 결과 |
| `created_at` | timestamptz | |

같은 `id` 재전송은 기존 적용 결과를 반환한다.

---

## 7. 대화

### `conversations`

- `id` uuid PK
- `user_id` uuid FK
- `cooking_session_id` uuid unique FK
- `last_message_at` timestamptz
- `created_at`, `updated_at`

### `conversation_messages`

| 컬럼 | 타입 | 규칙 |
|---|---|---|
| `id` | uuid PK | client request ID 재사용 가능 |
| `user_id` | uuid FK | |
| `conversation_id` | uuid FK | on delete cascade |
| `role` | text | message role |
| `content` | text | 길이 제한 |
| `input_method` | text null | 사용자 메시지 |
| `intent` | text null | router 결과 |
| `step_id_at_send` | uuid null FK | 질문 시점 |
| `action_type` | text null | 제안 행동 |
| `action_status` | text | 기본 NONE |
| `model_name` | text null | assistant message |
| `prompt_version` | text null | assistant message |
| `created_at` | timestamptz | |

클라이언트는 임의 assistant/tool 메시지를 insert할 수 없다. 메시지 쓰기는 Edge Function을 통한다.

### `conversation_summaries`

- `id`, `user_id`, `conversation_id`
- `from_message_id`, `to_message_id`
- `summary` text
- `decisions` jsonb: 확정된 재료 대체 등
- `unresolved_issues` jsonb
- `model_name`, `prompt_version`, `created_at`

요약은 최근 메시지 문맥을 줄이기 위한 파생 데이터이며 원래 상태의 권위가 아니다.

---

## 8. 운영 및 분석

### `idempotency_records`

- `user_id`, `scope`, `idempotency_key` 복합 PK
- `request_hash`
- `resource_type`, `resource_id`
- `response_code`, `response_body`(민감값 제외)
- `expires_at`, `created_at`

### `usage_ledger`

- `id`, `user_id`
- `usage_type`: EXTRACTION/CHAT/STT
- `resource_id`
- `units`, `estimated_cost_micros`
- `status`: RESERVED/COMMITTED/RELEASED
- `created_at`

quota는 클라이언트 카운트가 아니라 이 ledger 또는 원자적 DB 함수로 계산한다.

### `analytics_events`

- `id`, `user_id` null 가능, `anonymous_install_id` 해시
- `event_name`, `properties` jsonb
- `session_id` null, `occurred_at`, `received_at`

자유 입력 원문, 자막, AI 답변 전체를 analytics 속성에 저장하지 않는다.

---

## 9. RLS 매트릭스

| 테이블 | 사용자 SELECT | 사용자 INSERT/UPDATE/DELETE | 서버 |
|---|---:|---:|---:|
| profiles/preferences | 본인 | 본인, 일부 컬럼 | 전체 |
| source_videos | 인증 사용자 제한적 읽기 | 없음 | 전체 |
| extraction_jobs | 본인 | 없음(함수 통해 생성/취소) | 전체 |
| recipe_sources/source_* | 자신이 참조 가능한 결과 읽기 | 없음 | 전체 |
| user_recipes/ingredients/steps | 본인 | 본인 또는 RPC 정책 | 전체 |
| cooking_sessions/progress | 본인 | 제한적; 상태 변경은 함수 권장 | 전체 |
| session_changes | 본인 읽기 | 직접 쓰기 없음 | 전체 |
| conversations/messages/summaries | 본인 | 메시지는 함수 통해 쓰기 | 전체 |
| usage_ledger | 본인 요약만 | 없음 | 전체 |
| analytics_events | 직접 읽기 없음 | 수집 함수로만 | 전체 |

개인 테이블 정책 기본형:

```sql
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id)
```

정책만 믿지 않고 `anon`/`authenticated` grant도 필요한 동작으로 제한한다. `user_id`와 RLS join에 쓰는 FK에는 index를 둔다.

---

## 10. 인덱스와 제약

### 필수 인덱스

- 모든 개인 테이블 `user_id`
- `source_videos(platform, platform_video_id)` unique
- `extraction_jobs(user_id, created_at desc)`
- active extraction partial unique(`user_id`, `source_video_id`)
- `recipe_sources(source_video_id, version)` unique
- `user_recipes(user_id, updated_at desc)`
- `recipe_steps(user_recipe_id, position)` unique
- `cooking_sessions(user_id, status, last_activity_at desc)`
- `session_step_progress(cooking_session_id, recipe_step_id)` unique
- `conversation_messages(conversation_id, created_at)`
- `idempotency_records(user_id, scope, idempotency_key)` unique

### 중요 check

- position >= 1
- 시간·분량은 null 또는 0 이상
- end timestamp는 start 이상
- 종료 상태의 세션은 해당 종료 시각 필수
- current step은 같은 user recipe에 속해야 함(서버 함수에서 추가 검증)
- 공백만 있는 title/name/instruction 금지

---

## 11. 삭제와 보존

| 데이터 | 기본 정책 초안 |
|---|---|
| 음성 원본 | STT 후 즉시 삭제, 영구 저장 안 함 |
| 대화 | 사용자가 레시피/계정 삭제 시 삭제 |
| 조리 세션 | 사용자 삭제 요청 시 삭제 |
| 실패 상세 로그 | 30일 등 제한 기간 후 삭제 |
| 익명 미사용 계정 | 운영 정책 기간 후 연관 개인 데이터와 삭제 |
| 공용 영상/추출 원본 | 개인 계정 삭제와 분리; 정책·저작권 요청에 따라 관리 |
| analytics | 식별 최소화 후 정해진 기간 보존 |

정확한 기간은 개인정보처리방침 및 운영 비용 검토 후 확정한다.

