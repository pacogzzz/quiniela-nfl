# 🏈 QUINIELA NFL · LA CORTE — Guía para quien la opera

Esta guía es para la persona que va a hacerse cargo de la quiniela: cambiarla,
probarla y operarla durante la temporada. No necesitas saber programar. Sí
necesitas entender cómo están acomodadas las piezas y qué NO tocar.

**La app en vivo:** https://quiniela-nfl-beta.vercel.app

---

## 1. Qué es esto, en corto

La quiniela son **tres servicios gratuitos** conectados entre sí:

| Pieza | Qué guarda | Piénsalo como |
|---|---|---|
| **GitHub** | El código | El archivero donde vive todo |
| **Supabase** | La base de datos | El cuaderno con los jugadores, partidos, puntos |
| **Vercel** | El sitio web | La ventana por donde entra la gente |

Y funcionan así:

```
  Tú cambias el código
          ↓
      GitHub  ──────►  Vercel  ──────►  la gente ve el cambio
                                            ↕
                                        Supabase
                                    (puntos y jugadores)
```

Lo importante: **cuando subes un cambio a GitHub, Vercel actualiza el sitio
solo, en menos de un minuto.** No hay que hacer nada más.

El proyecto es un solo archivo de página web (`index.html`) más el diseño de
la base de datos (`supabase/migrations/`). No hay compilación ni nada raro.

---

## 2. LO PRIMERO: consigue tus accesos

⚠️ **Nada de lo demás sirve si no resuelves esto.** Ahora mismo las tres
cuentas están a nombre de Paco. Elijan uno de estos caminos:

### Opción A — Te agregan como colaborador *(la más rápida)*

Paco sigue siendo dueño, tú puedes trabajar. Paco hace esto:

- **GitHub:** en el repo → Settings → Collaborators → te invita
- **Supabase:** Organization → Team → Invite member (rol *Owner* o *Administrator*)
- **Vercel:** Project → Settings → Members → te agrega

### Opción B — Te transfieren todo *(la más limpia si tú vas a ser el dueño)*

- **GitHub:** Settings → Danger Zone → Transfer ownership
- **Supabase:** Project Settings → General → Transfer project (a tu organización)
- **Vercel:** Project Settings → Transfer

### Opción C — Empiezas de cero en tus cuentas

Como todavía no hay jugadores registrados ni datos reales, esto casi no cuesta.
Sigues el `README.md` desde el paso 1. Tarda unos 20 minutos.

> **Recomendación:** si el restaurante es tuyo y vas a operar esto por años,
> ve por la **B** o la **C**. La **A** es buena si Paco va a seguir metido.

### ✅ Anota estos datos cuando tengas acceso

- [ ] Correo y contraseña de **GitHub**
- [ ] Correo y contraseña de **Supabase**
- [ ] Correo y contraseña de **Vercel**
- [ ] **Contraseña de la base de datos** de Supabase (es distinta a la de la cuenta)
- [ ] La carpeta del proyecto en tu computadora

---

## 3. Cómo hacer cambios (con Claude Code)

### Instalación, una sola vez

1. Instala **Claude Code**: https://claude.com/claude-code
2. Descarga el proyecto a tu computadora. En una terminal:
   ```
   git clone https://github.com/pacogzzz/quiniela-nfl.git
   cd quiniela-nfl
   ```
3. Dentro de esa carpeta, escribe `claude` y ya estás adentro.

### La regla de oro

**Habla en español, describe QUÉ quieres, no CÓMO se hace.** Claude lee el
proyecto completo y decide el cómo.

### Ejemplos que funcionan

> «Cambia los puntos de los folios del lunes de 10 a 15.»

> «Quiero agregar un premio para el lugar 11: una gorra. Actualiza la sección
> de premios.»

> «El botón de reservar debe mandar al WhatsApp 834 111 2233 en lugar del que
> tiene.»

> «Ya salió el calendario oficial de la NFL. Te paso los partidos de la semana
> 1, cárgalos.»

> «Un jugador dice que canjeó su folio y no le aparecieron los puntos.
> Revísalo.»

### Cómo pedir bien

| ✅ Hazlo así | ❌ Evita esto |
|---|---|
| «Los puntos del lunes ahora son 15» | «Cambia la variable pts_folio_lunes» |
| «Súbelo y que quede en línea» | (asumir que ya se subió solo) |
| «Antes de subirlo, corre las pruebas» | (subir cambios de base de datos sin probar) |
| «Muéstrame cómo quedó» | (confiar sin ver) |

### Después de cada cambio

Pídele siempre: **«súbelo a GitHub»**. Vercel actualiza el sitio en ~1 minuto.
Si no lo subes, el cambio solo existe en tu computadora.

