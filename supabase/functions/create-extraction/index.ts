import { corsHeaders, error, json, requireUser } from "../_shared/http.ts";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const activeStatuses = ["QUEUED", "FETCHING_SOURCE", "EXTRACTING", "VALIDATING"];

Deno.serve(async (request) => {
  const requestId = request.headers.get("X-Request-Id") ?? crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return error(requestId, "METHOD_NOT_ALLOWED", "지원하지 않는 요청입니다.", 405);

  const auth = await requireUser(request);
  if (auth instanceof Response) return auth;

  const idempotencyKey = request.headers.get("Idempotency-Key");
  if (!idempotencyKey || !uuidPattern.test(idempotencyKey)) {
    return error(requestId, "INVALID_REQUEST", "올바른 멱등 키가 필요합니다.", 400);
  }
  const body = await request.json().catch(() => null) as { sourceVideoId?: unknown } | null;
  if (typeof body?.sourceVideoId !== "string" || !uuidPattern.test(body.sourceVideoId)) {
    return error(requestId, "INVALID_REQUEST", "영상 식별자가 올바르지 않습니다.", 400);
  }

  const selectFields = "id, status, cache_hit, recipe_source_id";
  const { data: repeated } = await auth.admin.from("extraction_jobs")
    .select(selectFields)
    .eq("user_id", auth.user.id)
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();
  if (repeated) return jobResponse(repeated, requestId, 200);

  const { data: active } = await auth.admin.from("extraction_jobs")
    .select(selectFields)
    .eq("user_id", auth.user.id)
    .eq("source_video_id", body.sourceVideoId)
    .in("status", activeStatuses)
    .maybeSingle();
  if (active) return jobResponse(active, requestId, 200);

  const { data: source } = await auth.admin.from("source_videos")
    .select("id")
    .eq("id", body.sourceVideoId)
    .maybeSingle();
  if (!source) return error(requestId, "VIDEO_NOT_SUPPORTED", "분석할 영상을 찾지 못했습니다.", 422);

  const { data: created, error: databaseError } = await auth.admin.from("extraction_jobs")
    .insert({
      user_id: auth.user.id,
      source_video_id: body.sourceVideoId,
      idempotency_key: idempotencyKey,
      status: "QUEUED",
      progress_stage: "WAITING_FOR_EXTRACTION",
    })
    .select(selectFields)
    .single();
  if (databaseError) {
    console.error("create-extraction database error", databaseError.code);
    return error(requestId, "INTERNAL_ERROR", "분석 요청을 등록하지 못했습니다.", 500, true);
  }

  return jobResponse(created, requestId, 202);
});

function jobResponse(job: Record<string, unknown>, requestId: string, status: number): Response {
  return json({
    data: {
      jobId: job.id,
      status: job.status,
      cacheHit: job.cache_hit,
      recipeSourceId: job.recipe_source_id,
    },
    requestId,
  }, status);
}
