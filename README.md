# 🏈 QUINIELA NFL EN LA CORTE · Temporada 2026-27

> 👉 **¿Vas a operar la quiniela y no eres programador?** Empieza por
> **[EMPIEZA-AQUI.md](EMPIEZA-AQUI.md)** — accesos, rutina semanal y cómo pedirle
> cambios a Claude Code. Este README es la referencia técnica a detalle.

App de una sola página respaldada por Supabase. Pensada para ~200 participantes de la
comunidad de La Corte, con ranking en tiempo real.

> **Proyecto nuevo e independiente.** No toca ni reemplaza la quiniela mundial.
> Se despliega en su propio proyecto de Supabase y su propia URL de Vercel.

---

## ⚠️ LEE ESTO PRIMERO — el calendario

La NFL publica el calendario oficial de la temporada 2026 en mayo de 2026, y **los
enfrentamientos exactos no están cargados en esta app**. No los inventé: cargar
partidos falsos sería peor que dejarlos vacíos.

Lo que **sí** está cargado y es correcto:

| Elemento | Estado |
|---|---|
| Los 32 equipos, conferencias y divisiones | ✅ Completo |
| Estructura de 18 semanas + 4 rondas de playoffs | ✅ Completo |
| Fechas y horarios de cada jornada (jue/dom/lun) | ✅ Completo |
| Fechas extraordinarias (Thanksgiving, Black Friday, Navidad, sábados de diciembre) | ✅ Completo |
| **Qué equipo juega contra qué equipo** | ⬜ Por definir (TBD) |

**Cómo lo completas:** panel **ADMIN → IMPORTAR CALENDARIO OFICIAL**. Pegas el calendario
en texto plano y la app lo carga de golpe. Formato, una línea por partido:

```
semana,AAAA-MM-DD,HH:MM,VISITANTE,LOCAL,SLOT,estadio
1,2026-09-10,19:15,DAL,PHI,TNF,Lincoln Financial Field
1,2026-09-13,12:00,ATL,TB,SUN,Raymond James Stadium
1,2026-09-14,19:15,KC,LV,MNF,Allegiant Stadium
```

- La hora va en **hora de Tampico (CST, UTC-6)**.
- `SLOT` = `TNF` · `SUN` · `SUN_LATE` · `SNF` · `MNF` · `ESPECIAL`.
- Códigos de equipo: `BUF MIA NE NYJ BAL CIN CLE PIT HOU IND JAX TEN DEN KC LV LAC DAL NYG PHI WAS CHI DET GB MIN ATL CAR NO TB ARI LAR SF SEA`.
- El import **reemplaza por completo** las semanas que aparezcan en el texto. Hazlo antes
  de que la gente empiece a pronosticar.

También puedes editar partido por partido en **ADMIN → PARTIDOS Y RESULTADOS**.

### Fechas base que ya están cargadas

Semana 1 arranca el **jueves 10 de septiembre de 2026** (el jueves posterior al Labor Day).
Cada semana N: jueves = 10-sep-2026 + 7×(N-1).

| Fecha | Qué es | Cómo quedó marcado |
|---|---|---|
| Jue 26-nov-2026 | Thanksgiving (3 juegos) | Estelares (anotador), puntaje normal |
| Vie 27-nov-2026 | Black Friday | ⭐ Extraordinario (15 pts) |
| Sáb 19-dic-2026 | Sábado de diciembre | ⭐ Extraordinario |
| Vie 25-dic-2026 | Navidad (3 juegos) | ⭐ Extraordinario |
| Sáb 2-ene-2027 | Sábado de fin de año | ⭐ Extraordinario |
| Dom 10-ene-2027 | Semana 18 (todo domingo) | Normal |
| 16-18 ene 2027 | Comodines | Sáb = extraordinario |
| 23-24 ene 2027 | Divisional | Sáb = extraordinario |
| 31 ene 2027 | Finales de Conferencia | Normal |
| **Dom 14-feb-2027** | **Super Bowl LXI** | Estelar |

Son ~6 meses de temporada, como lo planeaste. Verifica estas fechas contra el calendario
oficial cuando salga y corrígelas en el import si hace falta.

---

## 🎯 Las 4 formas de ganar puntos

### 1. Puntos de confianza

Cada semana tiene **N partidos**. Antes del primer kickoff repartes los valores de
confianza **1 a N, sin repetir ninguno** (el N va al partido que más seguro te sientes).
Cuando arranca la semana, **se cierra todo**.

Por cada **ganador acertado**:

| Tipo de partido | Puntos fijos | + tu confianza |
|---|---|---|
| Normal (jue/dom/lun) | **5** | + el valor que le pusiste |
| ⭐ Extraordinario (mié/vie/sáb) | **15** | + el valor que le pusiste |

