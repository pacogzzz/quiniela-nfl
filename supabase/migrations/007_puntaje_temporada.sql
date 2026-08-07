-- 007_puntaje_temporada.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas. Los dos lados tienen que decir lo mismo.
--
-- QUE CAMBIA
-- ==========
-- Decision de La Corte antes de arrancar la temporada 2026-27: el puntaje se
-- simplifica. Ya no hay "puntos por ganador acertado" encima de la confianza.
--
--   ANTES  acertar = 5 (o 15 si era extraordinario) + tu numero de confianza
--   AHORA  acertar = tu numero de confianza, y ya.
--
-- El motivo: con el esquema viejo un partido extraordinario valia 15 + hasta
-- 16 = 31 puntos, casi el doble que uno normal, y eso decidia la quiniela por
-- calendario y no por quien le atina. Ahora los 16 numeros que reparte cada
-- quien son TODO lo que esta en juego por pronosticos: 1+2+...+16 = 136 por
-- week. Los puntos extra de los dias raros ya no vienen del partido sino del
-- consumo, que es lo que a La Corte le interesa premiar.
--
-- 1. conf_mode pasa a 'solo'. Ese modo ya existia y ya estaba probado; no hay
--    que tocar la vista `ranking`, que lo lee en caliente.
-- 2. pts_win_normal y pts_win_especial se BORRAN de la tabla config. Con
--    conf_mode='solo' no se usan, y el panel de ADMIN lista las claves que
--    existen: dejarlas ahi es invitar a que alguien las mueva creyendo que
--    hacen algo. La vista las sigue leyendo con cfg_int(clave, default), asi
--    que borrarlas no truena nada.
-- 3. El folio de dia extraordinario sube de 10 a 15. Es justo el punto
--    anterior: el premio por un miercoles o un sabado se paga por venir al
--    restaurante, no por el pronostico.
-- 4. El underdog deja de pagar lo mismo por las tres opciones.

BEGIN;

-- 1 y 2. La confianza es lo unico que paga por acertar
UPDATE config SET valor = 'solo', updated_at = NOW() WHERE clave = 'conf_mode';
DELETE FROM config WHERE clave IN ('pts_win_normal', 'pts_win_especial');

-- 3. El dia raro se premia en la caja, no en la quiniela
UPDATE config SET valor = '15', updated_at = NOW() WHERE clave = 'pts_folio_especial';

-- 4. UNDERDOG CON TRES VALORES
-- ============================
-- Aclaracion de como funciona, porque se presta a confusion: cada week hay UNA
-- ventana de underdog con TRES candidatos (A, B, C) y cada quien escoge UNO.
-- No son tres oportunidades: es una sola, con tres puertas.
--
-- Lo que cambia es que las tres puertas dejan de pagar igual. Ahora cada
-- opcion trae su propio valor —8, 10 y 12 por omision— para que el underdog
-- mas improbable pague mas y escoger sea de verdad una decision. El techo son
-- 12 puntos, que es lo que se anuncia.
--
-- `puntos` se queda como respaldo: si una week vieja no trae los valores por
-- opcion, se sigue pagando lo que decia esa columna. Nada de recalcular hacia
-- atras una temporada ya jugada.
ALTER TABLE underdog_weeks ADD COLUMN IF NOT EXISTS puntos_a INT;
ALTER TABLE underdog_weeks ADD COLUMN IF NOT EXISTS puntos_b INT;
ALTER TABLE underdog_weeks ADD COLUMN IF NOT EXISTS puntos_c INT;

-- Las weeks que todavia no se juegan estrenan los valores nuevos. Las que ya
-- tienen pronosticos registrados NO se tocan: cambiarles el precio despues de
-- que la gente escogio es cambiarle las reglas al juego a medio partido.
UPDATE underdog_weeks uw
   SET puntos_a = 8, puntos_b = 10, puntos_c = 12, puntos = 12
 WHERE NOT EXISTS (SELECT 1 FROM underdog_picks up WHERE up.week = uw.week);

UPDATE config SET valor = '12', updated_at = NOW() WHERE clave = 'pts_underdog';

-- La vista tiene que pagar lo que dice cada opcion. COALESCE al valor viejo
-- para que las weeks sin valores por opcion sigan cuadrando.
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
  SELECT por_user_id AS user_id, COALESCE(SUM(puntos),0) AS pts_consumo
  FROM folios WHERE usado AND por_user_id IS NOT NULL
  GROUP BY por_user_id
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
ORDER BY total_puntos DESC, p.nombre;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT clave, valor FROM config
--    WHERE clave IN ('conf_mode','pts_folio_especial','pts_underdog',
--                    'pts_win_normal','pts_win_especial');
--
-- Tiene que devolver TRES renglones: conf_mode = solo, pts_folio_especial = 15
-- y pts_underdog = 12. Si aparecen pts_win_normal o pts_win_especial, el
-- DELETE no corrio y los partidos siguen pagando puntos de mas.
--
--   SELECT week, puntos_a, puntos_b, puntos_c FROM underdog_weeks ORDER BY week LIMIT 5;
--
-- Tiene que decir 8, 10 y 12 en las weeks que nadie ha jugado todavia.
