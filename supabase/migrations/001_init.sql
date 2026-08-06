-- =====================================================================
-- QUINIELA NFL 2026-27 – La Corte
-- Migration: 001_init.sql
--
-- Proyecto COMPLETAMENTE INDEPENDIENTE de la quiniela mundial.
-- Debe correrse en un proyecto Supabase NUEVO (no reutilizar el del mundial).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =====================================================================
-- 1. CONFIGURACIÓN (perillas de puntaje editables desde el panel admin)
-- =====================================================================
CREATE TABLE IF NOT EXISTS config (
  clave      TEXT PRIMARY KEY,
  valor      TEXT NOT NULL,
  etiqueta   TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO config (clave, valor, etiqueta) VALUES
  ('pts_win_normal',    '5',         'Puntos por ganador acertado (partido normal)'),
  ('pts_win_especial',  '15',        'Puntos por ganador acertado (partido extraordinario: mié/vie/sáb)'),
  ('conf_mode',         'additive',  'Cómo se aplican los puntos de confianza: additive | flat | solo'),
  ('pts_anotador',      '3',         'Puntos por acertar el primer equipo en anotar (partido estelar)'),
  ('pts_underdog',      '20',        'Puntos por acertar el underdog de la semana'),
  ('pts_folio_lunes',   '10',        'Puntos de consumo · lunes'),
  ('pts_folio_jueves',  '5',         'Puntos de consumo · jueves'),
  ('pts_folio_domingo', '5',         'Puntos de consumo · domingo'),
  ('pts_folio_especial','10',        'Puntos de consumo · días extraordinarios (mié/vie/sáb)'),
  ('lock_mode',         'semana',    'Cuándo se cierran los pronósticos: semana | partido'),
  ('underdog_top_n',    '10',        'Solo participan en underdog los jugadores fuera del top N'),
  ('whatsapp',          '528343144848', 'WhatsApp del restaurante (con lada país, sin +)'),
  ('telefono',          '8343144848',   'Teléfono del restaurante'),
  ('pts_bono_instalacion','25',       'Puntos de regalo por instalar la app en el teléfono')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION cfg_int(p_clave TEXT, p_default INT)
RETURNS INT LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT valor::INT FROM config WHERE clave = p_clave), p_default)
$$;

CREATE OR REPLACE FUNCTION cfg_text(p_clave TEXT, p_default TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT valor FROM config WHERE clave = p_clave), p_default)
$$;

-- =====================================================================
-- 2. EQUIPOS
-- =====================================================================
CREATE TABLE IF NOT EXISTS teams (
  code   TEXT PRIMARY KEY,
  ciudad TEXT NOT NULL,
  nombre TEXT NOT NULL,
  conf   TEXT NOT NULL CHECK (conf IN ('AFC','NFC')),
  div    TEXT NOT NULL CHECK (div  IN ('Este','Norte','Sur','Oeste')),
  color  TEXT NOT NULL DEFAULT '#333333'
);

INSERT INTO teams (code, ciudad, nombre, conf, div, color) VALUES
  ('BUF','Buffalo','Bills','AFC','Este','#00338D'),
  ('MIA','Miami','Dolphins','AFC','Este','#008E97'),
  ('NE','New England','Patriots','AFC','Este','#002244'),
  ('NYJ','New York','Jets','AFC','Este','#125740'),
  ('BAL','Baltimore','Ravens','AFC','Norte','#241773'),
  ('CIN','Cincinnati','Bengals','AFC','Norte','#FB4F14'),
  ('CLE','Cleveland','Browns','AFC','Norte','#311D00'),
  ('PIT','Pittsburgh','Steelers','AFC','Norte','#FFB612'),
  ('HOU','Houston','Texans','AFC','Sur','#03202F'),
  ('IND','Indianapolis','Colts','AFC','Sur','#002C5F'),
  ('JAX','Jacksonville','Jaguars','AFC','Sur','#006778'),
  ('TEN','Tennessee','Titans','AFC','Sur','#4B92DB'),
  ('DEN','Denver','Broncos','AFC','Oeste','#FB4F14'),
  ('KC','Kansas City','Chiefs','AFC','Oeste','#E31837'),
  ('LV','Las Vegas','Raiders','AFC','Oeste','#A5ACAF'),
  ('LAC','Los Angeles','Chargers','AFC','Oeste','#0080C6'),
  ('DAL','Dallas','Cowboys','NFC','Este','#041E42'),
  ('NYG','New York','Giants','NFC','Este','#0B2265'),
  ('PHI','Philadelphia','Eagles','NFC','Este','#004C54'),
  ('WAS','Washington','Commanders','NFC','Este','#5A1414'),
  ('CHI','Chicago','Bears','NFC','Norte','#0B162A'),
  ('DET','Detroit','Lions','NFC','Norte','#0076B6'),
  ('GB','Green Bay','Packers','NFC','Norte','#203731'),
  ('MIN','Minnesota','Vikings','NFC','Norte','#4F2683'),
  ('ATL','Atlanta','Falcons','NFC','Sur','#A71930'),
  ('CAR','Carolina','Panthers','NFC','Sur','#0085CA'),
  ('NO','New Orleans','Saints','NFC','Sur','#D3BC8D'),
  ('TB','Tampa Bay','Buccaneers','NFC','Sur','#D50A0A'),
  ('ARI','Arizona','Cardinals','NFC','Oeste','#97233F'),
  ('LAR','Los Angeles','Rams','NFC','Oeste','#003594'),
  ('SF','San Francisco','49ers','NFC','Oeste','#AA0000'),
  ('SEA','Seattle','Seahawks','NFC','Oeste','#002244')
ON CONFLICT (code) DO NOTHING;

