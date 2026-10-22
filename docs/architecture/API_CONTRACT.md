# 밥벌이 MVP API 계약 초안

## 0. 공통 규칙

- Base: Supabase Edge Functions URL
- 인증: `Authorization: Bearer <user JWT>` 필수
- 콘텐츠: `application/json; charset=utf-8`
- 모든 요청에 `X-Request-Id` UUID 권장
- 비용 발생·상태 변경 요청에 `Idempotency-Key` UUID 필수
- ID는 UUID, 시각은 UTC ISO 8601, 화면에서 현지 시간으로 변환
- 서버는 클라이언트가 보낸 `user_id`를 신뢰하지 않고 JWT에서 결정
- 오류 응답은 안정적인 `code`, 사용자 표시 가능 `message`, `retryable`을 포함

### 성공 봉투

```json
{
  "data": {},
  "requestId": "uuid"
}
```

### 오류 봉투

```json
{
  "error": {
    "code": "VIDEO_NOT_ACCESSIBLE",
    "message": "이 영상에는 접근할 수 없어요.",
    "retryable": false,
    "details": null
  },
  "requestId": "uuid"
}
```

`details`에는 스택, provider secret, 자막 원문을 포함하지 않는다.

---

## 1. `POST /validate-video`

**목적:** URL 정규화, 지원 여부와 영상 메타데이터 확인.

요청:

```json
{
  "url": "https://youtu.be/example",
  "inputMethod": "SHARE"
}
```

성공 `200`:

```json
{
  "data": {
    "sourceVideoId": "uuid",
    "canonicalUrl": "https://www.youtube.com/watch?v=example",
    "platformVideoId": "example",
    "title": "영상 제목",
    "channelName": "채널명",
    "thumbnailUrl": "https://...",
    "availability": "PUBLIC",
    "analysisSupport": "SUPPORTED"
  },
  "requestId": "uuid"
}
```

주요 오류: `INVALID_URL`, `UNSUPPORTED_PLATFORM`, `VIDEO_NOT_ACCESSIBLE`, `LIVE_VIDEO_UNSUPPORTED`, `SOURCE_PROVIDER_UNAVAILABLE`.

---

## 2. `POST /create-extraction`

**목적:** 분석 결과 재사용 또는 비동기 분석 작업 생성.
**멱등:** `Idempotency-Key` 필수.

요청:

```json
{
  "sourceVideoId": "uuid",
  "allowLimitedAnalysis": false
}
```

신규 작업 `202`:

```json
{
  "data": {
    "jobId": "uuid",
    "status": "QUEUED",
    "cacheHit": false,
    "recipeSourceId": null
  },
  "requestId": "uuid"
}
```

캐시 결과 `200`은 `cacheHit=true`, `recipeSourceId`를 반환한다. 동일 영상의 진행 작업이 있으면 그 `jobId`를 반환한다.

주요 오류: `ANONYMOUS_QUOTA_EXCEEDED`, `RATE_LIMITED`, `VIDEO_NOT_SUPPORTED`, `EXTRACTION_UNAVAILABLE`.

---

## 3. `POST /cancel-extraction`

요청:

```json
{ "jobId": "uuid" }
```

- 소유자만 취소 가능
- 취소 불가능한 단계면 `409 JOB_NOT_CANCELLABLE`
- 이미 취소된 작업 재호출은 성공 상태를 반환

분석 상태 읽기는 RLS가 적용된 `extraction_jobs` Data API를 사용한다. Realtime 알림을 받아도 row를 재조회한다.

---

## 4. `POST /materialize-user-recipe`

**목적:** 공용 추출 원본을 개인 편집 가능한 레시피로 생성.
**멱등:** 사용자와 source version 조합으로 중복 방지.

요청:

```json
{ "recipeSourceId": "uuid" }
```

응답:

```json
{
  "data": {
    "userRecipeId": "uuid",
    "status": "REVIEWING",
    "created": true
  },
  "requestId": "uuid"
}
```

일반 재료·단계 편집은 RLS 기반 Data API 또는 원자적 RPC로 구현할 수 있다. 단계 순서 변경처럼 여러 row가 함께 바뀌는 작업은 RPC를 사용한다.

---

## 5. `POST /start-cooking-session`

요청:

```json
{
  "userRecipeId": "uuid",
  "deviceId": "uuid"
}
```

응답 `201` 또는 기존 active 세션 `200`:

```json
{
  "data": {
    "sessionId": "uuid",
    "status": "COOKING",
    "currentStepId": "uuid",
    "revision": 1,
    "resumed": false
  },
  "requestId": "uuid"
}
```

빈 단계 레시피는 `422 RECIPE_NOT_READY`.

---

## 6. `POST /sync-session-mutations`

**목적:** 오프라인 outbox 변경을 순서대로 멱등 적용.

요청:

```json
{
  "sessionId": "uuid",
  "mutations": [
    {
      "operationId": "uuid",
      "baseRevision": 4,
      "type": "COMPLETE_STEP",
      "targetId": "step-uuid",
      "payload": {},
      "occurredAt": "2026-10-23T00:00:00Z"
    }
  ]
}
```

응답:

```json
{
  "data": {
    "sessionId": "uuid",
    "revision": 5,
    "results": [
      {
        "operationId": "uuid",
        "status": "APPLIED",
        "appliedRevision": 5,
        "conflict": null
      }
    ]
  },
  "requestId": "uuid"
}
```

허용 mutation 초안:

