/**
 * Wipe + seed gönderiler (Twitter tarzı — gövdede link yok).
 * Paylaşım linki paylaş butonundan gelir.
 * node tools/seed_posts.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = {
  email: 'admin@gaunengineering.com.tr',
  password: '123456',
};

const AUTHOR = {
  admin: 'admin',
  community: 'community',
  company_ays: 'company_ays',
};

const now = Date.now();
const ago = (ms) => new Date(now - ms).toISOString();

const posts = [
  {
    id: 'test_mt_kickoff',
    authorId: AUTHOR.community,
    authorName: 'Mühendislik Topluluğu',
    authorHandle: '@muhendislik',
    content:
      'Yeni dönem kick-off Perşembe 18:30 · A Blok amfi.\nTakvimini şimdiden boşalt 👋\n#mt #kampüs #etkinlik',
    createdAt: ago(25 * 60 * 1000),
    likeCount: 12,
    replyCount: 1,
    repostCount: 2,
    isCommunity: true,
    hashtags: ['mt', 'kampüs', 'etkinlik'],
    media: [{ url: 'https://picsum.photos/seed/mtkicktest/800/500', type: 'image' }],
  },
  {
    id: 'test_ays_staj',
    authorId: AUTHOR.company_ays,
    authorName: 'AYS Tech',
    authorHandle: '@aystech',
    content:
      'Yaz staj başvuruları açıldı — Flutter & Firebase.\nÖzgeçmişini CV-AI ile hazırlayıp başvurabilirsin.\n#staj #aystech #flutter',
    createdAt: ago(2 * 3600 * 1000),
    likeCount: 8,
    replyCount: 0,
    repostCount: 1,
    isCommunity: false,
    hashtags: ['staj', 'aystech', 'flutter'],
    media: [{ url: 'https://picsum.photos/seed/aysstaj/800/500', type: 'image' }],
  },
  {
    id: 'test_mt_summit',
    authorId: AUTHOR.community,
    authorName: 'Mühendislik Topluluğu',
    authorHandle: '@muhendislik',
    content:
      'GAÜN Tech Summit 2026 erken kayıt başladı.\nKonuşmacılar ve atölyeler yakında.\n#techsummit #gaun',
    createdAt: ago(8 * 3600 * 1000),
    likeCount: 21,
    replyCount: 1,
    repostCount: 4,
    isCommunity: true,
    hashtags: ['techsummit', 'gaun'],
    media: [{ url: 'https://picsum.photos/seed/summittest/800/500', type: 'image' }],
  },
  {
    id: 'test_ays_cv',
    authorId: AUTHOR.company_ays,
    authorName: 'AYS Tech',
    authorHandle: '@aystech',
    content:
      'CV-AI ile ATS uyumlu özgeçmiş: dil seç, üret, indir.\nFirma başvurularında fark yaratır.\n#cv #ats #aystech',
    createdAt: ago(24 * 3600 * 1000),
    likeCount: 15,
    replyCount: 0,
    repostCount: 2,
    isCommunity: false,
    hashtags: ['cv', 'ats', 'aystech'],
    media: [],
  },
  {
    id: 'test_mt_hackathon',
    authorId: AUTHOR.community,
    authorName: 'Mühendislik Topluluğu',
    authorHandle: '@muhendislik',
    content:
      'Hackathon mentör saatleri Cumartesi 14:00–17:00.\nTakımını getir, sorunu çözelim.\n#hackathon #mt',
    createdAt: ago(28 * 3600 * 1000),
    likeCount: 9,
    replyCount: 0,
    repostCount: 1,
    isCommunity: true,
    hashtags: ['hackathon', 'mt'],
    media: [],
  },
];

const comments = [
  {
    id: 'test_c1',
    postId: 'test_mt_kickoff',
    authorId: AUTHOR.admin,
    authorName: 'Platform Admin',
    authorHandle: '@admin',
    content: 'Not alındı, yayındayız 🚀',
    createdAt: ago(18 * 60 * 1000),
    likeCount: 2,
    isPinned: true,
  },
  {
    id: 'test_c2',
    postId: 'test_mt_summit',
    authorId: AUTHOR.company_ays,
    authorName: 'AYS Tech',
    authorHandle: '@aystech',
    content: 'Sponsor masamız hazır — görüşmek üzere.',
    createdAt: ago(6 * 3600 * 1000),
    likeCount: 3,
  },
];

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

function toFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    if (typeof v === 'string') out[k] = { stringValue: v };
    else if (typeof v === 'boolean') out[k] = { booleanValue: v };
    else if (typeof v === 'number') out[k] = { integerValue: String(v) };
    else if (Array.isArray(v)) {
      out[k] = {
        arrayValue: {
          values: v.map((x) => {
            if (typeof x === 'string') return { stringValue: x };
            if (typeof x === 'object') {
              return { mapValue: { fields: toFields(x) } };
            }
            return { booleanValue: !!x };
          }),
        },
      };
    } else if (typeof v === 'object') {
      out[k] = { mapValue: { fields: toFields(v) } };
    }
  }
  return out;
}

function listCollection(idToken, collection) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${collection}?pageSize=300`;
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
            const json = JSON.parse(raw || '{}');
            resolve(json.documents || []);
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

function deleteDoc(idToken, name) {
  const path = name.split('/documents/')[1];
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: 'DELETE',
        headers: { Authorization: `Bearer ${idToken}` },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => (raw += c));
        res.on('end', () => resolve({ status: res.statusCode }));
      },
    );
    req.on('error', reject);
    req.end();
  });
}

function patchDoc(idToken, docPath, fields) {
  const keys = Object.keys(fields);
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}?${keys
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&')}`;
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ fields: toFields(fields) });
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
        res.on('end', () => resolve({ status: res.statusCode, body: raw }));
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

(async () => {
  const auth = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email: ADMIN.email, password: ADMIN.password, returnSecureToken: true },
  );
  if (auth.status !== 200 || !auth.json.idToken) {
    console.error('Admin giriş başarısız', auth.status, auth.json);
    process.exit(1);
  }
  const token = auth.json.idToken;

  for (const col of ['posts', 'reports', 'comments']) {
    try {
      const docs = await listCollection(token, col);
      for (const d of docs) {
        const del = await deleteDoc(token, d.name);
        console.log(`DEL ${d.name.split('/').pop()} → ${del.status}`);
      }
    } catch (e) {
      console.warn(`wipe ${col}:`, e.message || e);
    }
  }

  for (const p of posts) {
    const { id, ...fields } = p;
    const res = await patchDoc(token, `posts/${id}`, fields);
    console.log(`posts/${id} → ${res.status}`);
  }
  for (const c of comments) {
    const { id, ...fields } = c;
    const res = await patchDoc(token, `comments/${id}`, fields);
    console.log(`comments/${id} → ${res.status}`);
  }
  console.log(`Seed bitti · ${posts.length} gönderi (link gömülü değil)`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