### Hay pruebas automáticas — úsalas

El proyecto trae 93 pruebas que revisan que las reglas de puntos y la seguridad
funcionen. Se corren así:

```
cd test
npm install     (solo la primera vez)
npm test
```

**Siempre que se toque la base de datos, pide: «corre las pruebas antes de
subir».** Durante la construcción estas pruebas encontraron dos errores serios
de verdad, incluyendo uno que dejaba a cualquier jugador volverse administrador.
No son adorno.

---

## 4. Antes de que arranque la temporada

### 🔴 Cargar el calendario oficial — lo más importante

Ahora mismo **las fechas y horarios están correctos**, pero los enfrentamientos
dicen "Por definir". La NFL publica el calendario oficial en mayo. Cuando salga:

1. Entra a la app → pestaña **⚙️ ADMIN** → sección **IMPORTAR CALENDARIO OFICIAL**
2. Pega los partidos, uno por línea:
   ```
   semana,AAAA-MM-DD,HH:MM,VISITANTE,LOCAL,SLOT,estadio
   1,2026-09-10,19:15,DAL,PHI,TNF,Lincoln Financial Field
   ```
   La hora va en **hora de Tampico**. `SLOT` es `TNF`, `SUN`, `SUN_LATE`, `SNF`,
   `MNF` o `ESPECIAL`.
3. **Hazlo ANTES de que la gente empiece a pronosticar.** El importador
   reemplaza semanas completas y borra los pronósticos de esas semanas.

O más fácil: pídeselo a Claude Code y le pasas el calendario como lo tengas.

### Lo demás antes de arrancar

- [ ] Revisar que el teléfono/WhatsApp del restaurante sea el correcto
      (ADMIN → CONFIGURACIÓN → llaves `whatsapp` y `telefono`)
- [ ] Confirmar los 10 premios
- [ ] Publicar los 3 underdogs de la semana 1
- [ ] Imprimir folios de los primeros días de juego
- [ ] Probar todo con 2-3 amigos antes de repartir el link a las 200 personas
- [ ] Ya que probaste: **ADMIN → RESET GENERAL** para dejar la tabla limpia
      (borra pronósticos y puntos, NO borra usuarios ni calendario)

---

## 5. La rutina de cada semana

Esta es la parte que sí requiere disciplina. Toma unos 15 minutos por semana.

| Día | Qué haces |
|---|---|
| **Miércoles** | ADMIN → UNDERDOG → publicar los 3 equipos de la semana |
| **Jueves** | Generar folios del día antes de abrir. Al terminar el partido: cargar marcador y primer anotador |
| **Domingo** | Generar folios. Cargar los marcadores conforme terminan |
| **Lunes** | Generar folios. Cargar el último marcador → **CERRAR SEMANA** |

### ⚠️ Lo que más se olvida: cerrar la semana

Cada lunes, cuando ya cargaste todos los resultados, entra a
**ADMIN → CIERRE DE SEMANA** y presiona **Cerrar semana**.

Eso congela la tabla de ese día, y de ahí sale **quién puede jugar el underdog
la semana siguiente** (solo los que quedaron del lugar 11 hacia abajo).

**Si no cierras la semana, el underdog no avanza.** Es el paso más fácil de
olvidar y el que más reclamos genera.

---

## 6. El panel de ADMIN, sección por sección

Solo lo ves si tu perfil tiene rol `admin` o `manager`. Sabes que lo tienes
porque aparece la pestaña **⚙️ ADMIN** y una insignia dorada **ADMIN** junto a
tu nombre.

| Sección | Para qué |
|---|---|
| **Partidos y resultados** | Poner qué equipos juegan, el marcador final y qué equipo anotó primero |
| **Importar calendario** | Cargar muchos partidos de golpe |
| **Folios de consumo** | Generar los códigos que le das a la gente que consume. Eliges fecha y cantidad; el sistema calcula los puntos según el día |
| **Underdog de la semana** | Publicar los 3 equipos underdog y cuántos puntos valen |
| **Cierre de semana** | Congelar la tabla del lunes |
| **Configuración de puntaje** | Cambiar cuánto vale cada cosa, sin tocar código |
| **Historial** | Agregar quinielas pasadas |
| **Zona de peligro** | Reset general (ver advertencias abajo) |

### Cómo nombrar a otro administrador

Supabase → **Table Editor** → tabla `profiles` → busca a la persona → cambia
la columna `role`:

- `user` — jugador normal
- `manager` — puede cargar resultados, generar folios, cerrar semanas
- `admin` — todo lo anterior + configuración, importar calendario y reset

Para los meseros o encargados que solo van a generar folios y cargar
marcadores, usa **`manager`**. Deja `admin` para ti.

