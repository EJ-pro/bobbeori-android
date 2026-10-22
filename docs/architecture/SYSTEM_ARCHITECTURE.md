# 밥벌이 MVP 시스템 아키텍처

## 0. 문서 정보

| 항목 | 내용 |
|---|---|
| 문서 버전 | v0.1 |
| 작성일 | 2026-10-23 |
| 기준 문서 | PRD v0.1, USER_FLOW v0.1, SCREEN_SPEC v0.1 |
| 범위 | Android 앱, Supabase, AI 및 외부 영상 연동 |

이 문서는 구현 전에 시스템 경계와 책임을 확정하기 위한 설계안이다. 실제 Supabase 프로젝트, 테이블 또는 외부 AI 리소스는 아직 생성하지 않는다.

---

## 1. 결정 요약

| 영역 | 결정 |
|---|---|
| 클라이언트 | Android 네이티브, Kotlin, Compose |
| 앱 구조 | UI → ViewModel → UseCase → Repository → Local/Remote DataSource |
| 로컬 저장 | Room을 세션·레시피 캐시 및 동기화 대기열에 사용 |
| 설정 저장 | DataStore 사용 |
| 백엔드 | Supabase Auth, Postgres, Edge Functions, Realtime, Queues |
| 첫 사용자 인증 | Supabase 익명 로그인, 추후 Google/이메일 계정 연결 |
| 데이터 보안 | 개인 테이블 RLS 필수, `auth.uid()` 기반 소유권 |
| AI 키 | Edge Function 비밀값에만 저장 |
| 영상 분석 | 요청 접수와 실제 처리를 분리한 비동기 작업 |
| 분석 진행 표시 | DB 상태를 원본으로 사용, Realtime은 빠른 알림용 |
| 조리 세션 | 로컬 우선 반영 후 멱등 동기화 |
| AI 상태 변경 | 답변 생성과 상태 변경 명령을 분리 |
| 음성 원본 | MVP에서 서버 영구 저장하지 않음 |
| 영상 원본 | 저장·재배포하지 않고 메타데이터와 근거 위치만 보관 |

---

## 2. 시스템 경계

```text
┌──────────────── Android 앱 ────────────────┐
│ Compose UI                                 │
│ ViewModel / UseCase                        │
│ Repository                                 │
│ ├─ Room: 레시피·세션·동기화 대기열        │
│ ├─ DataStore: 사용자 설정                  │
│ └─ Supabase Client: Auth/DB/Functions      │
└───────────────────┬────────────────────────┘
                    │ JWT + publishable key
┌───────────────────▼ Supabase ──────────────┐
│ Auth: 익명/영구 사용자                     │
│ Postgres + RLS                             │
│ Realtime: 분석 상태 변경 알림              │
│ Queues: 분석 작업 내구성                   │
│ Edge Functions                             │
│ ├─ 영상 검증·분석 접수                     │
│ ├─ 분석 worker                             │
│ ├─ 조리 대화                               │
│ ├─ 상태 변경                               │
│ └─ 계정/데이터 삭제                        │
└───────────────┬───────────────┬────────────┘
                │               │
        ┌───────▼──────┐ ┌─────▼──────────┐
        │ YouTube 허용 │ │ AI/STT 제공자   │
        │ API/메타데이터│ │ 구조화·대화     │
        └──────────────┘ └────────────────┘
```

### 시스템 밖의 범위

- 원본 YouTube 영상 파일 저장과 재배포
- 웹 클라이언트
- 장보기, 냉장고, 영수증, OCR, 캘린더
- 항상 듣는 음성 처리
- 사진 기반 익힘 판정

---

## 3. 책임 분리

### 3.1 Android 앱이 책임지는 것

