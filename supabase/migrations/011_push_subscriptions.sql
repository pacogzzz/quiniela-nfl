-- 011_push_subscriptions.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas.
--
-- QUE AGREGA
-- ==========
-- Notificaciones push del navegador (como Facebook o Instagram): cada
-- suscripcion es el "buzon" de un dispositivo (endpoint + llaves de
-- cifrado) que el navegador entrega cuando alguien acepta el permiso. El
-- envio de verdad lo hace la funcion de Supabase `send-push`
-- (supabase/functions/send-push/index.ts), que usa la llave privada VAPID
-- y corre con el service_role, sin pasar por RLS. Esta tabla solo guarda
-- quien quiere recibirlas.

BEGIN;

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint   TEXT NOT NULL UNIQUE,
  p256dh     TEXT NOT NULL,
  auth       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_push_subs_user ON push_subscriptions(user_id);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push subs propia"  ON push_subscriptions;
DROP POLICY IF EXISTS "push subs insert"  ON push_subscriptions;
DROP POLICY IF EXISTS "push subs delete"  ON push_subscriptions;
CREATE POLICY "push subs propia" ON push_subscriptions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR mi_rol() IN ('admin','manager'));
CREATE POLICY "push subs insert" ON push_subscriptions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "push subs delete" ON push_subscriptions FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR mi_rol() = 'admin');

GRANT SELECT, INSERT, DELETE ON push_subscriptions TO authenticated;
REVOKE UPDATE ON push_subscriptions FROM authenticated;
REVOKE ALL ON push_subscriptions FROM anon;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT count(*) FROM push_subscriptions;