**Ejemplo — semana de 16 partidos, todos acertados:**

```
Partido más seguro (confianza 16) →  5 + 16 = 21 pts
Segundo más seguro (confianza 15) →  5 + 15 = 20 pts
...
Menos seguro       (confianza  1) →  5 +  1 =  6 pts
                                     ------------
MÁXIMO SEMANAL                          216 pts
```

Un partido extraordinario usa 15 en lugar de 5, así que puede valer hasta 31 puntos él solo.

> **Nota sobre esta regla.** En el documento original había dos cosas que no encajaban:
> *"repartirán sus 16 puntos de confianza"* y *"5 puntos por ganador acertado… 17 partidos
> = 85 puntos"* (las 85 salen solo del fijo, sin sumar la confianza). Quedó confirmado
> el modo **fijo + confianza**, que es el que hace que repartir la confianza cambie algo.
>
> Si algún día quieres cambiarlo, es una sola llave en **ADMIN → CONFIGURACIÓN**.
> `conf_mode` acepta:
>
> - `additive` — 5 (ó 15) **+** la confianza asignada. ← **el oficial**
> - `flat` — solo los 5 (ó 15). Los números de confianza quedan de orden visual.
> - `solo` — solo la confianza, sin el fijo. La quiniela de confianza clásica de la NFL.
>
> El cambio aplica a todo el histórico automáticamente, sin recalcular nada a mano.

La app cuenta sola cuántos partidos hay cada semana, así que las semanas con byes o con
juegos movidos ajustan el rango de confianza sin que hagas nada.

### 2. Puntos de consumo (folios)

| Día | Puntos |
|---|---|
| Lunes | **10** (el incentivo del día flojo) |
| Jueves | **5** |
| Domingo | **5** |
| Día extraordinario (mié/vie/sáb) | **10** (configurable) |

Cómo funciona: en **ADMIN → FOLIOS** generas un lote de folios para una fecha (por
ejemplo 30 folios para el domingo). Se imprimen o se anotan y se le entrega uno a cada
consumidor **al momento de empezar a consumir** — no importa qué ni cuánto consuma. El
cliente lo captura en la pestaña QUINIELA y se le abonan los puntos.

- Cada folio es de **un solo uso**.
- **Un folio canjeado por persona por día** (la base de datos lo bloquea; nadie puede
  juntar cinco folios del mismo domingo).

### 3. Puntos de anotador

Solo en **partidos estelares**: Thursday Night, Sunday Night, Monday Night, más los
extraordinarios de miércoles/viernes/sábado. Aciertas **qué equipo anota primero** y
te llevas **3 puntos** por partido.

### 4. Underdog 🦄

- Cada semana el admin publica **3 equipos underdog** (opción A, B y C) en
  **ADMIN → UNDERDOG DE LA SEMANA**.
- Solo pueden jugarlo **los que quedaron del lugar #11 hacia abajo** en el corte del lunes
  anterior. Los del top 10 ven un mensaje explicándoles por qué no les toca.
- Eliges **uno**. Si gana su partido: **+20 puntos** (configurable). Si pierde: no pasa
  nada, no se resta.
- La ventana se abre el miércoles y cierra con el primer kickoff de la semana.

**Importante — el corte del lunes:** cada lunes, cuando ya cargaste todos los resultados,
entra a **ADMIN → CIERRE DE SEMANA** y presiona *Cerrar semana*. Eso congela la tabla de
ese día y de ahí sale quién puede jugar el underdog la semana siguiente. **Si no cierras
la semana, la elegibilidad no avanza.**

---

## 🧭 Secciones de la app

| Pestaña | Qué tiene |
|---|---|
| **GRUPOS** | Los 32 equipos por conferencia y división, con récord G-P-E y puntos a favor/contra, actualizado con los resultados que cargas |
| **CALENDARIO** | Todos los partidos con filtros (semana, equipo, horario, fecha) y botón **RESERVAR** que abre WhatsApp con el mensaje ya escrito |
| **QUINIELA** | Selector de semana, marcador de mis puntos, tabla de cómo se ganan puntos, captura de folios, caja del Underdog y la hoja de pronósticos de la semana |
| **RANKING** | Tabla del #1 hacia abajo con el desglose por tipo de punto, y una línea marcando dónde empieza la zona Underdog |
| **HISTORIAL** | Quinielas pasadas de La Corte (ya viene cargada la del Mundial 2026). Se editan desde ADMIN |
| **PREMIOS** | Los 10 premios y tu posición actual |
| **ADMIN** | Solo visible para `admin` / `manager` |

---

## 🚀 Instalación

### Paso 1 — Proyecto de Supabase **nuevo**

