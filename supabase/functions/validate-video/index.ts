import { corsHeaders, error, json, requireUser } from "../_shared/http.ts";

function youtubeVideoId(rawUrl: string): string | null {
  try {
    const url = new URL(rawUrl.trim());
    const host = url.hostname.toLowerCase().replace(/^www\./, "");
    let candidate: string | null = null;
    if (host === "youtu.be") {
      candidate = url.pathname.split("/").filter(Boolean)[0] ?? null;
    } else if (host === "youtube.com" || host.endsWith(".youtube.com")) {
      if (url.pathname === "/watch") candidate = url.searchParams.get("v");
      if (["shorts", "live", "embed"].includes(url.pathname.split("/")[1])) {
        candidate = url.pathname.split("/")[2] ?? null;
      }
    }
    return candidate && /^[A-Za-z0-9_-]{11}$/.test(candidate) ? candidate : null;
  } catch {
    return null;
  }
}

Deno.serve(async (request) => {
  const requestId = request.headers.get("X-Request-Id") ?? crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return error(requestId, "METHOD_NOT_ALLOWED", "지원하지 않는 요청입니다.", 405);

  const auth = await requireUser(request);
  if (auth instanceof Response) return auth;

  const body = await request.json().catch(() => null) as { url?: unknown; inputMethod?: unknown } | null;
  if (typeof body?.url !== "string") {
    return error(requestId, "INVALID_REQUEST", "영상 링크를 입력해 주세요.", 400);
  }
  const videoId = youtubeVideoId(body.url);
  if (!videoId) {
    return error(requestId, "INVALID_URL", "올바른 YouTube 영상 링크를 입력해 주세요.", 400);
  }

  const canonicalUrl = `https://www.youtube.com/watch?v=${videoId}`;
  const { data: source, error: databaseError } = await auth.admin
    .from("source_videos")
    .upsert(
      { platform: "YOUTUBE", platform_video_id: videoId, canonical_url: canonicalUrl },
      { onConflict: "platform,platform_video_id" },
    )
    .select("id, canonical_url, platform_video_id, title, channel_name, thumbnail_url, availability")
    .single();
  if (databaseError) {
    console.error("validate-video database error", databaseError.code);
    return error(requestId, "INTERNAL_ERROR", "영상을 확인하지 못했습니다.", 500, true);
  }

  return json({
    data: {
      sourceVideoId: source.id,
      canonicalUrl: source.canonical_url,
      platformVideoId: source.platform_video_id,
      title: source.title,
      channelName: source.channel_name,
      thumbnailUrl: source.thumbnail_url,
      availability: source.availability,
      analysisSupport: "SUPPORTED",
    },
    requestId,
  });
});
