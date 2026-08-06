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
manifest.json · sw.js · icons/  PWA: permiten instalarla en el teléfono
vercel.json                     cabeceras de caché (ver trampa 6)
supabase/migrations/001_init.sql esquema, RLS, RPCs, calendario sembrado
supabase/migrations/002_grants.sql permisos de tabla
supabase/migrations/003_bonos.sql  delta de bonos para la base ya desplegada
supabase/migrations/004_login_usuario.sql delta del login con usuario
test/                           117 pruebas contra Postgres real (PGlite)
EMPIEZA-AQUI.md                 guía para quien opera (no técnico)
README.md                       referencia técnica
```

**Las migraciones se aplican de dos maneras.** `001_init.sql` es la fuente de
verdad y lo único que cargan las pruebas: toda tabla nueva va ahí. Los archivos
numerados aparte (`003_bonos.sql`) son el *delta* para la base que ya está
corriendo en Supabase, que no puede volver a ejecutar `001` completo. Cuando
agregues algo al esquema, va en los dos lados.

## Pruebas — córrelas antes de subir cambios de SQL

```bash
cd test && npm test     # suite.mjs (76 lógica) + rls.mjs (41 seguridad)
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

3. **Se entra con USUARIO + CONTRASEÑA, sin enlaces ni códigos.** Supabase solo
   sabe autenticar por correo, así que el front traduce usuario → correo con la
   RPC `correo_de_usuario()` (`SECURITY DEFINER`, la puede llamar `anon` porque
   se usa *antes* de haber sesión) y con ese correo pide la sesión.
   **Requisito del panel: "Confirm email" tiene que estar APAGADO** en
   Authentication → Providers → Email. Encendido, `signUp` no devuelve sesión y
   el registro se queda a medias.

4. **El correo se sigue pidiendo, y no es opcional.** Es la única vía de
   recuperar la contraseña (`resetPasswordForEmail`). Al volver de ese correo la
   URL trae `type=recovery` y Supabase deja una **sesión temporal válida**:
   `initApp()` lo detecta *antes* de entrar a la app, porque si no el usuario
   entraría sin cambiar su contraseña.

   Sigue existiendo `pedirPerfil()` como rescate: si `signUp` crea la cuenta pero
   el insert en `profiles` falla, queda una cuenta sin perfil. Por eso el usuario
   se valida con `usuario_disponible()` **antes** de crear la cuenta.

5. **Los emparejamientos del calendario están en TBD.** Las fechas son reales; los
   equipos se cargan con el importador de ADMIN cuando la NFL publique el oficial.
   No inventar partidos.

6. **El service worker sirve el HTML por RED PRIMERO, nunca desde caché.** La app
   es un solo `index.html` que se actualiza con cada `git push`. Si se cacheara
   primero, la gente que la tiene instalada se quedaría con la versión vieja
   durante días. Por eso `sw.js` usa network-first para el HTML, la rama de caché
   solo acepta `/icons/` y `/manifest.json`, y `vercel.json` prohíbe que el CDN
   cachee `sw.js`. Si tocas el service worker, verifica que un cambio en
   `index.html` de verdad llegue tras recargar.

7. **`ALTER DEFAULT PRIVILEGES` cambia el resultado según CUÁNDO se crea la tabla.**
   `001_init.sql` termina concediendo CRUD completo a `authenticated` sobre toda
   tabla creada *después*. Una tabla nueva declarada dentro de `001` no lo hereda,
   pero la misma tabla creada por un delta (que corre después) sí. Resultado: la
   base migrada y una instalación nueva quedan con permisos distintos. Cierra la
   diferencia con un `REVOKE` explícito en ambos archivos, como hace `bonos`.

8. **`vercel.json` no admite comentarios, ni con la llave `"//"`.** Vercel valida
   ese archivo contra un esquema estricto y rechaza cualquier propiedad que no
   reconozca. El despliegue truena de inmediato, antes de construir, con
   `should NOT have additional property`. El truco de `"//"` funciona en
   `package.json` de npm, aquí no. El *porqué* de esas cabeceras va en este
   archivo (trampa 6), no en el JSON.

