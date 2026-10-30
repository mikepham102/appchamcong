// HongCha HRM — Edge Function: create-employee
// V84.33 (30/10/2026)
//
// Trước: chỉ Owner được tạo nhân viên (`caller.role !== "owner"` => FORBIDDEN),
//        nên Manager dù đã được cấp quyền `employee_create` vẫn không lưu được.
// Sau:   - Owner: tạo nhân viên cho chi nhánh đang làm việc.
//        - Manager: được tạo KHI có quyền `employee_create` bật tại chính chi nhánh đó,
//          và đang có membership manager active tại chi nhánh đó.
//        - Nhân viên mới luôn thuộc chi nhánh của người tạo (không nhận store_id từ client).
//        - audit_logs ghi kèm store_id của chi nhánh.
//
// Giữ nguyên toàn bộ hành vi cũ: gửi email mời, hoàn tác nếu tạo hồ sơ lỗi,
// hoàn tác nếu ghi audit lỗi, kiểm tra email/trùng email/lương.

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

const STAFF_ROLES = ["owner", "manager"];

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

    if (caller.employment_status !== "active") return json({ error: "FORBIDDEN" }, 403);
    if (!STAFF_ROLES.includes(caller.role)) return json({ error: "FORBIDDEN" }, 403);
    if (!caller.store_id) return json({ error: "CALLER_NO_STORE" }, 400);

    // Người tạo phải đang có quyền đúng vai trò tại chi nhánh đang làm việc.
    const { data: membership, error: membershipError } = await admin
      .from("store_memberships")
      .select("id")
      .eq("user_id", callerId)
      .eq("store_id", caller.store_id)
      .eq("role", caller.role)
      .eq("is_active", true)
      .maybeSingle();
    if (membershipError || !membership) return json({ error: "FORBIDDEN" }, 403);

    // Manager chỉ được tạo khi chi nhánh bật quyền employee_create.
    if (caller.role === "manager") {
      const { data: permission, error: permissionError } = await admin
        .from("manager_permissions")
        .select("enabled")
        .eq("store_id", caller.store_id)
        .eq("permission_key", "employee_create")
        .maybeSingle();
      if (permissionError || permission?.enabled !== true) return json({ error: "FORBIDDEN" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const full_name = String(body.full_name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const phone = String(body.phone || "").trim();
    const hourly_rate = Number(body.hourly_rate ?? 0);

    if (!full_name) return json({ error: "FULL_NAME_REQUIRED" }, 400);
    if (!/^\S+@\S+\.\S+$/.test(email)) return json({ error: "EMAIL_INVALID" }, 400);
    if (!Number.isFinite(hourly_rate) || hourly_rate < 0) return json({ error: "HOURLY_RATE_INVALID" }, 400);
    if (hourly_rate > 100000000) return json({ error: "HOURLY_RATE_TOO_LARGE" }, 400);

    const redirectToRaw = String(body.redirect_to || "").trim();
    const redirectTo = redirectToRaw || undefined;
    const targetStoreId = caller.store_id;

    const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { full_name, role: "employee", store_id: targetStoreId },
      redirectTo,
    });
    if (inviteError || !inviteData?.user) {
      const raw = inviteError?.message || "INVITE_FAILED";
      const lower = raw.toLowerCase();
      if (lower.includes("already") || lower.includes("registered") || lower.includes("exists")) {
        return json({ error: "EMAIL_ALREADY_REGISTERED", detail: raw }, 409);
      }
      return json({ error: "INVITE_FAILED", detail: raw }, 400);
    }
    const newUser = inviteData.user;

    const { error: profileError } = await admin.from("profiles").upsert(
      {
        id: newUser.id,
        email,
        full_name,
        phone: phone || null,
        role: "employee",
        employment_status: "invited",
        hourly_rate,
        store_id: targetStoreId,
      },
      { onConflict: "id" },
    );
    if (profileError) {
      await admin.auth.admin.deleteUser(newUser.id);
      return json({ error: "PROFILE_CREATE_FAILED", detail: profileError.message }, 500);
    }

    const { error: auditError } = await admin.from("audit_logs").insert({
      actor_id: callerId,
      store_id: targetStoreId,
      action: "create_employee_account",
      entity_type: "profile",
      entity_id: newUser.id,
      old_data: null,
      new_data: {
        full_name,
        email,
        phone: phone || null,
        role: "employee",
        employment_status: "invited",
        hourly_rate,
        store_id: targetStoreId,
        created_by_role: caller.role,
      },
    });
    if (auditError) {
      const { error: cleanupProfileError } = await admin.from("profiles").delete().eq("id", newUser.id);
      const { error: cleanupAuthError } = await admin.auth.admin.deleteUser(newUser.id);
      return json(
        {
          error: "AUDIT_LOG_FAILED",
          detail: auditError.message,
          cleanup_errors: [cleanupProfileError?.message, cleanupAuthError?.message].filter(Boolean),
        },
        500,
      );
    }

    return json({
      ok: true,
      user_id: newUser.id,
      email,
      status: "invited",
      message: "Employee account created and invitation sent.",
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
