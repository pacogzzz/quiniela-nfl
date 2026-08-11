-- 010_racha_premios.sql
--
-- Delta para la base que YA ESTA CORRIENDO en Supabase. Los mismos cambios
-- viven en 001_init.sql, que es la fuente de verdad y lo que cargan las
-- pruebas.
--
-- QUE AGREGA
-- ==========
-- "Mejor racha" antes contaba partidos ganadores seguidos. Ahora cuenta
-- WEEKS SEGUIDAS jugando (guardaste tu pronostico antes de que cerrara) y
-- cada cierto numero de semanas desbloquea un premio real para canjear en
-- La Corte: se premia la constancia, no solo el acierto.
--
-- Los primeros 4 niveles son fijos (Week 3, 8, 13, 18); de ahi en adelante
-- se repite el nivel 4 cada 5 semanas, para que la escalera nunca se acabe
-- sin tener que inventar un nivel nuevo cada temporada.
--
-- La tabla `racha_premios` guarda un codigo por cada nivel que un jugador
-- desbloquea. Nadie puede escribir ahi directo (ni jugador ni admin): todo
-- pasa por dos funciones SECURITY DEFINER:
--   reclamar_racha()          -- el jugador la llama; recalcula su racha
--                                 del lado del servidor y le otorga los
--                                 codigos que le falten. Idempotente.
--   canjear_codigo_racha(cod) -- solo admin/manager; la usa tu gente en el
--                                 restaurante cuando el cliente ensena su
--                                 codigo, igual que ya hacen con folios.

BEGIN;

CREATE TABLE IF NOT EXISTS racha_premios (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nivel        INT  NOT NULL,
  racha        INT  NOT NULL,
  premio       TEXT NOT NULL,
  codigo       TEXT NOT NULL UNIQUE,
  canjeado     BOOL NOT NULL DEFAULT FALSE,
  canjeado_at  TIMESTAMPTZ,
  canjeado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, nivel)
);
CREATE INDEX IF NOT EXISTS idx_racha_premios_user ON racha_premios(user_id);

CREATE OR REPLACE FUNCTION racha_semanas_de(p_user UUID)
RETURNS INT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  w INT;
  v_racha INT := 0;
BEGIN
  FOR w IN
    SELECT DISTINCT week FROM games WHERE week > 0 AND semana_arrancada(week)
    ORDER BY week DESC
  LOOP
    IF EXISTS (SELECT 1 FROM picks WHERE user_id = p_user AND week = w) THEN
      v_racha := v_racha + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;
  RETURN v_racha;
END $$;

CREATE OR REPLACE FUNCTION racha_nivel_de(p_racha INT)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_racha < 3  THEN 0
    WHEN p_racha < 8  THEN 1
    WHEN p_racha < 13 THEN 2
    WHEN p_racha < 18 THEN 3
    ELSE 4 + ((p_racha - 18) / 5)
  END
$$;

CREATE OR REPLACE FUNCTION racha_premio_de(p_nivel INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_nivel = 1 THEN 'Promo 3x2 de cortesía'
    WHEN p_nivel = 2 THEN 'Entrada + Promo 3x2 de cortesía'
    WHEN p_nivel = 3 THEN 'Descuento 15%'
    WHEN p_nivel >= 4 THEN 'Descuento 25%'
    ELSE NULL
  END
$$;

CREATE OR REPLACE FUNCTION reclamar_racha()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
GRANT EXECUTE ON FUNCTION reclamar_racha() TO authenticated;

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

  UPDATE racha_premios
     SET canjeado = TRUE, canjeado_at = NOW(), canjeado_por = auth.uid()
   WHERE id = r.id;

  RETURN json_build_object('ok', true, 'premio', r.premio,
    'nombre', (SELECT nombre FROM profiles WHERE id = r.user_id));
END $$;
GRANT EXECUTE ON FUNCTION canjear_codigo_racha(TEXT) TO authenticated;

ALTER TABLE racha_premios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "racha premios propia" ON racha_premios;
DROP POLICY IF EXISTS "racha premios admin del" ON racha_premios;
CREATE POLICY "racha premios propia" ON racha_premios FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR mi_rol() IN ('admin','manager'));
CREATE POLICY "racha premios admin del" ON racha_premios FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

-- DELETE queda a nivel de tabla (admin necesita poder limpiarla en un
-- reset general); la política de arriba es la que de verdad restringe a
-- solo admin. INSERT/UPDATE siguen bloqueados: eso pasa SIEMPRE por
-- reclamar_racha() / canjear_codigo_racha().
GRANT SELECT, DELETE ON racha_premios TO authenticated;
REVOKE INSERT, UPDATE ON racha_premios FROM authenticated;
REVOKE ALL ON racha_premios FROM anon;

COMMIT;

-- PARA COMPROBAR QUE QUEDO (correr aparte y leer el resultado):
--
--   SELECT reclamar_racha();
--   SELECT * FROM racha_premios ORDER BY created_at DESC LIMIT 10;
