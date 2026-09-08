/* Firebase Cloud Messaging service worker (web). */
/* eslint-disable no-undef */
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE',
  authDomain: 'ayskampuss.firebaseapp.com',
  projectId: 'ayskampuss',
  storageBucket: 'ayskampuss.firebasestorage.app',
  messagingSenderId: '378741313538',
  appId: '1:378741313538:web:d6941781b364ee6c91971b',
  measurementId: 'G-LY8L1F561Z',
});

try {
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage((payload) => {
    const n = (payload && payload.notification) || {};
    const d = (payload && payload.data) || {};
    const title = n.title || d.title || 'KampüsteyimAPP';
    const body = n.body || d.body || '';
    if (!body && title === 'KampüsteyimAPP') return;
    return self.registration.showNotification(title, {
      body,
      icon: '/kampusteyim_icon.png',
      badge: '/kampusteyim_icon.png',
      data: d,
    });
  });
} catch (_) {}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = (event.notification && event.notification.data) || {};
  const link = data.link || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (let i = 0; i < list.length; i += 1) {
        const client = list[i];
        if (client.url && 'focus' in client) {
          client.focus();
          return;
        }
      }
      if (clients.openWindow) return clients.openWindow(link);
      return undefined;
    }),
  );
});
