-- =====================================================================
-- 003_bonos.sql · BONOS (puntos otorgados a mano)
--
-- QUE ES ESTO
-- Todo lo de aqui ya vive dentro de 001_init.sql, que es el archivo que
-- manda y el unico que corren las pruebas. Este archivo existe solo para
-- la base de datos que YA esta desplegada en Supabase: le aplica nada mas
-- lo nuevo, sin volver a correr la migracion completa.
--
-- COMO SE CORRE
--   Supabase -> SQL Editor -> New query -> pegar todo -> Run
--
-- Es idempotente: correrlo dos veces no rompe nada.
--
-- QUE AGREGA
--   1. La tabla `bonos` (cuarta forma de ganar puntos)
--   2. La llave de config pts_bono_instalacion = 25
--   3. La funcion otorgar_bono_instalacion()
--   4. La vista `ranking` recalculada para sumar los bonos
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Llave de configuracion
-- ---------------------------------------------------------------------
INSERT INTO config (clave, valor, etiqueta) VALUES
  ('pts_bono_instalacion','25','Puntos de regalo por instalar la app en el teléfono')
ON CONFLICT (clave) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Tabla
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bonos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  motivo     TEXT NOT NULL,
  puntos     INT  NOT NULL,
  creado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bonos_user ON bonos(user_id);

-- El bono de instalacion se cobra UNA sola vez por persona. Los demas
-- motivos si se pueden repetir.
CREATE UNIQUE INDEX IF NOT EXISTS idx_bonos_instalacion_unico
  ON bonos(user_id) WHERE motivo = 'instalacion';

-- ---------------------------------------------------------------------
-- 3. RLS + politicas
--    (RLS dice CUALES filas; los GRANT de abajo dicen SI SE PUEDE TOCAR
--     la tabla. Hacen falta los dos.)
-- ---------------------------------------------------------------------
ALTER TABLE bonos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bonos read" ON bonos;
DROP POLICY IF EXISTS "bonos ins"  ON bonos;
DROP POLICY IF EXISTS "bonos del"  ON bonos;
CREATE POLICY "bonos read" ON bonos FOR SELECT TO authenticated USING (true);
CREATE POLICY "bonos ins"  ON bonos FOR INSERT TO authenticated
  WITH CHECK (mi_rol() IN ('admin','manager'));
CREATE POLICY "bonos del"  ON bonos FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

-- ---------------------------------------------------------------------
-- 4. GRANT  <- sin esto la app responde "permission denied for table"
--             aunque las politicas de arriba esten perfectas
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, DELETE ON bonos TO authenticated;

-- OJO con este REVOKE, no sobra.
-- 001_init.sql termina con un ALTER DEFAULT PRIVILEGES que le da
-- SELECT/INSERT/UPDATE/DELETE a `authenticated` sobre toda tabla que se cree
-- DESPUES. Como esta migracion corre despues, `bonos` heredaria UPDATE sin
-- que nadie lo pidiera, y la base migrada quedaria con permisos distintos a
-- una instalacion nueva. (De todos modos RLS lo frena, porque no hay politica
-- de UPDATE, pero los dos candados deben decir lo mismo.)
REVOKE UPDATE ON bonos FROM authenticated;

-- Y lo mismo con los visitantes sin cuenta: el ALTER DEFAULT PRIVILEGES de
-- 001 tambien reparte SELECT a `anon`. RLS igual les devuelve 0 filas (no hay
-- politica de lectura para anon), pero que la tabla ni siquiera se les abra.
REVOKE ALL ON bonos FROM anon;

-- ---------------------------------------------------------------------
-- 5. La RPC que cobra el bono de instalacion
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION otorgar_bono_instalacion()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid UUID; v_pts INT;
BEGIN
  -- auth.uid() y no current_user: dentro de SECURITY DEFINER current_user es
  -- el DUENO de la funcion (postgres), no quien la llama.
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  v_pts := cfg_int('pts_bono_instalacion', 25);

  INSERT INTO bonos (user_id, motivo, puntos)
  VALUES (uid, 'instalacion', v_pts)
  ON CONFLICT (user_id) WHERE motivo = 'instalacion' DO NOTHING;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', true, 'ya', true, 'puntos', 0);
  END IF;
  RETURN json_build_object('ok', true, 'ya', false, 'puntos', v_pts);
END $$;
GRANT EXECUTE ON FUNCTION otorgar_bono_instalacion() TO authenticated;

-- ---------------------------------------------------------------------
-- 6. Vista de ranking, ahora con los bonos
--    (identica a la de 001_init.sql; se repite entera porque CREATE OR
--     REPLACE VIEW no permite agregar columnas a medias)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS ranking;
CREATE VIEW ranking AS
WITH conf AS (
  SELECT
    pk.user_id,
    COALESCE(SUM(
      CASE
        WHEN g.score_a IS NOT NULL
         AND g.score_a <> g.score_b
         AND pk.ganador = (CASE WHEN g.score_a > g.score_b THEN 'A' ELSE 'B' END)
        THEN
          CASE cfg_text('conf_mode','additive')
            WHEN 'flat' THEN (CASE WHEN g.is_special
                                   THEN cfg_int('pts_win_especial',15)
                                   ELSE cfg_int('pts_win_normal',5) END)
            WHEN 'solo' THEN COALESCE(pk.confianza,0)
            ELSE (CASE WHEN g.is_special
                       THEN cfg_int('pts_win_especial',15)
                       ELSE cfg_int('pts_win_normal',5) END)
                 + COALESCE(pk.confianza,0)
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
  SELECT por_user_id AS user_id, COALESCE(SUM(puntos),0) AS pts_consumo
  FROM folios WHERE usado AND por_user_id IS NOT NULL
  GROUP BY por_user_id
),
und AS (
  SELECT
    up.user_id,
    COALESCE(SUM(
      CASE
        WHEN up.opcion = 'A' AND underdog_acierto(uw.opt_a_game, uw.opt_a_team) THEN uw.puntos
        WHEN up.opcion = 'B' AND underdog_acierto(uw.opt_b_game, uw.opt_b_team) THEN uw.puntos
        WHEN up.opcion = 'C' AND underdog_acierto(uw.opt_c_game, uw.opt_c_team) THEN uw.puntos
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

-- ---------------------------------------------------------------------
-- 7. Realtime (para que el ranking se mueva solo al dar un bono)
-- ---------------------------------------------------------------------
DO $rt$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE bonos; EXCEPTION WHEN OTHERS THEN NULL; END;
END
$rt$;

-- ---------------------------------------------------------------------
-- 8. Verificacion — debe devolver 4 renglones en TRUE
-- ---------------------------------------------------------------------
SELECT 'tabla bonos existe'      AS revision,
       to_regclass('public.bonos') IS NOT NULL AS ok
UNION ALL
SELECT 'la vista suma pts_bono',
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='ranking' AND column_name='pts_bono')
UNION ALL
SELECT 'los authenticated pueden leer bonos',
       has_table_privilege('authenticated','public.bonos','SELECT')
UNION ALL
SELECT 'existe la llave de config',
       EXISTS (SELECT 1 FROM config WHERE clave='pts_bono_instalacion');
