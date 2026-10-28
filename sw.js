const CACHE = 'theone-v82';
const PRECACHE = [
  './TheOne_V6.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './son_hit.wav',
  './son_victoire.wav',
  './son_defaite.mp3',
  './son_mucus.mp3',
  './son_kill.mp3',
  './son_ambiance.m4a',
  'https://cdnjs.cloudflare.com/ajax/libs/howler/2.2.4/howler.min.js',
  'https://unpkg.com/react@18.3.1/umd/react.production.min.js',
  'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

function putInCache(req, res) {
  if (res && res.status === 200 && res.type !== 'opaque') {
    const clone = res.clone();
    caches.open(CACHE).then(c => c.put(req, clone));
  }
  return res;
}

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const isPage = e.request.mode === 'navigate' || e.request.destination === 'document';
  if (isPage) {
    // Page: network first so updates show up on the next launch; cache only when offline
    e.respondWith(
      fetch(e.request).then(res => putInCache(e.request, res))
        .catch(() => caches.match(e.request).then(c => c || caches.match('./TheOne_V6.html')))
    );
    return;
  }
  // Assets (sounds, icons, libraries, fonts): cache first, then network
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request).then(res => putInCache(e.request, res)))
  );
});
