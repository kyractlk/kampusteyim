/**
 * Keep only: Platform Admin, AYS Tech, Mühendislik Topluluğu, Kayra Çatalkaya (+ Guard bot).
 * Delete ALL posts. Delete other users (Auth via CF + Firestore).
 * Give Kayra gold tick linked to AYS Tech.
 *
 * node tools/purge_keep_core.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = {
  email: 'admin@gaunengineering.com.tr',
  password: '123456',
};

const KEEP_EMAILS = new Set([
  'admin@gaunengineering.com.tr',
  'hr@aystech.com',
  'mt@gantep.edu.tr',
  'info@aystech.com.tr',
  'kayra@gaunengineering.com.tr',
  'kayra@aystech.com',
  'kayra@aystech.com.tr',
  'guard@aystech.com',
]);

const KEEP_NAME_PATTERNS = [
  /^platform\s*admin$/i,
  /^ays\s*tech$/i,
  /mühendislik\s*toplulu/i,
  /muhendislik\s*toplulu/i,
  /kayra\s*çatalkaya/i,
  /kayra\s*catalkaya/i,
  /^ays\s*tech\s*guard$/i,
];

const KEEP_USERNAMES = new Set([
  'admin',
  'aystech',
  'muhendislik',
  'aystechbot',
  'kayra',
  'kayracatalkaya',
]);

const KEEP_IDS = new Set([
  'admin',
  'company_ays',
  'community',
  'ays_guard',
]);

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
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}'), raw });
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

function request(method, url, idToken, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const u = new URL(url);
    const headers = { Authorization: `Bearer ${idToken}` };
    if (data) {
      headers['Content-Type'] = 'application/json';
      headers['Content-Length'] = Buffer.byteLength(data);
    }
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method,
        headers,
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => {
          let json = {};
          try {
            json = JSON.parse(raw || '{}');
          } catch (_) {
            json = { raw };
          }
          resolve({ status: res.statusCode, json, raw });
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function fieldStr(fields, key) {
  const f = fields?.[key];
  if (!f) return '';
  if (f.stringValue != null) return f.stringValue;
  if (f.integerValue != null) return String(f.integerValue);
  if (f.booleanValue != null) return String(f.booleanValue);
  return '';
}

function keepUser(doc) {
  const name = `${fieldStr(doc.fields, 'firstName')} ${fieldStr(doc.fields, 'lastName')}`.trim();
  const full = fieldStr(doc.fields, 'fullName') || name;
  const email = fieldStr(doc.fields, 'email').toLowerCase();
  const username = fieldStr(doc.fields, 'username').toLowerCase();
  const id = doc.name.split('/').pop();
  const stable = fieldStr(doc.fields, 'stableId') || id;

  if (KEEP_IDS.has(id) || KEEP_IDS.has(stable)) return true;
  if (email && KEEP_EMAILS.has(email)) return true;
  if (username && KEEP_USERNAMES.has(username)) return true;
  if (KEEP_NAME_PATTERNS.some((re) => re.test(full) || re.test(name))) return true;
  if (/kayra/i.test(full) && /çatalkaya|catalkaya/i.test(full)) return true;
  // Keep deleted stubs? No — skip those without keep match
  return false;
}

async function listAll(idToken, collection) {
  const docs = [];
  let pageToken = '';
  do {
    let url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${collection}?pageSize=300`;
    if (pageToken) url += `&pageToken=${encodeURIComponent(pageToken)}`;
    const res = await request('GET', url, idToken);
    const batch = res.json.documents || [];
    docs.push(...batch);
    pageToken = res.json.nextPageToken || '';
  } while (pageToken);
  return docs;
}

async function deleteDoc(idToken, name) {
  const path = name.split('/documents/')[1];
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  return request('DELETE', url, idToken);
}

async function patchDoc(idToken, path, fields) {
  const keys = Object.keys(fields);
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}?${keys
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&')}`;
  return request('PATCH', url, idToken, { fields });
}

async function callAdminDelete(idToken, uid, email) {
  // Firebase callable HTTP protocol
  return postJson(
    `https://europe-west1-${PROJECT}.cloudfunctions.net/adminDeleteAccount`,
    { data: { uid, email } },
    { Authorization: `Bearer ${idToken}` },
  );
}

async function main() {
  console.log('Auth…');
  const sign = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      email: ADMIN.email,
      password: ADMIN.password,
      returnSecureToken: true,
    },
  );
  if (sign.status !== 200 || !sign.json.idToken) {
    console.error('Login failed', sign.status, sign.json);
    process.exit(1);
  }
  const idToken = sign.json.idToken;
  console.log('Logged in as', ADMIN.email);

  console.log('Listing users…');
  const users = await listAll(idToken, 'users');
  console.log('Users total:', users.length);
  const keep = [];
  const drop = [];
  for (const u of users) {
    const id = u.name.split('/').pop();
    const full =
      fieldStr(u.fields, 'fullName') ||
      `${fieldStr(u.fields, 'firstName')} ${fieldStr(u.fields, 'lastName')}`.trim();
    const email = fieldStr(u.fields, 'email');
    const username = fieldStr(u.fields, 'username');
    if (keepUser(u)) {
      keep.push({ id, full, email, username });
    } else {
      drop.push({ id, full, email, username, doc: u });
    }
  }
  console.log('\nKEEP (' + keep.length + '):');
  keep.forEach((k) => console.log('  ', k.id, '|', k.email, '|', k.full, '| @' + k.username));
  console.log('\nDROP (' + drop.length + '):');
  drop.forEach((d) => console.log('  ', d.id, '|', d.email, '|', d.full, '| @' + d.username));

  console.log('\nDeleting ALL posts…');
  const posts = await listAll(idToken, 'posts');
  console.log('Posts total:', posts.length);
  let deletedPosts = 0;
  for (const p of posts) {
    const res = await deleteDoc(idToken, p.name);
    if (res.status >= 200 && res.status < 300) deletedPosts += 1;
    else console.warn('post delete fail', res.status, p.name.split('/').pop());
  }
  console.log('Deleted posts:', deletedPosts);

  console.log('\nDeleting study_rooms…');
  const rooms = await listAll(idToken, 'study_rooms');
  let deletedRooms = 0;
  for (const r of rooms) {
    const res = await deleteDoc(idToken, r.name);
    if (res.status >= 200 && res.status < 300) deletedRooms += 1;
  }
  console.log('Deleted study_rooms:', deletedRooms, '/', rooms.length);

  console.log('\nDeleting non-keep users…');
  let deletedUsers = 0;
  for (const d of drop) {
    const cf = await callAdminDelete(idToken, d.id, d.email);
    const result = cf.json?.result || cf.json?.error || cf.json;
    if (cf.status >= 200 && cf.status < 300 && !cf.json?.error) {
      deletedUsers += 1;
      console.log('OK CF', d.id, d.full);
    } else {
      console.warn('CF fail', d.id, cf.status, JSON.stringify(result).slice(0, 250));
      // Fallback: Firestore doc delete only
      const res = await deleteDoc(idToken, d.doc.name);
      if (res.status >= 200 && res.status < 300) {
        deletedUsers += 1;
        console.log('OK FS', d.id, d.full);
      } else {
        console.warn('FS fail', d.id, res.status, res.raw?.slice?.(0, 200));
      }
    }
  }
  console.log('Deleted users:', deletedUsers);

  let kayra = keep.find(
    (k) => /kayra/i.test(k.full) && /çatalkaya|catalkaya/i.test(k.full),
  );
  if (!kayra) {
    kayra = keep.find((k) => /kayra/i.test(k.full) || /kayra/i.test(k.username || ''));
  }
  let ays = keep.find(
    (k) =>
      (/^ays\s*tech$/i.test(k.full) || k.username === 'aystech' || k.id === 'company_ays') &&
      !/guard/i.test(k.full),
  );
  console.log('\nKayra:', kayra);
  console.log('AYS Tech:', ays);

  if (kayra && ays) {
    console.log('Giving Kayra gold tick linked to AYS Tech…');
    const patch = await patchDoc(idToken, `users/${kayra.id}`, {
      hasGoldBadge: { booleanValue: true },
      hasBlueBadge: { booleanValue: false },
      affiliatedCommunityId: { stringValue: ays.id },
      affiliatedCommunityName: { stringValue: 'AYS Tech' },
      updatedAt: { stringValue: new Date().toISOString() },
    });
    console.log('Kayra patch', patch.status, JSON.stringify(patch.json).slice(0, 400));
  } else {
    console.warn('Kayra or AYS not found — check KEEP list above');
  }

  console.log('\nDone.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