-- =====================================================================
-- 3. PERFILES
-- =====================================================================
CREATE TABLE IF NOT EXISTS profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre     TEXT NOT NULL,
  email      TEXT NOT NULL,
  tel        TEXT NOT NULL DEFAULT '',
  -- Con el que la gente entra a la app. Va aparte del correo porque es mas
  -- facil de recordar y de dictar en el restaurante. Nullable a proposito:
  -- si el registro se corta a la mitad, el perfil se rescata y se completa.
  usuario    TEXT,
  role       TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','manager','admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS usuario TEXT;

-- Unico sin importar mayusculas: "PacoG" y "pacog" son el mismo usuario, si no
-- dos personas podrian registrar el mismo nombre escrito distinto.
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_usuario
  ON profiles(lower(usuario)) WHERE usuario IS NOT NULL;

-- Para entrar escribiendo el usuario en vez del correo.
-- Supabase solo sabe autenticar por correo, asi que el front traduce
-- usuario -> correo con esta funcion y luego pide la sesion.
--
-- Es SECURITY DEFINER y la puede llamar gente SIN sesion, porque justamente
-- se usa antes de iniciarla. Devuelve el correo solo con el usuario EXACTO;
-- no permite listar ni buscar por partes.
CREATE OR REPLACE FUNCTION correo_de_usuario(p_usuario TEXT)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT email FROM profiles WHERE lower(usuario) = lower(trim(p_usuario))
$$;
GRANT EXECUTE ON FUNCTION correo_de_usuario(TEXT) TO anon, authenticated;

-- Para avisar "ese usuario ya esta ocupado" ANTES de crear la cuenta, y no
-- dejar cuentas huerfanas sin perfil.
CREATE OR REPLACE FUNCTION usuario_disponible(p_usuario TEXT)
RETURNS BOOL LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM profiles WHERE lower(usuario) = lower(trim(p_usuario))
  )
$$;
GRANT EXECUTE ON FUNCTION usuario_disponible(TEXT) TO anon, authenticated;

-- =====================================================================
-- 4. PARTIDOS
--    week 1..18  = temporada regular
--    week 19..22 = Comodines / Divisional / Campeonato / Super Bowl
-- =====================================================================
CREATE TABLE IF NOT EXISTS games (
  id            TEXT PRIMARY KEY,
  week          INT  NOT NULL,
  kickoff       TIMESTAMPTZ NOT NULL,
  team_a        TEXT REFERENCES teams(code),          -- visitante
  team_b        TEXT REFERENCES teams(code),          -- local
  venue         TEXT NOT NULL DEFAULT '',
  slot          TEXT NOT NULL DEFAULT 'SUN'
                CHECK (slot IN ('TNF','SUN','SUN_LATE','SNF','MNF','ESPECIAL')),
  is_stellar    BOOL NOT NULL DEFAULT FALSE,          -- cuenta para "anotador"
  is_special    BOOL NOT NULL DEFAULT FALSE,          -- vale 15 pts en vez de 5
  flags_manual  BOOL NOT NULL DEFAULT FALSE,          -- si TRUE el trigger no recalcula
  score_a       INT,
  score_b       INT,
  first_scorer  TEXT CHECK (first_scorer IN ('A','B') OR first_scorer IS NULL)
);

CREATE INDEX IF NOT EXISTS idx_games_week    ON games(week);
CREATE INDEX IF NOT EXISTS idx_games_kickoff ON games(kickoff);

-- Auto-clasificación de partidos extraordinarios / estelares.
-- Regla del cliente: miércoles, viernes y sábado son días extraordinarios (15 pts).
-- Estelares (anotador): TNF, SNF, MNF y todos los extraordinarios.
CREATE OR REPLACE FUNCTION games_auto_flags()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE dow INT;
BEGIN
  IF NEW.flags_manual THEN RETURN NEW; END IF;
  dow := EXTRACT(DOW FROM (NEW.kickoff AT TIME ZONE 'America/Mexico_City'));
  -- 0=dom 1=lun 2=mar 3=mié 4=jue 5=vie 6=sáb
  NEW.is_special := dow IN (3,5,6);
  NEW.is_stellar := NEW.is_special OR NEW.slot IN ('TNF','SNF','MNF','ESPECIAL');
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_games_auto_flags ON games;
CREATE TRIGGER trg_games_auto_flags
  BEFORE INSERT OR UPDATE OF kickoff, slot, flags_manual ON games
  FOR EACH ROW EXECUTE FUNCTION games_auto_flags();

-- Helper: ¿ya arrancó la semana?
CREATE OR REPLACE FUNCTION semana_arrancada(p_week INT)
RETURNS BOOL LANGUAGE sql STABLE AS $$
  SELECT COALESCE(MIN(kickoff) <= NOW(), FALSE) FROM games WHERE week = p_week
$$;

CREATE OR REPLACE FUNCTION semana_inicio(p_week INT)
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE AS $$
  SELECT MIN(kickoff) FROM games WHERE week = p_week
$$;

-- =====================================================================
-- 5. PRONÓSTICOS (confianza + anotador)
-- =====================================================================
CREATE TABLE IF NOT EXISTS picks (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  game_id    TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  week       INT  NOT NULL DEFAULT 0,    -- denormalizado desde games (trigger)
  ganador    TEXT CHECK (ganador IN ('A','B') OR ganador IS NULL),
  confianza  INT  CHECK (confianza IS NULL OR confianza >= 1),
  primero    TEXT CHECK (primero IN ('A','B') OR primero IS NULL),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, game_id)
);

-- Un mismo valor de confianza no puede repetirse dentro de la misma semana
CREATE UNIQUE INDEX IF NOT EXISTS idx_picks_conf_unica
  ON picks(user_id, week, confianza) WHERE confianza IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_picks_user ON picks(user_id);
CREATE INDEX IF NOT EXISTS idx_picks_week ON picks(week);

CREATE OR REPLACE FUNCTION picks_before_write()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  g        games;
  v_lock   TEXT;
  v_limite TIMESTAMPTZ;
  v_role   TEXT;
