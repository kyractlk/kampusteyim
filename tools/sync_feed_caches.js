/** node tools/sync_feed_caches.js — süresi dolmuş story / eski reel temizliği */
const https = require('https');
const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = { email: 'admin@gaunengineering.com.tr', password: '123456' };

function postJson(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
          ...headers,
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}') });
          } catch (e) {
            resolve({ status: res.statusCode, json: {}, raw });
          }
        });
      },
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

(async () => {
  const sign = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email: ADMIN.email, password: ADMIN.password, returnSecureToken: true },
  );
  if (sign.status !== 200 || !sign.json.idToken) {
    console.error('Login failed', sign.json);
    process.exit(1);
  }
  const res = await postJson(
    `https://europe-west1-${PROJECT}.cloudfunctions.net/syncFeedCaches`,
    { data: {} },
    { Authorization: `Bearer ${sign.json.idToken}` },
  );
  console.log('HTTP', res.status);
  if (res.json?.error) {
    console.error(res.json.error);
    process.exit(1);
  }
  console.log(JSON.stringify(res.json?.result || res.json, null, 2));
})();
