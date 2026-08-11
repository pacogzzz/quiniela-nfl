-- 009_cierre_semana.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas.
--
-- QUE AGREGA
-- ==========
-- La pantalla obligatoria de "cierre de semana" (resumen de la week que
-- acaba de terminar) necesita dos cosas que todavia no existian:
--
-- 1. Saber que semana fue la ultima que cada quien ya vio, para no
--    volver a mostrarle el mismo resumen ni saltarse una semana que
--    todavia no ha visto. Una columna en `profiles`, nada mas: cada quien
--    puede actualizar SU propia fila (la politica "profiles update" de
--    001_init.sql ya lo permite, no hace falta ninguna politica nueva).
--
-- 2. Cuantos partidos acerto CADA usuario en CADA semana, para el
--    porcentaje de "fuiste del X% de la liga" y para armar el resumen.
--    Esto exige agregar datos de TODOS los usuarios sin exponer los
--    pronosticos de nadie -- exactamente el mismo problema que ya resolvio
--    la vista `ranking` (ver 005_privacidad_picks.sql). La vista nueva usa
--    el mismo patron: agrega por usuario y semana, nunca devuelve el
--    pronostico individual de un partido.

BEGIN;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS ultima_week_vista INT NOT NULL DEFAULT 0;

-- Aciertos (y partidos jugados) de cada usuario, por semana. Misma logica
-- de "quien gano" que ya usa la vista `ranking`: score_a vs score_b decide
-- el ganador real, y se compara contra el pronostico guardado.
CREATE OR REPLACE VIEW aciertos_semana AS
SELECT
  pk.user_id,
  g.week,
  COUNT(*) FILTER (
    WHERE g.score_a IS NOT NULL
      AND g.score_a <> g.score_b
      AND pk.ganador = (CASE WHEN g.score_a > g.score_b THEN 'A' ELSE 'B' END)
  ) AS aciertos,
  COUNT(*) FILTER (
    WHERE g.score_a IS NOT NULL AND g.score_a <> g.score_b
  ) AS jugados
FROM picks pk
JOIN games g ON g.id = pk.game_id
GROUP BY pk.user_id, g.week;

GRANT SELECT ON aciertos_semana TO authenticated;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='profiles' AND column_name='ultima_week_vista';
--
--   SELECT * FROM aciertos_semana ORDER BY week, aciertos DESC LIMIT 10;