BEGIN
  SELECT * INTO g FROM games WHERE id = NEW.game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partido inexistente'; END IF;

  NEW.week       := g.week;
  NEW.updated_at := NOW();

  -- Los admin/manager pueden corregir sin restricción de tiempo
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IN ('admin','manager') THEN RETURN NEW; END IF;

  v_lock := cfg_text('lock_mode','semana');
  IF v_lock = 'partido' THEN
    v_limite := g.kickoff;
  ELSE
    v_limite := semana_inicio(g.week);
  END IF;

  IF v_limite IS NOT NULL AND NOW() >= v_limite THEN
    RAISE EXCEPTION 'Los pronósticos de la semana % ya están cerrados', g.week;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_picks_before_write ON picks;
CREATE TRIGGER trg_picks_before_write
  BEFORE INSERT OR UPDATE ON picks
  FOR EACH ROW EXECUTE FUNCTION picks_before_write();

-- Guardar la semana completa de forma atómica.
-- p_picks = [{"game_id":"W01-TNF","ganador":"A","confianza":16,"primero":"B"}, ...]
-- Se limpian primero los valores de confianza para poder reordenarlos sin
-- chocar con el índice único (user_id, week, confianza).
CREATE OR REPLACE FUNCTION guardar_semana(p_week INT, p_picks JSONB)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid       UUID := auth.uid();
  v_role    TEXT;
  v_lock    TEXT;
  v_inicio  TIMESTAMPTZ;
  v_n       INT;
  v_confs   INT[];
  it        JSONB;
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  SELECT role INTO v_role FROM profiles WHERE id = uid;
  v_lock   := cfg_text('lock_mode','semana');
  v_inicio := semana_inicio(p_week);

  IF v_role NOT IN ('admin','manager')
     AND v_lock = 'semana'
     AND v_inicio IS NOT NULL
     AND NOW() >= v_inicio THEN
    RETURN json_build_object('ok', false, 'msg', 'La semana ' || p_week || ' ya cerró');
  END IF;

  SELECT COUNT(*) INTO v_n FROM games WHERE week = p_week;

  -- Todos los partidos enviados deben pertenecer a la semana indicada
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_picks) e
    LEFT JOIN games g ON g.id = e->>'game_id'
    WHERE g.id IS NULL OR g.week <> p_week
  ) THEN
    RETURN json_build_object('ok', false, 'msg', 'Hay partidos que no son de esta semana');
  END IF;

  -- Validar que los valores de confianza sean distintos y estén en rango
  SELECT array_agg(NULLIF(e->>'confianza','')::INT)
    INTO v_confs
    FROM jsonb_array_elements(p_picks) e
   WHERE NULLIF(e->>'confianza','') IS NOT NULL;

  IF v_confs IS NOT NULL THEN
    IF (SELECT COUNT(*) FROM unnest(v_confs)) <> (SELECT COUNT(DISTINCT x) FROM unnest(v_confs) x) THEN
      RETURN json_build_object('ok', false, 'msg', 'Hay valores de confianza repetidos');
    END IF;
    IF (SELECT MAX(x) FROM unnest(v_confs) x) > v_n OR (SELECT MIN(x) FROM unnest(v_confs) x) < 1 THEN
      RETURN json_build_object('ok', false, 'msg', 'La confianza debe ir de 1 a ' || v_n);
    END IF;
  END IF;

  -- Liberar los valores actuales para permitir reordenamientos
  UPDATE picks pk SET confianza = NULL
   WHERE pk.user_id = uid
     AND pk.week = p_week
     AND (
       v_lock <> 'partido'
       OR v_role IN ('admin','manager')
       OR EXISTS (SELECT 1 FROM games g WHERE g.id = pk.game_id AND g.kickoff > NOW())
     );

  FOR it IN SELECT * FROM jsonb_array_elements(p_picks) LOOP
    -- En modo "partido" se ignoran en silencio los juegos que ya arrancaron,
    -- para que un kickoff temprano no tumbe el guardado de toda la semana.
    IF v_lock = 'partido' AND v_role NOT IN ('admin','manager')
       AND EXISTS (SELECT 1 FROM games g WHERE g.id = it->>'game_id' AND g.kickoff <= NOW()) THEN
      CONTINUE;
    END IF;

    INSERT INTO picks (user_id, game_id, ganador, confianza, primero)
    VALUES (
      uid,
      it->>'game_id',
      NULLIF(it->>'ganador',''),
      NULLIF(it->>'confianza','')::INT,
      NULLIF(it->>'primero','')
    )
    ON CONFLICT (user_id, game_id) DO UPDATE
      SET ganador   = EXCLUDED.ganador,
          confianza = EXCLUDED.confianza,
          primero   = EXCLUDED.primero;
  END LOOP;

  RETURN json_build_object('ok', true, 'msg', 'Semana ' || p_week || ' guardada');
END $$;

GRANT EXECUTE ON FUNCTION guardar_semana(INT, JSONB) TO authenticated;