- URL 형식 1차 검증과 공유 Intent 처리
- 화면 상태와 사용자 입력 관리
- 레시피 및 진행 중 세션 로컬 캐시
- 조리 단계의 즉각적인 로컬 전환
- 네트워크 복구 후 변경 재전송
- 마이크 권한, 음성 캡처, Android TTS
- 사용자의 확인이 필요한 상태 변경 UI

앱은 AI API와 service role 키를 직접 사용하지 않는다. 영상 지원 가능 여부, 사용량 제한, 분석 생성과 AI 답변의 최종 판단도 앱에 두지 않는다.

### 3.2 Postgres가 책임지는 것

- 데이터의 최종 영속성
- 사용자별 소유권과 RLS
- 관계 무결성, enum/check 제약과 유일성
- 분석 작업 및 조리 세션의 현재 서버 상태
- 멱등 요청 기록과 중복 방지
- 공용 추출 원본과 사용자 수정본 분리

### 3.3 Edge Functions가 책임지는 것

- JWT 검증과 서버 권한 검사
- 외부 서비스 호출
- 비밀키 사용
- 입력 정규화 및 서버 재검증
- 비용 발생 작업의 사용량·속도 제한
- AI 구조화 출력 검증
- 허용된 상태 전이와 감사 로그

### 3.4 Queue worker가 책임지는 것

- 장시간 영상 분석 처리
- 재시도 가능한 실패와 영구 실패 구분
- 중복 소비에도 안전한 처리
- 결과 원자적 저장 후 작업 상태 갱신
- 처리 실패 메시지의 재노출 또는 격리

---

## 4. Android 아키텍처

### 4.1 모듈 전략

MVP 초기에는 과도한 Gradle 멀티모듈을 피하고 단일 `app` 모듈 안에서 패키지를 분리한다. 기능과 팀 규모가 커질 때 모듈화한다.

```text
com.bobbeori.bobbeori_app
├─ app
│  ├─ BobbeoriApp
│  ├─ AppContainer
│  └─ navigation
├─ core
│  ├─ designsystem
│  ├─ model
│  ├─ network
│  ├─ database
│  ├─ datastore
│  └─ common
├─ feature
│  ├─ onboarding
│  ├─ home
│  ├─ extraction
│  ├─ recipe_review
│  ├─ cooking_ready
│  ├─ cooking
│  ├─ chat
│  ├─ saved_recipes
│  └─ settings
└─ data
   ├─ auth
   ├─ video
   ├─ recipe
   ├─ extraction
   ├─ cooking
   └─ conversation
```

### 4.2 레이어 의존 방향

```text
Compose Screen
    ↓ observes StateFlow / sends UiAction
ViewModel
    ↓
UseCase
    ↓
Repository interface
    ↓
Repository implementation
    ├─ Room DAO
    ├─ Supabase Data API
    └─ Supabase Edge Functions
```

- UI 모델과 네트워크 DTO를 분리한다.
- ViewModel은 Supabase SDK 타입을 직접 노출하지 않는다.
- 사용자 행동은 `UiAction`, 화면 출력은 불변 `UiState`, 일회성 이동은 `UiEffect`로 구분한다.
- repository가 로컬과 원격의 병합·동기화 정책을 가진다.

### 4.3 로컬 데이터

Room에 최소 다음을 저장한다.

- 저장 및 진행 중인 사용자 레시피 캐시
- 레시피 단계와 재료
- 조리 세션, 현재 단계 및 단계 진행 기록
- 최근 대화와 대화 요약
- 서버 전송 대기 mutation outbox

DataStore에는 다음을 저장한다.

- 온보딩 완료 여부
- TTS 설정
- 음성 인식 전송 전 확인 여부
- 마지막 활성 세션 ID

Supabase Auth 세션은 SDK가 제공하는 안전한 세션 저장 방식을 따르며 직접 평문 파일에 복제하지 않는다.

### 4.4 오프라인 우선 범위

