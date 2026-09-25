-- 013_folio_diario_compartido.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad.
--
-- QUE CAMBIA
-- ==========
-- Antes, un folio era de UN SOLO USO TOTAL: en cuanto alguien lo
-- canjeaba, quedaba "usado" para siempre y nadie más lo podía volver a
-- usar. Eso no sirve para un código que se anuncia o se pone en las
-- mesas para TODOS los clientes del día.
--
-- Ahora `folios` es solo el catálogo de códigos por día (normalmente uno
-- solo, "el código del día"), y cada canje individual queda en la tabla
-- nueva `folio_canjes`. La regla de "uno por persona por día" se sigue
-- cumpliendo igual de estricta, solo que ahora vive en un UNIQUE
-- (user_id, fecha) en vez de en el propio código.
--
-- IMPORTANTE: esta migración MIGRA los canjes que ya existan (folios con
-- usado=true) a folio_canjes ANTES de borrar las columnas viejas, para no
-- perder puntos que la gente ya se ganó hoy.

BEGIN;

-- 1. La tabla nueva de canjes individuales.
CREATE TABLE IF NOT EXISTS folio_canjes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code       TEXT NOT NULL REFERENCES folios(code) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fecha      DATE NOT NULL,
  puntos     INT  NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, fecha)
);
CREATE INDEX IF NOT EXISTS idx_folio_canjes_user ON folio_canjes(user_id);

-- 2. Migrar los canjes que ya existían bajo el modelo viejo (si la
-- columna `usado` todavía existe -- esto hace que la migración se pueda
-- correr una sola vez sin tronar si ya no está).
DO $mig$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name='folios' AND column_name='usado') THEN
    INSERT INTO folio_canjes (code, user_id, fecha, puntos, created_at)
    SELECT code, por_user_id, fecha, puntos, COALESCE(usado_at, created_at)
    FROM folios
    WHERE usado = TRUE AND por_user_id IS NOT NULL
    ON CONFLICT (user_id, fecha) DO NOTHING;
  END IF;
END $mig$;

-- 3. La vista `ranking` depende de las columnas viejas (usado/por_user_id):
-- hay que reapuntarla a folio_canjes ANTES de poder borrarlas.
CREATE OR REPLACE VIEW ranking AS
WITH conf AS (
  SELECT
    pk.user_id,
    COALESCE(SUM(
      CASE
        WHEN g.score_a IS NOT NULL
         AND g.score_a <> g.score_b
         AND pk.ganador = (CASE WHEN g.score_a > g.score_b THEN 'A' ELSE 'B' END)
        THEN
          CASE cfg_text('conf_mode','solo')
            WHEN 'flat' THEN (CASE WHEN g.is_special
                                   THEN cfg_int('pts_win_especial',15)
                                   ELSE cfg_int('pts_win_normal',5) END)
            WHEN 'additive' THEN (CASE WHEN g.is_special
                                       THEN cfg_int('pts_win_especial',15)
                                       ELSE cfg_int('pts_win_normal',5) END)
                                 + COALESCE(pk.confianza,0)
            ELSE COALESCE(pk.confianza,0)
          END
        ELSE 0
      END
    ),0) AS pts_confianza,
    COALESCE(SUM(
      CASE
        WHEN g.is_stellar
         AND g.first_scorer IS NOT NULL
         AND pk.primero = g.first_scorer
        THEN cfg_int('pts_anotador',3)
        ELSE 0
      END
    ),0) AS pts_anotador
  FROM picks pk
  JOIN games g ON g.id = pk.game_id
  GROUP BY pk.user_id
),
cons AS (
  SELECT user_id, COALESCE(SUM(puntos),0) AS pts_consumo
  FROM folio_canjes
  GROUP BY user_id
),
und AS (
  SELECT
    up.user_id,
    COALESCE(SUM(
      CASE
        WHEN up.opcion = 'A' AND underdog_acierto(uw.opt_a_game, uw.opt_a_team) THEN COALESCE(uw.puntos_a, uw.puntos)
        WHEN up.opcion = 'B' AND underdog_acierto(uw.opt_b_game, uw.opt_b_team) THEN COALESCE(uw.puntos_b, uw.puntos)
        WHEN up.opcion = 'C' AND underdog_acierto(uw.opt_c_game, uw.opt_c_team) THEN COALESCE(uw.puntos_c, uw.puntos)
        ELSE 0
      END
    ),0) AS pts_underdog
  FROM underdog_picks up
  JOIN underdog_weeks uw ON uw.week = up.week
  GROUP BY up.user_id
),
bon AS (
  SELECT user_id, COALESCE(SUM(puntos),0) AS pts_bono
  FROM bonos
  GROUP BY user_id
)
SELECT
  p.id,
  p.nombre,
  p.email,
  COALESCE(c.pts_confianza,0) AS pts_confianza,
  COALESCE(c.pts_anotador,0)  AS pts_anotador,
  COALESCE(k.pts_consumo,0)   AS pts_consumo,
  COALESCE(u.pts_underdog,0)  AS pts_underdog,
  COALESCE(b.pts_bono,0)      AS pts_bono,
  COALESCE(c.pts_confianza,0) + COALESCE(c.pts_anotador,0)
    + COALESCE(k.pts_consumo,0) + COALESCE(u.pts_underdog,0)
    + COALESCE(b.pts_bono,0) AS total_puntos
