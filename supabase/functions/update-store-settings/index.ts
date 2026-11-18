// @ts-ignore Deno resolves this URL import; standard TypeScript tooling may not.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const deno = (globalThis as typeof globalThis & {
  Deno: {
    serve: (handler: (req: Request) => Response | Promise<Response>) => void;
    env: { get(name: string): string | undefined };
  };
}).Deno;

deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = deno.env.get("SUPABASE_URL");
  const anonKey = deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration is incomplete" }, 500);

  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return json({ error: "Login session is required" }, 401);

  let body: { password?: string; settings?: Record<string, unknown> };
  try { body = await req.json(); } catch { return json({ error: "Invalid request body" }, 400); }
  if (typeof body.password !== "string" || body.password.length < 1 || body.password.length > 256) {
    return json({ error: "Password is required" }, 400);
  }
  const allowed = ["store_name", "whatsapp_number", "whatsapp_number_putra", "whatsapp_number_putri", "bank_name", "bank_account_number", "bank_account_name", "payment_instructions"];
  if (!body.settings || typeof body.settings !== "object" || Array.isArray(body.settings)) return json({ error: "Settings are required" }, 400);
  const keys = Object.keys(body.settings);
  if (keys.some((key) => !allowed.includes(key))) return json({ error: "Unsupported setting field" }, 400);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user?.email) return json({ error: "Session is invalid or expired" }, 401);

  const { data: profile, error: profileError } = await admin.from("profiles")
    .select("role").eq("id", userData.user.id).maybeSingle();
  if (profileError || profile?.role !== "super_admin") return json({ error: "Super Admin access is required" }, 403);

  const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: passwordError } = await verifier.auth.signInWithPassword({
    email: userData.user.email,
    password: body.password,
  });
  if (passwordError) return json({ error: "Password is incorrect. No changes were saved." }, 401);

  const { error: updateError } = await admin.from("store_settings").update(body.settings).eq("id", true);
  if (updateError) return json({ error: "Failed to save settings" }, 500);
  return json({ success: true });
});
