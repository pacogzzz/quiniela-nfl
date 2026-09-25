-- 014_racha_vigencia.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad.
--
-- QUE CAMBIA
-- ==========
-- Los premios de racha (racha_premios) ahora VENCEN. Cada premio trae una
-- fecha limite (`expira_at`), la app la muestra en un aviso fijo arriba y
-- el restaurante ya no puede canjear un codigo vencido.
--
--   * expira_at = 23:59:59 (hora de Tampico) del dia N desde que se
--     desbloquea, con N = config `racha_vigencia_dias` (15 por omision;
--     editable desde ADMIN -> Configuracion).
--   * Los premios que YA se habian dado (sin fecha) y siguen sin canjear
--     reciben N dias contados desde HOY: quien lo gano ayer no sabia que
--     vencia, asi que no se le descuenta el tiempo que ya paso.

BEGIN;

ALTER TABLE racha_premios ADD COLUMN IF NOT EXISTS expira_at TIMESTAMPTZ;

INSERT INTO config (clave, valor, etiqueta) VALUES
  ('racha_vigencia_dias', '15', 'Días que tiene el jugador para canjear un premio de racha desde que lo desbloquea')
ON CONFLICT (clave) DO NOTHING;

-- Premios ya otorgados y sin canjear: N dias desde hoy.
UPDATE racha_premios
   SET expira_at = ((NOW() AT TIME ZONE 'America/Mexico_City')::DATE
                    + cfg_int('racha_vigencia_dias', 15) + TIME '23:59:59')
                   AT TIME ZONE 'America/Mexico_City'
 WHERE expira_at IS NULL AND NOT canjeado;

-- reclamar_racha(): igual que antes, pero ahora fija expira_at (y lo
-- devuelve en `nuevos`). search_path incluye "extensions" por
-- gen_random_uuid() (ver 012_fix_search_path_extensions.sql).
CREATE OR REPLACE FUNCTION reclamar_racha()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  uid UUID := auth.uid();
  v_racha INT;
  v_nivel_max INT;
  n INT;
  v_codigo TEXT;
  v_insertado RECORD;
  v_expira TIMESTAMPTZ;
  nuevos JSONB := '[]'::JSONB;
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  v_racha := racha_semanas_de(uid);
  v_nivel_max := racha_nivel_de(v_racha);

  v_expira := ((NOW() AT TIME ZONE 'America/Mexico_City')::DATE
               + cfg_int('racha_vigencia_dias', 15) + TIME '23:59:59')
              AT TIME ZONE 'America/Mexico_City';

  FOR n IN 1..v_nivel_max LOOP
    v_codigo := 'RACHA-' || UPPER(SUBSTR(MD5(gen_random_uuid()::TEXT), 1, 6));

    INSERT INTO racha_premios (user_id, nivel, racha, premio, codigo, expira_at)
    VALUES (uid, n, v_racha, racha_premio_de(n), v_codigo, v_expira)
    ON CONFLICT (user_id, nivel) DO NOTHING
    RETURNING nivel, racha, premio, codigo, expira_at INTO v_insertado;

    IF FOUND THEN
      nuevos := nuevos || jsonb_build_object(
        'nivel', v_insertado.nivel, 'racha', v_insertado.racha,
        'premio', v_insertado.premio, 'codigo', v_insertado.codigo,
        'expira_at', v_insertado.expira_at
      );
    END IF;
  END LOOP;

  RETURN json_build_object('ok', true, 'racha', v_racha, 'nivel', v_nivel_max, 'nuevos', nuevos);
END $$;
GRANT EXECUTE ON FUNCTION reclamar_racha() TO authenticated;

-- canjear_codigo_racha(): ahora rechaza los codigos vencidos.
CREATE OR REPLACE FUNCTION canjear_codigo_racha(p_codigo TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role TEXT;
  r      racha_premios;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role NOT IN ('admin','manager') THEN
    RETURN json_build_object('ok', false, 'msg', 'Sin permiso');
  END IF;

  SELECT * INTO r FROM racha_premios WHERE codigo = UPPER(TRIM(p_codigo)) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'msg', 'Código no encontrado');
  END IF;
  IF r.canjeado THEN
    RETURN json_build_object('ok', false, 'msg',
      'Ya se canjeó el ' || TO_CHAR(r.canjeado_at, 'DD/MM/YYYY HH24:MI'));
  END IF;
  IF r.expira_at IS NOT NULL AND r.expira_at < NOW() THEN
    RETURN json_build_object('ok', false, 'msg',
      'Este código venció el ' || TO_CHAR(r.expira_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY'));
  END IF;

  UPDATE racha_premios
     SET canjeado = TRUE, canjeado_at = NOW(), canjeado_por = auth.uid()
   WHERE id = r.id;

  RETURN json_build_object('ok', true, 'premio', r.premio,
    'nombre', (SELECT nombre FROM profiles WHERE id = r.user_id));
END $$;
GRANT EXECUTE ON FUNCTION canjear_codigo_racha(TEXT) TO authenticated;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT nivel, premio, canjeado, expira_at FROM racha_premios ORDER BY created_at LIMIT 5;
--   -- los que no estan canjeados deben traer expira_at a 15 dias de hoy
