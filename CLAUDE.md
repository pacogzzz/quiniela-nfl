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
supabase/migrations/005_privacidad_picks.sql  cierra los pronósticos ajenos
supabase/migrations/006_privacidad_bonos.sql  cierra los bonos ajenos
supabase/migrations/007_puntaje_temporada.sql puntaje final antes de arrancar
test/                           130 pruebas contra Postgres real (PGlite)
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
cd test && npm test     # suite.mjs (78 lógica) + rls.mjs (52 seguridad)
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
**quiniela · perfil · calendario · grupos · ranking · premios · historial ·
admin**, y la app abre en *quiniela*: a lo que entra la gente es a pronosticar.
La pestaña se llama PERFIL y no MI PERFIL porque con dos palabras el texto se
parte en dos renglones y desalinea la barra entera.

**El orden dentro de "quiniela" cambia con el ancho, y es a propósito.**
El marcado deja `<aside class="q-side">` (underdog + folio) antes que
`.q-main`, porque en escritorio es la columna izquierda. Debajo de 980 px el
CSS lo invierte con `order`: primero el tablero (MI QUINIELA + las seis cifras
+ *cómo se ganan puntos*), luego los partidos, y los dos accionables **hasta
el final**. Nada de marcado duplicado.

Medido a 375 px con 8 partidos: encabezado 80 · cifras 301 · ayuda 445 ·
selector de semana 605 · **primer partido 787**. Antes de mover el perfil a su
pestaña el primer partido caía en 1 478. Si se vuelve a meter algo arriba de
los partidos, hay que volver a medir.

`preview-diseno.html` fue la maqueta que se usó para aprobar el diseño. Ya está
integrado en la app; el archivo se puede borrar cuando estorbe.

**El Capi** es el guía de la quiniela y aparece de tres formas distintas:

- **Burbuja** (dentro de *quiniela*, pegada al desplegable de puntos): sólo la
  ilustración + *¿Cómo funciona?* + *Pregúntale al Capi*. `estadoCapi()` elige
  la pose según lo que falte —faltan ganadores → `ganador`, falta confianza →
  `confianza`, etc.— y `renderCapi()` la pinta y fija qué pizarrón abre.
- **Dentro de la tarjeta del underdog**: la lámina `underdog`, que es la única
  donde sale el bulldog. Abre el pizarrón del *ranking*, que es donde se
  explica el corte del lunes y quién puede jugarlo.
- **Estratega** (en *mi perfil*): la tarjeta grande con las jugadas concretas.
  Ver abajo.

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

## "Mi perfil" y El Estratega

La ficha de perfil salió de la columna izquierda de *quiniela* y ahora tiene su
propia pestaña. **Nada se repite y todo son cuadros del mismo tamaño**: arriba
una tira horizontal con nombre, rol y posición, y debajo una cifra por cuadro.
La lista vertical que había antes repetía los puntos totales y el porcentaje de
aciertos que ya salían arriba. Cuando el dato tiene dos formas (puntos y
conteo), el número grande son los **puntos** y el conteo va en la etiqueta
chica: nunca dos cuadros para lo mismo.

