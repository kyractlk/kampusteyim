/**
 * Mail önizlemelerini Firestore outbox üzerinden gönderir.
 * node tools/send_email_previews.js
 */
const https = require('https');

const API_KEY = 'AIzaSyBndeLh7kUr53XKqS9WvE5P3YMsfrRfLLE';
const PROJECT = 'ayskampuss';
const TO = process.argv[2] || 'alikayracatalkaya@gmail.com';
const BRAND_HOME = 'https://ayskampuss.web.app';
const AYS_LOGO = 'https://ayskampuss.web.app/brand/ays-logo.png';
const MT_LOGO = 'https://ayskampuss.web.app/mt-logo.png';

function branded({ title, greeting, bodyHtml, ctaLabel, ctaUrl, logoUrl, brandLine }) {
  const logo = logoUrl || AYS_LOGO;
  const brand = brandLine || 'AYS Tech · GAÜN Mühendislik Topluluğu';
  const cta =
    ctaLabel && ctaUrl
      ? `<p style="margin:28px 0 8px;text-align:center;"><a href="${ctaUrl}" style="display:inline-block;background:#0B1F3A;color:#fff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:700;">${ctaLabel}</a></p>`
      : '';
  return `<!DOCTYPE html><html lang="tr"><body style="margin:0;background:#EEF2F7;font-family:Segoe UI,Roboto,Arial,sans-serif;">
  <table width="100%" style="padding:32px 12px;"><tr><td align="center">
  <table width="560" style="background:#fff;border-radius:20px;border:1px solid #E2E8F0;overflow:hidden;">
  <tr><td style="background:linear-gradient(135deg,#0B1F3A,#12355C);padding:28px;text-align:center;">
  <img src="${logo}" width="72" height="72" style="border-radius:50%;background:#fff;padding:4px;"/>
  <p style="margin:14px 0 0;color:#fff;font-size:20px;font-weight:800;">KampüsteyimAPP</p>
  <p style="margin:4px 0 0;color:#A8C5E2;font-size:13px;">${brand}</p>
  </td></tr>
  <tr><td style="padding:28px;">
  <h1 style="margin:0 0 16px;font-size:20px;color:#0B1F3A;">${title}</h1>
  ${greeting ? `<p style="margin:0 0 16px;font-size:16px;">${greeting}</p>` : ''}
  <div style="font-size:15px;line-height:1.65;color:#334155;">${bodyHtml}</div>
  ${cta}
  </td></tr>
  <tr><td style="padding:0 28px 28px;text-align:center;font-size:12px;color:#94A3B8;">
  <a href="${BRAND_HOME}" style="color:#0EA5E9;">ayskampuss.web.app</a>
  </td></tr></table></td></tr></table></body></html>`;
}

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
        res.on('end', () => resolve({ status: res.statusCode, raw }));
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
    if (typeof v === 'string') out[k] = { stringValue: v };
  }
  return out;
}

(async () => {
  const loginRes = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    {
      email: 'admin@gaunengineering.com.tr',
      password: '123456',
      returnSecureToken: true,
    },
  );
  const login = JSON.parse(loginRes.raw || '{}');
  if (!login.idToken) {
    console.error('login fail', login);
    process.exit(1);
  }

  const samples = [
    ['[Örnek] Hoş geldin · AYS logolu', branded({
      title: 'KampüsteyimAPP’e hoş geldin!',
      greeting: 'Merhaba Ali Kayra,',
      bodyHtml: '<p>Bu <b>AYS</b> logolu hoş geldin şablonudur.</p>',
      ctaLabel: 'Uygulamaya git',
      ctaUrl: BRAND_HOME,
      logoUrl: AYS_LOGO,
    })],
    ['[Örnek] Hoş geldin · MT logolu', branded({
      title: 'KampüsteyimAPP’e hoş geldin!',
      greeting: 'Merhaba Ali Kayra,',
      bodyHtml: '<p>Bu <b>MT</b> logolu hoş geldin şablonudur.</p>',
      ctaLabel: 'Uygulamaya git',
      ctaUrl: BRAND_HOME,
      logoUrl: MT_LOGO,
      brandLine: 'GAÜN Mühendislik Topluluğu · AYS Tech',
    })],
    ['[Örnek] Şikayet alındı', branded({
      title: 'Şikayetin alındı',
      greeting: 'Merhaba,',
      bodyHtml: '<p>Şikayetini aldık. Guard + admin inceliyor.</p>',
      ctaLabel: 'KampüsteyimAPP',
      ctaUrl: BRAND_HOME,
    })],
    ['[Örnek] Moderasyon · Uyarı', branded({
      title: 'Uyarı · AYS Tech Guard',
      greeting: 'Merhaba,',
      bodyHtml: '<p>Paylaşımın kurallara aykırı bulundu. Bu bir uyarıdır.</p>',
      ctaLabel: 'KampüsteyimAPP',
      ctaUrl: BRAND_HOME,
    })],
    ['[Örnek] Moderasyon · Susturma', branded({
      title: 'Susturma · AYS Tech Guard',
      greeting: 'Merhaba,',
      bodyHtml: '<p>Hesabın 24 saat susturuldu.</p>',
      ctaLabel: 'KampüsteyimAPP',
      ctaUrl: BRAND_HOME,
    })],
    ['[Örnek] Şifre sıfırlama', branded({
      title: 'Şifre sıfırlama',
      greeting: 'Merhaba,',
      bodyHtml: '<p>Şifreni sıfırlamak için butona tıkla (örnek).</p>',
      ctaLabel: 'Şifreyi sıfırla',
      ctaUrl: `${BRAND_HOME}/login`,
    })],
    ['[Örnek] Yeni ilan', branded({
      title: 'Yeni staj ilanı',
      greeting: 'Merhaba,',
      bodyHtml: '<p><b>AYS Tech</b> yeni staj ilanı yayınladı.</p>',
      ctaLabel: 'İlanı gör',
      ctaUrl: BRAND_HOME,
    })],
    ['[Örnek] Firma teklifi', branded({
      title: 'Firma teklifi',
      greeting: 'Merhaba,',
      bodyHtml: '<p>AYS Tech sana özel bir teklif gönderdi.</p>',
      ctaLabel: 'Teklifi gör',
      ctaUrl: BRAND_HOME,
    })],
  ];

  for (let i = 0; i < samples.length; i++) {
    const [subject, html] = samples[i];
    const id = `preview_${Date.now()}_${i}`;
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/mail_outbox?documentId=${id}`;
    const res = await postJson(
      url,
      {
        fields: toFields({
          to: TO,
          subject,
          html,
          createdAt: new Date().toISOString(),
        }),
      },
      { Authorization: `Bearer ${login.idToken}` },
    );
    console.log(res.status, subject);
  }
  console.log(`Kuyruğa alındı → ${TO} (${samples.length} mail). Trigger gönderecek.`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
