/**
 * Seed: Firebase Auth + Firestore demo kullanıcıları.
 * Çalıştır: node tools/seed_firebase_users.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';

/** Sadece admin + MT + AYS Tech + Guard AI */
const STABLE_IDS = {
  'admin@gaunengineering.com.tr': 'admin',
  'mt@gantep.edu.tr': 'community',
  'hr@aystech.com': 'company_ays',
  'guard@aystech.com': 'ays_guard',
};

const users = [
  {
    email: 'admin@gaunengineering.com.tr',
    password: '123456',
    firstName: 'Platform',
    lastName: 'Admin',
    role: 'admin',
    isSuperAdmin: true,
    staffRoleId: 'role_super',
    bio: 'KampüsteyimAPP süper admin · tüm yetkiler açık',
    studentNo: '000000001',
    username: 'admin',
    usernameStatus: 'ok',
  },
  {
    email: 'mt@gantep.edu.tr',
    password: '123456',
    firstName: 'Mühendislik',
    lastName: 'Topluluğu',
    role: 'community',
    isCommunity: true,
    hasGoldBadge: true,
    communityLogoUrl: 'assets/logos/mt_circle.png',
    bio: 'Gaziantep Üniversitesi Mühendislik Topluluğu resmi hesabı',
    studentNo: '000000000',
    username: 'muhendislik',
    usernameStatus: 'ok',
  },
  {
    email: 'hr@aystech.com',
    password: '123456',
    firstName: 'AYS Tech',
    lastName: '',
    role: 'company',
    studentNo: 'C00001',
    hasGoldBadge: true,
    username: 'aystech',
    usernameStatus: 'ok',
    communityLogoUrl: 'assets/logos/ays_circle.png',
    bio:
      'Firma hesabı · staj ve iş ilanları · onaylı işveren · AYS Tech',
    linksWeb: 'https://aystech.com.tr',
  },
  {
    email: 'guard@aystech.com',
    password: '123456',
    firstName: 'AYS Tech',
    lastName: 'Guard',
    role: 'company',
    studentNo: 'AI0001',
    hasBlueBadge: true,
    isBot: true,
    username: 'aystechbot',
    usernameStatus: 'ok',
    communityLogoUrl: 'assets/logos/ays_guard_circle.png',
    photoUrl: 'assets/logos/ays_guard_circle.png',
    bio:
      'KampüsteyimAPP platform AI’si · içerik güvenliği, moderasyon ve yardımcı asistan. AYS Tech tarafından işletilir.',
    linksWeb: 'https://aystech.com.tr',
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

function patchFirestore(idToken, docPath, fields) {
  // Firestore REST: convert simple map to fields format
  const toFields = (obj) => {
    const out = {};
    for (const [k, v] of Object.entries(obj)) {
      if (v === undefined || v === null) continue;
      if (typeof v === 'string') out[k] = { stringValue: v };
      else if (typeof v === 'boolean') out[k] = { booleanValue: v };
      else if (typeof v === 'number') out[k] = { integerValue: String(v) };
      else if (Array.isArray(v)) {
        out[k] = {
          arrayValue: {
            values: v.map((x) =>
              typeof x === 'string' ? { stringValue: x } : { booleanValue: !!x },
            ),
          },
        };
      } else if (typeof v === 'object') {
        out[k] = { mapValue: { fields: toFields(v) } };
      }
    }
    return out;
  };

  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}?updateMask.fieldPaths=${Object.keys(fields)
    .map(encodeURIComponent)
    .join('&updateMask.fieldPaths=')}`;

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
        res.on('end', () =>
          resolve({ status: res.statusCode, body: raw }),
        );
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function ensureUser(u) {
  // 1) sign in with current password
  let res = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email: u.email, password: u.password, returnSecureToken: true },
  );

  if (res.status === 200 && res.json.idToken) {
    console.log(`OK login  ${u.email} → ${res.json.localId}`);
    return res.json;
  }

  // 2) eski demo şifre 1234 → 123456'ya yükselt
  if (u.password === '123456') {
    const old = await postJson(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
      { email: u.email, password: '1234', returnSecureToken: true },
    );
    if (old.status === 200 && old.json.idToken) {
      const upd = await postJson(
        `https://identitytoolkit.googleapis.com/v1/accounts:update?key=${API_KEY}`,
        {
          idToken: old.json.idToken,
          password: '123456',
          returnSecureToken: true,
        },
      );
      if (upd.status === 200 && upd.json.idToken) {
        console.log(`OK upgrade ${u.email} → ${upd.json.localId}`);
        return upd.json;
      }
    }
  }

  // 3) sign up
  res = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      email: u.email,
      password: u.password,
      returnSecureToken: true,
      displayName: `${u.firstName} ${u.lastName}`.trim(),
    },
  );

  if (res.status === 200 && res.json.idToken) {
    console.log(`OK create ${u.email} → ${res.json.localId}`);
    return res.json;
  }

  console.error(`FAIL ${u.email}`, res.status, res.json);
  return null;
}

(async () => {
  for (const u of users) {
    const auth = await ensureUser(u);
    if (!auth) continue;
    const profile = {
      email: u.email,
      firstName: u.firstName,
      lastName: u.lastName,
      fullName: `${u.firstName} ${u.lastName}`.trim(),
      role: u.role,
      studentNo: u.studentNo || '',
      university: 'Gaziantep Üniversitesi',
      city: 'Gaziantep',
      isSuperAdmin: !!u.isSuperAdmin,
      isCommunity: !!u.isCommunity,
      hasGoldBadge: !!u.hasGoldBadge,
      hasBlueBadge: !!u.hasBlueBadge,
      isBot: !!u.isBot,
      staffRoleId: u.staffRoleId || '',
      communityLogoUrl: u.communityLogoUrl || '',
      photoUrl: u.photoUrl || u.communityLogoUrl || '',
      affiliatedCommunityId: u.affiliatedCommunityId || '',
      affiliatedCommunityName: u.affiliatedCommunityName || '',
      bio: u.bio || '',
      username: u.username || '',
      usernameStatus: u.usernameStatus || 'ok',
      notificationPrefs: {
        pushEnabled: true,
        likes: true,
        comments: true,
        follows: true,
        reposts: true,
        jobs: true,
        offers: true,
        community: true,
        admin: true,
      },
      updatedAt: new Date().toISOString(),
    };
    const fs = await patchFirestore(auth.idToken, `users/${auth.localId}`, {
      ...profile,
      stableId: STABLE_IDS[u.email] || auth.localId,
    });
    console.log(`  firestore users/${auth.localId} → ${fs.status}`);

    if (u.username) {
      const handle = await patchFirestore(
        auth.idToken,
        `handles/${String(u.username).toLowerCase()}`,
        {
          userId: STABLE_IDS[u.email] || auth.localId,
          authUid: auth.localId,
          status: 'ok',
          updatedAt: new Date().toISOString(),
        },
      );
      console.log(`  handle @${u.username} → ${handle.status}`);
    }
  }
  console.log('Seed bitti.');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
