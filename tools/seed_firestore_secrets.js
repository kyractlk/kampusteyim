/**
 * Firestore REST ile app_secrets/runtime yazar.
 * firebase login oturumundaki access token kullanır.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const https = require('https');

function loadEnv() {
  const p = path.join(__dirname, '..', '.env.secrets');
  const env = {};
  if (fs.existsSync(p)) {
    for (const line of fs.readFileSync(p, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (m) env[m[1]] = m[2];
    }
  }
  return env;
}

function getAccessToken() {
  try {
    return execSync('npx -y firebase-tools@latest login:ci --no-localhost', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 5000,
    });
  } catch (_) {
    // fallback: gcloud
  }
  try {
    return execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
  } catch (_) {
    return null;
  }
}

function firestorePatch(token, fields) {
  const body = JSON.stringify({ fields });
  const url =
    '/v1/projects/ayskampuss/databases/(default)/documents/app_secrets/runtime?key=';
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'firestore.googleapis.com',
        path: '/v1/projects/ayskampuss/databases/(default)/documents/app_secrets/runtime',
        method: 'PATCH',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve({ status: res.statusCode, data }));
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  const env = loadEnv();
  let token = process.env.GOOGLE_ACCESS_TOKEN;
  if (!token) {
    try {
      token = execSync('gcloud auth print-access-token', { encoding: 'utf8' }).trim();
    } catch (e) {
      console.error('Access token alınamadı. gcloud auth login veya GOOGLE_ACCESS_TOKEN ver.');
      process.exit(1);
    }
  }

  const fields = {
    openai_api_key: { stringValue: env.OPENAI_API_KEY || '' },
    openai_cv_model: { stringValue: env.OPENAI_CV_MODEL || 'gpt-4o-mini' },
    smtp_host: { stringValue: env.SMTP_HOST || 'smtp.gaunengineering.com.tr' },
    smtp_port: { stringValue: env.SMTP_PORT || '465' },
    smtp_user: { stringValue: env.SMTP_USER || '' },
    smtp_pass: { stringValue: env.SMTP_PASS || '' },
    updated_at: { stringValue: new Date().toISOString() },
  };

  // create via PATCH upsert
  const result = await firestorePatch(token, fields);
  console.log(result.status, result.data.slice(0, 500));
  if (result.status >= 400) process.exit(1);
  console.log('OK secrets written to app_secrets/runtime');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