9. **Los despliegues los dispara un Deploy Hook, no la integración de Git.**
   Vercel en plan Hobby sólo publica commits cuyo autor de GitHub esté ligado a
   la cuenta dueña del proyecto, así que los push de un colaborador quedaban
   bloqueados. `.github/workflows/deploy.yml` llama un Deploy Hook —que no revisa
   autoría— con el secret `VERCEL_DEPLOY_HOOK` del repo. Si nadie ve sus cambios
   en vivo, revisa primero la pestaña **Actions** de GitHub, no el panel de Vercel.

10. **Una prueba de seguridad que corre como `anon` NO prueba al participante.**
    `picks read` estuvo en `USING (true)` toda la vida: cualquiera con sesión leía
    los pronósticos de los otros ~200 antes del kickoff. La prueba que debía
    cacharlo ("NO puede ver pronósticos ajenos") corría como visitante sin cuenta,
    y `anon` nunca tuvo permiso — pasaba en verde sin probar nada. Toda política
    nueva se prueba desde los **dos** roles. Arreglado en `005_privacidad_picks.sql`.

    **El mismo `USING (true)` estaba en `bonos`** y se encontró después, por la
    misma vía. Ahí no se filtraban los puntos (el ranking ya publica `pts_bono`
    de todos) sino el **motivo**, que lo escribe ADMIN a mano. Cerrado en
    `006_privacidad_bonos.sql`. Si aparece otra tabla con `USING (true)` para
    `authenticated`, la pregunta correcta es *¿qué columna de aquí no debería
    ver el de al lado?*, no *¿son públicos los totales?*.

## Diseño: "La Corte premium" (agosto 2026)

Carbón `#0B0D10` + dorado `#D4AF37`, tipografías Bebas Neue (títulos) e Inter
(texto), ambas por CDN de Google. **El dorado marca jerarquía y acción — nunca
decora.** Los tokens viven en `:root` al inicio del `<style>`; los alias viejos
(`--dorado`, `--azul`) siguen ahí porque el JS los escribe en estilos en línea.

Móvil primero: la navegación es una barra fija abajo y solo a partir de 980 px
sube a pestañas bajo el header. El orden de las pestañas es
**quiniela · calendario · grupos · ranking · premios · historial · admin**, y
la app abre en *quiniela*: a lo que entra la gente es a pronosticar.

En la pantalla de quiniela la columna izquierda es perfil → Capi →
underdog/folio/premios, y la derecha los partidos. **En celular todo eso va
arriba de los partidos**, así que las seis cifras y los tres accionables se
vuelven carruseles horizontales por debajo de 720 px. Apilados sumaban 1 600 px
y el primer partido quedaba a tres pantallas de scroll; con los carruseles
queda a 1 478 px. Si se agrega algo más a esa columna, hay que volver a medir.

`preview-diseno.html` fue la maqueta que se usó para aprobar el diseño. Ya está
integrado en la app; el archivo se puede borrar cuando estorbe.

**El Capi** es el guía de la quiniela. `renderCapi()` elige **texto y pose
juntos** según el estado real: faltan ganadores → pose `ganador`, falta
confianza → `confianza`, falta underdog → `underdog`, etc. No es adorno.

Las 12 poses viven en `icons/capi/<momento>.webp`. El nombre es el momento, no
el número de lámina, y la lista está en `CAPI_POSES` dentro de `index.html`.
Las demás pestañas llevan una tarjeta fija que se arma sola desde
`data-capi` / `data-txt` en el HTML (ver `pintarCapiTips()`).

**Tres láminas son pizarrones, no poses:** `calendario`, `confianza` y
`ranking` traen texto explicando la mecánica. A 100 px ese texto no se lee, así
que de cada una salen DOS archivos: `<momento>.webp` (solo el personaje,
recortado) para la tarjeta y `board-<momento>.webp` (la lámina entera, 900 px)
que se abre en el modal con el botón *¿Cómo funciona?*. La lista está en
`CAPI_BOARDS`; el recorte del personaje, en `CON_PIZARRON` del optimizador.