| 기능 | 오프라인 동작 |
|---|---|
| 기존 레시피 보기 | 가능 |
| 진행 중 조리 | 가능 |
| 단계 완료·이동 | 로컬 반영 후 동기화 |
| 레시피 사용자 수정 | 로컬 저장 후 동기화 |
| 새 영상 분석 | 불가 |
| 새 AI 답변 | 불가 |
| 원본 영상 열기 | 외부 앱 캐시 여부에 의존 |

---

## 5. 인증 전략

### 5.1 첫 실행

1. 기존 세션이 없으면 `signInAnonymously()`를 호출한다.
2. 발급된 사용자는 일반 인증 사용자와 동일하게 JWT와 `auth.uid()`를 가진다.
3. 앱 DB에는 `profiles.id = auth.users.id` 레코드를 만든다.
4. 분석 1회와 기본 조리 체험을 허용한다.

Supabase의 익명 사용자는 DB 관점에서 `authenticated` 역할이므로, 영구 사용자와 구분할 때 JWT의 `is_anonymous` claim을 확인한다.

### 5.2 계정 연결

- 저장, 기기 변경 복구 또는 추가 사용량이 필요할 때 Google/이메일 연결을 제안한다.
- 신규 영구 계정으로 갈아타기보다 가능한 경우 익명 사용자에 identity를 연결해 user ID를 유지한다.
- 이미 존재하는 계정으로 로그인할 때는 익명 데이터 병합 정책을 별도 실행한다.

### 5.3 익명 사용자 위험 관리

- 익명 가입 endpoint에 CAPTCHA 또는 이에 준하는 봇 방지를 적용한다.
- IP/사용자 단위 분석 요청 rate limit을 둔다.
- 익명 사용자는 1회 분석 등 서버 측 quota로 제한한다.
- 오래된 미사용 익명 계정과 개인 데이터 정리 작업을 운영 정책으로 둔다.
- 로그아웃이나 앱 데이터 삭제 시 같은 익명 계정으로 복귀할 수 없음을 안내한다.

---

## 6. 주요 런타임 흐름

### 6.1 링크 검증 및 분석

```text
Android
  └─ POST validate-video
       ├─ URL 정규화
       ├─ 영상 접근성/메타데이터 확인
       └─ source_video upsert
  └─ POST create-extraction (Idempotency-Key)
       ├─ 사용자 quota 확인
       ├─ 기존 완료 결과/진행 작업 확인
       ├─ extraction_job 생성
       └─ durable queue enqueue
Queue consumer
  └─ process-extraction
       ├─ source 획득
       ├─ Recipe Extractor 호출
       ├─ JSON Schema 검증
       ├─ Extraction Validator 호출/규칙 검증
       ├─ recipe_source 버전 저장
       └─ job COMPLETED 또는 NEEDS_REVIEW
Android
  ├─ Realtime 알림 수신
  └─ 반드시 job row 재조회 후 화면 이동
```

Realtime은 놓칠 수 있는 알림 채널로만 사용한다. 앱 시작·복귀·재연결 시 DB의 `extraction_jobs` 상태를 다시 조회한다.

### 6.2 레시피 검토

- 분석 원본은 불변 version으로 저장한다.
- 사용자가 검토를 시작하면 `user_recipes`와 하위 재료·단계 사본을 만든다.
- 사용자 편집은 공용 `recipe_sources`를 수정하지 않는다.
- 원본 복원은 source version의 필드를 개인 사본으로 다시 복사하는 명시적 작업이다.

### 6.3 조리 세션

```text
사용자 행동
  → Room transaction으로 단계/진행 기록/outbox 저장
  → UI 즉시 갱신
  → 네트워크 가능 시 sync-session-mutations 호출
  → 서버가 operation_id 중복 검사
  → 허용된 상태 전이 적용
  → server_revision 반환
  → 로컬 동기화 완료 표시
```

클라이언트는 각 mutation에 UUID `operation_id`, 세션의 `base_revision`, 발생 시각을 포함한다. 서버는 같은 operation을 한 번만 적용한다.

