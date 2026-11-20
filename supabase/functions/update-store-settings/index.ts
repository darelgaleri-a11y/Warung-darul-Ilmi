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

const BUCKET = "store-assets";
const LOGO_PATH_PREFIX = "branding/store-logo";
const MAX_LOGO_BYTES = 2 * 1024 * 1024;
const ALLOWED_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);
const ALLOWED_SETTINGS = new Set([
  "store_name", "whatsapp_number", "whatsapp_number_putra", "whatsapp_number_putri",
  "bank_name", "bank_account_number", "bank_account_name", "payment_instructions",
]);

function isValidImage(bytes: Uint8Array, contentType: string): boolean {
  if (contentType === "image/png") return bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a;
  if (contentType === "image/jpeg") return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (contentType === "image/webp") return bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP";
  return false;
}

function getLogoStoragePath(publicUrl: unknown): string | null {
  if (typeof publicUrl !== "string" || !publicUrl.trim()) return null;
  try {
    const parsed = new URL(publicUrl);
    const marker = `/storage/v1/object/public/${BUCKET}/`;
    const markerIndex = parsed.pathname.indexOf(marker);
    if (markerIndex < 0) return null;
    const path = decodeURIComponent(parsed.pathname.slice(markerIndex + marker.length));
    return path.startsWith("branding/") ? path : null;
  } catch {
    return null;
  }
}

deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = deno.env.get("SUPABASE_URL");
  const anonKey = deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "Server configuration is incomplete" }, 500);

  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return json({ error: "Login session is required" }, 401);

  type LogoPayload = { contentType?: string; base64?: string };
  type RequestBody = { password?: string; settings?: Record<string, unknown>; logo?: LogoPayload | null; removeLogo?: boolean };
  let body: RequestBody;
  try { body = await req.json(); } catch { return json({ error: "Invalid request body" }, 400); }

  if (typeof body.password !== "string" || body.password.length < 1 || body.password.length > 256) return json({ error: "Password is required" }, 400);
  if (!body.settings || typeof body.settings !== "object" || Array.isArray(body.settings)) return json({ error: "Settings are required" }, 400);
  if (Object.keys(body.settings).some((key) => !ALLOWED_SETTINGS.has(key))) return json({ error: "Unsupported setting field" }, 400);
  if (body.logo && body.removeLogo) return json({ error: "Choose either a new logo or remove the current logo" }, 400);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user?.email) return json({ error: "Session is invalid or expired" }, 401);
  const { data: profile, error: profileError } = await admin.from("profiles").select("role").eq("id", userData.user.id).maybeSingle();
  if (profileError || profile?.role !== "super_admin") return json({ error: "Super Admin access is required" }, 403);

  const verifier = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: passwordError } = await verifier.auth.signInWithPassword({ email: userData.user.email, password: body.password });
  if (passwordError) return json({ error: "Password is incorrect. No changes were saved." }, 401);

  const updates: Record<string, unknown> = { ...body.settings };
  const storage = admin.storage.from(BUCKET);
  const logoChangeRequested = Boolean(body.logo) || body.removeLogo === true;
  let previousLogoPath: string | null = null;
  let uploadedLogoPath: string | null = null;

  if (logoChangeRequested) {
    const { data: currentSettings, error: currentSettingsError } = await admin.from("store_settings")
      .select("brand_logo_url").eq("id", true).maybeSingle();
    if (currentSettingsError || !currentSettings) {
      return json({ error: "Could not read the current store settings. No logo changes were made." }, 500);
    }
    previousLogoPath = getLogoStoragePath(currentSettings.brand_logo_url);
  }

  if (body.logo) {
    const contentType = body.logo.contentType || "";
    const encoded = body.logo.base64 || "";
    if (!ALLOWED_TYPES.has(contentType)) return json({ error: "Logo must be PNG, JPG, or WebP" }, 400);
    if (!encoded || encoded.length > Math.ceil(MAX_LOGO_BYTES * 4 / 3) + 8 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) return json({ error: "Logo is empty or exceeds the 2 MB limit" }, 413);

    let bytes: Uint8Array;
    try { bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0)); } catch { return json({ error: "Logo data is invalid" }, 400); }
    if (bytes.byteLength > MAX_LOGO_BYTES) return json({ error: "Logo exceeds the 2 MB limit" }, 413);
    if (!isValidImage(bytes, contentType)) return json({ error: "The file content does not match its image type" }, 400);

    const extension = contentType === "image/png" ? "png" : contentType === "image/jpeg" ? "jpg" : "webp";
    uploadedLogoPath = `${LOGO_PATH_PREFIX}-${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await storage.upload(uploadedLogoPath, bytes, { contentType, cacheControl: "3600", upsert: false });
    if (uploadError) return json({ error: "Failed to upload the logo. Check the store-assets bucket migration." }, 500);

    const { data: publicData } = storage.getPublicUrl(uploadedLogoPath);
    updates.brand_logo_url = publicData.publicUrl;
  } else if (body.removeLogo === true) {
    updates.brand_logo_url = null;
  }

  const { data: savedSettings, error: updateError } = await admin.from("store_settings")
    .update(updates).eq("id", true).select("id").maybeSingle();
  if (updateError || !savedSettings) {
    if (uploadedLogoPath) {
      const { error: cleanupError } = await storage.remove([uploadedLogoPath]);
      if (cleanupError) {
        return json({ error: "Failed to save settings. The previous logo is still active, but temporary logo cleanup also failed." }, 500);
      }
    }
    return json({ error: updateError ? "Failed to save settings. The previous logo was kept." : "Store settings row was not updated. The previous logo was kept." }, 500);
  }

  // The database now points to the new URL (or null), so it is safe to remove the old file.
  if (previousLogoPath && previousLogoPath !== uploadedLogoPath) {
    const { error: removeError } = await storage.remove([previousLogoPath]);
    if (removeError) {
      return json({ error: "Settings were saved successfully, but the previous logo file could not be deleted. The new logo is active; ask an administrator to remove the unused old file from Storage." }, 500);
    }
  }

  return json({ success: true });
});
