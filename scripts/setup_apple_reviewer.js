/**
 * App Store inceleme hesabını sıfırdan kurar / şifreyi hizalar.
 * node scripts/setup_apple_reviewer.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const APPLE = {
  email: 'apple.review@kampusteyim.app',
  password: 'AppleReview2026!',
  firstName: 'Apple',
  lastName: 'Reviewer',
  username: 'applereview',
};
const OFFICIAL = 'IYUCw4gXk4bjquDGxUSjtQrcjBi1';

function postJson(url, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: `${u.pathname}${u.search}`,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(data),
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => {
          raw += c;
        });
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, json: JSON.parse(raw || '{}') });
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

function firestore(method, path, idToken, body) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = https.request(
      {
        hostname: 'firestore.googleapis.com',
        path,
        method,
        headers: {
          Authorization: `Bearer ${idToken}`,
          ...(data
            ? {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
              }
            : {}),
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (c) => {
          raw += c;
        });
        res.on('end', () => {
          let json = {};
          try {
            json = JSON.parse(raw || '{}');
          } catch (_) {
            json = { raw };
          }
          resolve({ status: res.statusCode, json });
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function ensureAuth() {
  const sign = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      email: APPLE.email,
      password: APPLE.password,
      returnSecureToken: true,
    },
  );
  if (sign.status === 200 && sign.json.localId) {
    console.log('Apple Auth login OK', sign.json.localId);
    return sign.json;
  }

  const created = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      email: APPLE.email,
      password: APPLE.password,
      displayName: `${APPLE.firstName} ${APPLE.lastName}`,
      returnSecureToken: true,
    },
  );
  if (created.status === 200 && created.json.localId) {
    console.log('Apple Auth created', created.json.localId);
    return created.json;
  }

  console.error('Apple Auth failed', created.status, created.json);
  process.exit(1);
}

async function main() {
  const auth = await ensureAuth();
  const uid = auth.localId;
  const idToken = auth.idToken;
  const now = new Date().toISOString();
  const base = `/v1/projects/${PROJECT}/databases/(default)/documents`;

  const userFields = {
    email: { stringValue: APPLE.email },
    firstName: { stringValue: APPLE.firstName },
    lastName: { stringValue: APPLE.lastName },
    fullName: { stringValue: `${APPLE.firstName} ${APPLE.lastName}` },
    studentNo: { stringValue: 'APPLE0001' },
    phone: { stringValue: '' },
    city: { stringValue: 'Gaziantep' },
    university: { stringValue: 'Gaziantep Üniversitesi' },
    faculty: { stringValue: 'Mühendislik Fakültesi' },
    department: { stringValue: 'Bilgisayar Mühendisliği' },
    bio: {
      stringValue:
        'App Store inceleme test hesabı. Tüm öğrenci akışını bu hesapla deneyebilirsiniz.',
    },
    role: { stringValue: 'student' },
    isCommunity: { booleanValue: false },
    isSuperAdmin: { booleanValue: false },
    isEventOrganizer: { booleanValue: false },
    panelAccess: { booleanValue: false },
    username: { stringValue: APPLE.username },
    usernameStatus: { stringValue: 'ok' },
    accountStatus: { stringValue: 'approved' },
    authUid: { stringValue: uid },
    stableId: { stringValue: uid },
    emailVerified: { booleanValue: true },
    kvkkAcceptedAt: { stringValue: now },
    marketingConsent: { booleanValue: false },
    isPrivateAccount: { booleanValue: false },
    hideFromSearch: { booleanValue: false },
    following: { arrayValue: { values: [{ stringValue: OFFICIAL }] } },
    followers: { arrayValue: {} },
    incomingFollowRequests: { arrayValue: {} },
    outgoingFollowRequests: { arrayValue: {} },
    updatedAt: { stringValue: now },
    createdByAdmin: { stringValue: 'setup_apple_reviewer' },
  };

  const userRes = await firestore(
    'PATCH',
    `${base}/users/${uid}?updateMask.fieldPaths=${Object.keys(userFields).join(
      '&updateMask.fieldPaths=',
    )}`,
    idToken,
    { fields: userFields },
  );
  console.log('Apple profile', userRes.status, userRes.json.error || 'ok');

  const handleRes = await firestore(
    'PATCH',
    `${base}/handles/${APPLE.username}`,
    idToken,
    {
      fields: {
        status: { stringValue: 'ok' },
        authUid: { stringValue: uid },
        uid: { stringValue: uid },
        userId: { stringValue: uid },
        username: { stringValue: APPLE.username },
        updatedAt: { stringValue: now },
      },
    },
  );
  console.log('Apple handle', handleRes.status, handleRes.json.error || 'ok');

  const verify = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      email: APPLE.email,
      password: APPLE.password,
      returnSecureToken: true,
    },
  );
  console.log(
    verify.status === 200 ? 'LOGIN_OK' : 'LOGIN_FAIL',
    verify.json.localId || verify.json.error,
  );
  console.log('email:', APPLE.email);
  console.log('password:', APPLE.password);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
