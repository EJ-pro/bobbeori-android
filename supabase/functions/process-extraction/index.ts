import { corsHeaders, error, json, requireUser } from "../_shared/http.ts";

type Confidence = "CONFIRMED" | "INFERRED" | "UNKNOWN";
type Recipe = {
  title: string; servingsValue: number | null; servingsConfidence: Confidence;
  totalTimeMinutes: number | null; totalTimeConfidence: Confidence;
  validationStatus: "VALID" | "NEEDS_REVIEW";
  ingredients: Array<{ name: string; quantity: number | null; quantityText: string | null; unit: string | null; preparation: string | null; isOptional: boolean; confidence: Confidence; evidenceText: string | null; evidenceStartSeconds: number | null }>;
  steps: Array<{ instruction: string; durationSeconds: number | null; heatLevel: string | null; cautions: string[]; startTimestampSeconds: number | null; endTimestampSeconds: number | null; confidence: Confidence }>;
};

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  const requestId = request.headers.get("X-Request-Id") ?? crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return error(requestId, "METHOD_NOT_ALLOWED", "지원하지 않는 요청입니다.", 405);
  const auth = await requireUser(request);
  if (auth instanceof Response) return auth;
  const body = await request.json().catch(() => null) as { jobId?: unknown } | null;
  if (typeof body?.jobId !== "string" || !uuidPattern.test(body.jobId)) return error(requestId, "INVALID_REQUEST", "분석 작업 식별자가 올바르지 않습니다.", 400);

  const { data: job } = await auth.admin.from("extraction_jobs").select("id,user_id,source_video_id,status").eq("id", body.jobId).eq("user_id", auth.user.id).maybeSingle();
  if (!job) return error(requestId, "EXTRACTION_NOT_FOUND", "분석 작업을 찾지 못했습니다.", 404);
  if (["COMPLETED", "NEEDS_REVIEW"].includes(job.status)) return currentJob(auth.admin, job.id, requestId);
  if (!["QUEUED", "FAILED"].includes(job.status)) return error(requestId, "EXTRACTION_ALREADY_RUNNING", "이미 분석 중인 영상입니다.", 409, true);

  try {
    await setJobState(auth.admin, job.id, "FETCHING_SOURCE", "FETCHING_TRANSCRIPT");
    const { data: source, error: sourceError } = await auth.admin.from("source_videos").select("platform_video_id,canonical_url,title").eq("id", job.source_video_id).single();
    if (sourceError) throw new WorkerError("VIDEO_NOT_SUPPORTED", false);
    const fixtureMode = Deno.env.get("EXTRACTION_FIXTURE_MODE") === "true";
    const transcript = fixtureMode ? fixtureTranscript() : await fetchTranscript(source.platform_video_id, source.canonical_url);

    await setJobState(auth.admin, job.id, "EXTRACTING", "GENERATING_RECIPE");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-6-luna";
    const recipe = fixtureMode ? fixtureRecipe() : await extractRecipe(transcript, source.title, model);
    validateRecipe(recipe);

    await setJobState(auth.admin, job.id, "VALIDATING", "SAVING_RECIPE");
    const { error: completionError } = await auth.admin.rpc("complete_extraction_job", {
      p_job_id: job.id, p_user_id: auth.user.id, p_recipe: recipe,
      p_model_provider: fixtureMode ? "FIXTURE" : "OPENAI",
      p_model_name: fixtureMode ? "fixture-v1" : model,
      p_model_version: "recipe.v1/extractor.v1",
    });
    if (completionError) throw new WorkerError("EXTRACTION_SAVE_FAILED", true);
    return currentJob(auth.admin, job.id, requestId);
  } catch (cause) {
    const workerError = cause instanceof WorkerError ? cause : new WorkerError("EXTRACTION_FAILED", true);
    console.error("process-extraction failed", workerError.code, cause);
    await auth.admin.from("extraction_jobs").update({ status: "FAILED", progress_stage: "FAILED", error_code: workerError.code, retryable: workerError.retryable, completed_at: new Date().toISOString() }).eq("id", job.id).eq("user_id", auth.user.id);
    return error(requestId, workerError.code, workerError.userMessage, 422, workerError.retryable);
  }
});

