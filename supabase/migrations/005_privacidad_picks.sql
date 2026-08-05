-- 005_privacidad_picks.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. El cambio equivalente
-- vive tambien en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas. Los dos lados tienen que decir lo mismo.
--
-- QUE ARREGLA
-- ===========
-- La politica anterior era literalmente:
--     CREATE POLICY "picks read" ON picks FOR SELECT TO authenticated USING (true);
--
-- USING (true) quiere decir "cualquiera con sesion ve TODAS las filas". Como la
-- quiniela es abierta y la llave anon es publica, cualquier participante podia
-- leer los pronosticos de los otros ~200 ANTES del kickoff con UNA sola consulta
-- a la API. En una quiniela de confianza eso es ventaja directa, y con dinero de
-- por medio es el hueco mas caro que podia tener el proyecto.
--
-- No lo cacharon las pruebas porque la que existia ("NO puede ver pronosticos
-- ajenos") corria como VISITANTE SIN CUENTA, y anon efectivamente no puede. El
-- caso que faltaba era el participante CON sesion. Ya quedo cubierto en rls.mjs.
--
-- REGLA NUEVA
-- ===========
-- 1. Cada quien ve siempre los suyos.
-- 2. Admin y manager ven todos (los necesitan para operar y auditar).
-- 3. Los ajenos se destapan SOLOS cuando el partido arranca. Despues del kickoff
--    el pronostico ya no se puede cambiar, asi que no queda ventaja que robar, y
--    la gracia de la quiniela es justamente ver que puso cada quien.
--
-- El punto 3 es la razon de amarrar la regla a games.kickoff y no a un switch
-- manual: nadie tiene que acordarse de destapar nada.

DROP POLICY IF EXISTS "picks read" ON picks;
CREATE POLICY "picks read" ON picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
    OR EXISTS (
      SELECT 1 FROM games g
      WHERE g.id = picks.game_id
        AND g.kickoff <= NOW()
    )
  );

-- Mismo razonamiento para el underdog. Aqui el "ya no se puede cambiar" ocurre
-- cuando el admin cierra la semana (abierto = FALSE) o cuando arranca alguno de
-- los partidos en juego, lo que pase primero.
DROP POLICY IF EXISTS "up read" ON underdog_picks;
CREATE POLICY "up read" ON underdog_picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
    OR EXISTS (
      SELECT 1 FROM underdog_weeks uw
      WHERE uw.week = underdog_picks.week
        AND (
          uw.abierto = FALSE
          OR EXISTS (
            SELECT 1 FROM games g
            WHERE g.id IN (uw.opt_a_game, uw.opt_b_game, uw.opt_c_game)
              AND g.kickoff <= NOW()
          )
        )
    )
  );