1. [supabase.com](https://supabase.com) → **New project**.
2. Nómbralo `quiniela-nfl` (⚠️ **no** reutilices el proyecto del mundial).
3. Contraseña fuerte, región `us-east-1` o `us-west-1`.
4. Guarda la contraseña de la base en tu gestor de contraseñas. No es la misma
   que la de tu cuenta y no se puede recuperar después, solo resetear.

> **Si estás usando una cuenta de Supabase distinta a la del mundial:** perfecto,
> el código no cambia nada. La app se conecta con dos valores de texto (URL y llave
> anon) que pegas en el Paso 5. Nada más está enlazado a una cuenta.
>
> Dos cosas que sí conviene tener presentes:
>
> - **El plan gratis pausa los proyectos tras ~1 semana sin actividad.** Si montas
>   esto en verano y la temporada arranca en septiembre, lo vas a encontrar pausado.
>   No se pierde nada: se despausa desde el dashboard con un clic y los datos siguen
>   ahí. Solo entra una vez cada tantos días, o date por enterado de que el primer
>   día que abras la app en septiembre tendrás que despausarlo primero.
> - **La quiniela mundial se queda en la cuenta vieja.** Su parche de seguridad
>   (`002_fix_profiles_guard.sql`) hay que correrlo allá, en el proyecto del mundial,
>   no aquí.

### Paso 2 — Correr la migración

1. Supabase → **SQL Editor** → **New query**.
2. Pega **todo** el contenido de `supabase/migrations/001_init.sql` y dale **Run**.
3. En **Table Editor** debes ver: `profiles`, `teams`, `games`, `picks`, `folios`,
   `underdog_weeks`, `underdog_picks`, `week_snapshots`, `historial`, `config`.
4. `teams` debe tener 32 filas y `games` **301** (288 de temporada regular + 13 de playoffs).

   > La plantilla trae 16 partidos por semana (los 32 equipos jugando). En la realidad,
   > las semanas con byes tienen menos. Eso se corrige solo cuando importes el
   > calendario oficial, que reemplaza la semana completa.

### Paso 3 — Activar login por correo (OTP)

1. **Authentication → Providers → Email**: habilitado.
2. Activa **Confirm email** (modo OTP, no magic link).
3. **Authentication → URL Configuration**: pon tu URL de Vercel en *Site URL* y en
   *Redirect URLs* (lo puedes actualizar después de desplegar).

### Paso 4 — Credenciales

**Settings → API**, copia el **Project URL** y la llave **anon / public**.

### Paso 5 — Pegarlas en `index.html`

Busca estas dos líneas cerca del inicio del `<script>`:

```js
const SUPABASE_URL      = 'https://YOUR_PROJECT_REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

Reemplázalas por las tuyas y guarda.

> La llave `anon` es pública a propósito: lo que protege los datos son las políticas de
> Row Level Security, no el secreto de la llave.

### Paso 6 — Desplegar en Vercel

**Opción A (recomendada):** sube el repo a GitHub → [vercel.com](https://vercel.com) →
**New Project** → importa el repo → deja todo por defecto (sin build command,
output `./`) → **Deploy**.

**Opción B:**
```bash
npm i -g vercel
vercel --prod
```

Después regresa a Supabase → **Authentication → URL Configuration** y pon ahí la URL final.

### Paso 7 — Hacerte admin

1. Abre la app desplegada y regístrate con tu correo.
2. Supabase → **Table Editor** → `profiles` → busca tu fila y cambia `role` de `user` a `admin`.
3. Recarga la app: aparece la pestaña **ADMIN**.

### Paso 8 — Verificar Realtime

Supabase → **Database → Replication** (o *Publications*) → confirma que `supabase_realtime`
incluya `games`, `picks`, `folios`, `underdog_picks` y `underdog_weeks`. La migración
intenta agregarlas sola; si alguna no quedó, actívala con el switch.

---

## 👥 Roles

| Rol | Puede hacer |
|---|---|
| `user` | Registrarse, pronosticar, canjear folios, jugar underdog |
| `manager` | Todo lo anterior + cargar resultados, generar folios, configurar underdog, cerrar semanas |
| `admin` | Todo + importar calendario, editar configuración de puntaje, historial, reset |

Se cambian en **Table Editor → `profiles` → columna `role`**.

---

## ⚙️ Configuración de puntaje

Todo se edita en **ADMIN → CONFIGURACIÓN DE PUNTAJE** sin tocar código.

| Llave | Default | Qué hace |
|---|---|---|
| `pts_win_normal` | `5` | Ganador acertado, partido normal |
| `pts_win_especial` | `15` | Ganador acertado, partido extraordinario |
| `conf_mode` | `additive` | `additive` · `flat` · `solo` (ver arriba) |
| `pts_anotador` | `3` | Primer equipo en anotar, partidos estelares |
| `pts_underdog` | `20` | Acertar el underdog de la semana |
| `pts_folio_lunes` | `10` | Folio de consumo, lunes |
| `pts_folio_jueves` | `5` | Folio de consumo, jueves |
| `pts_folio_domingo` | `5` | Folio de consumo, domingo |
| `pts_folio_especial` | `10` | Folio de consumo, día extraordinario |
| `lock_mode` | `semana` | `semana` = todo cierra al primer kickoff · `partido` = cada juego cierra en su hora |
| `underdog_top_n` | `10` | Solo juegan underdog los que están debajo de esta posición |
| `whatsapp` | `528343144848` | WhatsApp del restaurante (con lada país, sin `+`) |
| `telefono` | `8343144848` | Teléfono para el botón de llamar |

> `pts_underdog` es el valor por defecto al crear una semana; cada semana guarda su propio
> valor de puntos, así que puedes hacer una semana más generosa que otra.

---

## 🗓️ Rutina semanal sugerida

| Día | Qué haces en ADMIN |
|---|---|
| **Miércoles** | Publicar los 3 underdogs de la semana |
| **Jue / dom / lun** | Generar los folios del día antes de abrir; cargar resultados y primer anotador conforme terminan los partidos |
| **Lunes (tarde-noche)** | Cargar el último resultado → **Cerrar semana** |

---

## 🔒 Qué está protegido a nivel base de datos

No basta con esconder botones: estas reglas se aplican en Postgres, así que no se pueden
saltar desde el navegador.

- Nadie puede guardar ni modificar pronósticos después del cierre de la semana.
- Los valores de confianza **no se pueden repetir** dentro de una misma semana
  (índice único, más validación en el guardado).
- Un folio solo se canjea una vez, y solo **un folio por persona por día**.
- El underdog solo lo puede registrar quien está fuera del top 10 según el último corte.
- Los resultados solo los cargan `admin` y `manager`.
- Cada quien solo puede escribir sus propios pronósticos.

---

## ✅ Pruebas automatizadas

La migración y las reglas de seguridad están probadas contra un **Postgres 18 real**
(PGlite, corre en Node, no necesita Docker ni instalar nada más).

```bash
cd test
npm install
npm test
```

**93 pruebas**, en dos bloques:

`suite.mjs` — **60 pruebas de lógica**
- Estructura: 32 equipos, 301 partidos, 27 políticas, RLS activo en las 10 tablas
- Fechas: que el arranque caiga en jueves, Thanksgiving en jueves 26-nov,
  Black Friday en viernes, Navidad en viernes, Super Bowl en domingo 14-feb
- Auto-marcado: que mié/vie/sáb queden como extraordinarios y que ningún
  jue/dom/lun se marque por error
- Puntaje: que `(5+16) + 0 + (15+1) = 37` sea exactamente lo que da el ranking
- Que un empate no reparta puntos
- Que no se puedan repetir valores de confianza (por índice y por validación)
- Que **intercambiar** dos confianzas (16↔15) funcione — el bug clásico de este tipo de app
- Que borrar un pronóstico de verdad lo borre
- Que tras el kickoff ya no se pueda guardar nada
- Folios: valor correcto por día, un solo uso, uno por persona por día
- Underdog: acierto, y que el corte del lunes decida bien quién es elegible
- Que cambiar `conf_mode` recalcule todo el histórico al instante

`rls.mjs` — **33 pruebas de seguridad**, simulando roles reales de Supabase.
Que un jugador normal **no pueda**: escribir pronósticos a nombre de otro, cargar
marcadores, cambiar el puntaje, borrar partidos, fabricarse folios, leer folios
ajenos, editar el underdog, **ascenderse a admin**, escribir el historial ni
inventarse un corte de semana. Y que **sí pueda** hacer lo suyo, que el admin
sí pueda administrar, y que un visitante sin cuenta solo vea el calendario.

> Si tocas el SQL, corre `npm test` antes de subirlo. Estas pruebas ya atraparon
> un hueco real de escalación de privilegios durante el desarrollo.

---

## 🧪 Probar con datos antes de la temporada

Como la temporada empieza en septiembre, todo aparece "abierto". Para probar el flujo
completo de puntos:

1. Importa 2-3 partidos de prueba con fecha pasada.
2. Cárgales marcador y primer anotador en ADMIN.
3. Revisa que el RANKING sume bien.
4. Cuando termines, **ADMIN → RESET GENERAL** limpia pronósticos, folios, cortes y
   resultados (no borra usuarios ni el calendario).

---

## 💻 Desarrollo local

Abre `index.html` en el navegador. No hay build. Solo asegúrate de tener las credenciales
de Supabase puestas en el archivo.