### 6.4 AI 대화

```text
Android → POST cooking-chat
  입력: session_id, message, input_method, step_id, request_id
Edge Function
  1. 세션 소유권 확인
  2. 현재 레시피/단계/변경사항/요약 조회
  3. Conversation Router로 intent 분류
  4. Cooking Companion 답변 생성
  5. 상태 변경 후보 action 검증
  6. 메시지 저장
  7. answer + proposed_action 반환
Android
  ├─ 정보 응답 표시
  └─ 확인 필요 action이면 사용자 확인 UI
Android → POST apply-session-action
  └─ 서버가 허용된 전이만 원자적으로 적용
```

AI 모델은 DB를 직접 수정하지 않는다. 모델 출력은 “행동 제안”일 뿐이며 서버의 allowlist와 상태 전이 검증을 통과해야 한다.

---

## 7. 비동기 작업 전략

영상 분석은 Edge Function의 단일 HTTP 요청 안에서 끝난다고 가정하지 않는다. Edge Functions에는 wall-clock 및 CPU 제한이 있으므로 요청 접수와 작업 수행을 분리한다.

### MVP 권장 구조

1. `create-extraction`이 작업 row와 queue message를 한 트랜잭션 경계로 생성한다.
2. 비공개 `recipe-extraction` queue를 사용한다.
3. 예약 호출 또는 서버 측 트리거가 `process-extraction` worker를 깨운다.
4. worker는 한 번에 제한된 메시지만 읽고 visibility timeout 안에 처리한다.
5. 성공 시 queue message를 archive하고 실패 시 retry count와 next attempt를 기록한다.
6. 최대 재시도 초과 시 job을 `FAILED`로 전환하고 메시지를 격리한다.

클라이언트에 Queue API 권한을 주지 않는다. queue payload에는 `job_id`, `source_video_id`, `requested_by`처럼 내부 조회용 ID만 넣고 자막 전문이나 비밀값을 넣지 않는다.

---

## 8. 동기화와 충돌 규칙

### 8.1 서버 원본

- 분석 작업과 공용 레시피 원본: 서버가 절대 원본
- 사용자 레시피: 서버가 장기 원본, 로컬은 편집 가능한 캐시
- 활성 조리 세션: 로컬 우선 사용, 서버는 복구·기기 간 동기화 원본
- 설정: 기기 경험 설정은 로컬, 계정 관련 설정만 서버

### 8.2 revision 규칙

- `cooking_sessions.revision`은 서버 mutation마다 1 증가한다.
- 클라이언트는 `base_revision`을 전송한다.
- 같으면 적용한다.
- 다르면 operation 유형별로 판단한다.
  - 서로 다른 단계의 완료 기록: 병합 가능
  - 현재 단계 변경 충돌: 자동 덮어쓰기 금지
  - 같은 재료의 서로 다른 대체값: 사용자 확인 필요
  - 세션 완료/중단 이후 뒤늦은 일반 변경: 거부

### 8.3 Outbox

각 로컬 변경은 UI 상태와 같은 Room transaction 안에서 outbox에 저장한다. WorkManager는 네트워크 연결 시 순서대로 전송한다. 성공 응답을 받은 operation만 삭제하며 재전송해도 서버의 멱등 처리로 중복 적용되지 않는다.

---

## 9. 보안 경계

### Android에 포함 가능

- Supabase project URL
- Supabase publishable key
- 공개 feature flag

### Android에 포함 금지

- Supabase secret/service role key
- AI provider API key
- YouTube 서버용 secret
- DB 비밀번호
- signing keystore와 비밀번호

### 서버 규칙