async function currentJob(admin: any, jobId: string, requestId: string): Promise<Response> {
  const { data: current, error: queryError } = await admin.from("extraction_jobs").select("id,status,cache_hit,recipe_source_id").eq("id", jobId).single();
  if (queryError) return error(requestId, "INTERNAL_ERROR", "분석 상태를 확인하지 못했습니다.", 500, true);
  return json({ data: { jobId: current.id, status: current.status, cacheHit: current.cache_hit, recipeSourceId: current.recipe_source_id }, requestId });
}

async function setJobState(admin: any, jobId: string, status: string, progressStage: string): Promise<void> {
  const values: Record<string, unknown> = { status, progress_stage: progressStage, error_code: null, retryable: null, completed_at: null };
  if (status === "FETCHING_SOURCE") { values.started_at = new Date().toISOString(); values.attempt_count = 1; }
  const { error: updateError } = await admin.from("extraction_jobs").update(values).eq("id", jobId);
  if (updateError) throw new WorkerError("EXTRACTION_STATE_FAILED", true);
}

async function fetchTranscript(videoId: string, canonicalUrl: string): Promise<string> {
  const providerUrl = Deno.env.get("TRANSCRIPT_PROVIDER_URL");
  const providerKey = Deno.env.get("TRANSCRIPT_PROVIDER_KEY");
  if (!providerUrl || !providerKey) throw new WorkerError("TRANSCRIPT_PROVIDER_NOT_CONFIGURED", false);
  const response = await fetch(providerUrl, { method: "POST", headers: { Authorization: `Bearer ${providerKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ videoId, url: canonicalUrl, language: "ko" }) });
  if (!response.ok) throw new WorkerError("TRANSCRIPT_UNAVAILABLE", response.status >= 500);
  const payload = await response.json() as { transcript?: unknown };
  if (typeof payload.transcript !== "string" || payload.transcript.trim().length < 20) throw new WorkerError("SOURCE_INSUFFICIENT", false);
  return payload.transcript.slice(0, 120_000);
}

async function extractRecipe(transcript: string, videoTitle: string | null, model: string): Promise<Recipe> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new WorkerError("OPENAI_NOT_CONFIGURED", false);
  const response = await fetch("https://api.openai.com/v1/responses", { method: "POST", headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" }, body: JSON.stringify({
    model,
    input: [
      { role: "system", content: "You extract Korean cooking recipes from transcripts. Never invent missing quantities or times; use null and UNKNOWN. Return steps in cooking order and preserve useful video timestamps." },
      { role: "user", content: `영상 제목: ${videoTitle ?? "알 수 없음"}\n\n자막:\n${transcript}` },
    ],
    text: { format: { type: "json_schema", name: "recipe_extraction", strict: true, schema: recipeSchema } },
  }) });
  if (!response.ok) throw new WorkerError("AI_PROVIDER_UNAVAILABLE", response.status >= 500 || response.status === 429);
  const payload = await response.json() as { status?: string; output?: Array<{ content?: Array<{ type?: string; text?: string; refusal?: string }> }> };
  if (payload.status !== "completed") throw new WorkerError("AI_RESPONSE_INCOMPLETE", true);
  const content = payload.output?.flatMap((item) => item.content ?? []).find((item) => item.type === "output_text");
  if (!content?.text) throw new WorkerError(content?.refusal ? "AI_RESPONSE_REFUSED" : "AI_RESPONSE_INVALID", false);
  return JSON.parse(content.text) as Recipe;
}

function validateRecipe(recipe: Recipe): void {
  if (!recipe.title?.trim() || !recipe.ingredients?.length || !recipe.steps?.length) throw new WorkerError("SOURCE_INSUFFICIENT", false);
  if (recipe.ingredients.some((item) => !item.name?.trim()) || recipe.steps.some((item) => !item.instruction?.trim())) throw new WorkerError("AI_RESPONSE_INVALID", false);
}

class WorkerError extends Error {
  constructor(public code: string, public retryable: boolean) { super(code); }
  get userMessage(): string {
    const messages: Record<string, string> = {
      TRANSCRIPT_PROVIDER_NOT_CONFIGURED: "자막 수집 서비스 설정이 필요합니다.", OPENAI_NOT_CONFIGURED: "AI 분석 서비스 설정이 필요합니다.",
      TRANSCRIPT_UNAVAILABLE: "영상 자막을 가져오지 못했습니다.", SOURCE_INSUFFICIENT: "레시피를 만들 만큼 충분한 요리 정보를 찾지 못했습니다.",
      AI_PROVIDER_UNAVAILABLE: "AI 분석 서비스가 일시적으로 응답하지 않습니다.", AI_RESPONSE_REFUSED: "이 영상은 AI가 분석할 수 없습니다.",
    };
    return messages[this.code] ?? "레시피 분석에 실패했습니다.";
  }
}

function fixtureTranscript(): string { return "[00:00] 김치볶음밥을 만듭니다. [00:10] 밥 한 공기와 김치 반 컵을 준비합니다. [00:30] 팬에 식용유 한 큰술을 두르고 김치를 2분 볶습니다. [02:30] 밥을 넣고 중불에서 3분 볶습니다."; }
function fixtureRecipe(): Recipe { return {
  title: "김치볶음밥", servingsValue: 1, servingsConfidence: "CONFIRMED", totalTimeMinutes: 6, totalTimeConfidence: "INFERRED", validationStatus: "VALID",
  ingredients: [
    { name: "밥", quantity: 1, quantityText: "한 공기", unit: "공기", preparation: null, isOptional: false, confidence: "CONFIRMED", evidenceText: "밥 한 공기", evidenceStartSeconds: 10 },
    { name: "김치", quantity: 0.5, quantityText: "반 컵", unit: "컵", preparation: null, isOptional: false, confidence: "CONFIRMED", evidenceText: "김치 반 컵", evidenceStartSeconds: 10 },
    { name: "식용유", quantity: 1, quantityText: "한 큰술", unit: "큰술", preparation: null, isOptional: false, confidence: "CONFIRMED", evidenceText: "식용유 한 큰술", evidenceStartSeconds: 30 },
  ],
  steps: [
    { instruction: "팬에 식용유를 두르고 김치를 볶는다.", durationSeconds: 120, heatLevel: null, cautions: [], startTimestampSeconds: 30, endTimestampSeconds: 150, confidence: "CONFIRMED" },
    { instruction: "밥을 넣고 중불에서 볶는다.", durationSeconds: 180, heatLevel: "중불", cautions: [], startTimestampSeconds: 150, endTimestampSeconds: 330, confidence: "CONFIRMED" },
  ],
}; }

const nullableNumber = { type: ["number", "null"] }, nullableInteger = { type: ["integer", "null"] }, nullableString = { type: ["string", "null"] };
const confidence = { type: "string", enum: ["CONFIRMED", "INFERRED", "UNKNOWN"] };
const recipeSchema = { type: "object", additionalProperties: false, required: ["title", "servingsValue", "servingsConfidence", "totalTimeMinutes", "totalTimeConfidence", "validationStatus", "ingredients", "steps"], properties: {
  title: { type: "string" }, servingsValue: nullableNumber, servingsConfidence: confidence, totalTimeMinutes: nullableInteger, totalTimeConfidence: confidence, validationStatus: { type: "string", enum: ["VALID", "NEEDS_REVIEW"] },
  ingredients: { type: "array", items: { type: "object", additionalProperties: false, required: ["name", "quantity", "quantityText", "unit", "preparation", "isOptional", "confidence", "evidenceText", "evidenceStartSeconds"], properties: { name: { type: "string" }, quantity: nullableNumber, quantityText: nullableString, unit: nullableString, preparation: nullableString, isOptional: { type: "boolean" }, confidence, evidenceText: nullableString, evidenceStartSeconds: nullableInteger } } },
  steps: { type: "array", items: { type: "object", additionalProperties: false, required: ["instruction", "durationSeconds", "heatLevel", "cautions", "startTimestampSeconds", "endTimestampSeconds", "confidence"], properties: { instruction: { type: "string" }, durationSeconds: nullableInteger, heatLevel: nullableString, cautions: { type: "array", items: { type: "string" } }, startTimestampSeconds: nullableInteger, endTimestampSeconds: nullableInteger, confidence } } },
} };
