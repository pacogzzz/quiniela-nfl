-- 012_fix_search_path_extensions.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql (y en 010_racha_premios.sql), que son la fuente de
-- verdad.
--
-- QUE ARREGLA
-- ===========
-- generar_folios() y reclamar_racha() son SECURITY DEFINER con
-- `SET search_path = public`. En un Supabase real, las funciones de
-- pgcrypto (gen_random_bytes, gen_random_uuid) viven en el esquema
-- "extensions", no en "public" -- asi que dentro de esas funciones,
-- Postgres no las encuentra y truena con:
--
--   function gen_random_bytes(integer) does not exist
--
-- En las pruebas locales (PGlite) no se nota porque ahi pgcrypto queda
-- instalado directo en public. Se corrige agregando "extensions" al
-- search_path de las dos funciones -- son un CREATE OR REPLACE, corren
-- sin tocar datos ni permisos.

BEGIN;

CREATE OR REPLACE FUNCTION generar_folios(p_fecha DATE, p_cantidad INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_role  TEXT;
  v_pts   INT;
  v_code  TEXT;
  v_out   TEXT[] := '{}';
  i       INT;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role NOT IN ('admin','manager') THEN
    RETURN json_build_object('ok', false, 'msg', 'Sin permiso');
  END IF;
  IF p_cantidad < 1 OR p_cantidad > 500 THEN
    RETURN json_build_object('ok', false, 'msg', 'Cantidad debe ser 1-500');
  END IF;

  v_pts := puntos_por_fecha(p_fecha);

  FOR i IN 1..p_cantidad LOOP
    LOOP
      v_code := 'LC' || TO_CHAR(p_fecha,'MMDD') || '-' ||
                UPPER(SUBSTRING(encode(gen_random_bytes(4),'hex') FROM 1 FOR 5));
      EXIT WHEN NOT EXISTS (SELECT 1 FROM folios WHERE code = v_code);
    END LOOP;
    INSERT INTO folios (code, fecha, puntos) VALUES (v_code, p_fecha, v_pts);
    v_out := array_append(v_out, v_code);
  END LOOP;

  RETURN json_build_object('ok', true, 'puntos', v_pts, 'codes', v_out);
END $$;

-- Solo aplica si ya corriste 010_racha_premios.sql; si no lo has corrido
-- todavia, este CREATE OR REPLACE simplemente no encuentra la funcion
-- anterior que reemplazar y crea la version buena directo -- no truena.
CREATE OR REPLACE FUNCTION reclamar_racha()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  uid UUID := auth.uid();
  v_racha INT;
  v_nivel_max INT;
  n INT;
  v_codigo TEXT;
  v_insertado RECORD;
  nuevos JSONB := '[]'::JSONB;
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  v_racha := racha_semanas_de(uid);
  v_nivel_max := racha_nivel_de(v_racha);

  FOR n IN 1..v_nivel_max LOOP
    v_codigo := 'RACHA-' || UPPER(SUBSTR(MD5(gen_random_uuid()::TEXT), 1, 6));

    INSERT INTO racha_premios (user_id, nivel, racha, premio, codigo)
    VALUES (uid, n, v_racha, racha_premio_de(n), v_codigo)
    ON CONFLICT (user_id, nivel) DO NOTHING
    RETURNING nivel, racha, premio, codigo INTO v_insertado;

    IF FOUND THEN
      nuevos := nuevos || jsonb_build_object(
        'nivel', v_insertado.nivel, 'racha', v_insertado.racha,
        'premio', v_insertado.premio, 'codigo', v_insertado.codigo
      );
    END IF;
  END LOOP;

  RETURN json_build_object('ok', true, 'racha', v_racha, 'nivel', v_nivel_max, 'nuevos', nuevos);
END $$;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT generar_folios(CURRENT_DATE, 1);
--   -- debe responder {"ok":true, ...} y NO el error de gen_random_bytes
