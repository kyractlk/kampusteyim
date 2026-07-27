/**
 * Admin: kullanıcıyı kuruma bağla (adminSetUserBadges link_org).
 * node tools/link_user_org.js kznc00 aystech
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const ADMIN = {
  email: 'admin@gaunengineering.com.tr',
  password: '123456',
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

async function main() {
  const userKey = (process.argv[2] || 'kznc00').trim();
  const orgKey = (process.argv[3] || 'aystech').trim();
  const grantBlue = process.argv.includes('--blue');
  const grantGold = process.argv.includes('--gold');

  console.log(`Bağlanıyor: ${userKey} → ${orgKey}`);

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

  const res = await postJson(
    `https://europe-west1-${PROJECT}.cloudfunctions.net/adminSetUserBadges`,
    {
      data: {
        userId: userKey,
        action: 'link_org',
        orgId: orgKey,
        grantBlueBadge: grantBlue,
        grantGoldBadge: grantGold,
      },
    },
    { Authorization: `Bearer ${idToken}` },
  );

  console.log('HTTP', res.status);
  if (res.json?.error) {
    console.error('Hata:', JSON.stringify(res.json.error, null, 2));
    process.exit(1);
  }
  console.log('Sonuç:', JSON.stringify(res.json?.result || res.json, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
