/* =====================================================================
   SERVICE WORKER · Quiniela NFL La Corte
   =====================================================================

   Hace dos cosas:
     1. Permite instalar la app en el telefono (Android exige un service
        worker con manejador de fetch para ofrecer "Instalar").
     2. Deja la app usable sin senal, mostrando la ultima version vista.

   ⚠️ LA REGLA QUE NO SE PUEDE ROMPER: el HTML va SIEMPRE por red primero.

   Esta app es un solo index.html que se actualiza con cada `git push`. Si
   el HTML se sirviera desde cache primero, la gente se quedaria con una
   version vieja durante dias sin enterarse: cambias el puntaje, arreglas
   un bug, y a nadie le llega. Por eso:

     HTML   -> red primero, cache solo si no hay senal
     iconos -> cache primero (nunca cambian, y si cambian, cambia CACHE)

   Para publicar una version nueva de los archivos cacheados, sube el
   numero de CACHE. El `activate` borra los caches viejos.
   ===================================================================== */

// v4: board-calendario.webp cambio de contenido (pizarron del telefono en
// vez de "elige tu partido"). Mismo caso que v2/v3: sin subir este numero,
// quien ya abrio ese pizarron se queda con la version vieja cacheada.
const CACHE = 'quiniela-nfl-v4';

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

  // --- Iconos y manifest: cache primero ---
  // Lista explicita a proposito. Antes esta rama agarraba TODO lo del mismo
  // dominio, asi que cualquier archivo nuevo que se agregara al proyecto se
  // quedaba pegado en la cache vieja para siempre. Mejor que lo desconocido
  // vaya por red: como mucho se pierde el modo sin senal, no la correccion.
  const esEstatico = url.pathname.startsWith('/icons/') ||
                     url.pathname === '/manifest.json';
  if (!esEstatico) return;

  e.respondWith(
    caches.match(req).then((hit) =>
      hit || fetch(req).then((res) => {
        if (res.ok) {
          const copia = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copia));
        }
        return res;
      })
    )
  );
});
