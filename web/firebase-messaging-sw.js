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
  messaging.onBackgroundMessage(() => {});
} catch (_) {}