-- =====================================================================
-- 6. FOLIOS DE CONSUMO
-- =====================================================================
CREATE TABLE IF NOT EXISTS folios (
  code        TEXT PRIMARY KEY,
  fecha       DATE NOT NULL,               -- día de juego al que aplica
  puntos      INT  NOT NULL,
  usado       BOOL NOT NULL DEFAULT FALSE,
  por_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  usado_at    TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Un solo folio canjeado por persona por día
CREATE UNIQUE INDEX IF NOT EXISTS idx_folios_uno_por_dia
  ON folios(por_user_id, fecha) WHERE por_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_folios_fecha ON folios(fecha);

-- Puntos que corresponden a una fecha según el día de la semana
CREATE OR REPLACE FUNCTION puntos_por_fecha(p_fecha DATE)
RETURNS INT LANGUAGE plpgsql STABLE AS $$
DECLARE dow INT;
BEGIN
  dow := EXTRACT(DOW FROM p_fecha);
  RETURN CASE dow
    WHEN 1 THEN cfg_int('pts_folio_lunes',10)     -- lunes
    WHEN 4 THEN cfg_int('pts_folio_jueves',5)     -- jueves
    WHEN 0 THEN cfg_int('pts_folio_domingo',5)    -- domingo
    ELSE        cfg_int('pts_folio_especial',10)  -- mié / vie / sáb (extraordinarios)
  END;
END $$;

CREATE OR REPLACE FUNCTION canjear_folio(p_code TEXT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  f   folios;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  SELECT * INTO f FROM folios WHERE code = UPPER(TRIM(p_code)) FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'msg', 'Folio inválido');
  END IF;
  IF f.usado THEN
    RETURN json_build_object('ok', false, 'msg', 'Ese folio ya fue canjeado');
  END IF;

  IF EXISTS (SELECT 1 FROM folios WHERE por_user_id = uid AND fecha = f.fecha) THEN
    RETURN json_build_object('ok', false, 'msg',
      'Ya canjeaste un folio del ' || TO_CHAR(f.fecha,'DD/MM/YYYY') || '. Es uno por día.');
  END IF;

  UPDATE folios
     SET usado = TRUE, por_user_id = uid, usado_at = NOW()
   WHERE code = f.code;

  RETURN json_build_object('ok', true, 'puntos', f.puntos,
                           'msg', '+' || f.puntos || ' puntos de consumo');
END $$;

GRANT EXECUTE ON FUNCTION canjear_folio(TEXT) TO authenticated;

-- Generar folios en lote para una fecha (solo admin/manager)
CREATE OR REPLACE FUNCTION generar_folios(p_fecha DATE, p_cantidad INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

GRANT EXECUTE ON FUNCTION generar_folios(DATE, INT) TO authenticated;

-- =====================================================================
-- 7. UNDERDOG
-- =====================================================================
CREATE TABLE IF NOT EXISTS underdog_weeks (
  week        INT PRIMARY KEY,
  abierto     BOOL NOT NULL DEFAULT TRUE,
  puntos      INT  NOT NULL DEFAULT 20,
  opt_a_game  TEXT REFERENCES games(id) ON DELETE SET NULL,
  opt_a_team  TEXT REFERENCES teams(code),
  opt_b_game  TEXT REFERENCES games(id) ON DELETE SET NULL,
  opt_b_team  TEXT REFERENCES teams(code),
  opt_c_game  TEXT REFERENCES games(id) ON DELETE SET NULL,
  opt_c_team  TEXT REFERENCES teams(code),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS underdog_picks (
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week       INT  NOT NULL REFERENCES underdog_weeks(week) ON DELETE CASCADE,
  opcion     TEXT NOT NULL CHECK (opcion IN ('A','B','C')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, week)
);

-- Fotografía del ranking al cierre de cada semana (lunes).
-- De aquí sale la elegibilidad del underdog de la semana siguiente.
CREATE TABLE IF NOT EXISTS week_snapshots (
  week       INT  NOT NULL,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  posicion   INT  NOT NULL,
  total      INT  NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (week, user_id)
);

CREATE OR REPLACE FUNCTION underdog_acierto(p_game TEXT, p_team TEXT)
RETURNS BOOL LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN g.score_a IS NULL OR g.score_a = g.score_b THEN FALSE
    ELSE (CASE WHEN g.score_a > g.score_b THEN g.team_a ELSE g.team_b END) = p_team
  END
  FROM games g WHERE g.id = p_game
$$;

-- ¿Puede este usuario jugar el underdog de la semana N?
-- Sí, si en el corte de la semana N-1 quedó fuera del top 10.
-- Si no existe corte previo (semana 1) todos pueden.
CREATE OR REPLACE FUNCTION underdog_elegible(p_user UUID, p_week INT)
RETURNS BOOL LANGUAGE plpgsql STABLE AS $$
DECLARE v_pos INT; v_hay BOOL;
BEGIN
  SELECT EXISTS (SELECT 1 FROM week_snapshots WHERE week = p_week - 1) INTO v_hay;
  IF NOT v_hay THEN RETURN TRUE; END IF;
  SELECT posicion INTO v_pos FROM week_snapshots WHERE week = p_week - 1 AND user_id = p_user;
  IF v_pos IS NULL THEN RETURN TRUE; END IF;   -- no estaba en la tabla → puede
  RETURN v_pos > cfg_int('underdog_top_n', 10);
END $$;

-- =====================================================================
-- 8. HISTORIAL (quinielas pasadas de La Corte)
-- =====================================================================
CREATE TABLE IF NOT EXISTS historial (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo      TEXT NOT NULL,
  temporada   TEXT NOT NULL DEFAULT '',
  descripcion TEXT NOT NULL DEFAULT '',
  url         TEXT NOT NULL DEFAULT '',
  ganador_1   TEXT NOT NULL DEFAULT '',
  ganador_2   TEXT NOT NULL DEFAULT '',
  ganador_3   TEXT NOT NULL DEFAULT '',
  emoji       TEXT NOT NULL DEFAULT '🏆',
  orden       INT  NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO historial (titulo, temporada, descripcion, emoji, orden)
SELECT 'Quiniela Mundial FIFA', '2026',
       'Nuestra primera quiniela: 104 partidos, marcador exacto, ganador y primer anotador.',
       '⚽', 1
WHERE NOT EXISTS (SELECT 1 FROM historial);

-- =====================================================================
-- 8B. BONOS (puntos otorgados a mano)
--
-- Cuarta fuente de puntos, aparte de confianza, consumo y underdog.
-- Nació para premiar a quien instala la app en su teléfono —el canal por
-- el que le llegan los avisos—, pero sirve para cualquier cosa que quieras
-- premiar: una trivia, un cumpleaños, una promoción de un día.
-- =====================================================================
CREATE TABLE IF NOT EXISTS bonos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  motivo     TEXT NOT NULL,
  puntos     INT  NOT NULL,
  creado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bonos_user ON bonos(user_id);

-- El bono de instalación se cobra UNA sola vez por persona. Los demás motivos
-- sí se pueden repetir (nada impide dar dos bonos de trivia al mismo jugador).
CREATE UNIQUE INDEX IF NOT EXISTS idx_bonos_instalacion_unico
  ON bonos(user_id) WHERE motivo = 'instalacion';

-- Otorga el bono por instalar la app. Es idempotente: si ya lo cobró, responde
-- ok igual pero sin sumar nada, así el front puede llamarla sin miedo cada vez
-- que detecte que la app corre instalada.
--
-- SECURITY DEFINER porque el jugador NO tiene permiso de escribir en `bonos`
-- (la política solo deja a admin/manager). Si lo tuviera, se regalaría los
-- puntos que quisiera.
CREATE OR REPLACE FUNCTION otorgar_bono_instalacion()
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid UUID; v_pts INT;
BEGIN
  -- auth.uid() y no current_user: dentro de SECURITY DEFINER current_user es el
  -- DUEÑO de la función (postgres), no quien la llama.
  uid := auth.uid();
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  v_pts := cfg_int('pts_bono_instalacion', 25);

  -- El ON CONFLICT contra el índice parcial es la garantía de verdad: aunque
  -- entren dos llamadas a la vez, solo una inserta.
  INSERT INTO bonos (user_id, motivo, puntos)
  VALUES (uid, 'instalacion', v_pts)
  ON CONFLICT (user_id) WHERE motivo = 'instalacion' DO NOTHING;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', true, 'ya', true, 'puntos', 0);
  END IF;
  RETURN json_build_object('ok', true, 'ya', false, 'puntos', v_pts);
END $$;
GRANT EXECUTE ON FUNCTION otorgar_bono_instalacion() TO authenticated;

-- =====================================================================
-- 9. VISTA DE RANKING
-- =====================================================================
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

-- Cerrar la semana: congela el ranking del día (lunes) en week_snapshots
CREATE OR REPLACE FUNCTION cerrar_semana(p_week INT)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_role TEXT; v_n INT;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role NOT IN ('admin','manager') THEN
    RETURN json_build_object('ok', false, 'msg', 'Sin permiso');
  END IF;

  DELETE FROM week_snapshots WHERE week = p_week;

  INSERT INTO week_snapshots (week, user_id, posicion, total)
  SELECT p_week, r.id, ROW_NUMBER() OVER (ORDER BY r.total_puntos DESC, r.nombre ASC), r.total_puntos
  FROM ranking r;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE underdog_weeks SET abierto = FALSE WHERE week = p_week;

  RETURN json_build_object('ok', true, 'msg', 'Semana ' || p_week || ' cerrada · ' || v_n || ' jugadores');
END $$;

GRANT EXECUTE ON FUNCTION cerrar_semana(INT) TO authenticated;

-- =====================================================================
-- 10. RLS
-- =====================================================================
ALTER TABLE profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams           ENABLE ROW LEVEL SECURITY;
ALTER TABLE games           ENABLE ROW LEVEL SECURITY;
ALTER TABLE picks           ENABLE ROW LEVEL SECURITY;
ALTER TABLE folios          ENABLE ROW LEVEL SECURITY;
ALTER TABLE underdog_weeks  ENABLE ROW LEVEL SECURITY;
ALTER TABLE underdog_picks  ENABLE ROW LEVEL SECURITY;
ALTER TABLE week_snapshots  ENABLE ROW LEVEL SECURITY;
ALTER TABLE historial       ENABLE ROW LEVEL SECURITY;
ALTER TABLE config          ENABLE ROW LEVEL SECURITY;
ALTER TABLE bonos           ENABLE ROW LEVEL SECURITY;

-- Helper de rol sin recursión de políticas
CREATE OR REPLACE FUNCTION mi_rol()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM profiles WHERE id = auth.uid()
$$;
GRANT EXECUTE ON FUNCTION mi_rol() TO authenticated;

-- profiles
DROP POLICY IF EXISTS "profiles read"   ON profiles;
DROP POLICY IF EXISTS "profiles insert" ON profiles;
DROP POLICY IF EXISTS "profiles update" ON profiles;
CREATE POLICY "profiles read"   ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles insert" ON profiles FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
CREATE POLICY "profiles update" ON profiles FOR UPDATE TO authenticated
  USING (id = auth.uid() OR mi_rol() = 'admin');

-- La política de arriba deja que cada quien edite SU fila (nombre, tel...),
-- pero por sí sola también dejaría que un jugador se cambiara su propio
-- `role` a 'admin'. Este trigger cierra esa puerta: el rol solo lo mueve un
-- admin, o el service_role / editor SQL de Supabase (donde auth.uid() es NULL,
-- que es como se nombra al primer administrador).
CREATE OR REPLACE FUNCTION profiles_guard_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    -- OJO: aquí NO sirve current_user. Dentro de una función SECURITY DEFINER
    -- current_user es el DUEÑO de la función (postgres), no quien la llama, así
    -- que cualquier excepción basada en él dejaría pasar a todo el mundo.
    -- La señal buena es auth.uid(): es NULL en el editor SQL / Table Editor de
    -- Supabase (así se nombra al primer admin) y trae el id de un jugador real.
    IF auth.uid() IS NOT NULL AND COALESCE(mi_rol(),'user') <> 'admin' THEN
      RAISE EXCEPTION 'Solo un administrador puede cambiar roles';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_profiles_guard_role ON profiles;
CREATE TRIGGER trg_profiles_guard_role
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION profiles_guard_role();

-- teams / games / historial / config: lectura pública
DROP POLICY IF EXISTS "teams read"     ON teams;
DROP POLICY IF EXISTS "games read"     ON games;
DROP POLICY IF EXISTS "historial read" ON historial;
DROP POLICY IF EXISTS "config read"    ON config;
CREATE POLICY "teams read"     ON teams     FOR SELECT USING (true);
CREATE POLICY "games read"     ON games     FOR SELECT USING (true);
CREATE POLICY "historial read" ON historial FOR SELECT USING (true);
CREATE POLICY "config read"    ON config    FOR SELECT USING (true);

DROP POLICY IF EXISTS "games write"  ON games;
DROP POLICY IF EXISTS "games ins"    ON games;
DROP POLICY IF EXISTS "games del"    ON games;
CREATE POLICY "games write" ON games FOR UPDATE TO authenticated
  USING (mi_rol() IN ('admin','manager'));
CREATE POLICY "games ins"   ON games FOR INSERT TO authenticated
  WITH CHECK (mi_rol() IN ('admin','manager'));
CREATE POLICY "games del"   ON games FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

DROP POLICY IF EXISTS "config write" ON config;
CREATE POLICY "config write" ON config FOR UPDATE TO authenticated
  USING (mi_rol() = 'admin');

DROP POLICY IF EXISTS "historial ins" ON historial;
DROP POLICY IF EXISTS "historial upd" ON historial;
DROP POLICY IF EXISTS "historial del" ON historial;
CREATE POLICY "historial ins" ON historial FOR INSERT TO authenticated
  WITH CHECK (mi_rol() = 'admin');
CREATE POLICY "historial upd" ON historial FOR UPDATE TO authenticated
  USING (mi_rol() = 'admin');
CREATE POLICY "historial del" ON historial FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

-- picks: todos leen (el ranking lo necesita), cada quien escribe lo suyo
DROP POLICY IF EXISTS "picks read"   ON picks;
DROP POLICY IF EXISTS "picks insert" ON picks;
DROP POLICY IF EXISTS "picks update" ON picks;
DROP POLICY IF EXISTS "picks delete" ON picks;
-- Los pronosticos son PRIVADOS: cada quien ve solo los suyos, siempre. La
-- quiniela es abierta y la llave anon es publica, asi que USING (true) dejaba
-- que cualquier participante leyera los picks de los demas y jugara con
-- ventaja. Admin y manager si ven todos, para resolver reclamos de puntaje.
-- La tabla de posiciones no depende de esto: sale de la vista `ranking`, que
-- corre como dueno y no pasa por RLS.
-- Ver 005_privacidad_picks.sql (delta para la base ya desplegada).
CREATE POLICY "picks read"   ON picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
  );
CREATE POLICY "picks insert" ON picks FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "picks update" ON picks FOR UPDATE TO authenticated USING (user_id = auth.uid());
CREATE POLICY "picks delete" ON picks FOR DELETE TO authenticated USING (user_id = auth.uid());

-- folios: lectura solo admin/manager o del propio usuario; el canje va por RPC
DROP POLICY IF EXISTS "folios read" ON folios;
DROP POLICY IF EXISTS "folios del"  ON folios;
CREATE POLICY "folios read" ON folios FOR SELECT TO authenticated
  USING (por_user_id = auth.uid() OR mi_rol() IN ('admin','manager'));
CREATE POLICY "folios del"  ON folios FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

-- underdog
DROP POLICY IF EXISTS "uw read" ON underdog_weeks;
DROP POLICY IF EXISTS "uw ins"  ON underdog_weeks;
DROP POLICY IF EXISTS "uw upd"  ON underdog_weeks;
CREATE POLICY "uw read" ON underdog_weeks FOR SELECT USING (true);
CREATE POLICY "uw ins"  ON underdog_weeks FOR INSERT TO authenticated
  WITH CHECK (mi_rol() IN ('admin','manager'));
CREATE POLICY "uw upd"  ON underdog_weeks FOR UPDATE TO authenticated
  USING (mi_rol() IN ('admin','manager'));

DROP POLICY IF EXISTS "up read" ON underdog_picks;
DROP POLICY IF EXISTS "up ins"  ON underdog_picks;
DROP POLICY IF EXISTS "up upd"  ON underdog_picks;
-- Mismo criterio que "picks read": el underdog tambien es privado.
CREATE POLICY "up read" ON underdog_picks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR mi_rol() IN ('admin','manager')
  );
CREATE POLICY "up ins"  ON underdog_picks FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND underdog_elegible(auth.uid(), week)
    AND EXISTS (SELECT 1 FROM underdog_weeks w WHERE w.week = underdog_picks.week AND w.abierto)
    AND NOT semana_arrancada(week)
  );
CREATE POLICY "up upd"  ON underdog_picks FOR UPDATE TO authenticated
  USING (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM underdog_weeks w WHERE w.week = underdog_picks.week AND w.abierto)
    AND NOT semana_arrancada(week)
  );

