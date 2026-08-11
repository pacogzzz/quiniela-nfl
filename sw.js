/* =====================================================================
   SERVICE WORKER · Quiniela NFL La Corte
   =====================================================================

   Hace dos cosas:
     1. Permite instalar la app en el telefono (Android exige un service
        worker con manejador de fetch para ofrecer "Instalar").
     2. Deja la app usable sin senal, mostrando la ultima version vista.

   ⚠️ LA REGLA QUE NO SE PUEDE ROMPER: el HTML y los iconos van SIEMPRE
   por red primero.

   Esta app es un solo index.html que se actualiza con cada `git push`, y
   sus iconos (el Capi, los pizarrones de "cómo funciona", etc.) cambian
   de contenido de vez en cuando SIN cambiar de nombre de archivo. Si algo
   se sirviera de la cache primero, quien ya lo hubiera visto se quedaria
   con la version vieja para siempre —pasó ya varias veces con distintas
   imagenes antes de este cambio. Por eso todo va igual:

     HTML e iconos -> red primero, cache SOLO si no hay señal

   La cache deja de ser la fuente de verdad; es nada más el respaldo para
   cuando el celular no tiene internet. Ya no hace falta acordarse de subir
   CACHE cada vez que una imagen cambia de contenido —eso es justo lo que
   fallaba antes.
   ===================================================================== */

const CACHE = 'quiniela-nfl-v6';

// Lo minimo para que la app abra sin senal.
const BASICOS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/apple-touch-icon.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE)
      // addAll falla entero si UN archivo falla; los metemos de a uno para
      // que un icono faltante no tumbe toda la instalacion.
      .then((c) => Promise.allSettled(BASICOS.map((u) => c.add(u))))
      // Sin esto el service worker nuevo se queda "esperando" a que el
      // usuario cierre todas las pestanas. Con la app instalada eso puede
      // no pasar en semanas.
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;

  // Solo GET. Nada de tocar los POST/PATCH que van a Supabase.
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Todo lo que no sea de este dominio (la API de Supabase, el CDN, el
  // realtime por websocket) pasa de largo sin que lo toquemos. Cachear
  // respuestas de la API dejaria ranking y marcadores congelados.
  if (url.origin !== location.origin) return;

  // --- HTML: red primero ---
  // Se mira TAMBIEN la ruta, no solo mode/accept: una peticion de index.html
  // hecha desde JS no es "navigate" y manda accept: */*, asi que sin esto se
  // colaba a la rama de cache y devolvia la app vieja.
  const esHTML = req.mode === 'navigate' ||
                 (req.headers.get('accept') || '').includes('text/html') ||
                 url.pathname === '/' ||
                 url.pathname.endsWith('.html');

  if (esHTML) {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copia = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copia));
          return res;
        })
        .catch(async () =>
          (await caches.match(req)) ||
          (await caches.match('/index.html')) ||
          Response.error()
        )
    );
    return;
  }

  // --- Iconos y manifest: red primero, cache solo de respaldo ---
  // Lista explicita a proposito. Antes esta rama agarraba TODO lo del mismo
  // dominio, asi que cualquier archivo nuevo que se agregara al proyecto se
  // quedaba pegado en la cache vieja para siempre. Mejor que lo desconocido
  // vaya por red: como mucho se pierde el modo sin senal, no la correccion.
  const esEstatico = url.pathname.startsWith('/icons/') ||
                     url.pathname === '/manifest.json';
  if (!esEstatico) return;

  // Iban por cache primero, y esa fue justo la causa de que varias imagenes
  // (el pizarron del calendario, el de confianza, el Capi del cierre de
  // semana...) se quedaran viejas en celulares que ya las habian visto,
  // aunque el archivo en el servidor ya fuera el correcto. La cache normal
  // del navegador (Cache-Control en vercel.json) ya evita descargar de más
  // cuando nada cambió; esta cache aparte solo entra si de plano no hay
  // señal.
  e.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copia = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copia));
        }
        return res;
      })
      .catch(() => caches.match(req))
  );
});
