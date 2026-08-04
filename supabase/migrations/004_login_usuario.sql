-- =====================================================================
-- 004_login_usuario.sql · ENTRAR CON USUARIO Y CONTRASEÑA
--
-- QUE ES ESTO
-- Todo lo de aqui ya vive dentro de 001_init.sql. Este archivo existe solo
-- para la base que YA esta desplegada en Supabase: le aplica nada mas lo
-- nuevo, sin volver a correr la migracion completa.
--
-- COMO SE CORRE
--   Supabase -> SQL Editor -> New query -> pegar todo -> Run
--
-- Es idempotente: correrlo dos veces no rompe nada.
--
-- ⚠️ ADEMAS DE ESTO HAY QUE APAGAR UNA OPCION EN EL PANEL (ver el final).
--
-- QUE AGREGA
--   1. La columna `usuario` en profiles, unica sin importar mayusculas
--   2. correo_de_usuario()  -> para entrar escribiendo el usuario
--   3. usuario_disponible() -> para avisar si un usuario ya esta ocupado
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La columna del usuario
-- ---------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS usuario TEXT;

-- Unico sin importar mayusculas: "PacoG" y "pacog" son el mismo usuario.
-- Si no, dos personas podrian registrar el mismo nombre escrito distinto.
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_usuario
  ON profiles(lower(usuario)) WHERE usuario IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Traducir usuario -> correo
--
-- Supabase solo sabe autenticar por correo. Para que la gente pueda entrar
-- escribiendo su usuario, el front consulta aqui primero.
--
-- La puede llamar gente SIN sesion, porque se usa justo antes de iniciarla.
-- Solo responde con el usuario EXACTO: no deja listar ni buscar por partes.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION correo_de_usuario(p_usuario TEXT)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT email FROM profiles WHERE lower(usuario) = lower(trim(p_usuario))
$$;
GRANT EXECUTE ON FUNCTION correo_de_usuario(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Avisar si el usuario ya esta ocupado, ANTES de crear la cuenta
--    (si no, quedarian cuentas sin perfil, que es un problema conocido
--     de este proyecto)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION usuario_disponible(p_usuario TEXT)
RETURNS BOOL LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM profiles WHERE lower(usuario) = lower(trim(p_usuario))
  )
$$;
GRANT EXECUTE ON FUNCTION usuario_disponible(TEXT) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Verificacion — deben salir 3 renglones en TRUE
-- ---------------------------------------------------------------------
SELECT 'la columna usuario existe' AS revision,
       EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name='profiles' AND column_name='usuario') AS ok
UNION ALL
SELECT 'el usuario no se puede repetir',
       EXISTS (SELECT 1 FROM pg_indexes
               WHERE tablename='profiles' AND indexname='idx_profiles_usuario')
UNION ALL
SELECT 'se puede entrar con usuario',
       to_regprocedure('public.correo_de_usuario(text)') IS NOT NULL;

-- =====================================================================
-- ⚠️ FALTA UN PASO EN EL PANEL, SIN EL NO FUNCIONA NADA
--
--   Supabase -> Authentication -> Providers -> Email
--   -> APAGA la opcion "Confirm email"
--
-- Con esa opcion encendida, Supabase obliga a confirmar por correo antes de
-- dejar entrar, que es justo el sistema de enlaces que estamos quitando.
-- Apagada, el jugador se registra y entra de inmediato.
--
-- (Deja ENCENDIDO el proveedor de Email; lo unico que se apaga es la
--  confirmacion. El correo se sigue usando para recuperar la contrasena.)
-- =====================================================================
