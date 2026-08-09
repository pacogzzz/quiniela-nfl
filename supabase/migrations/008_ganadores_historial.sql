-- Delta para la base ya desplegada: agrega puntos y premio por cada uno de
-- los 3 ganadores del historial, para poder mostrarlos en tarjetas de podio
-- en vez de una sola línea de texto libre. Ver 001_init.sql (fuente de verdad).

ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_1_puntos INT  NOT NULL DEFAULT 0;
ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_1_premio TEXT NOT NULL DEFAULT '';
ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_2_puntos INT  NOT NULL DEFAULT 0;
ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_2_premio TEXT NOT NULL DEFAULT '';
ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_3_puntos INT  NOT NULL DEFAULT 0;
ALTER TABLE historial ADD COLUMN IF NOT EXISTS ganador_3_premio TEXT NOT NULL DEFAULT '';
