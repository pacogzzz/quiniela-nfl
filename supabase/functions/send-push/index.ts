// send-push/index.ts
//
// Manda una notificación push a TODOS los que ya activaron el permiso en
// el navegador. Solo la puede llamar admin/manager — desde la app, el
// botón "📣 Mandar a todos" del panel de ADMIN es lo único que la invoca
// (mandarNotificacionPush() en index.html), pero esta función revisa el
// permiso por su cuenta: aunque alguien la llamara directo con curl, sin
// ser admin no pasa.
//
// Por qué es una función aparte (Edge Function) y no algo del lado del
// cliente: mandar un push de verdad exige la llave PRIVADA de VAPID, y esa
// llave nunca puede vivir en el navegador — cualquiera con acceso al
// código fuente podría mandar notificaciones a nombre de La Corte. Aquí, en
// cambio, vive como secreto del proyecto (ver README abajo) y nunca sale
// del servidor.
//
// VARIABLES DE ENTORNO QUE NECESITA (Supabase Dashboard → Edge Functions →
// Secrets, o `supabase secrets set`):
//   VAPID_PUBLIC_KEY   — la misma que aparece en index.html (VAPID_PUBLIC_KEY)
//   VAPID_PRIVATE_KEY  — SOLO aquí, nunca en el cliente
// (SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY ya los pone
// Supabase automáticamente en toda Edge Function, no hay que darlos de alta.)

import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

webpush.setVapidDetails(
  "mailto:corporativo@lacorterestaurante.com",
  VAPID_PUBLIC_KEY,
  VAPID_PRIVATE_KEY,
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // service_role: para leer TODAS las suscripciones sin que RLS se lo
  // impida (send-push necesita ver a todo mundo, no solo a quien llama).
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // El cliente propio del usuario que llama: sirve para saber QUIÉN es,
  // usando el token que mandó (nunca confiar en un user_id que venga en el
  // body — cualquiera podría escribir el que quisiera ahí).
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await caller.auth.getUser();
  if (!user) return json({ ok: false, msg: "No autenticado" }, 401);

  const { data: perfil } = await admin.from("profiles").select("role").eq("id", user.id).single();
  if (!perfil || !["admin", "manager"].includes(perfil.role)) {
    return json({ ok: false, msg: "Sin permiso" }, 403);
  }

  const { title, body, url } = await req.json().catch(() => ({}));
  if (!title || !body) return json({ ok: false, msg: "Falta título o mensaje" }, 400);

  const { data: subs, error } = await admin.from("push_subscriptions").select("*");
  if (error) return json({ ok: false, msg: error.message }, 500);

  let enviados = 0, fallidos = 0;
  await Promise.all((subs ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify({ title, body, url: url || "/" }),
      );
      enviados++;
    } catch (err) {
      fallidos++;
      // 404/410 = el navegador ya invalidó ese buzón (desinstaló la app,
      // borró datos del sitio, etc.). Se borra para no reintentar para
      // siempre contra algo que ya nunca va a funcionar.
      const status = (err as { statusCode?: number }).statusCode;
      if (status === 404 || status === 410) {
        await admin.from("push_subscriptions").delete().eq("id", s.id);
      }
    }
  }));

  return json({ ok: true, enviados, fallidos });
});
