/**
 * Nefret içeren test postlarını soft-delete (Guard kota hatası sonrası temizlik).
 * node tools/purge_hate_posts.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = {
  email: 'admin@gaunengineering.com.tr',
  password: '123456',
};

function postJson(url, body) {
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
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}') });
          } catch (e) {
            reject(e);
          }
        });
      },
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function listPosts(idToken) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/posts?pageSize=100`;
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: 'GET',
        headers: { Authorization: `Bearer ${idToken}` },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(raw || '{}').documents || []);
          } catch (e) {
            reject(e);
          }
        });
      },
    );
    req.on('error', reject);
    req.end();
  });
}

function patchPost(idToken, docPath, fields) {
  const keys = Object.keys(fields);
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}?${keys
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&')}`;
  const body = JSON.stringify({
    fields: Object.fromEntries(
      Object.entries(fields).map(([k, v]) => {
        if (typeof v === 'boolean') return [k, { booleanValue: v }];
        if (typeof v === 'number') return [k, { doubleValue: v }];
        return [k, { stringValue: String(v) }];
      }),
    ),
  });
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${idToken}`,
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => resolve(res.statusCode));
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function isHate(content) {
  const t = String(content || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/ş/g, 's')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c');
  const compact = t.replace(/[^a-z]/g, '');
  let masked = compact;
  for (const s of [
    'psikoloji',
    'psikolog',
    'sikayet',
    'klasik',
    'muzik',
    'fizik',
    'bisiklet',
  ]) {
    masked = masked.split(s).join('x'.repeat(s.length));
  }
  return (
    compact.includes('zenci') ||
    compact.includes('nigger') ||
    compact.includes('siktir') ||
    compact.includes('orospu') ||
    (masked.includes('sik') && (compact.length >= 8 || !/\s/.test(t.trim()))) ||
    (/olum/.test(t) && /zenci/.test(t))
  );
}

(async () => {
  const auth = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email: ADMIN.email, password: ADMIN.password, returnSecureToken: true },
  );
  const token = auth.json.idToken;
  if (!token) {
    console.error('auth fail', auth.json);
    process.exit(1);
  }
  const docs = await listPosts(token);
  let n = 0;
  for (const d of docs) {
    const id = d.name.split('/').pop();
    const content = d.fields?.content?.stringValue || '';
    if (!isHate(content)) continue;
    const code = await patchPost(token, `posts/${id}`, {
      deletedAt: new Date().toISOString(),
      deletedBy: 'ays_guard',
      moderatedByGuard: true,
      guardDecision: 'block',
      guardSummary: 'Nefret içeriği — kota sonrası yerel temizlik',
      guardConfidence: 0.99,
    });
    console.log('SOFT-DEL', id, content.slice(0, 40), '→', code);
    n += 1;
  }
  console.log(`Bitti · ${n} gönderi soft-delete`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
