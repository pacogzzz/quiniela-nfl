-- =====================================================================
-- QUINIELA NFL 2026-27 – La Corte
-- Migration: 002_grants.sql
--
-- Permisos a nivel tabla para los roles de la API de Supabase.
--
-- Postgres tiene DOS candados independientes y hacen falta los dos:
--
--   1. GRANT  → "¿este rol puede tocar esta tabla, aunque sea?"
--   2. RLS    → "de las filas de esa tabla, ¿cuáles?"
--
-- 001_init.sql traía las políticas RLS (candado 2) pero no los GRANT
-- (candado 1), así que la API respondía "permission denied for table".
--
-- Correrlo es seguro con la app en marcha: solo abre la puerta a nivel
-- tabla; quién ve y escribe qué filas lo siguen decidiendo las políticas
-- RLS de 001, que no se tocan aquí.
-- =====================================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ─── Lectura pública (visitantes sin cuenta) ───────────────────────
-- Calendario, equipos, premios e historial se ven sin registrarse.
GRANT SELECT ON teams          TO anon, authenticated;
GRANT SELECT ON games          TO anon, authenticated;
GRANT SELECT ON config         TO anon, authenticated;
GRANT SELECT ON historial      TO anon, authenticated;
GRANT SELECT ON underdog_weeks TO anon, authenticated;

-- ─── Usuarios con sesión ───────────────────────────────────────────
-- Se concede amplio a nivel tabla: lo que de verdad limita a cada quien
-- son las políticas RLS (un jugador solo escribe sus propios picks, solo
-- admin/manager cargan resultados, etc.).
GRANT SELECT, INSERT, UPDATE, DELETE ON profiles        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON picks           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON underdog_picks  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON folios          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON games           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON underdog_weeks  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON historial       TO authenticated;
GRANT SELECT, UPDATE                 ON config          TO authenticated;
GRANT SELECT                         ON week_snapshots  TO authenticated;
GRANT SELECT                         ON ranking         TO authenticated;

-- ─── Que las tablas futuras nazcan con permisos ────────────────────
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated;

-- ─── Comprobación ──────────────────────────────────────────────────
-- Debe devolver una fila por tabla, ninguna con "SIN PERMISO".
SELECT
  c.relname AS tabla,
  CASE WHEN has_table_privilege('anon',          c.oid, 'SELECT') THEN 'sí' ELSE '—' END AS anon_lee,
  CASE WHEN has_table_privilege('authenticated', c.oid, 'SELECT') THEN 'sí' ELSE 'SIN PERMISO' END AS user_lee
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r','v')
ORDER BY c.relname;