---

## 7. Las reglas de la quiniela, en resumen

Hay **4 formas de ganar puntos**:

1. **Confianza** — Cada semana repartes valores del 1 al N (N = partidos de esa
   semana) sin repetir. Le pones el número más alto al partido del que estás
   más seguro. Si le atinas al ganador: **5 puntos + el número que le pusiste**.
   En partidos extraordinarios (miércoles, viernes, sábado) son **15 + tu número**.
   Todo se cierra en el primer kickoff de la semana.

2. **Consumo** — Folios que se entregan al consumir. Lunes 10 puntos (para
   jalar gente el día flojo), jueves y domingo 5. Uno por persona por día.

3. **Anotador** — 3 puntos por atinarle al primer equipo que anota, solo en
   partidos estelares (Thursday, Sunday y Monday Night, más los extraordinarios).

4. **Underdog** — Solo para quienes van del lugar 11 hacia abajo. Eligen 1 de 3
   equipos; si gana, +20 puntos. Si pierde, no pasa nada.

**La idea:** que todos puedan ganar. Por eso los puntos de juego pesan más que
los de consumo, y por eso existe el underdog para los que van atrás.

El detalle completo está en `README.md`.

---

## 8. Cosas que NO debes hacer

🚫 **No corras "RESET GENERAL" con la temporada empezada.** Borra todos los
pronósticos, puntos y folios de todo el mundo. No se puede deshacer.

🚫 **No importes el calendario a media temporada** sin avisar. Reemplaza semanas
completas y borra los pronósticos de esas semanas.

🚫 **Nunca compartas la llave `service_role`** de Supabase (Settings → API).
Esa sí es secreta y da control total. La llave `anon` en cambio es pública a
propósito: va dentro de la página web, cualquiera la puede ver, y no es un
problema — lo que protege los datos son las reglas de seguridad de la base.

🚫 **No cambies el puntaje a media temporada** sin avisarle a los jugadores.
El sistema recalcula todo el histórico al instante, así que las posiciones
cambian de golpe.

🚫 **No subas cambios de base de datos sin correr las pruebas.**

---

## 9. Si algo se rompe

### «La página no carga / sale error de permisos»

Lo más probable: el proyecto de Supabase se **pausó por inactividad** (el plan
gratis pausa después de ~1 semana sin uso). Entra al dashboard de Supabase y
dale **Restore**. No se pierde nada.

### «No me llega el correo para entrar»

1. Revisa spam.
2. Supabase → Authentication → URL Configuration: el **Site URL** debe ser la
   dirección real de la app.
3. Supabase → Authentication → Providers → Email debe estar encendido.

### «Un jugador dice que sus puntos están mal»

Casi siempre es una de tres:
- Falta cargar el marcador de un partido
- El primer anotador quedó vacío
- No se cerró la semana (afecta el underdog)

Pídele a Claude Code: **«revisa por qué a [nombre] no le cuadran los puntos»**.

### Cuando de plano no sepas

Abre Claude Code en la carpeta del proyecto y **describe lo que ves**, tal cual,
incluyendo el mensaje de error completo si hay uno. No hace falta que sepas
qué significa.

---

## 10. Referencia rápida

| | |
|---|---|
| **App** | https://quiniela-nfl-beta.vercel.app |
| **Código** | https://github.com/pacogzzz/quiniela-nfl |
| **Base de datos** | supabase.com → proyecto `quiniela-nfl` |
| **Hosting** | vercel.com → proyecto `quiniela-nfl` |
| **Arranca la temporada** | Jueves 10 de septiembre de 2026 |
| **Termina** | Super Bowl LXI, domingo 14 de febrero de 2027 |

### Los archivos

| Archivo | Qué es |
|---|---|
| `index.html` | La app completa. Aquí vive todo lo que se ve |
| `supabase/migrations/001_init.sql` | El diseño de la base de datos |
| `supabase/migrations/002_grants.sql` | Permisos de la base de datos |
| `test/` | Las 93 pruebas automáticas |
| `README.md` | Documentación técnica a detalle |
| `EMPIEZA-AQUI.md` | Este documento |

---

## Una nota honesta

Esta app la construyó Claude (el asistente de IA) junto con Paco. Durante la
construcción, Claude cometió errores reales: dejó un hueco que permitía a
cualquier jugador volverse administrador, y olvidó permisos de base de datos
que tumbaron la app en producción. **Los dos se detectaron con las pruebas
automáticas y probando en el navegador, no leyendo el código.**

La moraleja para ti: cuando pidas un cambio, pide también que se pruebe y que
te enseñen el resultado. Claude es muy útil y muy rápido, pero no infalible.
Las pruebas están ahí por algo.
