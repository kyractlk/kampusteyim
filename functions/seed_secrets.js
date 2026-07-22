/**
 * Firestore'a app_secrets/runtime yazar (yalnızca Admin SDK).
 * Kullanım: node seed_secrets.js
 * Anahtarları .env.secrets veya ortam değişkeninden okur — repoya commit etme.
 */
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

function loadEnvFile() {
  const p = path.join(__dirname, '..', '.env.secrets');
  if (!fs.existsSync(p)) return;
  const lines = fs.readFileSync(p, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

async function main() {
  loadEnvFile();
  initializeApp({
    credential: applicationDefault(),
    projectId: process.env.GCLOUD_PROJECT || 'ayskampuss',
  });

  const db = getFirestore();
  const payload = {
    openai_api_key: process.env.OPENAI_API_KEY || '',
    openai_cv_model: process.env.OPENAI_CV_MODEL || 'gpt-4o-mini',
    smtp_host: process.env.SMTP_HOST || 'smtp.gaunengineering.com.tr',
    smtp_port: process.env.SMTP_PORT || '465',
    smtp_user: process.env.SMTP_USER || 'info@gaunengineering.com.tr',
    smtp_pass: process.env.SMTP_PASS || '',
    updated_at: new Date().toISOString(),
  };

  if (!payload.openai_api_key || !payload.smtp_pass) {
    console.error('OPENAI_API_KEY ve SMTP_PASS gerekli (.env.secrets)');
    process.exit(1);
  }

  await db.collection('app_secrets').doc('runtime').set(payload, { merge: true });
  console.log('OK: app_secrets/runtime yazıldı (istemci kuralları deny-all).');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
