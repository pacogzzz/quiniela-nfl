-- 006_privacidad_bonos.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. El cambio equivalente
-- vive tambien en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas. Los dos lados tienen que decir lo mismo.
--
-- QUE ARREGLA
-- ===========
-- La politica anterior era literalmente:
--     CREATE POLICY "bonos read" ON bonos FOR SELECT TO authenticated USING (true);
--
-- Es el MISMO hueco que ya se cerro en los pronosticos con 005: USING (true)
-- quiere decir "cualquiera con sesion ve TODAS las filas". Como la llave anon
-- es publica y la quiniela es abierta, cualquier participante podia sacar de
-- una consulta la lista completa de bonos de los otros ~200.
--
-- Aqui lo que se filtra no son los puntos —esos ya son publicos, el ranking
-- muestra la columna pts_bono de todo el mundo— sino el MOTIVO, que lo escribe
-- ADMIN a mano y puede decir cualquier cosa: "por ayudar en la cocina",
-- "disculpa por el error del lunes", "cumpleanos". Eso no es dato para que lo
-- lea la banca entera.
--
-- REGLA NUEVA
-- ===========
-- 1. Cada quien ve UNICAMENTE sus propios bonos.
-- 2. Admin y manager ven todos: son quienes los otorgan y quienes tienen que
--    responder cuando alguien reclama por que le sumaron o le quitaron puntos.
--
-- QUE NO SE ROMPE
-- ===============
-- - La tabla de posiciones: sale de la vista `ranking`, que corre con los
--   permisos de su dueno y no pasa por RLS. Los totales de todos se siguen
--   viendo, incluido el desglose de bonos.
-- - El bono de instalacion: lo inserta otorgar_bono_instalacion(), que es
--   SECURITY DEFINER y tampoco pasa por esta politica.
-- - La app leyendo si ya se cobro el bono de instalacion: consulta sus propias
--   filas, que es justo lo que esta politica permite.
--
-- Las politicas de INSERT y DELETE no se tocan: ya eran correctas (solo
-- admin/manager insertan, solo admin borra).

DROP POLICY IF EXISTS "bonos read" ON bonos;
CREATE POLICY "bonos read" ON bonos FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
  );
