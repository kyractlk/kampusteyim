/**
 * gaunmt rename + Kayra superadmin + Apple review hesabı + gereksiz Auth silme yok
 * (yalnızca mevcut çekirdek + apple).
 *
 * node tools/setup_core_and_apple.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = {
  email: 'admin@gaunengineering.com.tr',
  password: '123456',
};

const APPLE = {
  email: 'apple.review@kampusteyim.app',
  password: 'AppleReview2026!',
  firstName: 'Apple',
  lastName: 'Reviewer',
  username: 'applereview',
  studentNo: 'APPLE0001',
};

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
          } catch (_) {
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

async function listAll(idToken, collection) {
  const docs = [];
  let pageToken = '';
  do {
    let url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${collection}?pageSize=300`;
    if (pageToken) url += `&pageToken=${encodeURIComponent(pageToken)}`;
    const res = await request('GET', url, idToken);
    docs.push(...(res.json.documents || []));
    pageToken = res.json.nextPageToken || '';
  } while (pageToken);
  return docs;
}

async function patchDoc(idToken, path, fields) {
  const keys = Object.keys(fields);
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}?${keys
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&')}`;
  return request('PATCH', url, idToken, { fields });
}

async function putDoc(idToken, path, fields) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  return request('PATCH', url, idToken, { fields });
}

async function deleteDoc(idToken, name) {
  const path = name.split('/documents/')[1];
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${path}`;
  return request('DELETE', url, idToken);
}

async function callAdminDelete(idToken, uid, email) {
  return postJson(
    `https://europe-west1-${PROJECT}.cloudfunctions.net/adminDeleteAccount`,
    { data: { uid, email } },
    { Authorization: `Bearer ${idToken}` },
  );
}

async function createAuthUser(email, password, displayName) {
  return postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      email,
      password,
      displayName,
      returnSecureToken: true,
    },
  );
}

async function main() {
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

  const users = await listAll(idToken, 'users');
  console.log('Users:', users.length);

  const KEEP_EMAILS = new Set([
    'alikayracatalkaya@gmail.com',
    'hr@aystech.com',
    'mt@gantep.edu.tr',
    'guard@aystech.com', // sistem botu
    APPLE.email,
  ]);

  // 1) muhendislik → gaunmt
  const mt = users.find(
    (u) => fieldStr(u.fields, 'email').toLowerCase() === 'mt@gantep.edu.tr',
  );
  if (mt) {
    const mtId = mt.name.split('/').pop();
    console.log('Rename username muhendislik → gaunmt on', mtId);
    const p = await patchDoc(idToken, `users/${mtId}`, {
      username: { stringValue: 'gaunmt' },
      usernameStatus: { stringValue: 'ok' },
      updatedAt: { stringValue: new Date().toISOString() },
    });
    console.log('  user patch', p.status);

    // handles: create gaunmt, delete muhendislik
    const authUid = mtId;
    const hPut = await putDoc(idToken, 'handles/gaunmt', {
      status: { stringValue: 'ok' },
      authUid: { stringValue: authUid },
      userId: { stringValue: fieldStr(mt.fields, 'stableId') || 'community' },
      uid: { stringValue: authUid },
      updatedAt: { stringValue: new Date().toISOString() },
    });
    console.log('  handle gaunmt', hPut.status);
    const oldH = await deleteDoc(
      idToken,
      `projects/${PROJECT}/databases/(default)/documents/handles/muhendislik`,
    );
    console.log('  delete handle muhendislik', oldH.status);
  } else {
    console.warn('MT community user not found');
  }

  // 2) Kayra → superadmin (admin kalabilir; kullanıcı “Kayra kalsın” dedi)
  const kayra = users.find(
    (u) =>
      fieldStr(u.fields, 'email').toLowerCase() ===
      'alikayracatalkaya@gmail.com',
  );
  if (kayra) {
    const kid = kayra.name.split('/').pop();
    const ays = users.find(
      (u) => fieldStr(u.fields, 'email').toLowerCase() === 'hr@aystech.com',
    );
    const aysId = ays ? ays.name.split('/').pop() : 'company_ays';
    console.log('Promote Kayra superadmin', kid);
    const p = await patchDoc(idToken, `users/${kid}`, {
      isSuperAdmin: { booleanValue: true },
      role: { stringValue: 'admin' },
      staffRoleId: { stringValue: 'role_super' },
      hasGoldBadge: { booleanValue: true },
      accountStatus: { stringValue: 'approved' },
      affiliatedCommunityId: { stringValue: aysId },
      affiliatedCommunityName: { stringValue: 'AYS Tech' },
      updatedAt: { stringValue: new Date().toISOString() },
    });
    console.log('  kayra patch', p.status);
  }

  // 3) Apple review hesabı
  let appleUid = null;
  const existingApple = users.find(
    (u) => fieldStr(u.fields, 'email').toLowerCase() === APPLE.email,
  );
  if (existingApple) {
    appleUid = existingApple.name.split('/').pop();
    console.log('Apple review already exists', appleUid);
  } else {
    const created = await createAuthUser(
      APPLE.email,
      APPLE.password,
      `${APPLE.firstName} ${APPLE.lastName}`,
    );
    if (created.status === 200 && created.json.localId) {
      appleUid = created.json.localId;
      console.log('Created Apple Auth', appleUid);
    } else if (created.json?.error?.message === 'EMAIL_EXISTS') {
      console.log('Apple email exists in Auth — sign-in to get uid');
      const s2 = await postJson(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
        {
          email: APPLE.email,
          password: APPLE.password,
          returnSecureToken: true,
        },
      );
      appleUid = s2.json.localId;
    } else {
      console.error('Apple create failed', created.status, created.json);
    }
  }

  if (appleUid) {
    const now = new Date().toISOString();
    const profile = await putDoc(idToken, `users/${appleUid}`, {
      email: { stringValue: APPLE.email },
      firstName: { stringValue: APPLE.firstName },
      lastName: { stringValue: APPLE.lastName },
      fullName: { stringValue: `${APPLE.firstName} ${APPLE.lastName}` },
      studentNo: { stringValue: APPLE.studentNo },
      phone: { stringValue: '' },
      city: { stringValue: 'Gaziantep' },
      university: { stringValue: 'Gaziantep Üniversitesi' },
      bio: {
        stringValue:
          'App Store inceleme test hesabı · Apple Review (KampüsteyimAPP)',
      },
      role: { stringValue: 'student' },
      isSuperAdmin: { booleanValue: false },
      username: { stringValue: APPLE.username },
      usernameStatus: { stringValue: 'ok' },
      accountStatus: { stringValue: 'approved' },
      stableId: { stringValue: appleUid },
      kvkkAcceptedAt: { stringValue: now },
      marketingConsent: { booleanValue: true },
      marketingAcceptedAt: { stringValue: now },
      updatedAt: { stringValue: now },
    });
    console.log('Apple profile', profile.status);
    const h = await putDoc(idToken, `handles/${APPLE.username}`, {
      status: { stringValue: 'ok' },
      authUid: { stringValue: appleUid },
      uid: { stringValue: appleUid },
      userId: { stringValue: appleUid },
      updatedAt: { stringValue: now },
    });
    console.log('Apple handle', h.status);
  }

  // 4) Diğer üyelikleri sil (admin platform hesabı hariç — hâlâ yönetim için; Guard kalır)
  // Kullanıcı: Kayra + aystech + gaunmt kalsın. Guard sistem. Admin opsiyonel sil.
  // Platform Admin'i SİLME — Kayra süperadmin olsa da seed/CF scriptleri admin ile çalışıyor.
  // Sadece KEEP dışında kalanları sil (şu an ekstra yok).
  const refreshed = await listAll(idToken, 'users');
  for (const u of refreshed) {
    const email = fieldStr(u.fields, 'email').toLowerCase();
    const id = u.name.split('/').pop();
    const isAdmin =
      email === 'admin@gaunengineering.com.tr' ||
      fieldStr(u.fields, 'username') === 'admin';
    if (KEEP_EMAILS.has(email) || isAdmin) continue;
    console.log('Deleting extra user', id, email);
    const cf = await callAdminDelete(idToken, id, email);
    console.log('  CF', cf.status, JSON.stringify(cf.json).slice(0, 200));
    if (cf.json?.error) {
      await deleteDoc(idToken, u.name);
    }
  }

  console.log('\nApple test login:');
  console.log('  email:', APPLE.email);
  console.log('  password:', APPLE.password);
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
