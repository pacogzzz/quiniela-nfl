// Recrea lo mínimo de Supabase que la migración necesita, para poder
// correrla contra un Postgres real (PGlite) sin Docker.
export const SHIM = `
CREATE ROLE authenticated;
CREATE ROLE anon;
CREATE ROLE service_role;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE auth.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT
);
-- auth.uid() de Supabase lee el JWT; aquí lo simulamos con una GUC de sesión
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $f$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID
$f$;
CREATE PUBLICATION supabase_realtime;
-- Supabase concede esto de fabrica; sin ello las FK a auth.users fallan
-- y algunos tests pasarian por la razon equivocada.
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
GRANT SELECT ON auth.users TO authenticated, anon;
`;