Lo nuevo de verdad es **El Estratega**: tres metas (top 10 · top 5 · #1) con la
distancia real en puntos, y debajo el Capi diciendo con qué jugadas se cierra
esa distancia.

Todo sale de datos reales y **nada se inventa**:

- La distancia sale de la vista `ranking`: `rankRows[9]`, `rankRows[4]` y
  `rankRows[0]` son quienes ocupan hoy esos lugares. Se suma 1 porque empatar
  no basta para pasar a nadie. Si ya está dentro de una meta, la tarjeta dice
  cuánta ventaja le lleva al primero que viene atrás de esa línea.
- Las jugadas salen de lo que esa persona **todavía puede hacer** esta semana
  (`oportunidadesSemana()` + `jugadasConfianza()`): si ya escogió underdog, si
  ya canjeó el folio del día o si el partido ya cerró, esa jugada no se
  sugiere. **Un consejo que no se puede seguir es peor que no dar consejo.**
- El orden es underdog → folios → primer anotador → aciertos, de lo más seguro
  a lo más difícil, y se corta en cuanto la suma cubre la distancia.

`comoCerrar()` es donde vive esa suma. Si el techo de la week no alcanza, dice
en cuántas weeks sí y cuántas quedan de temporada: el punto de todo esto es que
nadie sienta que ya perdió en la Week 3 de 22.

## Llenar por mí (autorrellenar)

`autollenar()` deja la week completa en un clic. Existe porque repartir 16
números uno por uno espanta a media banca, **y el que no llena no juega**.

No adivina el futuro ni compra momios: ordena los partidos por la diferencia de
récord entre los dos equipos —lo único objetivo y público que hay— y le da el
número más alto al que tiene el favorito más claro. También marca el primer
anotador de los estelares.

Dos cosas que no se deben quitar: pide confirmación si ya había pronósticos
—reemplaza todo— y en la Week 1, cuando nadie tiene récord, el aviso dice que
es un volado en vez de fingir que sabe algo. Los números ya gastados en
partidos cerrados no se reciclan.

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

17. **`ptsFolioDe()` en el JS es una copia de `puntos_por_fecha()` del SQL.**
    El Estratega necesita saber cuánto vale el folio de un día *antes* de que
    exista el folio, así que la regla (lun 10 · jue/dom 5 · mié/vie/sáb 15)
    está escrita en los dos lados. Si cambia en `001_init.sql`, cambia también
    en `index.html`: si no, el Capi promete puntos que la base no paga, que es
    exactamente la clase de error que hace que la gente deje de creerle.

    Lo mismo pasa con **`udPuntos()`**, que espeja el `COALESCE(puntos_a,
    puntos)` de la vista `ranking`. Toda regla de puntaje que el front tenga
    que anticipar vive en dos lugares; no hay forma de evitarlo sin pedirle al
    servidor un cálculo por cada tecla.

## Reglas de puntaje (configurables en la tabla `config`)

| Forma | Puntos |
|---|---|
| Confianza | El número que le pusiste, 1..N sin repetir. Con 16 partidos son **136 por week** |
| Anotador | 3 por acertar el primer equipo en anotar. **Solo estelares** (TNF · SNF · MNF) |
| Underdog | 8 · 10 · 12 según la opción. Solo para quienes están fuera del top 10 del corte del lunes |
| Consumo | folio por día: lun 10, jue/dom 5, extraordinarios (mié/vie/sáb) 15. Uno por persona por día |
| Bono | Puntos a mano desde ADMIN, por cualquier motivo. `instalacion` (25) se cobra solo, una vez por persona, al abrir la app instalada |

**Ya NO hay puntos fijos por acertar** (los viejos `pts_win_normal` = 5 y
`pts_win_especial` = 15). Se quitaron en `007_puntaje_temporada.sql`, config
incluida. Con el esquema anterior un partido extraordinario valía 15 + hasta
16 = 31 puntos, casi el doble que uno normal: la quiniela la decidía el
calendario y no quién le atinaba. El premio de los días raros se pasó al
folio, que es lo que a La Corte le sirve premiar.

`conf_mode` = **`solo` (oficial)** · `additive` · `flat`. Sigue siendo un
interruptor de la tabla `config` y cambiarlo recalcula todo el histórico al
instante; `additive` y `flat` leen los dos `pts_win_*` con su valor por
omisión, aunque ya no existan como renglones.

**El underdog es UNA ventana por week con TRES candidatos, no tres
oportunidades.** Cada quien escoge uno solo. Lo que cambia entre las tres
puertas es cuánto pagan (`puntos_a`, `puntos_b`, `puntos_c` en
`underdog_weeks`), para que el underdog más improbable valga más y escoger sea
de verdad una decisión. `puntos` quedó como el tope de la week y como respaldo
de las weeks viejas sin valores por opción.

**Ritual obligatorio:** cada lunes, ADMIN → *Cerrar week*. Congela la tabla y
de ahí sale la elegibilidad del underdog. Sin eso, el underdog no avanza.

## Convenciones

- Todo el texto de cara al usuario va en **español de México**, y del norte:
  como se habla en Tampico, no como sale de traducir del inglés. "Tu camino a
  la cima", no "tu camino hacia arriba"; "pégale a", no "acierta"; "a ese
  paso", no "a ese ritmo". Si una frase suena a manual traducido, está mal.
- **La jornada se llama "week", no "semana".** Es como le dice todo el que ve
  NFL. Los nombres de playoffs sí van en español (Comodines, Ronda Divisional,
  Final de Conferencia, Super Bowl) porque así se transmiten en México.
- Comentarios en español, explicando el *porqué* (sobre todo en el SQL).
- La llave `anon` es pública por diseño y vive en `index.html`. La `service_role`
  **nunca** se escribe en el repo.
- No romper la quiniela mundial: es otro proyecto, otra base de datos.
