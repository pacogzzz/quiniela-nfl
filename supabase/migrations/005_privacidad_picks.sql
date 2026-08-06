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
-- leer los pronosticos de los otros ~200 con UNA sola consulta a la API. En una
-- quiniela de confianza eso es ventaja directa, y con dinero de por medio es el
-- hueco mas caro que podia tener el proyecto.
--
-- No lo cacharon las pruebas porque la que existia ("NO puede ver pronosticos
-- ajenos") corria como VISITANTE SIN CUENTA, y anon efectivamente no puede. El
-- caso que faltaba era el participante CON sesion. Ya quedo cubierto en rls.mjs.
--
-- REGLA NUEVA
-- ===========
-- 1. Cada quien ve UNICAMENTE los suyos, siempre. Nunca los de nadie mas, ni
--    antes ni despues de los partidos. Decision del dueno de la quiniela.
-- 2. Admin y manager ven todos: lo necesitan para resolver reclamos de puntaje
--    ("yo puse otra cosa") y para auditar.
--
-- La tabla de posiciones NO depende de esto: sale de la vista `ranking`, que
-- corre con los permisos de su dueno y no pasa por RLS. Los totales de todos se
-- siguen viendo; lo que se esconde es el detalle de que puso cada quien.

DROP POLICY IF EXISTS "picks read" ON picks;
CREATE POLICY "picks read" ON picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
  );

-- Mismo criterio para el underdog.
DROP POLICY IF EXISTS "up read" ON underdog_picks;
CREATE POLICY "up read" ON underdog_picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
  );