- `SET_CURRENT_STEP`
- `COMPLETE_STEP`
- `SKIP_STEP`
- `REOPEN_STEP`
- `PAUSE_SESSION`
- `RESUME_SESSION`
- `COMPLETE_SESSION`
- `ABANDON_SESSION`
- `UPDATE_INGREDIENT_CHOICE`

충돌 응답은 HTTP `409`로 전체 batch를 버리지 않고 operation별 결과를 제공할 수 있다. 완료·중단 세션에 대한 뒤늦은 변경은 거부한다.

---

## 7. `POST /cooking-chat`

**목적:** 현재 조리 문맥 기반 의도 분류와 답변 생성.
**멱등:** `requestId`를 사용자 메시지 ID로 사용.

요청:

```json
{
  "sessionId": "uuid",
  "requestId": "uuid",
  "message": "물이 너무 많은 것 같아",
  "inputMethod": "VOICE",
  "stepIdAtSend": "uuid"
}
```

응답:

```json
{
  "data": {
    "userMessageId": "uuid",
    "assistantMessageId": "uuid",
    "intent": "TROUBLESHOOT",
    "answer": "불을 중약불로 유지하고 뚜껑을 연 채 조금 더 졸여주세요.",
    "speakText": "불을 중약불로 유지하고 조금 더 졸여주세요.",
    "source": {
      "type": "GENERAL_KNOWLEDGE",
      "timestampSeconds": null
    },
    "proposedAction": null
  },
  "requestId": "uuid"
}
```

상태 변경 후보 예시:

```json
{
  "type": "UPDATE_INGREDIENT_CHOICE",
  "requiresConfirmation": true,
  "label": "양파 대신 대파를 사용한 것으로 저장할까요?",
  "payload": {
    "ingredientId": "uuid",
    "replacement": "대파"
  }
}
```

AI가 제안한 action은 이 응답만으로 DB에 적용하지 않는다.

---

## 8. `POST /apply-session-action`

요청:

```json
{
  "sessionId": "uuid",
  "operationId": "uuid",
  "baseRevision": 5,
  "action": {
    "type": "UPDATE_INGREDIENT_CHOICE",
    "payload": {
      "ingredientId": "uuid",
      "replacement": "대파"
    }
  },
  "sourceMessageId": "uuid"
}
```

서버는 action allowlist, 세션 소유권, 현재 상태, 대상 레시피 소속을 다시 검증한다. 성공하면 session change, 관련 값, message action status를 한 transaction으로 갱신한다.

---

## 9. `POST /submit-analytics-events`

클라이언트에서 짧게 batch 전송한다.

```json
{
  "events": [
    {
      "id": "uuid",
      "name": "step_completed",
      "occurredAt": "2026-10-23T00:00:00Z",
      "properties": {
        "stepIndex": 2,
        "completionMethod": "VOICE"
      }
    }
  ]
}
```

서버는 event name별 허용 속성과 크기를 검증한다. 자유 대화·URL 원문·자막·AI 답변 전문은 거부한다.

---

## 10. `POST /delete-account-data`

- 사용자 재확인 토큰 또는 최근 인증 조건 적용
- 개인 레시피, 세션, 대화, 설정과 식별 가능한 분석 이벤트 삭제
- 익명 사용자는 auth user 삭제까지 서버에서 처리
- 공용 분석 원본은 개인 연결을 제거하고 별도 정책 적용
- 비동기 삭제라면 request ID와 상태 조회 방법 반환

---

## 11. HTTP 및 오류 코드

| HTTP | 의미 |
|---:|---|
| 200/201/202 | 성공/생성/비동기 접수 |
| 400 | 요청 형식 오류 |
| 401 | 인증 없음 또는 만료 |
| 403 | 소유권/기능 권한 없음 |
| 404 | 리소스 없음 또는 접근 불가를 숨김 |
| 409 | 상태·revision 충돌 |
| 422 | 유효하지만 현재 처리 불가능한 입력 |
| 429 | quota 또는 rate limit |
| 500 | 내부 오류 |
| 502/503/504 | 외부 서비스 실패/일시 불가/시간 초과 |

안정적인 오류 코드 초안:

- `INVALID_REQUEST`, `INVALID_URL`, `UNSUPPORTED_PLATFORM`
- `VIDEO_NOT_ACCESSIBLE`, `VIDEO_NOT_SUPPORTED`, `SOURCE_INSUFFICIENT`
- `JOB_NOT_CANCELLABLE`, `EXTRACTION_FAILED`, `EXTRACTION_TIMEOUT`
- `RECIPE_NOT_READY`, `SESSION_NOT_ACTIVE`, `REVISION_CONFLICT`
- `ACTION_NOT_ALLOWED`, `MESSAGE_TOO_LONG`, `AI_RESPONSE_INVALID`
- `ANONYMOUS_QUOTA_EXCEEDED`, `RATE_LIMITED`
- `PROVIDER_UNAVAILABLE`, `NETWORK_REQUIRED`, `INTERNAL_ERROR`

---

## 12. API 수용 기준

- 같은 멱등 키의 재전송이 리소스를 중복 생성하지 않는다.
- 다른 사용자의 UUID를 알아도 해당 데이터에 접근할 수 없다.
- 클라이언트가 body의 user ID를 조작해 소유권을 바꿀 수 없다.
- Realtime 이벤트를 놓쳐도 작업 row 재조회로 최종 상태를 복구한다.
- AI 응답 실패가 조리 세션 상태를 바꾸지 않는다.
- 상태 변경은 허용된 transition과 revision을 검증한다.
- 외부 provider 오류에 내부 정보가 노출되지 않는다.
- 오프라인 mutation 재전송이 중복 완료·중복 변경을 만들지 않는다.