- 모든 `public` 테이블에 RLS를 켠다.
- `anon` DB role의 테이블 접근은 기본 revoke한다.
- 필요한 동작만 `authenticated`에 grant한다.
- 개인 row 정책은 `(select auth.uid()) = user_id` 형태를 사용한다.
- RLS의 `user_id` 및 주요 외래키를 인덱싱한다.
- service role은 Edge Function 비밀값으로만 사용한다.
- 외부 응답과 AI JSON을 스키마 검증 후 저장한다.
- 로그에 access token, 자막 전문, 대화 전문을 기본 출력하지 않는다.

---

## 10. 관측성과 운영

### 로그 공통 필드

- `request_id`
- `user_id_hash` 또는 내부 user ID(접근 제한 로그)
- `function_name`
- `job_id`/`session_id`
- `duration_ms`
- `result_code`
- `retry_count`
- AI provider와 model version

### 필수 지표

- 분석 queue 길이와 가장 오래된 메시지 시간
- 상태별 분석 작업 수 및 성공률
- 분석 p50/p95 시간
- AI schema validation 실패율
- 대화 응답 p50/p95 시간과 실패율
- 세션 mutation 충돌률
- RLS/권한 오류율
- 완료된 조리 1회당 AI 비용

### 알림 조건 초안

- queue oldest age가 운영 기준 초과
- 분석 실패율이 15분 평균 기준 급증
- AI 응답 오류율 급증
- 동일 provider timeout 연속 발생
- RLS 정책 또는 DB migration 실패

---

## 11. 단계별 구현 순서

### A0 로컬 개발 기반

- Supabase CLI 초기화
- local project와 migration 체계
- dev/staging/prod 환경 분리 원칙
- 앱 BuildConfig에 로컬 publishable 설정 주입

### A1 인증과 데이터 골격

- 익명 로그인
- profiles trigger
- 개인 테이블과 RLS
- RLS 자동 테스트

### A2 링크와 분석

- validate-video
- source_videos/extraction_jobs
- queue와 worker
- recipe_sources 구조화 결과
- Realtime + 재조회 복구

### A3 사용자 레시피

- user_recipes와 하위 테이블
- 검토·수정·원본 복원
- Room 캐시

### A4 조리 세션

- sessions/progress/changes
- revision 및 idempotency
- Room outbox와 WorkManager

### A5 대화

- intent router와 companion
- messages/summaries
- apply-session-action
- Android 음성 입력과 TTS

### A6 출시 준비

- 데이터 삭제
- 익명 계정 정리
- quota/rate limit
- 운영 대시보드와 알림
- 개인정보·Play 데이터 보안 검토

---

## 12. 아직 확정하지 않은 결정

| ID | 항목 | 결정 시점 |
|---|---|---|
| A-01 | YouTube 정보/자막을 정책에 맞게 확보하는 구체적 제공자 | A2 전 기술 검증 |
| A-02 | AI 제공자와 모델 | 고정 평가 세트 비교 후 |
| A-03 | Queue worker 호출 방식과 유료 플랜 | 처리시간 PoC 후 |
| A-04 | 익명 분석 무료 횟수 | 비용 실험 후 |
| A-05 | Google 로그인 우선 여부 | 계정 UX 설계 시 |
| A-06 | 대화 스트리밍 방식 | AI SDK와 응답시간 PoC 후 |
| A-07 | 음성 인식을 Android 기기 기능으로 할지 서버 STT로 할지 | 한국어 주방 소음 테스트 후 |

---

## 13. 구현 참고 자료

- [Supabase Android Kotlin 빠른 시작](https://supabase.com/docs/guides/getting-started/quickstarts/kotlin)
- [Supabase 익명 로그인](https://supabase.com/docs/guides/auth/auth-anonymous)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Queues](https://supabase.com/docs/guides/queues)
- [Supabase Edge Function CPU 제한](https://supabase.com/docs/guides/troubleshooting/edge-function-cpu-limits)

Supabase Kotlin 클라이언트는 Supabase 문서에서 안내하지만 community-maintained 라이브러리이므로, 버전 업그레이드 시 호환성 검증을 수행한다.

