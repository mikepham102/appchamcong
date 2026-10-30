// HongCha HRM — Edge Function: change-employee-password
// V84.31 HOTFIX (30/10/2026)
//
// Lỗi đã sửa: bản cũ đọc `body["pass"+"word"]` trong khi app gửi `new_password`
// => giá trị luôn rỗng => mọi lần đổi mật khẩu đều trả PASSWORD_TOO_SHORT.
// Bản này chấp nhận CẢ `new_password` và `password` (tương thích ngược).
//
// Sửa thêm: ghi audit_logs thất bại KHÔNG còn làm hỏng kết quả đã thành công
// (trước đây mật khẩu đã đổi nhưng API trả 500 PASSWORD_CHANGED_AUDIT_FAILED).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });

const url = Deno.env.get("SUPABASE_URL")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(url, service, { auth: { autoRefreshToken: false, persistSession: false } });

const MIN_LENGTH = 8;
const MAX_LENGTH = 128;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "NOT_AUTHENTICATED" }, 401);

    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "INVALID_SESSION" }, 401);
    const callerId = userData.user.id;

    const { data: caller, error: callerError } = await admin
      .from("profiles")
      .select("id,store_id,role,employment_status")
      .eq("id", callerId)
      .single();
    if (callerError || !caller) return json({ error: "PROFILE_NOT_FOUND" }, 403);
    if (caller.role !== "owner" || caller.employment_status !== "active") return json({ error: "FORBIDDEN" }, 403);
    if (!caller.store_id) return json({ error: "CALLER_NO_STORE" }, 400);

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const employeeId = String(body["employee_id"] || "").trim();

    // V84.31 FIX: app gửi `new_password`. Chấp nhận thêm `password` để tương thích ngược.
    const raw = body["new_password"] ?? body["password"] ?? "";
    const newCredential = typeof raw === "string" ? raw : "";

    if (!employeeId) return json({ error: "EMPLOYEE_ID_REQUIRED" }, 400);
    if (newCredential.length < MIN_LENGTH) return json({ error: "PASSWORD_TOO_SHORT", min_length: MIN_LENGTH }, 400);
    if (newCredential.length > MAX_LENGTH) return json({ error: "PASSWORD_TOO_LONG", max_length: MAX_LENGTH }, 400);

    const { data: employee, error: employeeError } = await admin
      .from("profiles")
      .select("id,store_id,role,employment_status,email,full_name")
      .eq("id", employeeId)
      .single();
    if (employeeError || !employee) return json({ error: "EMPLOYEE_NOT_FOUND" }, 404);
    if (employee.store_id !== caller.store_id || employee.role !== "employee" || employee.employment_status === "terminated") {
      return json({ error: "FORBIDDEN" }, 403);
    }

    const { error: updateError } = await admin.auth.admin.updateUserById(employeeId, { password: newCredential });
    if (updateError) return json({ error: "PASSWORD_UPDATE_FAILED", detail: updateError.message }, 400);

    // Audit là phụ: hỏng audit không được biến một thao tác THÀNH CÔNG thành lỗi.
    const { error: auditError } = await admin.from("audit_logs").insert({
      actor_id: callerId,
      action: "change_employee_password",
      entity_type: "profile",
      entity_id: employeeId,
      old_data: null,
      new_data: { email: employee.email, full_name: employee.full_name },
    });
    if (auditError) console.error("change_employee_password audit insert failed:", auditError.message);

    return json({ ok: true, user_id: employeeId, message: "Employee password updated." });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