DROP POLICY IF EXISTS "ws read" ON week_snapshots;
CREATE POLICY "ws read" ON week_snapshots FOR SELECT TO authenticated USING (true);

-- bonos: todos leen (el ranking los suma y el desglose los muestra), pero solo
-- admin/manager los otorgan a mano. El bono de instalación NO entra por aquí:
-- entra por otorgar_bono_instalacion(), que es SECURITY DEFINER.
-- Sin UPDATE a propósito: un bono se da o se quita, no se edita.
DROP POLICY IF EXISTS "bonos read" ON bonos;
DROP POLICY IF EXISTS "bonos ins"  ON bonos;
DROP POLICY IF EXISTS "bonos del"  ON bonos;
CREATE POLICY "bonos read" ON bonos FOR SELECT TO authenticated USING (true);
CREATE POLICY "bonos ins"  ON bonos FOR INSERT TO authenticated
  WITH CHECK (mi_rol() IN ('admin','manager'));
CREATE POLICY "bonos del"  ON bonos FOR DELETE TO authenticated
  USING (mi_rol() = 'admin');

-- =====================================================================
-- 11. CALENDARIO 2026-27 (estructura oficial de fechas · equipos por definir)
--
--   Semana 1 arranca el jueves 10-sep-2026 (jueves posterior al Labor Day).
--   Semana N: jueves = 10-sep-2026 + 7*(N-1).
--   Horarios en CST (UTC-6, hora de Tampico).
--
--   Los EMPAREJAMIENTOS quedan en TBD: se cargan desde el panel admin
--   con el importador masivo cuando la NFL publique el calendario oficial.
-- =====================================================================
DO $seed$
DECLARE
  w        INT;
  jue      DATE;
  dom      DATE;
  lun      DATE;
  i        INT;
  gid      TEXT;
  n_temp   INT := 18;