**Las poses nuevas se optimizan antes de subirlas:** `python
tools/optimiza-capi.py <carpeta>`. Los PNG de Canva pesan ~700 KB cada uno y se
ven a 100 px; el script los deja en ~25 KB de WebP (8.3 MB → 313 KB). Subir los
originales al repo es tirar el plan de datos de 200 personas.

La corona de La Corte es **SVG en línea** (`#ic-corona`), no el emoji 👑:
Windows lo pinta morado, Android amarillo y iOS con joyas, y es la marca.

11. **Los logos de la NFL NO se guardan en el repo.** Son marca registrada y el
    repo es público. Se sirven del CDN de ESPN
    (`a.espncdn.com/i/teamlogos/nfl/500/<code>.png`), que usa nuestro mismo
    código de tres letras salvo Washington (`WAS` → `wsh`, ver `ESPN_SLUG`).
    Si la imagen no carga, `onerror` la borra y queda el círculo con las
    iniciales: el diseño nunca se rompe, ni sin red.

12. **Nada de `background-attachment:fixed`.** Con 16 partidos la página mide
    ~7000 px y el navegador tiene que repintar el fondo en cada cuadro del
    scroll. Se probó y congelaba el render. Si hace falta un fondo que no se
    mueva, se usa un pseudo-elemento con `position:fixed`, no esa propiedad.

13. **Las variables del JS son `let`, así que NO están en `window`.** Al depurar
    desde la consola, `sbProfile = {...}` (sin prefijo) sí toca la variable real,
    pero `iframe.contentWindow.sbProfile = {...}` no hace nada: hay que usar
    `contentWindow.eval('...')`. Las funciones sí son accesibles porque son
    declaraciones de función.

14. **El bono de instalación tiene DOS trampas, una por sistema.**

    *Android:* el evento `appinstalled` llega mientras seguimos en la pestaña
    del navegador, no en la app. Ahí `appInstalada()` todavía dice `false`, así
    que hay que cobrar el bono a la fuerza —`revisarBonoInstalacion(true)`—
    porque el aviso viene del navegador y es tan confiable como el modo
    standalone. Sin eso, quien instalaba desde Android **nunca** veía sus
    25 puntos.

    *iPhone:* no existe ningún evento. La única señal es `navigator.standalone`,
    que solo es `true` cuando la persona abre desde el ícono. Y iOS le da a la
    app instalada un **almacén aparte del de Safari**, así que ahí no hay
    sesión: tiene que volver a entrar con su usuario, y es en ese login donde
    cae el bono. Los pasos de la hoja de instalación dicen esto explícitamente;
    si se recortan, vuelve la queja de "instalé y no me dieron mis puntos".

    El renglón *Instala la app +25* del perfil existe para que el pendiente se
    vea, en vez de que la gente se entere por casualidad.

15. **La app SÍ abre en pantalla completa; el requisito es Safari.** El manifest
    trae `display: standalone` y el HTML las metas `apple-mobile-web-app-*`.
    Si alguien ve la barra de Safari abajo, el ícono se creó desde otro
    navegador (Chrome iOS, o el navegador interno de WhatsApp) o es un ícono
    viejo: se borra y se vuelve a agregar desde Safari.

16. **Si cambia `manifest.json`, sube el número de `CACHE` en `sw.js`.** El
    manifest se sirve *cache primero*, así que sin ese cambio la gente que ya
    tiene la app instalada se queda con el viejo para siempre.

## Reglas de puntaje (configurables en la tabla `config`)

| Forma | Puntos |
|---|---|
| Confianza | 5 + valor asignado (1..N sin repetir); 15 + valor en extraordinarios (mié/vie/sáb) |
| Consumo | folio por día: lun 10, jue/dom 5, extraordinarios 10. Uno por persona por día |
| Anotador | 3 por acertar el primer equipo en anotar (solo estelares) |
| Underdog | 20 si acierta. Solo para quienes están fuera del top 10 del corte del lunes |
| Bono | Puntos a mano desde ADMIN, por cualquier motivo. `instalacion` (25) se cobra solo, una vez por persona, al abrir la app instalada |

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
