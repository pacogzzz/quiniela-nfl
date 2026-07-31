# Quiniela NFL · La Corte — contexto del proyecto

App de quiniela de la NFL para el restaurante La Corte (Tampico), temporada
2026-27, ~200 participantes. Proyecto independiente de `quiniela-mundial`.

- **En vivo:** https://quiniela-nfl-beta.vercel.app
- **Supabase:** proyecto `wyjriexqwypqbnuegykd`
- **Arranca:** jueves 10-sep-2026 · **Termina:** Super Bowl LXI, 14-feb-2027

## Arquitectura

Un solo archivo (`index.html`) con Supabase por CDN. **Sin build, sin
framework, sin dependencias.** Desplegar = `git push` (Vercel redespliega solo
en ~1 min).

```
index.html                      la app completa (HTML + CSS + JS en línea)
supabase/migrations/001_init.sql esquema, RLS, RPCs, calendario sembrado
supabase/migrations/002_grants.sql permisos de tabla
test/                           93 pruebas contra Postgres real (PGlite)
EMPIEZA-AQUI.md                 guía para quien opera (no técnico)
README.md                       referencia técnica
```

## Pruebas — córrelas antes de subir cambios de SQL

```bash
cd test && npm test     # suite.mjs (60 lógica) + rls.mjs (33 seguridad)
```

Levantan un Postgres real en WASM, aplican las migraciones y verifican reglas
de puntaje y políticas de seguridad. **No necesitan Docker ni credenciales.**

Estas pruebas ya atraparon dos bugs reales. Si tocas el esquema o el puntaje,
agrega la prueba correspondiente.

## Trampas conocidas (aprendidas a golpes)

1. **RLS no basta: también hacen falta los GRANT.** Postgres tiene dos candados
   independientes. Políticas RLS perfectas + sin `GRANT` = `permission denied
   for table`. Toda tabla nueva necesita su GRANT en `001_init.sql`.
   El arnés de pruebas **no** concede permisos a propósito, justo para cachar esto.

2. **`current_user` no sirve dentro de `SECURITY DEFINER`** — devuelve el dueño
   de la función (`postgres`), no quien la llama. Para saber si hay un usuario
   real usa `auth.uid() IS NOT NULL`; NULL significa editor SQL / service_role.

3. **El login es por ENLACE, no por código.** La plantilla de correo de Supabase
   manda `{{ .ConfirmationURL }}`. Al hacer clic la página se recarga y se pierde
   lo capturado, por eso nombre y teléfono se guardan en `localStorage`
   (`PEND_KEY`) antes de enviar y el perfil se crea al regresar.

4. **`signInWithOtp` crea el usuario en `auth.users` al MANDAR el correo**, no al
   verificarlo. De ahí salen usuarios sin fila en `profiles`; existe el paso de
   rescate `pedirPerfil()`.

5. **Los emparejamientos del calendario están en TBD.** Las fechas son reales; los
   equipos se cargan con el importador de ADMIN cuando la NFL publique el oficial.
   No inventar partidos.

## Reglas de puntaje (configurables en la tabla `config`)

| Forma | Puntos |
|---|---|
| Confianza | 5 + valor asignado (1..N sin repetir); 15 + valor en extraordinarios (mié/vie/sáb) |
| Consumo | folio por día: lun 10, jue/dom 5, extraordinarios 10. Uno por persona por día |
| Anotador | 3 por acertar el primer equipo en anotar (solo estelares) |
| Underdog | 20 si acierta. Solo para quienes están fuera del top 10 del corte del lunes |

`conf_mode` = `additive` (oficial) · `flat` · `solo`. Cambiarlo recalcula todo
el histórico al instante.

**Ritual obligatorio:** cada lunes, ADMIN → *Cerrar semana*. Congela la tabla y
de ahí sale la elegibilidad del underdog. Sin eso, el underdog no avanza.

## Convenciones

- Todo el texto de cara al usuario va en **español de México**.
- Comentarios en español, explicando el *porqué* (sobre todo en el SQL).
- La llave `anon` es pública por diseño y vive en `index.html`. La `service_role`
  **nunca** se escribe en el repo.
- No romper la quiniela mundial: es otro proyecto, otra base de datos.