BEGIN
  FOR w IN 1..n_temp LOOP
    jue := DATE '2026-09-10' + (7 * (w - 1));
    dom := jue + 3;
    lun := jue + 4;

    IF w < 18 THEN
      -- Thursday Night Football
      INSERT INTO games (id, week, kickoff, slot, venue)
      VALUES (format('W%s-TNF', LPAD(w::TEXT,2,'0')), w,
              (jue + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'TNF', '')
      ON CONFLICT (id) DO NOTHING;
    END IF;

    -- Domingo temprano (9 juegos) · 12:00 CST
    FOR i IN 1..9 LOOP
      gid := format('W%s-D%s', LPAD(w::TEXT,2,'0'), LPAD(i::TEXT,2,'0'));
      INSERT INTO games (id, week, kickoff, slot, venue)
      VALUES (gid, w, (dom + TIME '12:00') AT TIME ZONE 'America/Mexico_City', 'SUN', '')
      ON CONFLICT (id) DO NOTHING;
    END LOOP;

    -- Domingo tarde (4 juegos) · 15:25 CST
    FOR i IN 10..13 LOOP
      gid := format('W%s-D%s', LPAD(w::TEXT,2,'0'), LPAD(i::TEXT,2,'0'));
      INSERT INTO games (id, week, kickoff, slot, venue)
      VALUES (gid, w, (dom + TIME '15:25') AT TIME ZONE 'America/Mexico_City', 'SUN_LATE', '')
      ON CONFLICT (id) DO NOTHING;
    END LOOP;

    -- Sunday Night Football
    INSERT INTO games (id, week, kickoff, slot, venue)
    VALUES (format('W%s-SNF', LPAD(w::TEXT,2,'0')), w,
            (dom + TIME '19:20') AT TIME ZONE 'America/Mexico_City', 'SNF', '')
    ON CONFLICT (id) DO NOTHING;

    IF w < 18 THEN
      -- Monday Night Football
      INSERT INTO games (id, week, kickoff, slot, venue)
      VALUES (format('W%s-MNF', LPAD(w::TEXT,2,'0')), w,
              (lun + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'MNF', '')
      ON CONFLICT (id) DO NOTHING;
    END IF;
  END LOOP;

  -- ── Semana 12: Día de Acción de Gracias (jue 26-nov-2026) ─────────
  -- 3 juegos estelares el jueves. Se marcan manualmente como estelares
  -- (anotador) pero NO extraordinarios: la regla de 15 pts es mié/vie/sáb.
  DELETE FROM games WHERE id = 'W12-TNF';
  INSERT INTO games (id, week, kickoff, slot, venue, is_stellar, is_special, flags_manual) VALUES
    ('W12-TG1', 12, (DATE '2026-11-26' + TIME '11:30') AT TIME ZONE 'America/Mexico_City',
     'ESPECIAL', 'Ford Field, Detroit', TRUE, FALSE, TRUE),
    ('W12-TG2', 12, (DATE '2026-11-26' + TIME '15:30') AT TIME ZONE 'America/Mexico_City',
     'ESPECIAL', 'AT&T Stadium, Dallas', TRUE, FALSE, TRUE),
    ('W12-TG3', 12, (DATE '2026-11-26' + TIME '19:20') AT TIME ZONE 'America/Mexico_City',
     'ESPECIAL', '', TRUE, FALSE, TRUE)
  ON CONFLICT (id) DO NOTHING;

  -- Black Friday (vie 27-nov-2026) → extraordinario, 15 pts
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W12-BF1', 12, (DATE '2026-11-27' + TIME '14:00') AT TIME ZONE 'America/Mexico_City',
     'ESPECIAL', '')
  ON CONFLICT (id) DO NOTHING;

  -- Semana 12 juega 10 en domingo (3 se movieron a jueves/viernes)
  DELETE FROM games WHERE id IN ('W12-D08','W12-D09','W12-D13');

  -- ── Semana 15: sábado 19-dic-2026 (extraordinario) ────────────────
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W15-SAB1', 15, (DATE '2026-12-19' + TIME '15:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W15-SAB2', 15, (DATE '2026-12-19' + TIME '19:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', '')
  ON CONFLICT (id) DO NOTHING;
  DELETE FROM games WHERE id IN ('W15-D08','W15-D09');

  -- ── Semana 16: Navidad, viernes 25-dic-2026 (extraordinario) ──────
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W16-NAV1', 16, (DATE '2026-12-25' + TIME '12:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W16-NAV2', 16, (DATE '2026-12-25' + TIME '15:30') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W16-NAV3', 16, (DATE '2026-12-25' + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', '')
  ON CONFLICT (id) DO NOTHING;
  DELETE FROM games WHERE id IN ('W16-TNF','W16-D08','W16-D09');

  -- ── Semana 17: sábado 2-ene-2027 (extraordinario) ─────────────────
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W17-SAB1', 17, (DATE '2027-01-02' + TIME '15:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W17-SAB2', 17, (DATE '2027-01-02' + TIME '19:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', '')
  ON CONFLICT (id) DO NOTHING;
  DELETE FROM games WHERE id IN ('W17-D08','W17-D09');

  -- ── Semana 18: sábado 9 y domingo 10 de enero 2027, sin TNF/MNF ───
  DELETE FROM games WHERE week = 18;
  FOR i IN 1..8 LOOP
    INSERT INTO games (id, week, kickoff, slot, venue)
    VALUES (format('W18-D%s', LPAD(i::TEXT,2,'0')), 18,
            (DATE '2027-01-10' + TIME '12:00') AT TIME ZONE 'America/Mexico_City', 'SUN', '')
    ON CONFLICT (id) DO NOTHING;
  END LOOP;
  FOR i IN 9..16 LOOP
    INSERT INTO games (id, week, kickoff, slot, venue)
    VALUES (format('W18-D%s', LPAD(i::TEXT,2,'0')), 18,
            (DATE '2027-01-10' + TIME '15:25') AT TIME ZONE 'America/Mexico_City', 'SUN_LATE', '')
    ON CONFLICT (id) DO NOTHING;
  END LOOP;

  -- ── PLAYOFFS ──────────────────────────────────────────────────────
  -- Semana 19 · Comodines (16-18 ene 2027)
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W19-WC1', 19, (DATE '2027-01-16' + TIME '15:30') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W19-WC2', 19, (DATE '2027-01-16' + TIME '19:00') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W19-WC3', 19, (DATE '2027-01-17' + TIME '12:00') AT TIME ZONE 'America/Mexico_City', 'SUN', ''),
    ('W19-WC4', 19, (DATE '2027-01-17' + TIME '15:30') AT TIME ZONE 'America/Mexico_City', 'SUN_LATE', ''),
    ('W19-WC5', 19, (DATE '2027-01-17' + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'SNF', ''),
    ('W19-WC6', 19, (DATE '2027-01-18' + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'MNF', '')
  ON CONFLICT (id) DO NOTHING;

  -- Semana 20 · Divisional (23-24 ene 2027)
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W20-DIV1', 20, (DATE '2027-01-23' + TIME '15:30') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W20-DIV2', 20, (DATE '2027-01-23' + TIME '19:15') AT TIME ZONE 'America/Mexico_City', 'ESPECIAL', ''),
    ('W20-DIV3', 20, (DATE '2027-01-24' + TIME '14:00') AT TIME ZONE 'America/Mexico_City', 'SUN', ''),
    ('W20-DIV4', 20, (DATE '2027-01-24' + TIME '17:30') AT TIME ZONE 'America/Mexico_City', 'SNF', '')
  ON CONFLICT (id) DO NOTHING;

  -- Semana 21 · Finales de Conferencia (31 ene 2027)
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W21-CONF1', 21, (DATE '2027-01-31' + TIME '14:00') AT TIME ZONE 'America/Mexico_City', 'SUN', ''),
    ('W21-CONF2', 21, (DATE '2027-01-31' + TIME '17:30') AT TIME ZONE 'America/Mexico_City', 'SNF', '')
  ON CONFLICT (id) DO NOTHING;

  -- Semana 22 · Super Bowl LXI (14 feb 2027)
  INSERT INTO games (id, week, kickoff, slot, venue) VALUES
    ('W22-SB', 22, (DATE '2027-02-14' + TIME '17:30') AT TIME ZONE 'America/Mexico_City',
     'SNF', 'Levi''s Stadium, Santa Clara')
  ON CONFLICT (id) DO NOTHING;
END
$seed$;

-- Semanas de underdog vacías listas para configurar
INSERT INTO underdog_weeks (week, abierto, puntos)
SELECT gs, TRUE, 20 FROM generate_series(1,22) gs
ON CONFLICT (week) DO NOTHING;

-- =====================================================================
-- 12. PERMISOS DE TABLA (GRANT)
--
-- Postgres tiene dos candados independientes y hacen falta LOS DOS:
--   GRANT → ¿este rol puede tocar la tabla?
--   RLS   → ¿cuáles filas de esa tabla?
-- Sin los GRANT, la API responde "permission denied for table" aunque
-- las políticas RLS estén perfectas.
-- =====================================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Lectura pública: calendario, equipos, premios e historial sin registrarse
GRANT SELECT ON teams          TO anon, authenticated;
GRANT SELECT ON games          TO anon, authenticated;
GRANT SELECT ON config         TO anon, authenticated;
GRANT SELECT ON historial      TO anon, authenticated;
GRANT SELECT ON underdog_weeks TO anon, authenticated;

-- Con sesión: amplio a nivel tabla, RLS decide las filas
GRANT SELECT, INSERT, UPDATE, DELETE ON profiles       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON picks          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON underdog_picks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON folios         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON games          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON underdog_weeks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON historial      TO authenticated;
GRANT SELECT, UPDATE                 ON config         TO authenticated;
GRANT SELECT                         ON week_snapshots TO authenticated;
GRANT SELECT, INSERT, DELETE         ON bonos          TO authenticated;
-- Un bono se da o se quita, no se edita. El REVOKE explicito mantiene esta
-- tabla igual aqui que en 003_bonos.sql, donde SI hace falta porque ahi la
-- tabla se crea despues del ALTER DEFAULT PRIVILEGES de mas abajo.
REVOKE UPDATE                        ON bonos          FROM authenticated;
REVOKE ALL                           ON bonos          FROM anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated;

-- =====================================================================
-- 13. REALTIME
-- =====================================================================
DO $rt$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE games;          EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE picks;          EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE folios;         EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE underdog_picks; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE underdog_weeks; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE bonos;          EXCEPTION WHEN OTHERS THEN NULL; END;
END
$rt$;