FROM profiles p
LEFT JOIN conf c ON c.user_id = p.id
LEFT JOIN cons k ON k.user_id = p.id
LEFT JOIN und  u ON u.user_id = p.id
LEFT JOIN bon  b ON b.user_id = p.id
ORDER BY total_puntos DESC, p.nombre ASC;

GRANT SELECT ON ranking TO authenticated;

-- 4. La política vieja de "folios read" TAMBIÉN depende de por_user_id
-- (además de la vista) -- hay que reemplazarla antes de poder borrar la
-- columna, si no, Postgres se niega con "other objects depend on it".
DROP POLICY IF EXISTS "folios read" ON folios;
CREATE POLICY "folios read" ON folios FOR SELECT TO authenticated
  USING (mi_rol() IN ('admin','manager'));

-- 5. Ahora sí, ya sin nada dependiendo de ellas, fuera las columnas viejas.
DROP INDEX IF EXISTS idx_folios_uno_por_dia;
ALTER TABLE folios DROP COLUMN IF EXISTS usado;
ALTER TABLE folios DROP COLUMN IF EXISTS por_user_id;
ALTER TABLE folios DROP COLUMN IF EXISTS usado_at;

-- 6. canjear_folio(): ya no marca el código como usado; inserta un canje
-- individual, y el candado de verdad es el UNIQUE(user_id,fecha).
CREATE OR REPLACE FUNCTION canjear_folio(p_code TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  f   folios;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  SELECT * INTO f FROM folios WHERE code = UPPER(TRIM(p_code));
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'msg', 'Folio inválido');
  END IF;

  IF EXISTS (SELECT 1 FROM folio_canjes WHERE user_id = uid AND fecha = f.fecha) THEN
    RETURN json_build_object('ok', false, 'msg',
      'Ya canjeaste un folio del ' || TO_CHAR(f.fecha,'DD/MM/YYYY') || '. Es uno por día.');
  END IF;

  BEGIN
    INSERT INTO folio_canjes (code, user_id, fecha, puntos) VALUES (f.code, uid, f.fecha, f.puntos);
  EXCEPTION WHEN unique_violation THEN
    RETURN json_build_object('ok', false, 'msg',
      'Ya canjeaste un folio del ' || TO_CHAR(f.fecha,'DD/MM/YYYY') || '. Es uno por día.');
  END;

  RETURN json_build_object('ok', true, 'puntos', f.puntos,
                           'msg', '+' || f.puntos || ' puntos de consumo');
END $$;

GRANT EXECUTE ON FUNCTION canjear_folio(TEXT) TO authenticated;

-- 7. RLS de folio_canjes: cada quien ve solo lo suyo; admin ve y borra todo.
ALTER TABLE folio_canjes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "folio canjes propia"     ON folio_canjes;
DROP POLICY IF EXISTS "folio canjes admin del"  ON folio_canjes;
CREATE POLICY "folio canjes propia" ON folio_canjes FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR mi_rol() IN ('admin','manager'));
CREATE POLICY "folio canjes admin del" ON folio_canjes FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

GRANT SELECT, DELETE ON folio_canjes TO authenticated;
REVOKE INSERT, UPDATE ON folio_canjes FROM authenticated;
REVOKE ALL ON folio_canjes FROM anon;

DO $rt$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE folio_canjes; EXCEPTION WHEN OTHERS THEN NULL; END;
END $rt$;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT count(*) FROM folio_canjes;                 -- tus canjes de hoy deben seguir aqui
--   SELECT pts_consumo FROM ranking WHERE id = auth.uid(); -- tus puntos de consumo no deben haber cambiado
