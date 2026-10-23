import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, idempotency-key, x-client-info, x-request-id",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function error(
  requestId: string,
  code: string,
  message: string,
  status: number,
  retryable = false,
): Response {
  return json({ error: { code, message, retryable }, requestId }, status);
}

export async function requireUser(request: Request): Promise<{
  user: User;
  admin: SupabaseClient;
} | Response> {
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return error(crypto.randomUUID(), "UNAUTHORIZED", "로그인이 필요합니다.", 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publishableKey || !serviceRoleKey) {
    return error(crypto.randomUUID(), "INTERNAL_ERROR", "서버 설정을 확인해 주세요.", 500, true);
  }

  const token = authorization.slice("Bearer ".length);
  const authClient = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data, error: authError } = await authClient.auth.getUser(token);
  if (authError || !data.user) {
    return error(crypto.randomUUID(), "UNAUTHORIZED", "로그인이 만료되었습니다.", 401);
  }

  return {
    user: data.user,
    admin: createClient(url, serviceRoleKey, { auth: { persistSession: false } }),
  };
}
