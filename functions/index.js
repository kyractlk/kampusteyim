const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const crypto = require('crypto');
const OpenAI = require('openai');
const nodemailer = require('nodemailer');

initializeApp();
const db = getFirestore();

/** XSS / HTML enjeksiyonuna karşı düz metin kaçışı */
function escapeHtml(input) {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Etiket ve kontrol karakterlerini temizler (bakım başlık/mesaj). */
function sanitizePlainText(input, maxLen = 800) {
  let s = String(input ?? '')
    .replace(/<[^>]*>/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .trim();
  if (s.length > maxLen) s = s.slice(0, maxLen);
  return s;
}

const EMAIL_RE = /^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$/i;

function isValidEmail(email) {
  const e = String(email || '').trim().toLowerCase();
  if (e.length < 5 || e.length > 120) return false;
  if (/[<>"'`;\\]/.test(e)) return false;
  return EMAIL_RE.test(e);
}

async function loadSecrets() {
  const snap = await db.collection('app_secrets').doc('runtime').get();
  if (!snap.exists) {
    throw new HttpsError(
      'failed-precondition',
      'app_secrets/runtime bulunamadı. tools/seed_secrets çalıştırın.',
    );
  }
  return snap.data();
}

async function getOpenAI() {
  const secrets = await loadSecrets();
  if (!secrets.openai_api_key) {
    throw new HttpsError('failed-precondition', 'OpenAI API key eksik');
  }
  return {
    client: new OpenAI({ apiKey: secrets.openai_api_key }),
    model: secrets.openai_cv_model || 'gpt-4o-mini',
  };
}

async function getMailer() {
  const secrets = await loadSecrets();
  const transporter = nodemailer.createTransport({
    host: secrets.smtp_host || 'smtp.gaunengineering.com.tr',
    port: Number(secrets.smtp_port || 465),
    secure: true,
    auth: {
      user: secrets.smtp_user,
      pass: secrets.smtp_pass,
    },
    tls: { rejectUnauthorized: false },
  });
  return { transporter, from: secrets.smtp_user };
}

async function sendMail({ to, subject, html }) {
  const { transporter, from } = await getMailer();
  await transporter.sendMail({ from, to, subject, html });
}

const BRAND_LOGO =
  'https://gaunengineering.com.tr/brand/ays-logo.png';
const BRAND_HOME = 'https://gaunengineering.com.tr';

/** Kısa, yapıştırılabilir sıfırlama kodu (token query string yok). */
function makeShortResetCode() {
  // Karışmayan karakterler (0/O, 1/l/I yok)
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz';
  const bytes = crypto.randomBytes(10);
  let out = '';
  for (let i = 0; i < bytes.length; i += 1) {
    out += alphabet[bytes[i] % alphabet.length];
  }
  return out;
}

/** Kendi KampüsteyimAPP sayfamıza giden kısa şifre sıfırlama linki. */
async function createAppPasswordResetLink(email) {
  const { getAuth } = require('firebase-admin/auth');
  const auth = getAuth();
  const normalized = String(email || '').trim().toLowerCase();
  if (!normalized.includes('@')) return null;

  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(normalized);
  } catch (_) {
    return null;
  }

  // Eski kullanılmamış tokenları iptal et
  const old = await db
    .collection('password_resets')
    .where('email', '==', normalized)
    .limit(30)
    .get();
  const batch = db.batch();
  let revokeCount = 0;
  old.docs.forEach((d) => {
    if (d.data()?.used === true) return;
    batch.update(d.ref, { used: true, revokedAt: new Date().toISOString() });
    revokeCount += 1;
  });
  if (revokeCount > 0) await batch.commit();

  let code = makeShortResetCode();
  // Çakışma çok nadir; varsa bir kez yenile
  if ((await db.collection('password_resets').doc(code).get()).exists) {
    code = makeShortResetCode();
  }

  const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 saat
  await db.collection('password_resets').doc(code).set({
    email: normalized,
    uid: userRecord.uid,
    used: false,
    createdAt: new Date().toISOString(),
    expiresAt: expiresAt.toISOString(),
  });

  return `${BRAND_HOME}/r/${code}`;
}

function passwordResetEmailHtml(link) {
  return brandedEmail({
    title: 'Şifre sıfırlama',
    greeting: 'Merhaba,',
    bodyHtml: `
      <p>KampüsteyimAPP hesabın için şifre sıfırlama talebi aldık.</p>
      <p>Aşağıdaki butona tıkla. Bağlantı <b>1 saat</b> geçerlidir.</p>
      <p style="margin:20px 0 8px;font-size:13px;color:#64748b;">Buton çalışmazsa bu kısa adresi tarayıcıya yapıştır:</p>
      <p style="margin:0;padding:14px 16px;background:#F1F5F9;border:1px dashed #94A3B8;border-radius:12px;text-align:center;word-break:break-all;">
        <a href="${link}" style="color:#0B1F3A;font-weight:700;font-size:15px;text-decoration:none;letter-spacing:0.02em;">${link}</a>
      </p>
    `,
    ctaLabel: 'Şifremi sıfırla',
    ctaUrl: link,
    footerNote: 'Bu talebi sen oluşturmadıysan bu maili yok sayabilirsin.',
  });
}

/** AYS logolu HTML e-posta şablonu */
function brandedEmail({
  title,
  greeting,
  bodyHtml,
  ctaLabel,
  ctaUrl,
  footerNote,
}) {
  const safeTitle = escapeHtml(String(title || 'KampüsteyimAPP'));
  const safeGreeting = greeting
    ? `<p style="margin:0 0 16px;font-size:16px;color:#1a2332;">${escapeHtml(greeting)}</p>`
    : '';
  const safeCtaLabel = escapeHtml(ctaLabel || '');
  const safeCtaUrl = escapeHtml(String(ctaUrl || '').replace(/[<>"']/g, ''));
  const cta =
    ctaLabel && ctaUrl
      ? `<p style="margin:28px 0 8px;text-align:center;">
          <a href="${safeCtaUrl}" style="display:inline-block;background:#0B1F3A;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:700;font-size:15px;">
            ${safeCtaLabel}
          </a>
        </p>
        <p style="margin:0 0 8px;text-align:center;font-size:12px;color:#6b7280;word-break:break-all;">
          <a href="${safeCtaUrl}" style="color:#0EA5E9;text-decoration:none;">${safeCtaUrl}</a>
        </p>`
      : '';
  const note = footerNote
    ? `<p style="margin:20px 0 0;font-size:13px;color:#6b7280;line-height:1.5;">${escapeHtml(footerNote)}</p>`
    : '';

  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>${safeTitle}</title>
</head>
<body style="margin:0;padding:0;background:#EEF2F7;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF2F7;padding:32px 12px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #E2E8F0;box-shadow:0 8px 28px rgba(11,31,58,0.08);">
          <tr>
            <td style="background:linear-gradient(135deg,#0B1F3A 0%,#12355C 100%);padding:28px 28px 22px;text-align:center;">
              <img src="${BRAND_LOGO}" alt="AYS Tech" width="64" height="64" style="display:inline-block;border-radius:50%;background:#ffffff;padding:4px;"/>
              <p style="margin:14px 0 0;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:0.2px;">KampüsteyimAPP</p>
              <p style="margin:4px 0 0;color:#A8C5E2;font-size:13px;">AYS Tech · GAÜN Mühendislik Topluluğu</p>
            </td>
          </tr>
          <tr>
            <td style="padding:28px 28px 8px;">
              <h1 style="margin:0 0 16px;font-size:20px;line-height:1.35;color:#0B1F3A;">${safeTitle}</h1>
              ${safeGreeting}
              <div style="font-size:15px;line-height:1.65;color:#334155;">${bodyHtml || ''}</div>
              ${cta}
              ${note}
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 28px;">
              <hr style="border:none;border-top:1px solid #E2E8F0;margin:0 0 16px;"/>
              <p style="margin:0;font-size:12px;color:#94A3B8;line-height:1.5;text-align:center;">
                Bu mail KampüsteyimAPP platformundan gönderildi.<br/>
                <a href="${BRAND_HOME}" style="color:#0EA5E9;text-decoration:none;">gaunengineering.com.tr</a>
                · AYS Tech · Kayra Çatalkaya
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function userAllowsPush(userData, type) {
  const prefs = userData?.notificationPrefs || {};
  if (prefs.pushEnabled === false) return false;
  switch (String(type || '')) {
    case 'like':
      return prefs.likes !== false;
    case 'comment':
      return prefs.comments !== false;
    case 'follow':
      return prefs.follows !== false;
    case 'repost':
      return prefs.reposts !== false;
    case 'job':
    case 'application':
      return prefs.jobs !== false;
    case 'offer':
      return prefs.offers !== false;
    case 'community':
      return prefs.community !== false;
    case 'activity':
      return prefs.activity !== false;
    case 'admin_broadcast':
      return prefs.admin !== false;
    case 'mention':
      return prefs.mentions !== false;
    default:
      return true;
  }
}

/**
 * Kullanıcı cihaz token’larına FCM gönder + geçersiz token’ları budar.
 * Mantık: users/{uid}.fcmTokens[] ↔ cihaz FCM kayıtları.
 */
async function sendFcmToUser(userId, tokens, payload) {
  const list = [
    ...new Set(
      (tokens || []).filter((t) => typeof t === 'string' && t.trim().length > 20),
    ),
  ];
  if (!list.length) return { successCount: 0, failureCount: 0, pruned: 0 };

  const { getMessaging } = require('firebase-admin/messaging');
  const messaging = getMessaging();
  let successCount = 0;
  let failureCount = 0;
  const invalid = [];

  for (let i = 0; i < list.length; i += 500) {
    const chunk = list.slice(i, i + 500);
    try {
      const res = await messaging.sendEachForMulticast({
        tokens: chunk,
        ...payload,
      });
      successCount += res.successCount || 0;
      failureCount += res.failureCount || 0;
      (res.responses || []).forEach((r, idx) => {
        if (r.success) return;
        const code = String(r.error?.code || '');
        if (
          code.includes('registration-token-not-registered') ||
          code.includes('invalid-registration-token') ||
          code.includes('invalid-argument')
        ) {
          invalid.push(chunk[idx]);
        }
      });
    } catch (e) {
      console.error('sendFcmToUser', userId, e?.message || e);
      failureCount += chunk.length;
    }
  }

  if (invalid.length && userId) {
    try {
      await db
        .collection('users')
        .doc(String(userId))
        .update({ fcmTokens: FieldValue.arrayRemove(...invalid) });
    } catch (_) {}
  }

  return { successCount, failureCount, pruned: invalid.length };
}

/** Ortak FCM payload — büyük image YOK; minik ikon AYS (`ic_stat_ays`). */
function buildCampusPushPayload({
  title,
  body,
  type = 'community',
  data = {},
  channelId,
}) {
  const ch =
    channelId ||
    (String(type) === 'admin_broadcast' ? 'mt_mobil_admin' : 'mt_mobil_social');
  return {
    notification: {
      title: String(title),
      body: String(body),
      // imageUrl YOK — uygulama ikonu mesaj gövdesinde gitmesin
    },
    data: {
      type: String(type),
      title: String(title),
      body: String(body),
      brand: 'AYS Tech',
      ...Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v ?? '')]),
      ),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: ch,
        icon: 'ic_notification_ays',
        color: '#33C5D1',
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          alert: { title: String(title), body: String(body) },
          sound: 'default',
          badge: 1,
        },
      },
    },
  };
}

function buildSystemPrompt(languageName, languageCode) {
  return `You are an elite ATS résumé localization specialist for KampüsteyimAPP CV-AI (GAÜN Engineering / AYS Tech).

MISSION: Produce a COMPLETE formal ATS translation into ${languageName} (${languageCode}).
Source text may be in ANY language or a mix. Target is ALWAYS ${languageName}.
This is NOT a loose paraphrase. Every narrative field must be fully rewritten in the TARGET language using that language's official orthography, spelling rules, and HR / résumé terminology (tam çeviri + imla + resmi ATS terimleri).

RAW NOTES (raw_notes):
- If raw_notes is present, EXTRACT facts into structured education / experiences / projects / skills / languages / about.
- Merge with structured fields without duplicating. Prefer structured fields when both exist; fill gaps from raw_notes.
- After structuring, TRANSLATE everything into ${languageName}. Do not leave raw_notes in the output JSON.

STRICT LOCALIZATION (never skip):
1. Translate ALL user-written content into ${languageName}: headline, about, motivation_letter, positions, company role titles when they are descriptive, degree titles, fields of study, EVERY experience/education/project description, skill names that are phrases (keep tech tokens like Flutter/Python), skill level labels, spoken language names AND proficiency labels.
2. Apply correct spelling/orthography of ${languageName} (e.g. Turkish İ/ı/ş/ğ, German umlauts, French accents, Arabic script if target is ar).
3. Use FORMAL résumé register only (corporate ATS diction). Never casual, slang, or mixed-language sentences.
   Terminology examples (match the TARGET language):
   - TR: "Geliştirdi", "Yönetti", "Koordine etti", "İleri düzey", "Orta düzey", "Başlangıç", "Ana dil", "Lisans", "Yüksek Lisans", "Profesyonel Özet", "Motivasyon Mektubu", "İş Deneyimi", "Temel Yetkinlikler", "Dil Yeterlilikleri"
   - EN: "Developed", "Led", "Coordinated", "Advanced", "Intermediate", "Beginner", "Native", "Bachelor of Science", "Master of Science", "Professional Summary", "Motivation Letter", "Professional Experience", "Core Competencies", "Language Proficiency"
   - DE: "Entwickelte", "Leitete", "Fortgeschritten", "Muttersprache", "Bachelor", "Berufserfahrung", "Motivationsschreiben", "Fachkompetenzen", "Sprachkenntnisse"
   - FR: "A développé", "A dirigé", "Avancé", "Langue maternelle", "Licence", "Expérience professionnelle", "Lettre de motivation", "Compétences clés"
   - ES: "Desarrolló", "Dirigió", "Avanzado", "Lengua materna", "Licenciatura", "Experiencia profesional", "Carta de motivación", "Competencias clave"
4. Action verbs MUST follow ${languageName} ATS conventions (past tense for past roles; present for current roles).
5. Skill levels MUST be localized proficiency terms (never leave "Advanced/Intermediate" in English if target ≠ en). For spoken languages prefer CEFR (A1–C2) or the local formal scale (Ana dil / Native / Muttersprache / …).
6. Proper nouns (person name, company, university brands, product names, tech stack names like Flutter/Firebase) stay unchanged unless the target script requires transliteration.
7. Keep dates, GPA numbers, emails, phones, URLs, and photoUrl unchanged.
8. Do NOT invent employers, degrees, or metrics. You MAY structure messy raw_notes into bullets using only stated facts.
9. If source and target language differ: ZERO leftover source-language sentences in about/descriptions/levels/positions/degrees.
10. Always return section_labels with FORMAL ATS section headings in ${languageName} for keys: profile, motivation, experience, education, projects, skills, languages.
11. Always echo personal_info.photoUrl unchanged when present.

TEMPLATE CONTENT:
- personal_info.headline: one formal professional title line in ${languageName} (max 80 chars).
- personal_info.about: 2–4 formal sentences (professional summary tone for ${languageName}).
- personal_info.motivation_letter: formal motivation letter paragraph(s) in ${languageName} (keep empty if source empty AND raw_notes has no motivation; do not invent).
- experiences[].position and experiences[].description: fully in ${languageName}; descriptions = 2–4 newline-separated bullet lines starting with strong action verbs.
- education[].degree / field / description: official academic terminology in ${languageName}.
- section_labels: required object — formal ATS headings in ${languageName}.

OUTPUT: ONLY valid JSON with keys: personal_info, education, experiences, projects, skills, languages, section_labels.
ATS-safe: no emoji, no markdown, plain text fields. Do NOT include raw_notes in output.`;
}

/**
 * Callable: generateAtsCv
 * data: { cvData, languageCode, languageName, userEmail, userName, studentNo }
 */
exports.generateAtsCv = onCall({ region: 'europe-west1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }

  const uid = request.auth.uid;
  const {
    cvData,
    languageCode = 'tr',
    languageName = 'Turkish',
    userEmail,
    userName,
    studentNo,
  } = request.data || {};

  if (!cvData) {
    throw new HttpsError('invalid-argument', 'cvData zorunlu');
  }

  const { client, model } = await getOpenAI();

  const rawNotes = String(cvData.raw_notes || cvData.rawNotes || '').trim();

  const payload = {
    personal_info: {
      name: cvData.personal_info?.name || userName || '',
      email: cvData.personal_info?.email || userEmail || '',
      phone: cvData.personal_info?.phone || '',
      address: cvData.personal_info?.address || '',
      linkedin: cvData.personal_info?.linkedin || '',
      github: cvData.personal_info?.github || '',
      website: cvData.personal_info?.website || '',
      about: cvData.personal_info?.about || '',
      motivation_letter: cvData.personal_info?.motivation_letter || '',
      headline: cvData.personal_info?.headline || cvData.personal_info?.title || '',
      department: cvData.personal_info?.department || '',
      class: cvData.personal_info?.class || '',
      studentNo: cvData.personal_info?.studentNo || studentNo || '',
      photoUrl: cvData.personal_info?.photoUrl || cvData.personal_info?.photo_url || '',
    },
    education: cvData.education || [],
    experiences: cvData.experiences || [],
    projects: cvData.projects || [],
    skills: cvData.skills || [],
    languages: cvData.languages || [],
    raw_notes: rawNotes,
  };

  const completion = await client.chat.completions.create({
    model,
    temperature: 0.25,
    max_tokens: 6000,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: buildSystemPrompt(languageName, languageCode) },
      {
        role: 'user',
        content:
          `LOCALIZE TO: ${languageName} (${languageCode}).\n` +
          'Source language may be anything. Translate EVERY user-written field into the TARGET language with correct orthography and formal ATS HR terms — not just section titles.\n' +
          'If raw_notes is non-empty: structure it into CV sections, then translate.\n' +
          'Do NOT paraphrase loosely. Do NOT leave source-language sentences.\n' +
          'Return ONLY JSON: personal_info (with headline), education, experiences, projects, skills, languages, section_labels (required).\n' +
          'Descriptions = newline-separated formal bullet lines in the TARGET language.\n\n' +
          JSON.stringify(payload),
      },
    ],
  });

  let text = completion.choices[0]?.message?.content?.trim() || '{}';
  if (text.startsWith('```')) {
    text = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
  }

  let polished;
  try {
    polished = JSON.parse(text);
  } catch (e) {
    throw new HttpsError('internal', 'AI JSON parse hatası');
  }

  // Merge immutable contact fields
  polished.personal_info = {
    ...payload.personal_info,
    ...(polished.personal_info || {}),
    email: payload.personal_info.email,
    phone: payload.personal_info.phone,
    studentNo: payload.personal_info.studentNo,
    linkedin: payload.personal_info.linkedin,
    github: payload.personal_info.github,
    website: payload.personal_info.website,
    photoUrl: payload.personal_info.photoUrl,
  };

  const exportId = `${languageCode}_${Date.now()}`;
  const exportDoc = {
    languageCode,
    languageName,
    model,
    polished,
    createdAt: new Date().toISOString(),
    userId: uid,
  };

  await db.collection('users').doc(uid).collection('cv_exports').doc(exportId).set(exportDoc);
  await db.collection('cvs').doc(uid).set(
    {
      user_id: uid,
      cv_data: cvData,
      last_export_id: exportId,
      last_language: languageCode,
      updated_at: new Date().toISOString(),
    },
    { merge: true },
  );

  // Mail bildirimi (başarısız olsa CV yine döner)
  if (userEmail) {
    try {
      await sendMail({
        to: userEmail,
        subject: `KampüsteyimAPP · ATS CV hazır (${languageName})`,
        html: brandedEmail({
          title: 'ATS CV hazır',
          greeting: userName ? `Merhaba ${userName},` : 'Merhaba,',
          bodyHtml:
            `<p><b>${languageName}</b> dilinde ATS uyumlu CV’n canlı AI ile üretildi (tam içerik çevirisi).</p>` +
            '<p>Uygulamadan <b>Profil → CV-AI → Önceki CV’lerim</b> üzerinden tekrar indirebilirsin.</p>',
          ctaLabel: 'KampüsteyimAPP’i aç',
          ctaUrl: BRAND_HOME,
        }),
      });
    } catch (mailErr) {
      console.warn('[mail]', mailErr.message);
    }
  }

  return {
    exportId,
    languageCode,
    languageName,
    polished,
  };
});

/**
 * Callable: notifyMail — genel süreç bildirimleri (ham HTML veya şablon)
 */
exports.notifyMail = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const { to, subject, html, title, bodyHtml, ctaLabel, ctaUrl, greeting } =
    request.data || {};
  if (!to || !subject) {
    throw new HttpsError('invalid-argument', 'to, subject zorunlu');
  }
  const finalHtml =
    html ||
    brandedEmail({
      title: title || subject,
      greeting,
      bodyHtml: bodyHtml || '<p>KampüsteyimAPP bildirimi</p>',
      ctaLabel,
      ctaUrl,
    });
  await sendMail({ to, subject, html: finalHtml });
  return { ok: true };
});

/**
 * Şikayet alındı onayı — AYS logolu HTML
 */
exports.notifyReportReceived = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const {
    to,
    reporterName = '',
    reason = '',
    targetType = 'post',
    snapshotUrl = '',
  } = request.data || {};
  if (!to) {
    throw new HttpsError('invalid-argument', 'to zorunlu');
  }
  const name = String(reporterName || '').trim() || 'Merhaba';
  const html = brandedEmail({
    title: 'Şikayetin alındı',
    greeting: `Merhaba ${name},`,
    bodyHtml: `
      <p>Şikayetini aldık. Moderasyon ekibimiz inceleyecek.</p>
      <p style="margin:16px 0;padding:14px 16px;background:#F8FAFC;border-radius:12px;border:1px solid #E2E8F0;">
        <strong>Tür:</strong> ${String(targetType)}<br/>
        <strong>Gerekçe:</strong> ${String(reason || '—')}
      </p>
      <p>Gerekirse ek bilgi için bu e-posta üzerinden dönüş yapabiliriz.</p>
    `,
    ctaLabel: snapshotUrl ? 'İlgili içeriği aç' : 'KampüsteyimAPP’e git',
    ctaUrl: snapshotUrl || BRAND_HOME,
    footerNote: 'Bu otomatik bir bilgilendirme mailidir.',
  });
  await sendMail({
    to,
    subject: 'KampüsteyimAPP · Şikayetin alındı',
    html,
  });
  return { ok: true };
});

/**
 * Push + inbox: ortak FCM (AYS minik ikon, büyük image yok)
 */
exports.dispatchPush = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const {
    toUserId,
    title,
    body,
    emoji = '🔔',
    type = 'community',
    actorId,
    targetId,
    personalize = false,
  } = request.data || {};
  if (!toUserId || !title || !body) {
    throw new HttpsError('invalid-argument', 'toUserId, title, body zorunlu');
  }

  let userDoc = await db.collection('users').doc(toUserId).get();
  let userData = userDoc.exists ? userDoc.data() || {} : {};
  if (!userDoc.exists || !(userData.fcmTokens || []).length) {
    try {
      const byStable = await db
        .collection('users')
        .where('stableId', '==', String(toUserId))
        .limit(1)
        .get();
      if (!byStable.empty) {
        userDoc = byStable.docs[0];
        userData = userDoc.data() || {};
      }
    } catch (_) {}
  }
  const inboxUid = userDoc.exists ? userDoc.id : toUserId;
  if (!userAllowsPush(userData, type)) {
    return { ok: true, delivered: 0, skipped: true, reason: 'prefs' };
  }
  let finalBody = String(body);
  if (personalize) {
    const first = String(userData.firstName || '').trim();
    const greeting = first ? `Merhaba ${first}` : 'Merhaba';
    if (finalBody.includes('{greeting}')) {
      finalBody = finalBody.replaceAll('{greeting}', greeting);
    } else if (!finalBody.toLowerCase().startsWith('merhaba')) {
      finalBody = `${greeting}, ${finalBody}`;
    }
  }

  const postLink =
    targetId
      ? `${BRAND_HOME}/post/${encodeURIComponent(String(targetId))}`
      : '';

  const inbox = {
    title,
    body: finalBody,
    emoji,
    type,
    actorId: actorId || null,
    targetId: targetId || null,
    link: postLink || null,
    read: false,
    createdAt: new Date().toISOString(),
  };
  await db.collection('users').doc(inboxUid).collection('notifications').add(inbox);

  const tokens = userData.fcmTokens || [];
  let delivered = 0;
  if (tokens.length) {
    const res = await sendFcmToUser(
      inboxUid,
      tokens,
      buildCampusPushPayload({
        title,
        body: finalBody,
        type,
        data: {
          emoji: String(emoji),
          toUserId: String(inboxUid),
          actorId: String(actorId || ''),
          targetId: String(targetId || ''),
          link: postLink,
        },
      }),
    );
    delivered = res.successCount || 0;
  }

  return { ok: true, delivered };
});

/**
 * Firma staj/iş ilanı: feed post + takipçilere push/inbox (+opsiyonel mail)
 */
async function findUserDocByAnyId(userId) {
  const id = String(userId || '');
  if (!id) return null;
  let doc = await db.collection('users').doc(id).get();
  if (doc.exists) return doc;
  try {
    const byStable = await db
      .collection('users')
      .where('stableId', '==', id)
      .limit(1)
      .get();
    if (!byStable.empty) return byStable.docs[0];
  } catch (_) {}
  return null;
}

async function collectFollowerDocs(actorId) {
  const actorDoc = await findUserDocByAnyId(actorId);
  const ids = new Set();
  const queryIds = new Set([String(actorId)]);
  if (actorDoc) {
    queryIds.add(actorDoc.id);
    const data = actorDoc.data() || {};
    if (data.stableId) queryIds.add(String(data.stableId));
    for (const f of data.followers || []) {
      if (f) ids.add(String(f));
    }
  }
  for (const qid of queryIds) {
    try {
      const snap = await db
        .collection('users')
        .where('following', 'array-contains', qid)
        .limit(500)
        .get();
      for (const d of snap.docs) ids.add(d.id);
    } catch (_) {}
  }
  const docs = [];
  const seen = new Set();
  for (const id of ids) {
    if (actorDoc && (id === actorDoc.id || id === actorDoc.data()?.stableId)) {
      continue;
    }
    if (id === String(actorId)) continue;
    const d = await findUserDocByAnyId(id);
    if (!d || seen.has(d.id)) continue;
    seen.add(d.id);
    docs.push(d);
  }
  return docs;
}

async function deliverToUserDoc({
  doc,
  title,
  body,
  emoji = '🔔',
  type = 'community',
  actorId = null,
  targetId = null,
  sendEmail = false,
  emailSubject,
  linkPath,
}) {
  const u = doc.data() || {};
  if (!userAllowsPush(u, type)) {
    return { delivered: 0, mailed: 0, skipped: true };
  }
  const inboxUid = doc.id;
  const link = linkPath
    ? `${BRAND_HOME}${linkPath.startsWith('/') ? linkPath : `/${linkPath}`}`
    : targetId
      ? `${BRAND_HOME}/post/${encodeURIComponent(String(targetId))}`
      : BRAND_HOME;

  await db.collection('users').doc(inboxUid).collection('notifications').add({
    title,
    body,
    emoji,
    type,
    actorId: actorId || null,
    targetId: targetId || null,
    link,
    read: false,
    createdAt: new Date().toISOString(),
  });

  let delivered = 0;
  const tokens = u.fcmTokens || [];
  if (tokens.length) {
    try {
      const res = await sendFcmToUser(
        inboxUid,
        tokens,
        buildCampusPushPayload({
          title: `${emoji} ${title}`.trim(),
          body,
          type,
          data: {
            emoji: String(emoji),
            toUserId: String(inboxUid),
            actorId: String(actorId || ''),
            targetId: String(targetId || ''),
            link,
          },
        }),
      );
      delivered = res.successCount || 0;
    } catch (_) {}
  }

  let mailed = 0;
  const email = String(u.email || '').trim();
  if (sendEmail && email.includes('@') && !email.includes('@invalid.local')) {
    try {
      const first = String(u.firstName || '').trim();
      const greeting = first ? `Merhaba ${escapeHtml(first)},` : 'Merhaba,';
      await sendMail({
        to: email,
        subject: emailSubject || `KampüsteyimAPP · ${title}`,
        html: brandedEmail({
          title,
          greeting,
          bodyHtml: `<p>${escapeHtml(body)}</p>`,
          ctaLabel: 'KampüsteyimAPP’e git',
          ctaUrl: link,
          footerNote: 'Bu bilgilendirme, takip ettiğin hesapların hareketleri içindir.',
        }),
      });
      mailed = 1;
    } catch (e) {
      console.warn('[deliverToUserDoc] mail', e?.message || e);
    }
  }
  return { delivered, mailed, skipped: false };
}

async function notifyFollowersOfActor({
  actorId,
  title,
  body,
  emoji = '✨',
  type = 'activity',
  targetId = null,
  sendEmail = false,
  emailSubject,
  linkPath,
}) {
  const followers = await collectFollowerDocs(actorId);
  let targeted = 0;
  let delivered = 0;
  let mailed = 0;
  for (const doc of followers) {
    const r = await deliverToUserDoc({
      doc,
      title,
      body,
      emoji,
      type,
      actorId,
      targetId,
      sendEmail,
      emailSubject,
      linkPath,
    });
    if (!r.skipped) targeted += 1;
    delivered += r.delivered || 0;
    mailed += r.mailed || 0;
  }
  return { ok: true, targeted, delivered, mailed };
}

async function createJobFeedPost(job, jobId) {
  if (job.feedPostId) return job.feedPostId;
  const type = String(job.type || 'internship');
  const typeLabel =
    type === 'internship' ? 'staj' : type === 'parttime' ? 'yarı zamanlı' : 'iş';
  const companyId = String(job.companyId || '');
  let handle = '@firma';
  let authorName = String(job.companyName || 'Firma');
  try {
    const c = await findUserDocByAnyId(companyId);
    if (c) {
      const d = c.data() || {};
      if (d.username) handle = `@${String(d.username).replace(/^@/, '')}`;
      const name = `${d.firstName || ''} ${d.lastName || ''}`.trim();
      if (name) authorName = name;
      else if (d.fullName) authorName = String(d.fullName);
    }
  } catch (_) {}

  const postId = `job_${jobId}`;
  const desc = String(job.description || '').trim().slice(0, 240);
  const loc = String(job.location || '').trim();
  const content = [
    `💼 Yeni ${typeLabel} ilanı`,
    '',
    String(job.title || ''),
    loc ? `📍 ${loc}` : '',
    desc ? `\n${desc}` : '',
    '',
    `#${typeLabel} #ilan`,
  ]
    .filter((l) => l !== '')
    .join('\n');

  await db.collection('posts').doc(postId).set(
    {
      authorId: companyId || 'company',
      authorName,
      authorHandle: handle,
      content,
      createdAt: new Date().toISOString(),
      likeCount: 0,
      replyCount: 0,
      repostCount: 0,
      isCommunity: false,
      hashtags: [typeLabel, 'ilan'],
      media: [],
      jobId: String(jobId),
      fromJob: true,
      moderatedByGuard: true,
      guardDecision: 'allow',
      guardSummary: 'İlan otomatik paylaşımı',
    },
    { merge: true },
  );
  try {
    await db.collection('jobs').doc(String(jobId)).set(
      { feedPostId: postId },
      { merge: true },
    );
  } catch (_) {}
  return postId;
}

async function notifyStudentsOfJob(payload) {
  const {
    jobId,
    companyId,
    companyName,
    title,
    type = 'internship',
    typeLabel,
    location = '',
  } = payload;

  const jobRef = db.collection('jobs').doc(String(jobId));
  try {
    const claimed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(jobRef);
      const data = snap.exists ? snap.data() || {} : {};
      if (data.pushNotifiedAt) return false;
      tx.set(
        jobRef,
        { pushNotifiedAt: new Date().toISOString() },
        { merge: true },
      );
      return true;
    });
    if (!claimed) {
      return { ok: true, targeted: 0, delivered: 0, skipped: true };
    }
  } catch (_) {
    // job doc henüz yoksa devam
  }

  let jobData = {};
  try {
    const snap = await jobRef.get();
    if (snap.exists) jobData = snap.data() || {};
  } catch (_) {}

  const postId = await createJobFeedPost(
    {
      ...jobData,
      companyId,
      companyName,
      title,
      type,
      location,
      description: jobData.description || '',
    },
    jobId,
  );

  const label =
    typeLabel ||
    (type === 'internship' ? 'staj' : type === 'parttime' ? 'yarı zamanlı' : 'iş');

  const pushTitle = `Yeni ${label} ilanı`;
  const pushBody = `${companyName} yeni bir ${label} ilanı yayınladı: ${title}${
    location ? ` · ${location}` : ''
  }`;

  const result = await notifyFollowersOfActor({
    actorId: companyId,
    title: pushTitle,
    body: pushBody,
    emoji: '💼',
    type: 'job',
    targetId: postId,
    sendEmail: true,
    emailSubject: `KampüsteyimAPP · ${companyName} ${label} ilanı`,
    linkPath: `/post/${encodeURIComponent(postId)}`,
  });

  try {
    await jobRef.set(
      {
        pushTargeted: result.targeted || 0,
        pushDelivered: result.delivered || 0,
        feedPostId: postId,
      },
      { merge: true },
    );
  } catch (_) {}

  return {
    ok: true,
    targeted: result.targeted || 0,
    delivered: result.delivered || 0,
    mailed: result.mailed || 0,
    feedPostId: postId,
    skipped: false,
  };
}

exports.notifyJobPosted = onCall({ region: 'europe-west1', timeoutSeconds: 180 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const {
    jobId,
    companyId,
    companyName,
    title,
    type = 'internship',
    typeLabel,
    location = '',
  } = request.data || {};
  if (!jobId || !companyName || !title) {
    throw new HttpsError('invalid-argument', 'jobId, companyName, title zorunlu');
  }
  return notifyStudentsOfJob({
    jobId,
    companyId: companyId || request.auth.uid,
    companyName,
    title,
    type,
    typeLabel,
    location,
  });
});

/**
 * Topluluk duyuru / etkinlik: audience'a göre bildirim (followers|members|campus)
 */
exports.notifyAudience = onCall(
  { region: 'europe-west1', timeoutSeconds: 180 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const {
      kind = 'announcement',
      actorId,
      actorName = 'Topluluk',
      audience = 'followers',
      title,
      body,
      emoji = '📢',
      targetId,
      sendEmail = false,
    } = request.data || {};
    if (!actorId || !title || !body) {
      throw new HttpsError('invalid-argument', 'actorId, title, body zorunlu');
    }

    const notifType = kind === 'event' ? 'community' : 'community';
    const pushTitle = String(title);
    const pushBody = `${actorName}: ${body}`;

    if (audience === 'followers') {
      return notifyFollowersOfActor({
        actorId,
        title: pushTitle,
        body: pushBody,
        emoji,
        type: notifType,
        targetId: targetId || null,
        sendEmail: !!sendEmail,
        emailSubject: `KampüsteyimAPP · ${actorName}`,
        linkPath:
          kind === 'event' && targetId
            ? `/event/${encodeURIComponent(String(targetId))}`
            : targetId
              ? `/announcement/${encodeURIComponent(String(targetId))}`
              : '/',
      });
    }

    // members / campus — kullanıcı listesinden filtrele
    const snap = await db.collection('users').limit(800).get();
    let targeted = 0;
    let delivered = 0;
    let mailed = 0;
    for (const doc of snap.docs) {
      const u = doc.data() || {};
      const role = String(u.role || 'student');
      if (role === 'company' || role === 'admin' || role === 'community') continue;
      if (u.isCommunity === true) continue;
      if (doc.id === actorId || u.stableId === actorId) continue;

      if (audience === 'members') {
        if (String(u.affiliatedCommunityId || '') !== String(actorId)) continue;
      }

      const r = await deliverToUserDoc({
        doc,
        title: pushTitle,
        body: pushBody,
        emoji,
        type: notifType,
        actorId,
        targetId: targetId || null,
        sendEmail: false,
        emailSubject: `KampüsteyimAPP · ${actorName}`,
      });
      if (!r.skipped) targeted += 1;
      delivered += r.delivered || 0;
      mailed += r.mailed || 0;
    }
    return { ok: true, targeted, delivered, mailed };
  },
);

/** İlan Firestore'a yazılınca otomatik kullanıcı özel push */
exports.onJobCreated = onDocumentCreated(
  { document: 'jobs/{jobId}', region: 'europe-west1' },
  async (event) => {
    const job = event.data?.data();
    if (!job || !job.title) return null;
    if (job.status === 'closed') return null;
    if (job.pushNotifiedAt) return null;
    return notifyStudentsOfJob({
      jobId: event.params.jobId,
      companyId: job.companyId,
      companyName: job.companyName,
      title: job.title,
      type: job.type || 'internship',
      location: job.location || '',
    });
  },
);

/**
 * Firma AI: başvuranlar arasından en güçlü CV sıralaması (gerekçeli)
 */
exports.rankApplicants = onCall({ region: 'europe-west1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const {
    jobTitle,
    jobDescription = '',
    requirements,
    applicantIds = [],
  } = request.data || {};
  if (!Array.isArray(applicantIds) || applicantIds.length === 0) {
    return { ranked: [] };
  }

  const profiles = [];
  for (const id of applicantIds.slice(0, 25)) {
    const userSnap = await db.collection('users').doc(id).get();
    let userData = userSnap.exists ? userSnap.data() || {} : {};
    // stableId ile de dene
    if (!userSnap.exists) {
      const q = await db.collection('users').where('stableId', '==', id).limit(1).get();
      if (!q.empty) userData = q.docs[0].data() || {};
    }
    const cvSnap = await db.collection('cvs').doc(id).get();
    const cvData = cvSnap.exists ? cvSnap.data()?.cv_data || null : null;
    const pi = cvData?.personal_info || {};
    const hasCv = !!(
      cvData &&
      (
        String(pi.about || '').trim().length >= 20 ||
        (cvData.education || []).length ||
        (cvData.experiences || []).length ||
        (cvData.skills || []).length >= 2
      )
    );
    profiles.push({
      studentId: id,
      name:
        `${userData.firstName || ''} ${userData.lastName || ''}`.trim() ||
        pi.name ||
        id,
      email: userData.email || pi.email || '',
      bio: userData.bio || '',
      hasCv,
      headline: pi.headline || '',
      about: pi.about || '',
      motivation_letter: pi.motivation_letter || '',
      education: (cvData?.education || []).slice(0, 3),
      experiences: (cvData?.experiences || []).slice(0, 4),
      skills: (cvData?.skills || []).slice(0, 12),
      projects: (cvData?.projects || []).slice(0, 3),
    });
  }

  const { client, model } = await getOpenAI();
  const completion = await client.chat.completions.create({
    model,
    temperature: 0.25,
    max_tokens: 3500,
    messages: [
      {
        role: 'system',
        content: `You are an expert Turkish HR / campus recruiting AI for KampüsteyimAPP (GAÜN / AYS Tech).

Rank internship/job applicants STRICTLY against the job. Be fair and specific.

Rules:
- Score 0–100 (integer). No CV or empty CV → score ≤ 25 and explain.
- reason: 2–4 Turkish sentences with CONCRETE justification (skills match, experience relevance, motivation quality, gaps).
- strengths: 2–4 short Turkish bullet phrases.
- gaps: 1–3 short Turkish bullet phrases (what is missing vs requirements).
- hasCv: boolean from profile.hasCv (do not invent CV content).
- Do NOT invent employers, degrees, or skills not present in the profile.
- Sort ranked by score descending.

Return ONLY JSON:
{"ranked":[{"studentId":"","name":"","score":0,"reason":"","hasCv":true,"headline":"","strengths":[""],"gaps":[""]}]}`,
      },
      {
        role: 'user',
        content: JSON.stringify({
          jobTitle,
          jobDescription,
          requirements,
          profiles,
        }),
      },
    ],
  });

  let text = completion.choices[0]?.message?.content?.trim() || '{}';
  if (text.startsWith('```')) {
    text = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpsError('internal', 'AI sıralama parse hatası');
  }

  const ranked = (parsed.ranked || []).map((r) => {
    const src = profiles.find((p) => p.studentId === String(r.studentId));
    return {
      studentId: String(r.studentId || ''),
      name: String(r.name || src?.name || ''),
      score: Number(r.score) || 0,
      reason: String(r.reason || ''),
      hasCv: r.hasCv === true || src?.hasCv === true,
      headline: String(r.headline || src?.headline || ''),
      strengths: Array.isArray(r.strengths) ? r.strengths.map(String) : [],
      gaps: Array.isArray(r.gaps) ? r.gaps.map(String) : [],
    };
  });

  return { ranked };
});

/**
 * Admin: şifre sıfırlama — kendi KampüsteyimAPP sayfamız (Firebase Auth action URL yok)
 */
exports.sendPasswordReset = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const { email } = request.data || {};
  if (!email) {
    throw new HttpsError('invalid-argument', 'email zorunlu');
  }

  const link = await createAppPasswordResetLink(email);
  const html = link
    ? passwordResetEmailHtml(link)
    : brandedEmail({
        title: 'Şifre sıfırlama',
        greeting: 'Merhaba,',
        bodyHtml: `
          <p>Bu e-posta için platform hesabı bulunamadı veya bağlantı üretilemedi.</p>
          <p>Hâlâ yardıma ihtiyacın varsa admin ile iletişime geç.</p>
        `,
        ctaLabel: 'KampüsteyimAPP’e git',
        ctaUrl: BRAND_HOME,
      });

  await sendMail({
    to: String(email).trim(),
    subject: 'KampüsteyimAPP · Şifre sıfırlama',
    html,
  });

  return { ok: true, sent: true };
});

/**
 * Giriş ekranı: şifremi unuttum (auth zorunlu değil)
 * Maildeki link kendi /sifre-sifirla sayfamıza gider.
 */
exports.requestPasswordReset = onCall({ region: 'europe-west1' }, async (request) => {
  const { email } = request.data || {};
  if (!email || !String(email).includes('@')) {
    throw new HttpsError('invalid-argument', 'Geçerli e-posta gerekli');
  }

  const normalized = String(email).trim().toLowerCase();
  const link = await createAppPasswordResetLink(normalized);

  if (link) {
    await sendMail({
      to: normalized,
      subject: 'KampüsteyimAPP · Şifre sıfırlama',
      html: passwordResetEmailHtml(link),
    });
  }

  // Enumeration koruması: hesap yoksa da aynı cevap
  return { ok: true };
});

/**
 * Kendi sayfamızdan yeni şifre kaydı — kısa kod (/r/xxxxx)
 */
exports.confirmPasswordReset = onCall({ region: 'europe-west1' }, async (request) => {
  const { token, code, newPassword } = request.data || {};
  const t = String(code || token || '').trim();
  const pass = String(newPassword || '');

  if (!t || t.length < 8) {
    throw new HttpsError('invalid-argument', 'Geçersiz bağlantı');
  }
  if (pass.length < 6) {
    throw new HttpsError('invalid-argument', 'Şifre en az 6 karakter olmalı');
  }

  const ref = db.collection('password_resets').doc(t);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Bağlantı geçersiz veya süresi dolmuş');
  }

  const data = snap.data() || {};
  if (data.used) {
    throw new HttpsError('failed-precondition', 'Bu bağlantı daha önce kullanılmış');
  }
  if (data.expiresAt && new Date(data.expiresAt).getTime() < Date.now()) {
    await ref.update({ used: true, expired: true });
    throw new HttpsError('deadline-exceeded', 'Bağlantının süresi dolmuş. Yeni talep oluştur.');
  }

  const { getAuth } = require('firebase-admin/auth');
  const auth = getAuth();
  try {
    await auth.updateUser(data.uid, { password: pass });
  } catch (e) {
    console.error('[confirmPasswordReset]', e);
    throw new HttpsError('internal', 'Şifre güncellenemedi');
  }

  await ref.update({
    used: true,
    usedAt: new Date().toISOString(),
  });

  try {
    await auth.revokeRefreshTokens(data.uid);
  } catch (_) {
    // opsiyonel
  }

  return { ok: true };
});

/**
 * Admin: seçili veya tüm kullanıcılara push + inbox (+ opsiyonel mail)
 */
exports.broadcastPush = onCall({ region: 'europe-west1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const {
    title,
    body,
    emoji = '📢',
    type = 'admin_broadcast',
    all = false,
    userIds = [],
    alsoMail = false,
  } = request.data || {};
  if (!title || !body) {
    throw new HttpsError('invalid-argument', 'title ve body zorunlu');
  }

  let targets = [];
  if (all) {
    const snap = await db.collection('users').limit(500).get();
    targets = snap.docs.map((d) => d.id);
  } else if (Array.isArray(userIds) && userIds.length) {
    targets = [...new Set(userIds.map(String))].slice(0, 500);
  } else {
    throw new HttpsError('invalid-argument', 'all=true veya userIds gerekli');
  }

  let delivered = 0;
  let noToken = 0;
  const displayTitle = `${emoji} ${title}`.trim();

  for (const uid of targets) {
    let userDoc = await db.collection('users').doc(uid).get();
    let data = userDoc.exists ? userDoc.data() || {} : {};
    // stableId / eski id ile gelirse Auth UID dokümanını bul
    if (!userDoc.exists || !(data.fcmTokens || []).length) {
      try {
        const byStable = await db
          .collection('users')
          .where('stableId', '==', String(uid))
          .limit(1)
          .get();
        if (!byStable.empty) {
          userDoc = byStable.docs[0];
          data = userDoc.data() || {};
        }
      } catch (_) {}
    }
    if (!userAllowsPush(data || {}, type)) continue;

    const inboxUid = userDoc.exists ? userDoc.id : uid;
    const inbox = {
      title: displayTitle,
      body,
      emoji,
      type,
      actorId: request.auth.uid,
      targetId: null,
      read: false,
      createdAt: new Date().toISOString(),
    };
    await db.collection('users').doc(inboxUid).collection('notifications').add(inbox);

    const tokens = data.fcmTokens || [];
    if (!tokens.length) {
      noToken += 1;
      continue;
    }
    const res = await sendFcmToUser(
      inboxUid,
      tokens,
      buildCampusPushPayload({
        title: displayTitle,
        body,
        type,
        channelId: 'mt_mobil_admin',
        data: {
          emoji: String(emoji),
          toUserId: String(inboxUid),
        },
      }),
    );
    delivered += res.successCount || 0;

    if (alsoMail && data.email) {
      try {
        await sendMail({
          to: data.email,
          subject: `KampüsteyimAPP · ${title}`,
          html: `<p>${body}</p><p>AYS Tech · Kayra Çatalkaya</p>`,
        });
      } catch (_) {}
    }
  }

  return { ok: true, targeted: targets.length, delivered, noToken };
});

exports._storage = getStorage;

/**
 * Kullanıcı adı AI moderasyon + uniqueness claim
 */
exports.claimUsername = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const uid = request.auth.uid;
  let {
    username = '',
    firstName = '',
    lastName = '',
    replaceTemp = false,
  } = request.data || {};
  username = String(username).trim().replace(/^@/, '').toLowerCase();

  const makeTemp = () => `user_${uid.slice(0, 8)}_${Date.now() % 10000}`;

  if (!/^[a-z0-9_]{3,24}$/.test(username)) {
    const temp = makeTemp();
    await db.collection('handles').doc(temp).set({
      uid,
      createdAt: new Date().toISOString(),
      temp: true,
    });
    await db.collection('users').doc(uid).set(
      { username: temp, usernameStatus: 'temp' },
      { merge: true },
    );
    return {
      allowed: false,
      status: 'temp',
      username: temp,
      message: 'Kullanıcı adı formatı geçersiz. Geçici ad atandı.',
    };
  }

  const { client, model } = await getOpenAI();
  let allowed = true;
  let reason = '';
  try {
    const completion = await client.chat.completions.create({
      model,
      temperature: 0,
      max_tokens: 300,
      messages: [
        {
          role: 'system',
          content:
            'You moderate usernames for a Turkish university campus app. Reject hate, sexual, insulting, impersonation (admin/mt/ays/gaun official), or spam handles. Return ONLY JSON: {"allowed":true|false,"reason":"short Turkish"}',
        },
        {
          role: 'user',
          content: JSON.stringify({ username, firstName, lastName }),
        },
      ],
    });
    let text = completion.choices[0]?.message?.content?.trim() || '{}';
    if (text.startsWith('```')) {
      text = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
    }
    const parsed = JSON.parse(text);
    allowed = parsed.allowed !== false;
    reason = String(parsed.reason || '');
  } catch (e) {
    allowed = true;
  }

  if (!allowed) {
    const temp = makeTemp();
    await db.collection('handles').doc(temp).set({
      uid,
      createdAt: new Date().toISOString(),
      temp: true,
    });
    await db.collection('users').doc(uid).set(
      { username: temp, usernameStatus: 'temp' },
      { merge: true },
    );
    return {
      allowed: false,
      status: 'temp',
      username: temp,
      message:
        reason ||
        'Bu kullanıcı adı uygun değil. Geçici bir ad atandı; lütfen değiştir.',
    };
  }

  const handleRef = db.collection('handles').doc(username);
  const existing = await handleRef.get();
  if (existing.exists && existing.data()?.uid !== uid) {
    const temp = makeTemp();
    await db.collection('handles').doc(temp).set({
      uid,
      createdAt: new Date().toISOString(),
      temp: true,
    });
    await db.collection('users').doc(uid).set(
      { username: temp, usernameStatus: 'temp' },
      { merge: true },
    );
    return {
      allowed: false,
      status: 'temp',
      username: temp,
      message: 'Bu kullanıcı adı başkasına ait. Geçici ad atandı.',
    };
  }

  if (replaceTemp) {
    const userSnap = await db.collection('users').doc(uid).get();
    const prev = userSnap.data()?.username;
    if (prev && prev !== username) {
      const prevDoc = await db.collection('handles').doc(prev).get();
      if (prevDoc.exists && prevDoc.data()?.uid === uid) {
        await db.collection('handles').doc(prev).delete();
      }
    }
  }

  await handleRef.set({
    uid,
    createdAt: new Date().toISOString(),
    temp: false,
  });
  await db.collection('users').doc(uid).set(
    { username, usernameStatus: 'ok' },
    { merge: true },
  );

  return {
    allowed: true,
    status: 'ok',
    username,
    message: 'Kullanıcı adı kaydedildi',
  };
});

/**
 * Şikayet AI ön denetimi
 */
exports.preReviewReport = onCall({ region: 'europe-west1', timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }
  const { reportId } = request.data || {};
  if (!reportId) {
    throw new HttpsError('invalid-argument', 'reportId zorunlu');
  }
  const ref = db.collection('reports').doc(String(reportId));
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', 'Şikayet bulunamadı');
  }
  const report = snap.data() || {};

  const { client, model } = await getOpenAI();
  const completion = await client.chat.completions.create({
    model,
    temperature: 0.1,
    max_tokens: 900,
    messages: [
      {
        role: 'system',
        content:
          'You are a careful campus content moderator AI for KampüsteyimAPP (Turkish university). Decide with HIGH confidence only. Return ONLY JSON: {"decision":"resolve_dismiss"|"resolve_action"|"needs_admin","confidence":0-1,"summary":"Turkish 2-3 sentences","labels":["spam"|"harassment"|"hate"|"misinfo"|"other"|"unclear"],"action":"none"|"soft_delete_post"|"flag_account","adminNote":"Turkish note for human admin"}. Rules: resolve_dismiss only if clearly false report confidence>=0.85; resolve_action only for clear spam/hate with evidence confidence>=0.9; otherwise needs_admin. Never invent facts.',
      },
      {
        role: 'user',
        content: JSON.stringify({
          reason: report.reason,
          details: report.details,
          targetType: report.targetType,
          snapshotTitle: report.snapshotTitle,
          snapshotBody: report.snapshotBody,
          snapshotAuthor: report.snapshotAuthor,
        }),
      },
    ],
  });

  let text = completion.choices[0]?.message?.content?.trim() || '{}';
  if (text.startsWith('```')) {
    text = text.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
  }
  let ai;
  try {
    ai = JSON.parse(text);
  } catch {
    ai = {
      decision: 'needs_admin',
      confidence: 0,
      summary: 'AI parse hatası — admin incelemeli.',
      labels: ['unclear'],
      action: 'none',
      adminNote: 'AI yanıtı okunamadı',
    };
  }

  const decision = String(ai.decision || 'needs_admin');
  const confidence = Number(ai.confidence) || 0;
  let status = 'open';
  let aiActed = false;

  if (decision === 'resolve_dismiss' && confidence >= 0.85) {
    status = 'dismissed';
    aiActed = true;
  } else if (decision === 'resolve_action' && confidence >= 0.9) {
    status = 'resolved';
    aiActed = true;
    if (ai.action === 'soft_delete_post' && report.targetType === 'post' && report.targetId) {
      try {
        await db.collection('posts').doc(String(report.targetId)).set(
          {
            deletedAt: new Date().toISOString(),
            deletedBy: 'ai_moderation',
          },
          { merge: true },
        );
      } catch (_) {}
    }
  }

  const patch = {
    status,
    aiDecision: decision,
    aiConfidence: confidence,
    aiSummary: String(ai.summary || ''),
    aiLabels: Array.isArray(ai.labels) ? ai.labels.map(String) : [],
    aiAction: String(ai.action || 'none'),
    aiAdminNote: String(ai.adminNote || ''),
    aiActed,
    aiReviewedAt: new Date().toISOString(),
  };
  await ref.set(patch, { merge: true });
  return { ok: true, ...patch };
});

/**
 * Kampüs zero-tolerance: harf-harf / gömülü küfür+nefret / leetspeak / rastgele.
 * OpenAI kotası olmasa da çalışır.
 */
function normalizeForSafety(rawText) {
  let t = String(rawText || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'i')
    .replace(/ş/g, 's')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c');
  t = t
    .replace(/0/g, 'o')
    .replace(/1/g, 'i')
    .replace(/3/g, 'e')
    .replace(/4/g, 'a')
    .replace(/5/g, 's')
    .replace(/7/g, 't')
    .replace(/8/g, 'b')
    .replace(/@/g, 'a')
    .replace(/\$/g, 's');
  return t;
}

/** Harf dışı sil + tekrarları sıkıştır. */
function compactLetters(text) {
  return String(text || '')
    .replace(/[^a-z]/g, '')
    .replace(/(.)\1{2,}/g, '$1$1');
}

/** Masum uzun kökleri maskele (kısa “asik” alt dize olarak silinmez — gömülü küfrü yutmasın). */
function maskInnocentStems(compact) {
  const safe = [
    'psikolojik',
    'psikoloji',
    'psikolog',
    'sikayetci',
    'sikayetler',
    'sikayet',
    'klasikler',
    'klasik',
    'bisiklet',
    'muzisyen',
    'muzik',
    'fiziksel',
    'fiziki',
    'fizik',
    'muhendislik',
    'muhendis',
    'universite',
    'asik',
  ];
  let t = compact;
  for (const s of safe) {
    if (t.includes(s)) t = t.split(s).join('x'.repeat(s.length));
  }
  return t;
}

/** Tek rastgele yığın — küfür gömme taşıyıcısı (cümle değil). */
function looksLikeObfuscationCarrier(raw, compact) {
  const trimmed = String(raw || '').trim();
  if (!trimmed || compact.length < 6) return false;
  const tokens = trimmed.split(/\s+/).filter(Boolean);
  // Tek token + yeterince uzun = klavye smash / gömme
  if (tokens.length === 1 && compact.length >= 8) return true;
  return false;
}

/** Araya en az bir ayırıcı zorunlu: s i k / s.i.k — psikoloji içindeki sik’e uymaz. */
function spacedStemRegex(stem) {
  return new RegExp(stem.split('').join('[\\W_]+'), 'i');
}

function blockHit(labels, summary) {
  return {
    hit: true,
    decision: 'block',
    action: 'postBan',
    confidence: 0.99,
    labels,
    summary,
    message:
      'Gönderin uygunsuz / nefret içeriği içerdiği için AYS Tech Guard tarafından engellendi. Kampüste buna yer yok.',
  };
}

function localSafetyScan(rawText) {
  // @mention'ları çıkar — muhendislik vb. false positive üretmesin
  const scrubbed = String(rawText || '').replace(/@[\wğüşıöçĞÜŞİÖÇ0-9_]+/gi, ' ');
  const text = normalizeForSafety(scrubbed);
  const compact = compactLetters(text);
  const masked = maskInnocentStems(compact);
  const obfuscated = looksLikeObfuscationCarrier(scrubbed, compact);

  // 1) Uzun / net kökler — her yerde alt dize (gömülü dahil)
  const alwaysStems = [
    // nefret
    'zenci',
    'nigger',
    'nigga',
    'heilhitler',
    'killall',
    'deathto',
    'faggot',
    'kike',
    'chink',
    // küfür / NSFW (uzun — yanlış pozitif düşük)
    'siktir',
    'sikerim',
    'sikeyim',
    'sikis',
    'sikiyon',
    'siktiğ',
    'siktig',
    'amcik',
    'amina',
    'amini',
    'orospu',
    'orosbucocugu',
    'picler',
    'yarrak',
    'yarrağ',
    'yarrag',
    'gotunu',
    'gotune',
    'serefsiz',
    'kahpe',
    'porno',
    'onlyfans',
    'fuckyou',
    'motherfucker',
    'dumbass',
  ];
  for (const stem of alwaysStems) {
    const s = stem.replace(/ğ/g, 'g');
    if (masked.includes(s) || compact.includes(s) || text.includes(s)) {
      const hate = /zenci|nigger|nigga|heil|killall|deathto|faggot|kike|chink/.test(s);
      return blockHit(
        [hate ? 'hate' : 'nsfw'],
        hate
          ? 'Nefret / ayrımcı içerik (gömülü — yerel Guard).'
          : 'Küfür / uygunsuz içerik (gömülü — yerel Guard).',
      );
    }
  }

  // 2) Kısa kökler — kelime / rastgele gömme / gerçekten ayrık harf
  const shortStems = ['sik', 'amk', 'pic'];
  for (const stem of shortStems) {
    const asWord = new RegExp(`(?:^|[^a-z])${stem}(?:[^a-z]|$)`, 'i');
    if (asWord.test(text)) {
      return blockHit(['nsfw'], 'Küfür (yerel Guard).');
    }
    // Gömülü: tek yığın / boşluksuz uzun metin (asdsadasikasa)
    if (
      masked.includes(stem) &&
      (obfuscated || (compact.length >= 8 && !/\s/.test(String(scrubbed || '').trim())))
    ) {
      return blockHit(['nsfw'], 'Küfür (gömülü harf kombinasyonu — yerel Guard).');
    }
    const raw = String(scrubbed || '');
    if (spacedStemRegex(stem).test(raw)) {
      return blockHit(['nsfw'], 'Küfür (ayrık harf — yerel Guard).');
    }
  }

  // 3) Esnek nefret aralıkları
  const spacedHate = [
    /z[\W_]*e[\W_]*n[\W_]*c[\W_]*i+/i,
    /n[\W_]*i+[\W_]*g+[\W_]*g+[\W_]*[ae]+[\W_]*r*/i,
    /h[\W_]*e[\W_]*i[\W_]*l[\W_]*h[\W_]*i[\W_]*t[\W_]*l[\W_]*e[\W_]*r/i,
    /s[\W_]*i[\W_]*k[\W_]*t[\W_]*i[\W_]*r/i,
    /o[\W_]*r[\W_]*o[\W_]*s[\W_]*p[\W_]*u/i,
  ];
  for (const re of spacedHate) {
    if (re.test(text) || re.test(rawText || '')) {
      return blockHit(['hate'], 'Nefret / küfür (ayrıştırılmış yazım — yerel Guard).');
    }
  }

  const hatePatterns = [
    /kara\s*orospu/,
    /cingene\s*(pis|olum|oldur)/,
    /yahudi\s*(pis|olum|oldur|kahpe)/,
    /ermeni\s*(pis|olum|oldur)/,
    /kurt\s*(pis|olum|oldur)/,
    /turk\s*(pis|olum|oldur)/,
    /olum\s*(size|onlara|hepsine)/,
    /(olum|oldurun|katledin|yakin).{0,40}(zenci|yabanci|multeci|suriyeli|ermeni|yahudi)/,
    /(zenci|yabanci|multeci|suriyeli|ermeni|yahudi).{0,40}(olum|oldurun|katledin)/,
    /kill\s+all/,
    /death\s+to/,
  ];
  for (const re of hatePatterns) {
    if (re.test(text) || re.test(compact)) {
      return blockHit(['hate'], 'Nefret / şiddet (yerel Guard kuralı).');
    }
  }

  return { hit: false };
}

/**
 * AYS Tech Guard — ortak denetim motoru (callable + Firestore trigger)
 */
async function runGuardPostReview({
  postId,
  authorId,
  authUid,
  content,
  mediaUrls,
}) {
  const text = String(content || '');
  const urls = [
    ...(String(text).match(/https?:\/\/[^\s<>\]]+/gi) || []),
    ...(String(text).match(/www\.[^\s<>\]]+/gi) || []),
    ...(Array.isArray(mediaUrls) ? mediaUrls.map(String) : []),
  ];

  const safeHost = (u) => {
    try {
      const h = new URL(u.startsWith('http') ? u : `https://${u}`).hostname;
      return (
        h.includes('gaunengineering.com.tr') ||
        h.includes('ayskampuss.web.app') ||
        h.includes('ayskampuss.firebaseapp.com') ||
        h.includes('aystech.com') ||
        h.includes('gantep.edu.tr') ||
        h.includes('picsum.photos') ||
        h.includes('firebasestorage.googleapis.com')
      );
    } catch {
      return false;
    }
  };
  const riskyUrls = urls.filter((u) => !safeHost(u));

  // 1) Yerel kural — OpenAI kotası olmasa da çalışır
  const local = localSafetyScan(text);
  let ai = {
    decision: 'allow',
    action: 'none',
    confidence: 0.5,
    summary: '',
    labels: [],
    message: '',
  };

  if (local.hit) {
    ai = {
      decision: local.decision,
      action: local.action,
      confidence: local.confidence,
      summary: local.summary,
      labels: local.labels,
      message: local.message,
    };
  } else {
    try {
      const { client, model } = await getOpenAI();
      const completion = await client.chat.completions.create({
        model,
        temperature: 0.1,
        max_tokens: 700,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content:
              'You are AYS Tech Guard for KampüsteyimAPP (GAÜN campus). ZERO TOLERANCE. Language-agnostic (TR/EN/any). Return ONLY JSON: {"decision":"allow"|"warn"|"block","action":"none"|"warn"|"mute"|"postBan","confidence":0-1,"summary":"Turkish short reason","labels":["safe"|"spam"|"phishing"|"malware"|"nsfw"|"hate"|"harassment"|"scam"|"other"],"message":"Turkish user-facing message"}. HARD RULES: (1) Hate/slurs/threats/NSFW/swears/phishing/malware → ALWAYS block+postBan confidence>=0.95. (2) Scan letter-by-letter combinations: bad words hidden in gibberish (asdsadasikasa→sik, asdalsdaezenciaşfsad→zenci), spaced (s i k), leetspeak, repeats — BLOCK. Turkish swears (sik, siktir, amk, orospu, …) and EN equivalents count even mid-string. (3) Innocent words OK: psikoloji, şikayet, aşık, klasik, müzik, fizik, mühendislik, mühendis, @mentions/handles. Never block only because of @username tags. (4) Doubt → block. Campus is not for maybe. Official links ok: ayskampuss, aystech, gantep.edu.tr.',
            },
            {
              role: 'user',
              content: JSON.stringify({
                content: text.slice(0, 4000),
                compactPreview: compactLetters(normalizeForSafety(text)).slice(0, 500),
                maskedPreview: maskInnocentStems(
                  compactLetters(normalizeForSafety(text)),
                ).slice(0, 500),
                urls: urls.slice(0, 20),
                riskyUrls: riskyUrls.slice(0, 20),
                authorId,
                postId,
                policy: 'zero_tolerance_campus_letter_scan',
              }),
            },
        ],
      });
      let raw = completion.choices[0]?.message?.content?.trim() || '{}';
      if (raw.startsWith('```')) {
        raw = raw.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
      }
      ai = { ...ai, ...JSON.parse(raw) };
    } catch (e) {
      console.error('runGuardPostReview AI', e?.code || e?.type || e.message || e);
      // Kota / API yoksa: yerel zaten geçtiyse allow; şüpheli URL varsa uyar
      if (riskyUrls.length >= 2) {
        ai = {
          decision: 'warn',
          action: 'warn',
          confidence: 0.75,
          summary: 'Birden fazla harici bağlantı — Guard inceledi (AI kota/hata).',
          labels: ['other'],
          message: 'Harici bağlantılar dikkatle incelendi.',
        };
      }
    }
  }

  const decision = String(ai.decision || 'allow');
  const action = String(ai.action || 'none');
  const confidence = Number(ai.confidence) || 0;
  const summary = String(ai.summary || ai.message || '');
  const message = String(
    ai.message || summary || 'İçerik AYS Tech Guard tarafından incelendi.',
  );

  const uid = authUid || null;
  const actor = 'ays_guard';

  async function findUserDoc() {
    if (uid) {
      const byUid = await db.collection('users').doc(uid).get();
      if (byUid.exists) return { ref: byUid.ref, data: byUid.data() || {}, uid };
    }
    if (authorId) {
      const q = await db
        .collection('users')
        .where('stableId', '==', String(authorId))
        .limit(1)
        .get();
      if (!q.empty) {
        return { ref: q.docs[0].ref, data: q.docs[0].data() || {}, uid: q.docs[0].id };
      }
      const byId = await db.collection('users').doc(String(authorId)).get();
      if (byId.exists) return { ref: byId.ref, data: byId.data() || {}, uid: byId.id };
    }
    return null;
  }

  async function notifyUser(userDoc, type, reason) {
    const userData = userDoc.data;
    const notifyUid = userDoc.uid;
    const email = userData.email;
    const title =
      type === 'warn'
        ? 'Uyarı · AYS Tech Guard'
        : type === 'mute'
          ? 'Susturma · AYS Tech Guard'
          : type === 'postBan'
            ? 'Paylaşım yasağı · AYS Tech Guard'
            : 'Moderasyon · AYS Tech Guard';
    try {
      await db
        .collection('users')
        .doc(notifyUid)
        .collection('notifications')
        .add({
          title,
          body: reason,
          emoji: type === 'warn' ? '⚠️' : '🛡️',
          type: 'moderation',
          actorId: actor,
          targetId: postId || null,
          read: false,
          createdAt: new Date().toISOString(),
        });
    } catch (_) {}
    if (email) {
      try {
        await sendMail({
          to: email,
          subject: `KampüsteyimAPP · ${title}`,
          html: brandedEmail({
            title,
            greeting: `Merhaba ${userData.firstName || ''},`,
            bodyHtml: `<p>${reason}</p><p>Bu işlem platform AI’si <b>AYS Tech Guard</b> (@aystechbot) tarafından otomatik alındı.</p>`,
            ctaLabel: 'KampüsteyimAPP’e git',
            ctaUrl: BRAND_HOME,
          }),
        });
      } catch (_) {}
    }
  }

  const blocked = decision === 'block' && confidence >= 0.8;
  const warnOnly = decision === 'warn' && confidence >= 0.7;

  let appliedType = 'none';
  if (blocked || warnOnly || (action !== 'none' && confidence >= 0.8)) {
    const user = await findUserDoc();
    const type = blocked
      ? action === 'mute'
        ? 'mute'
        : action === 'warn'
          ? 'warn'
          : 'postBan'
      : 'warn';
    appliedType = type;
    const until =
      type === 'mute'
        ? new Date(Date.now() + 24 * 3600 * 1000).toISOString()
        : type === 'postBan'
          ? new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString()
          : null;

    if (user && type !== 'none') {
      await user.ref.set(
        {
          restrictionType: type,
          restrictionReason: summary || message,
          restrictionUntil: until,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      await notifyUser(user, type, summary || message);
    }

    await db.collection('moderation_actions').add({
      userId: authorId || uid,
      authUid: uid,
      postId: postId || null,
      type,
      decision,
      action,
      confidence,
      summary,
      labels: Array.isArray(ai.labels) ? ai.labels.map(String) : [],
      urls: urls.slice(0, 20),
      actorId: actor,
      auto: true,
      createdAt: new Date().toISOString(),
    });
  }

  // Doğrudan eylem: yayınlanmış zararlı gönderiyi soft-delete
  if (postId) {
    const postRef = db.collection('posts').doc(String(postId));
    const existing = await postRef.get();
    if (existing.exists) {
      if (blocked) {
        await postRef.set(
          {
            deletedAt: new Date().toISOString(),
            deletedBy: 'ays_guard',
            moderatedByGuard: true,
            guardDecision: decision,
            guardSummary: summary,
            guardConfidence: confidence,
          },
          { merge: true },
        );
      } else {
        await postRef.set(
          {
            moderatedByGuard: true,
            guardDecision: decision,
            guardSummary: summary,
            guardConfidence: confidence,
            guardReviewedAt: new Date().toISOString(),
          },
          { merge: true },
        );
      }
    }
  }

  return {
    blocked,
    warning: warnOnly ? message || summary : null,
    action: appliedType,
    decision,
    confidence,
    message: blocked
      ? message ||
        'Gönderin AYS Tech Guard tarafından engellendi (zararlı/NSFW/şüpheli link).'
      : message,
  };
}

/**
 * AYS Tech Guard — gönderi içeriği + link denetimi (ön kontrol)
 */
exports.moderatePostContent = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const { postId, authorId, content, mediaUrls } = request.data || {};
    const result = await runGuardPostReview({
      postId,
      authorId,
      authUid: request.auth.uid,
      content,
      mediaUrls,
    });
    if (result.blocked) {
      return {
        blocked: true,
        action: result.action,
        message: result.message,
      };
    }
    if (result.warning) {
      return { blocked: false, warning: result.warning, action: 'warn' };
    }
    return { blocked: false, action: 'none' };
  },
);

/**
 * Her yeni gönderi → Guard otomatik inceler ve gerekirse doğrudan eylem alır.
 * Client atlatılsa bile tetiklenir.
 */
exports.guardOnPostCreated = onDocumentCreated(
  {
    region: 'europe-west1',
    document: 'posts/{postId}',
    timeoutSeconds: 120,
  },
  async (event) => {
    const postId = event.params.postId;
    const data = event.data?.data();
    if (!data) return null;

    // Guard kendi postları / tekrar inceleme
    if (data.fromGuard === true || data.authorId === 'ays_guard') return null;
    if (data.moderatedByGuard === true && data.guardDecision) return null;
    if (data.deletedAt) return null;

    const media = Array.isArray(data.media)
      ? data.media.map((m) => (m && m.url ? String(m.url) : '')).filter(Boolean)
      : [];

    console.log('[guardOnPostCreated]', postId, data.authorId);
    const result = await runGuardPostReview({
      postId,
      authorId: data.authorId || data.author_id,
      authUid: data.authUid || null,
      content: data.content || '',
      mediaUrls: media,
    });
    console.log('[guardOnPostCreated] result', postId, result.decision, result.blocked);

    // Twitter tarzı: engellenmediyse takipçilere aktivite bildirimi
    if (!result.blocked && data.fromJob !== true && data.fromAnnouncement !== true) {
      const authorId = String(data.authorId || data.author_id || '');
      const authorName = String(data.authorName || 'Bir hesap');
      const snippet = String(data.content || '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 120);
      if (authorId && snippet) {
        try {
          await notifyFollowersOfActor({
            actorId: authorId,
            title: 'Yeni paylaşım',
            body: `${authorName}: ${snippet}`,
            emoji: '✨',
            type: 'activity',
            targetId: postId,
            sendEmail: false,
            linkPath: `/post/${encodeURIComponent(postId)}`,
          });
        } catch (e) {
          console.warn('[guardOnPostCreated] follower notify', e?.message || e);
        }
      }
    }
    return result;
  },
);

const MT_LOGO = `${BRAND_HOME}/mt-logo.png`;
const AYS_LOGO = BRAND_LOGO;

function brandedEmailVariant({
  title,
  greeting,
  bodyHtml,
  ctaLabel,
  ctaUrl,
  footerNote,
  logoUrl,
  brandLine,
}) {
  const safeTitle = String(title || 'KampüsteyimAPP');
  const safeGreeting = greeting
    ? `<p style="margin:0 0 16px;font-size:16px;color:#1a2332;">${greeting}</p>`
    : '';
  const cta =
    ctaLabel && ctaUrl
      ? `<p style="margin:28px 0 8px;text-align:center;">
          <a href="${ctaUrl}" style="display:inline-block;background:#0B1F3A;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:700;font-size:15px;">
            ${ctaLabel}
          </a>
        </p>`
      : '';
  const note = footerNote
    ? `<p style="margin:20px 0 0;font-size:13px;color:#6b7280;line-height:1.5;">${footerNote}</p>`
    : '';
  const logo = logoUrl || AYS_LOGO;
  const brand = brandLine || 'AYS Tech · GAÜN Mühendislik Topluluğu';

  return `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>${safeTitle}</title></head>
<body style="margin:0;padding:0;background:#EEF2F7;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF2F7;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #E2E8F0;">
        <tr><td style="background:linear-gradient(135deg,#0B1F3A 0%,#12355C 100%);padding:28px;text-align:center;">
          <img src="${logo}" alt="KampüsteyimAPP" width="72" height="72" style="display:inline-block;border-radius:50%;background:#fff;padding:4px;"/>
          <p style="margin:14px 0 0;color:#fff;font-size:20px;font-weight:800;">KampüsteyimAPP</p>
          <p style="margin:4px 0 0;color:#A8C5E2;font-size:13px;">${brand}</p>
        </td></tr>
        <tr><td style="padding:28px;">
          <h1 style="margin:0 0 16px;font-size:20px;color:#0B1F3A;">${safeTitle}</h1>
          ${safeGreeting}
          <div style="font-size:15px;line-height:1.65;color:#334155;">${bodyHtml || ''}</div>
          ${cta}${note}
        </td></tr>
        <tr><td style="padding:0 28px 28px;text-align:center;font-size:12px;color:#94A3B8;">
          <a href="${BRAND_HOME}" style="color:#0EA5E9;text-decoration:none;">gaunengineering.com.tr</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

/** Kayıt sonrası hoş geldin maili */
exports.sendWelcomeEmail = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
  const { to, firstName, username, variant } = request.data || {};
  if (!to) throw new HttpsError('invalid-argument', 'to zorunlu');
  const name = firstName || 'Kampüs';
  const handle = username ? `@${String(username).replace(/^@/, '')}` : '';
  const isMt = variant === 'mt';
  const html = brandedEmailVariant({
    title: 'KampüsteyimAPP’e hoş geldin!',
    greeting: `Merhaba ${name},`,
    bodyHtml: `<p>Kampüs ağına katıldın${handle ? ` · kullanıcı adın <b>${handle}</b>` : ''}.</p>
      <p>Feed’de paylaş, etkinliklere başvur, CV-AI ve Staj-AI ile hazırlan.</p>
      <p>Güvenlik asistanımız <b>@aystechbot</b> (AYS Tech Guard) içerik ve linkleri denetler.</p>`,
    ctaLabel: 'Uygulamaya git',
    ctaUrl: BRAND_HOME,
    logoUrl: isMt ? MT_LOGO : AYS_LOGO,
    brandLine: isMt
      ? 'GAÜN Mühendislik Topluluğu · AYS Tech'
      : 'AYS Tech · GAÜN Mühendislik Topluluğu',
  });
  await sendMail({
    to,
    subject: 'KampüsteyimAPP · Hoş geldin!',
    html,
  });
  return { ok: true };
});

/**
 * Tüm HTML mail şablonlarını test için gönderir.
 * Varsayılan alıcı: alikayracatalkaya@gmail.com
 */
exports.previewAllEmails = onCall({ region: 'europe-west1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
  const to = String(request.data?.to || 'alikayracatalkaya@gmail.com').trim();
  const samples = [
    {
      subject: '[Örnek] Hoş geldin · AYS logolu',
      html: brandedEmailVariant({
        title: 'KampüsteyimAPP’e hoş geldin!',
        greeting: 'Merhaba Ali Kayra,',
        bodyHtml: '<p>Bu AYS logolu hoş geldin şablonudur.</p>',
        ctaLabel: 'Uygulamaya git',
        ctaUrl: BRAND_HOME,
        logoUrl: AYS_LOGO,
        brandLine: 'AYS Tech · GAÜN Mühendislik Topluluğu',
      }),
    },
    {
      subject: '[Örnek] Hoş geldin · MT logolu',
      html: brandedEmailVariant({
        title: 'KampüsteyimAPP’e hoş geldin!',
        greeting: 'Merhaba Ali Kayra,',
        bodyHtml: '<p>Bu MT logolu hoş geldin şablonudur.</p>',
        ctaLabel: 'Uygulamaya git',
        ctaUrl: BRAND_HOME,
        logoUrl: MT_LOGO,
        brandLine: 'GAÜN Mühendislik Topluluğu · AYS Tech',
      }),
    },
    {
      subject: '[Örnek] Şikayet alındı',
      html: brandedEmail({
        title: 'Şikayetin alındı',
        greeting: 'Merhaba,',
        bodyHtml: '<p>Şikayetini aldık. AYS Tech Guard ve admin ekibi inceliyor.</p>',
        ctaLabel: 'KampüsteyimAPP',
        ctaUrl: BRAND_HOME,
      }),
    },
    {
      subject: '[Örnek] Moderasyon · Uyarı',
      html: brandedEmail({
        title: 'Uyarı · AYS Tech Guard',
        greeting: 'Merhaba,',
        bodyHtml: '<p>Paylaşımın topluluk kurallarına aykırı bulundu. Bu bir uyarıdır.</p>',
        ctaLabel: 'Kuralları gör',
        ctaUrl: BRAND_HOME,
      }),
    },
    {
      subject: '[Örnek] Moderasyon · Susturma',
      html: brandedEmail({
        title: 'Susturma · AYS Tech Guard',
        greeting: 'Merhaba,',
        bodyHtml: '<p>Hesabın 24 saat susturuldu. Paylaşım ve yorum kısıtlandı.</p>',
        ctaLabel: 'KampüsteyimAPP',
        ctaUrl: BRAND_HOME,
      }),
    },
    {
      subject: '[Örnek] Şifre sıfırlama',
      html: brandedEmail({
        title: 'Şifre sıfırlama',
        greeting: 'Merhaba,',
        bodyHtml: '<p>Şifreni sıfırlamak için aşağıdaki butonu kullan (örnek bağlantı).</p>',
        ctaLabel: 'Şifreyi sıfırla',
        ctaUrl: `${BRAND_HOME}/r/ornekKisa`,
      }),
    },
    {
      subject: '[Örnek] Yeni ilan',
      html: brandedEmail({
        title: 'Yeni staj ilanı',
        greeting: 'Merhaba,',
        bodyHtml: '<p><b>AYS Tech</b> yeni bir staj ilanı yayınladı: Flutter Kampüs Stajı.</p>',
        ctaLabel: 'İlanı gör',
        ctaUrl: BRAND_HOME,
      }),
    },
    {
      subject: '[Örnek] Firma teklifi',
      html: brandedEmail({
        title: 'Firma teklifi',
        greeting: 'Merhaba,',
        bodyHtml: '<p>AYS Tech sana özel bir teklif gönderdi.</p>',
        ctaLabel: 'Teklifi gör',
        ctaUrl: BRAND_HOME,
      }),
    },
  ];

  const sent = [];
  for (const s of samples) {
    await sendMail({ to, subject: s.subject, html: s.html });
    sent.push(s.subject);
  }
  return { ok: true, to, count: sent.length, subjects: sent };
});

/**
 * AYS Tech Guard — rastgele espri patlaması
 * Saatlik tick; cooldown + yüksek skip → günde ~0–1, zaman tamamen rastgele.
 * İnternet: TR haber RSS + OpenAI (mümkünse web search).
 */
async function fetchTrHeadlines(limit = 10) {
  const urls = [
    'https://news.google.com/rss?hl=tr&gl=TR&ceid=TR:tr',
    'https://news.google.com/rss/headlines/section/topic/NATIONAL.tr_tr?hl=tr&gl=TR&ceid=TR:tr',
  ];
  const titles = [];
  for (const url of urls) {
    try {
      const res = await fetch(url, {
        headers: { 'User-Agent': 'KampusteyimAPP-AYSGuard/1.0' },
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) continue;
      const text = await res.text();
      const re = /<title(?:[^>]*)>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?<\/title>/gi;
      let m;
      while ((m = re.exec(text)) !== null) {
        let t = String(m[1] || '')
          .replace(/&amp;/g, '&')
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/<[^>]+>/g, '')
          .trim();
        if (!t || /^google\s*haber/i.test(t) || /^google news/i.test(t)) continue;
        if (t.length < 12 || t.length > 180) continue;
        if (!titles.includes(t)) titles.push(t);
        if (titles.length >= limit) break;
      }
      if (titles.length >= 4) break;
    } catch (e) {
      console.warn('[guard] rss', url, e?.message || e);
    }
  }
  return titles.slice(0, limit);
}

async function generateGuardJoke(headlines) {
  const { client, model } = await getOpenAI();
  const system =
    'Sen KampüsteyimAPP kampüs botusun: AYS Tech Guard (@aystechbot). ' +
    'SADECE espri / mizah yazarsın — kısa, zeki, sevimli Türkçe. ' +
    'Ton: üniversite öğrencisi sohbeti, absürt kampüs durumu, hafif self-deprecating mühendislik esprisi. ' +
    'YASAK: ders/lab/ödev hatırlatması, "unutmayın", motive edici vaaz, su iç / erken yat nasihatı, ' +
    'CV/staj ipucu, duyuru dili, ciddi güvenlik uyarısı. Bunlar espri değil. ' +
    'Küfür, nefret, ayrımcılık, ağır siyaset, kişisel saldırı YOK. ' +
    'Max ~260 karakter, 1–2 satır. İstersen sonda #KampüsteyimAPP #aystechbot. ' +
    'SADECE espri metnini döndür; tırnak veya JSON yok.';

  try {
    if (client.responses && typeof client.responses.create === 'function') {
      const r = await client.responses.create({
        model: model || 'gpt-4o-mini',
        tools: [{ type: 'web_search_preview' }],
        temperature: 1.05,
        input: [
          { role: 'system', content: system },
          {
            role: 'user',
            content:
              'Türkiye veya kampüs gündeminden bir kıvılcım alıp SADECE komik bir espri yaz. ' +
              'Nasihat yok, hatırlatma yok — punchline olsun.',
          },
        ],
      });
      const textOut = String(r.output_text || '').trim();
      if (textOut.length >= 20) return textOut.slice(0, 400);
    }
  } catch (e) {
    console.warn('[guard] responses/web_search', e?.message || e);
  }

  const completion = await client.chat.completions.create({
    model: model || 'gpt-4o-mini',
    temperature: 1.05,
    max_tokens: 220,
    messages: [
      { role: 'system', content: system },
      {
        role: 'user',
        content: headlines.length
          ? `Aşağıdaki başlıklardan BİRİNE bağlı SADECE espri yaz (nasihat/lab hatırlatması yok):\n${headlines
              .map((h, i) => `${i + 1}. ${h}`)
              .join('\n')}`
          : 'Kampüs / Wi‑Fi / kantin / proje teslimi absürtlüğünden random espri yaz. Nasihat yok.',
      },
    ],
  });
  return String(completion.choices?.[0]?.message?.content || '').trim().slice(0, 400);
}

function extractHashtags(text) {
  const tags = [];
  const re = /#([\p{L}\p{N}_]+)/gu;
  let m;
  while ((m = re.exec(text)) !== null) {
    const t = m[1];
    if (t && !tags.includes(t)) tags.push(t);
  }
  if (!tags.includes('KampüsteyimAPP')) tags.push('KampüsteyimAPP');
  if (!tags.includes('aystechbot')) tags.push('aystechbot');
  return tags.slice(0, 8);
}

/** Guard feed esprileri: ortak cooldown — sessizlikte daha sık. */
async function feedSilenceHours() {
  try {
    const snap = await db
      .collection('posts')
      .orderBy('createdAt', 'desc')
      .limit(40)
      .get();
    let lastHuman = 0;
    for (const d of snap.docs) {
      const data = d.data() || {};
      const author = String(data.authorId || '');
      if (!author || author === 'ays_guard') continue;
      const t = Date.parse(data.createdAt || '');
      if (Number.isFinite(t) && t > lastHuman) lastHuman = t;
    }
    if (!lastHuman) return 72; // hiç üye postu yok → uzun sessizlik
    return (Date.now() - lastHuman) / 3600 / 1000;
  } catch (e) {
    console.warn('[guard] silence', e?.message || e);
    return 0;
  }
}

async function guardFeedCooldownOk(cfg) {
  const silenceH = await feedSilenceHours();
  // Sessizlik uzadıkça min gap kısalır (sıkıldım / sohbet açma).
  let minGapH = Number(cfg.minGapHours) > 0 ? Number(cfg.minGapHours) : 30;
  if (silenceH >= 48) minGapH = Math.min(minGapH, 8);
  else if (silenceH >= 24) minGapH = Math.min(minGapH, 14);
  else if (silenceH >= 12) minGapH = Math.min(minGapH, 20);

  const lastAt = cfg.lastJokeAt ? Date.parse(cfg.lastJokeAt) : 0;
  const minGapMs = minGapH * 3600 * 1000;
  if (lastAt && Date.now() - lastAt < minGapMs) {
    return {
      ok: false,
      reason: 'cooldown',
      hoursLeft: ((minGapMs - (Date.now() - lastAt)) / 3600 / 1000).toFixed(1),
      silenceH: silenceH.toFixed(1),
      minGapH,
    };
  }
  const dayAgo = Date.now() - 24 * 3600 * 1000;
  const dailyMax = silenceH >= 24 ? 3 : silenceH >= 12 ? 2 : 1;
  try {
    const recent = await db
      .collection('posts')
      .where('authorId', '==', 'ays_guard')
      .orderBy('createdAt', 'desc')
      .limit(12)
      .get();
    const recentCount = recent.docs.filter((d) => {
      const data = d.data() || {};
      const t = Date.parse(data.createdAt || '');
      if (!Number.isFinite(t) || t < dayAgo) return false;
      if (String(d.id).startsWith('guard_week_')) return false;
      return data.guardJoke === true || data.guardMood || data.fromGuard === true;
    }).length;
    if (recentCount >= dailyMax) {
      return { ok: false, reason: 'daily_quota', recentCount, dailyMax, silenceH };
    }
  } catch (e) {
    console.warn('[guard] recent count', e?.message || e);
  }
  return { ok: true, silenceH, minGapH, dailyMax };
}

async function generateGuardBoredLine(silenceH) {
  const boredFallbacks = [
    'Akış suskun… ben de sıkıldım. Biri Wi‑Fi şikâyeti atsın bari. 📡',
    'Konuşulmuyor gibi. Kantin kuyruğu bile daha sosyal şu an. 😅',
    'Sessizlik uzun sürdü — “sıkıldım” demek için geldim. Merhaba kampüs.',
    'Üye aktivitesi yok, ben de ortalıkta geziyorum. Kimse yok mu? 👀',
    'Feed’e bakıyorum: boş. Benim ruh halim: biraz sıkılmış, biraz meraklı.',
  ];
  try {
    const { client, model } = await getOpenAI();
    const completion = await client.chat.completions.create({
      model: model || 'gpt-4o-mini',
      temperature: 1.1,
      max_tokens: 160,
      messages: [
        {
          role: 'system',
          content:
            'Sen KampüsteyimAPP botusun AYS Tech Guard (@aystechbot). ' +
            'Kampüs akışı uzun süredir sessiz. Kısa, sevimli, mizahi Türkçe yaz. ' +
            '“sıkıldım”, “kimse yok”, “konuşulmuyor” tonu OK. Nasihat/lab hatırlatması YOK. Max 220 karakter.',
        },
        {
          role: 'user',
          content: `Üye postu yokluğu yaklaşık ${Math.round(
            silenceH,
          )} saat. Buna uygun tek kısa espri / sıkılma cümlesi yaz.`,
        },
      ],
    });
    const t = String(completion.choices?.[0]?.message?.content || '').trim();
    if (t.length >= 12) return t.slice(0, 320);
  } catch (e) {
    console.warn('[guard] bored AI', e?.message || e);
  }
  return boredFallbacks[Math.floor(Math.random() * boredFallbacks.length)];
}

async function markGuardJokePosted(cfgRef, postId, preview) {
  const nextMinGap = 26 + Math.floor(Math.random() * 22);
  await cfgRef.set(
    {
      lastJokeAt: new Date().toISOString(),
      lastJokePostId: postId,
      minGapHours: nextMinGap,
      lastJokePreview: String(preview || '').slice(0, 120),
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
  return nextMinGap;
}

exports.guardDailyPost = onSchedule(
  {
    region: 'europe-west1',
    schedule: '23 * * * *',
    timeZone: 'Europe/Istanbul',
    timeoutSeconds: 120,
  },
  async () => {
    const hour = Number(
      new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/Istanbul',
        hour: 'numeric',
        hour12: false,
      }).format(new Date()),
    );
    if (hour < 10 || hour > 21) {
      console.log('guardDailyPost night skip', hour);
      return;
    }

    const cfgRef = db.collection('app_config').doc('guard_bot');
    const cfgSnap = await cfgRef.get();
    const cfg = cfgSnap.data() || {};
    const cd = await guardFeedCooldownOk(cfg);
    if (!cd.ok) {
      console.log('guardDailyPost skip', cd);
      return;
    }

    const silenceH = Number(cd.silenceH) || 0;
    // Sessizlikte daha yüksek şans; aktif akışta düşük.
    const chance = Number(cfg.jokeChance);
    let rollThreshold =
      chance > 0 && chance < 1 ? chance : silenceH >= 24 ? 0.35 : silenceH >= 12 ? 0.18 : 0.06;
    const roll = Math.random();
    if (roll > rollThreshold) {
      console.log('guardDailyPost skipped roll', { roll, rollThreshold, silenceH });
      return;
    }

    let content = '';
    try {
      if (silenceH >= 10) {
        content = await generateGuardBoredLine(silenceH);
      } else {
        const headlines = await fetchTrHeadlines(10);
        content = await generateGuardJoke(headlines);
        console.log('guardDailyPost headlines', headlines.slice(0, 3));
      }
    } catch (e) {
      console.error('guardDailyPost AI', e?.message || e);
    }

    if (!content || content.length < 16) {
      const fallback = [
        'Kampüs Wi‑Fi’si: "bağlandı" diyor, kalbi hâlâ "bağlanıyor…". 📡',
        'Proje dosyası adı: final_final_SON_v7_gercekten. Klasik. 😅',
        'Kantin kuyruğu + 3 dk’lık ders arası = olimpiyat disiplini.',
        'Akış sessiz… sıkıldım biraz. Birinin “merhaba” demesi lazım. 👀',
      ];
      content = fallback[Math.floor(Math.random() * fallback.length)];
    }

    content = content
      .replace(/^["'`]+|["'`]+$/g, '')
      .replace(/^```[\s\S]*?\n|```$/g, '')
      .trim();

    const postId = `guard_${Date.now()}`;
    const hashtags = extractHashtags(content);
    await db.collection('posts').doc(postId).set({
      authorId: 'ays_guard',
      authorName: 'AYS Tech Guard',
      authorHandle: '@aystechbot',
      content,
      createdAt: new Date().toISOString(),
      likeCount: 0,
      replyCount: 0,
      repostCount: 0,
      isCommunity: false,
      hashtags,
      media: [],
      fromGuard: true,
      guardJoke: true,
      moderatedByGuard: true,
      guardDecision: 'allow',
    });

    const nextMinGap = await markGuardJokePosted(cfgRef, postId, content);
    console.log('guardDailyPost joke created', postId, 'nextMinGapH', nextMinGap);
  },
);

/** Haftanın yıldızı — Pazartesi 10:00 */
exports.guardWeeklyStar = onSchedule(
  {
    region: 'europe-west1',
    schedule: '0 10 * * 1',
    timeZone: 'Europe/Istanbul',
    timeoutSeconds: 120,
  },
  async () => {
    if (Math.random() < 0.15) return; // nadiren atla
    const since = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
    const snap = await db
      .collection('posts')
      .where('createdAt', '>=', since)
      .limit(200)
      .get()
      .catch(async () => db.collection('posts').orderBy('createdAt', 'desc').limit(100).get());

    const score = {};
    const meta = {};
    for (const d of snap.docs) {
      const p = d.data();
      const id = p.authorId;
      if (!id || id === 'ays_guard') continue;
      score[id] =
        (score[id] || 0) +
        (Number(p.likeCount) || 0) +
        (Number(p.replyCount) || 0) * 2 +
        (Number(p.repostCount) || 0);
      meta[id] = p.authorHandle || p.authorName;
    }
    const top = Object.entries(score).sort((a, b) => b[1] - a[1])[0];
    if (!top) return;
    let uname = String(meta[top[0]] || top[0]).replace(/^@/, '');
    try {
      const q = await db.collection('users').where('stableId', '==', top[0]).limit(1).get();
      if (!q.empty && q.docs[0].data().username) {
        uname = String(q.docs[0].data().username).replace(/^@/, '');
      }
    } catch (_) {}

    const content =
      `⭐ Haftanın yıldızı: @${uname}\n` +
      `Bu hafta kampüste en aktif paylaşımlarıyla öne çıktı.\n` +
      `#haftanınyıldızı #KampüsteyimAPP #aystechbot`;

    await db.collection('posts').doc(`guard_week_${Date.now()}`).set({
      authorId: 'ays_guard',
      authorName: 'AYS Tech Guard',
      authorHandle: '@aystechbot',
      content,
      createdAt: new Date().toISOString(),
      likeCount: 0,
      replyCount: 0,
      repostCount: 0,
      isCommunity: false,
      hashtags: ['haftanınyıldızı', 'KampüsteyimAPP', 'aystechbot'],
      media: [],
      fromGuard: true,
      moderatedByGuard: true,
      guardDecision: 'allow',
    });
  },
);

/**
 * Saatlik tarama — anlık trigger kaçırdıysa Guard tekrar inceler.
 * Son ~3 saatteki, henüz Guard imzası olmayan gönderiler.
 */
exports.guardHourlySweep = onSchedule(
  {
    region: 'europe-west1',
    schedule: '5 * * * *',
    timeZone: 'Europe/Istanbul',
    timeoutSeconds: 300,
  },
  async () => {
    const since = new Date(Date.now() - 3 * 3600 * 1000).toISOString();
    let snap;
    try {
      snap = await db
        .collection('posts')
        .where('createdAt', '>=', since)
        .orderBy('createdAt', 'desc')
        .limit(40)
        .get();
    } catch (e) {
      console.warn('[guardHourlySweep] query fallback', e.message);
      snap = await db.collection('posts').orderBy('createdAt', 'desc').limit(40).get();
    }

    let reviewed = 0;
    let acted = 0;
    for (const doc of snap.docs) {
      if (reviewed >= 12) break; // maliyet / kota
      const data = doc.data() || {};
      if (data.fromGuard === true || data.authorId === 'ays_guard') continue;
      if (data.deletedAt) continue;
      if (data.moderatedByGuard === true && data.guardDecision) continue;

      const media = Array.isArray(data.media)
        ? data.media.map((m) => (m && m.url ? String(m.url) : '')).filter(Boolean)
        : [];

      try {
        const result = await runGuardPostReview({
          postId: doc.id,
          authorId: data.authorId || data.author_id,
          authUid: data.authUid || null,
          content: data.content || '',
          mediaUrls: media,
        });
        reviewed += 1;
        if (result.blocked) acted += 1;
        console.log('[guardHourlySweep]', doc.id, result.decision, result.blocked);
      } catch (err) {
        console.error('[guardHourlySweep] fail', doc.id, err.message);
      }
    }
    console.log('[guardHourlySweep] done', { reviewed, acted, scanned: snap.size });
  },
);

/**
 * Guard mood — neredeyse tamamen kapalı; espri kanalı guardDailyPost.
 * Çok nadir yedek espri (aynı cooldown + günde max 1).
 */
exports.guardMoodPost = onSchedule(
  {
    region: 'europe-west1',
    schedule: '25 * * * *',
    timeZone: 'Europe/Istanbul',
    timeoutSeconds: 120,
  },
  async () => {
    const hour = new Date(
      new Date().toLocaleString('en-US', { timeZone: 'Europe/Istanbul' }),
    ).getHours();
    if (hour < 11 || hour > 20) {
      console.log('[guardMoodPost] quiet hours', hour);
      return;
    }

    const cfgRef = db.collection('app_config').doc('guard_bot');
    const cfgSnap = await cfgRef.get();
    const cfg = cfgSnap.data() || {};
    const cd = await guardFeedCooldownOk(cfg);
    if (!cd.ok) {
      console.log('[guardMoodPost] skip', cd);
      return;
    }

    const silenceH = Number(cd.silenceH) || 0;
    // Sessizlikte mood kanalı da açılsın
    const moodChance = silenceH >= 24 ? 0.28 : silenceH >= 12 ? 0.12 : 0.03;
    const moodRoll = Math.random();
    if (moodRoll > moodChance) {
      console.log('[guardMoodPost] skipped — not inspired', { hour, moodRoll, moodChance, silenceH });
      return;
    }

    let content = '';
    try {
      if (silenceH >= 10) {
        content = await generateGuardBoredLine(silenceH);
      } else {
        const headlines = await fetchTrHeadlines(8);
        content = await generateGuardJoke(headlines);
      }
    } catch (e) {
      console.error('[guardMoodPost] AI', e.message);
      const fallback = [
        'Wi‑Fi bir an geldi bir an gitti — ilişki status: complicated. 📡',
        '“Son bir commit” diye başlayan gece, güneş doğunca bitiyor. 😅',
        'Kantin siparişi: hızlı. Ödeme sırası: epik.',
        'Sıkıldım biraz — akışta kimse yok gibi. 👀',
      ];
      content = fallback[Math.floor(Math.random() * fallback.length)];
    }

    content = String(content || '')
      .replace(/^["«]|["»]$/g, '')
      .trim();
    if (!content || content.length < 8) return;

    const hashtags = extractHashtags(content);
    const postId = `guard_mood_${Date.now()}`;
    await db.collection('posts').doc(postId).set({
      authorId: 'ays_guard',
      authorName: 'AYS Tech Guard',
      authorHandle: '@aystechbot',
      content,
      createdAt: new Date().toISOString(),
      likeCount: 0,
      replyCount: 0,
      repostCount: 0,
      isCommunity: false,
      hashtags: hashtags.slice(0, 6),
      media: [],
      fromGuard: true,
      guardJoke: true,
      guardMood: 'espri',
      moderatedByGuard: true,
      guardDecision: 'allow',
    });
    await markGuardJokePosted(cfgRef, postId, content);
    console.log('[guardMoodPost] posted joke', postId);
  },
);

/** Firestore outbox → SMTP (preview / manuel kuyruk) */
exports.onMailOutboxCreated = onDocumentCreated(
  { region: 'europe-west1', document: 'mail_outbox/{id}' },
  async (event) => {
    const data = event.data?.data() || {};
    const to = data.to;
    const subject = data.subject;
    const html = data.html;
    if (!to || !subject || !html) return;
    await sendMail({ to, subject, html });
    await event.data.ref.set(
      { sentAt: new Date().toISOString(), status: 'sent' },
      { merge: true },
    );
  },
);

// ─── AYS Tech planlı bakım ─────────────────────────────────────────

async function assertPlatformAdmin(uid) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError('permission-denied', 'Admin gerekli');
  }
  const d = snap.data() || {};
  if (d.isSuperAdmin === true || d.role === 'admin') return d;
  throw new HttpsError('permission-denied', 'Admin gerekli');
}

function emailDocId(email) {
  return crypto.createHash('sha256').update(String(email).toLowerCase()).digest('hex').slice(0, 40);
}

async function broadcastMaintenancePush({ title, body, type }) {
  const snap = await db.collection('users').limit(500).get();
  let delivered = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (!userAllowsPush(data, type)) continue;
    const inbox = {
      title,
      body,
      emoji: 'AYS',
      type,
      actorId: 'ays_tech',
      targetId: null,
      read: false,
      createdAt: new Date().toISOString(),
    };
    await db.collection('users').doc(doc.id).collection('notifications').add(inbox);
    const tokens = data.fcmTokens || [];
    if (!tokens.length) continue;
    const res = await sendFcmToUser(
      doc.id,
      tokens,
      buildCampusPushPayload({
        title,
        body,
        type,
        channelId: 'mt_mobil_admin',
        data: { emoji: 'AYS', toUserId: String(doc.id) },
      }),
    );
    delivered += res.successCount || 0;
  }
  return delivered;
}

async function notifyMaintenanceSubscribers({ title, bodyHtml, subject }) {
  const snap = await db
    .collection('maintenance_subscribers')
    .where('notified', '==', false)
    .limit(500)
    .get();
  let mailed = 0;
  let pushed = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const email = String(d.email || '').trim().toLowerCase();
    const uid = d.uid ? String(d.uid) : '';
    if (email.includes('@')) {
      try {
        await sendMail({
          to: email,
          subject,
          html: brandedEmail({
            title,
            greeting: 'Merhaba,',
            bodyHtml,
            ctaLabel: 'KampüsteyimAPP’e git',
            ctaUrl: BRAND_HOME,
            footerNote: 'Bu bildirim bakım aboneliğiniz nedeniyle gönderildi.',
          }),
        });
        mailed += 1;
      } catch (e) {
        console.warn('[maint] mail', email, e.message);
      }
    }
    if (uid) {
      try {
        const userDoc = await db.collection('users').doc(uid).get();
        const data = userDoc.exists ? userDoc.data() || {} : {};
        const tokens = data.fcmTokens || [];
        await db.collection('users').doc(uid).collection('notifications').add({
          title,
          body: 'Bakım tamamlandı · KampüsteyimAPP tekrar açık.',
          emoji: 'AYS',
          type: 'maintenance_end',
          actorId: 'ays_tech',
          targetId: null,
          read: false,
          createdAt: new Date().toISOString(),
        });
        if (tokens.length) {
          const res = await sendFcmToUser(
            uid,
            tokens,
            buildCampusPushPayload({
              title,
              body: 'Bakım tamamlandı · KampüsteyimAPP tekrar açık.',
              type: 'maintenance_end',
              channelId: 'mt_mobil_admin',
              data: { emoji: 'AYS', toUserId: String(uid) },
            }),
          );
          pushed += res.successCount || 0;
        }
      } catch (_) {}
    }
    await doc.ref.set(
      { notified: true, notifiedAt: new Date().toISOString() },
      { merge: true },
    );
  }
  return { mailed, pushed, count: snap.size };
}

/**
 * Admin: bakım planı kaydet / başlat
 */
exports.setMaintenance = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
  await assertPlatformAdmin(request.auth.uid);

  const {
    title = 'Planlı bakım',
    message = 'KampüsteyimAPP şu an AYS Tech tarafından planlı bakıma alındı.',
    plannedStart,
    plannedEnd,
    active = false,
    autoActivate = true,
    notifyOnStart = true,
  } = request.data || {};

  if (!plannedStart || !plannedEnd) {
    throw new HttpsError('invalid-argument', 'plannedStart ve plannedEnd zorunlu');
  }

  const ref = db.collection('app_config').doc('maintenance');
  const prev = (await ref.get()).data() || {};
  const wasActive = prev.active === true;
  const nowIso = new Date().toISOString();
  const sessionId =
    active && !wasActive
      ? `m_${Date.now().toString(36)}`
      : prev.sessionId || `m_${Date.now().toString(36)}`;

  const payload = {
    active: !!active,
    title: sanitizePlainText(title, 120) || 'Planlı bakım',
    message:
      sanitizePlainText(message, 800) ||
      'KampüsteyimAPP şu an AYS Tech tarafından planlı bakıma alındı.',
    plannedStart: new Date(plannedStart).toISOString(),
    plannedEnd: new Date(plannedEnd).toISOString(),
    autoActivate: autoActivate !== false,
    notifyOnStart: notifyOnStart !== false,
    sessionId,
    updatedAt: nowIso,
    updatedBy: request.auth.uid,
    subscriberCount: prev.subscriberCount || 0,
  };

  if (active) {
    payload.startedAt = prev.startedAt || nowIso;
    payload.endedAt = null;
  }

  await ref.set(payload, { merge: true });

  let pushed = 0;
  if (active && !wasActive && notifyOnStart !== false) {
    pushed = await broadcastMaintenancePush({
      title: `AYS Tech · ${payload.title}`,
      body: payload.message,
      type: 'maintenance_start',
    });
  }

  return {
    ok: true,
    active: payload.active,
    sessionId,
    pushed,
    message: payload.active
      ? `Bakım aktif · ${pushed} cihaz bilgilendirildi`
      : 'Bakım planı kaydedildi',
  };
});

/**
 * Admin: bakımı bitir + abonelere haber ver
 */
exports.endMaintenance = onCall({ region: 'europe-west1', timeoutSeconds: 180 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
  await assertPlatformAdmin(request.auth.uid);

  const ref = db.collection('app_config').doc('maintenance');
  const prev = (await ref.get()).data() || {};
  const nowIso = new Date().toISOString();

  await ref.set(
    {
      active: false,
      endedAt: nowIso,
      updatedAt: nowIso,
      updatedBy: request.auth.uid,
    },
    { merge: true },
  );

  const title = 'KampüsteyimAPP tekrar açık';
  const sub = await notifyMaintenanceSubscribers({
    title,
    subject: 'AYS Tech · Bakım tamamlandı',
    bodyHtml:
      '<p>Planlı bakım tamamlandı. KampüsteyimAPP’i yeniden kullanabilirsiniz.</p>',
  });

  const pushedAll = await broadcastMaintenancePush({
    title: 'AYS Tech · Bakım bitti',
    body: 'KampüsteyimAPP tekrar açık. İyi kullanımlar.',
    type: 'maintenance_end',
  });

  return {
    ok: true,
    mailed: sub.mailed,
    pushed: (sub.pushed || 0) + pushedAll,
    subscribers: sub.count,
    wasActive: prev.active === true,
  };
});

/**
 * Kullanıcı: bakım bitince haber ver (e-posta / push)
 */
exports.subscribeMaintenanceNotify = onCall({ region: 'europe-west1' }, async (request) => {
  let email = String(request.data?.email || '')
    .trim()
    .toLowerCase();
  const platform = String(request.data?.platform || 'web').slice(0, 16);
  // uid yalnızca auth token’dan — istemci spoof edemesin
  let uid = request.auth?.uid ? String(request.auth.uid) : '';

  if (!isValidEmail(email)) {
    throw new HttpsError('invalid-argument', 'Geçerli e-posta gerekli');
  }
  email = email.replace(/[<>"'`;\\]/g, '');

  const maint = (await db.collection('app_config').doc('maintenance').get()).data() || {};
  const sessionId = sanitizePlainText(maint.sessionId || 'default', 64);
  const id = emailDocId(`${sessionId}:${email}`);
  const ref = db.collection('maintenance_subscribers').doc(id);
  const exists = await ref.get();
  if (exists.exists && exists.data()?.notified !== true) {
    return { ok: true, already: true };
  }

  await ref.set({
    email,
    platform,
    uid: uid || null,
    sessionId,
    notified: false,
    createdAt: new Date().toISOString(),
  });

  await db
    .collection('app_config')
    .doc('maintenance')
    .set(
      { subscriberCount: FieldValue.increment(exists.exists ? 0 : 1) },
      { merge: true },
    );

  return { ok: true, already: false };
});

/**
 * Planlanan başlangıçta bakımı otomatik aç
 */
exports.maintenanceTick = onSchedule(
  {
    schedule: 'every 2 minutes',
    region: 'europe-west1',
    timeoutSeconds: 120,
  },
  async () => {
    const ref = db.collection('app_config').doc('maintenance');
    const snap = await ref.get();
    if (!snap.exists) return null;
    const d = snap.data() || {};
    if (d.active === true) return null;
    if (d.autoActivate === false) return null;
    if (!d.plannedStart) return null;
    if (d.endedAt && d.sessionId && d.startedAt) {
      // Bu oturum daha önce bitmişse yeniden açma
      const ended = new Date(d.endedAt).getTime();
      const start = new Date(d.plannedStart).getTime();
      if (ended >= start) return null;
    }
    const startMs = new Date(d.plannedStart).getTime();
    if (Number.isNaN(startMs) || Date.now() < startMs) return null;

    const nowIso = new Date().toISOString();
    const sessionId = d.sessionId || `m_${Date.now().toString(36)}`;
    await ref.set(
      {
        active: true,
        startedAt: nowIso,
        endedAt: null,
        sessionId,
        updatedAt: nowIso,
        updatedBy: 'maintenanceTick',
      },
      { merge: true },
    );

    if (d.notifyOnStart !== false) {
      await broadcastMaintenancePush({
        title: `AYS Tech · ${d.title || 'Planlı bakım'}`,
        body: d.message || 'KampüsteyimAPP planlı bakıma alındı.',
        type: 'maintenance_start',
      });
    }
    console.log('[maintenanceTick] activated', sessionId);
    return null;
  },
);

/** Çalışma odası chat AI (AYS Guard). */
exports.studyChatAi = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const roomId = String(request.data?.roomId || '').trim();
    const message = String(request.data?.message || '').trim();
    const senderName = String(request.data?.senderName || 'Öğrenci').trim();
    if (!roomId || !message) {
      throw new HttpsError('invalid-argument', 'roomId ve message gerekli');
    }

    const roomRef = db.collection('study_rooms').doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      throw new HttpsError('not-found', 'Oda bulunamadı');
    }
    const room = roomSnap.data() || {};
    if (room.chatOpen === false || room.status === 'ended') {
      throw new HttpsError('failed-precondition', 'Chat kapalı');
    }
    const uid = request.auth.uid;
    const parts = Array.isArray(room.participantIds) ? room.participantIds : [];
    const kicked = Array.isArray(room.kickedIds) ? room.kickedIds : [];
    if (kicked.includes(uid)) {
      throw new HttpsError('permission-denied', 'Çıkarıldın');
    }
    if (room.hostId !== uid && !parts.includes(uid)) {
      throw new HttpsError('permission-denied', 'Üye değilsin');
    }

    let reply =
      'Odaklanmaya devam 💪 Kısa molalar ve net hedefler en iyi sonucu verir.';
    try {
      const { client, model } = await getOpenAI();
      const completion = await client.chat.completions.create({
        model,
        temperature: 0.6,
        max_tokens: 220,
        messages: [
          {
            role: 'system',
            content:
              'Sen AYS Guard’sın — KampüsteyimAPP çalışma odası asistanısın. ' +
              'Kısa, motive edici, Türkçe cevap ver. Çalışma teknikleri, ' +
              'odak, Pomodoro ve sınav hazırlığı hakkında yardım et. ' +
              'Uygunsuz içerikte nazikçe sınır koy. En fazla 3 kısa cümle.',
          },
          {
            role: 'user',
            content: `${senderName}: ${message}`,
          },
        ],
      });
      reply =
        (completion.choices?.[0]?.message?.content || '').trim() || reply;
    } catch (e) {
      console.warn('[studyChatAi] openai', e?.message || e);
    }

    await roomRef.collection('messages').add({
      senderId: 'bot_ays_guard',
      senderName: 'AYS Guard',
      text: reply,
      createdAt: new Date().toISOString(),
      isAi: true,
    });
    await roomRef.collection('events').add({
      type: 'ai_reply',
      actorId: 'bot_ays_guard',
      at: new Date().toISOString(),
      forUid: uid,
    });

    return { ok: true, reply };
  },
);

/** 6 haneli sayısal silme kodu. */
function makeDeletionCode() {
  const n = crypto.randomInt(100000, 999999);
  return String(n);
}

function maskEmail(email) {
  const e = String(email || '');
  const at = e.indexOf('@');
  if (at < 2) return '***';
  return `${e.slice(0, 2)}***${e.slice(at)}`;
}

async function purgeUserAccount({
  uid,
  email,
  actorId,
  actorName,
  reason,
}) {
  const { getAuth } = require('firebase-admin/auth');
  const auth = getAuth();
  const userRef = db.collection('users').doc(uid);
  const snap = await userRef.get();
  const data = snap.exists ? snap.data() || {} : {};
  const username = String(data.username || '')
    .trim()
    .toLowerCase();

  if (username) {
    try {
      await db.collection('handles').doc(username).delete();
    } catch (_) {
      /* ignore */
    }
  }

  // Alt koleksiyonlar (bildirim vb.) — best effort
  for (const sub of ['notifications', 'cv', 'cv_exports']) {
    try {
      const subSnap = await userRef.collection(sub).limit(200).get();
      const batch = db.batch();
      subSnap.docs.forEach((d) => batch.delete(d.ref));
      if (!subSnap.empty) await batch.commit();
    } catch (_) {
      /* ignore */
    }
  }

  await userRef.set(
    {
      deleted: true,
      deletedAt: new Date().toISOString(),
      deletedBy: actorId,
      email: `deleted_${uid}@invalid.local`,
      firstName: 'Silinmiş',
      lastName: 'Hesap',
      fullName: 'Silinmiş hesap',
      phone: '',
      photoUrl: null,
      username: null,
      usernameStatus: 'deleted',
      fcmTokens: [],
      notificationPrefs: {},
    },
    { merge: true },
  );

  try {
    await auth.deleteUser(uid);
  } catch (e) {
    console.warn('[purgeUser] auth delete', e?.message || e);
  }

  await db.collection('account_deletion_logs').add({
    uid,
    email: String(email || data.email || '').toLowerCase(),
    username: username || null,
    actorId,
    actorName: actorName || null,
    reason: reason || 'self',
    at: new Date().toISOString(),
  });

  return { ok: true };
}

exports.requestAccountDeletion = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const uid = request.auth.uid;
    const { getAuth } = require('firebase-admin/auth');
    let email = '';
    try {
      const rec = await getAuth().getUser(uid);
      email = String(rec.email || '').toLowerCase();
    } catch (_) {
      throw new HttpsError('not-found', 'Kullanıcı bulunamadı');
    }
    if (!email.includes('@')) {
      throw new HttpsError('failed-precondition', 'E-posta yok');
    }

    // Eski kodları iptal
    const old = await db
      .collection('account_deletions')
      .where('uid', '==', uid)
      .limit(20)
      .get();
    const batch = db.batch();
    let n = 0;
    old.docs.forEach((d) => {
      if (d.data()?.used === true) return;
      batch.update(d.ref, { used: true, revokedAt: new Date().toISOString() });
      n += 1;
    });
    if (n > 0) await batch.commit();

    const code = makeDeletionCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
    await db.collection('account_deletions').doc(code).set({
      uid,
      email,
      used: false,
      createdAt: new Date().toISOString(),
      expiresAt: expiresAt.toISOString(),
    });

    const html = brandedEmail({
      title: 'Hesap silme kodu',
      greeting: 'Merhaba,',
      bodyHtml: `
        <p>KampüsteyimAPP hesabını silmek için doğrulama kodun:</p>
        <p style="font-size:28px;font-weight:800;letter-spacing:4px;color:#0B1F3A;text-align:center;margin:20px 0;">
          ${code}
        </p>
        <p>Kod <b>15 dakika</b> geçerlidir. Bu talebi sen oluşturmadıysan bu maili yok say.</p>
      `,
      footerNote: 'AYS Tech · Hesap güvenliği',
    });
    await sendMail({
      to: email,
      subject: 'KampüsteyimAPP · Hesap silme kodu',
      html,
    });

    return { ok: true, emailHint: `Kod ${maskEmail(email)} adresine gönderildi` };
  },
);

exports.confirmAccountDeletion = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const uid = request.auth.uid;
    const code = String(request.data?.code || '').trim();
    if (code.length < 4) {
      throw new HttpsError('invalid-argument', 'Kod gerekli');
    }

    const ref = db.collection('account_deletions').doc(code);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Kod geçersiz');
    }
    const d = snap.data() || {};
    if (d.used === true) {
      throw new HttpsError('failed-precondition', 'Kod kullanılmış');
    }
    if (d.uid !== uid) {
      throw new HttpsError('permission-denied', 'Kod bu hesaba ait değil');
    }
    if (d.expiresAt && new Date(d.expiresAt).getTime() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'Kodun süresi dolmuş');
    }

    await ref.set(
      { used: true, usedAt: new Date().toISOString() },
      { merge: true },
    );

    await purgeUserAccount({
      uid,
      email: d.email,
      actorId: uid,
      actorName: 'self',
      reason: 'self_email_code',
    });

    return { ok: true };
  },
);

exports.adminDeleteAccount = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const actorId = request.auth.uid;
    const targetUid = String(request.data?.uid || '').trim();
    const email = String(request.data?.email || '').trim().toLowerCase();
    if (!targetUid) {
      throw new HttpsError('invalid-argument', 'uid gerekli');
    }
    if (targetUid === actorId) {
      throw new HttpsError(
        'failed-precondition',
        'Kendi hesabını admin menüsünden silemezsin; profildeki silme akışını kullan.',
      );
    }

    const actorSnap = await db.collection('users').doc(actorId).get();
    const actor = actorSnap.data() || {};
    const isAdmin =
      actor.isSuperAdmin === true ||
      actor.role === 'admin' ||
      !!actor.staffRoleId;
    if (!isAdmin) {
      throw new HttpsError('permission-denied', 'Yetki yok');
    }

    const targetSnap = await db.collection('users').doc(targetUid).get();
    const target = targetSnap.data() || {};
    if (target.isSuperAdmin === true) {
      throw new HttpsError('permission-denied', 'Süper admin silinemez');
    }

    await purgeUserAccount({
      uid: targetUid,
      email: email || target.email,
      actorId,
      actorName: actor.fullName || actor.email || actorId,
      reason: 'admin',
    });

    return { ok: true };
  },
);

/**
 * Admin: firma / topluluk hesabı — Auth user + Firestore profil
 */
exports.adminCreateManagedAccount = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);

    const email = String(request.data?.email || '')
      .trim()
      .toLowerCase();
    const password = String(request.data?.password || '');
    const displayName = sanitizePlainText(request.data?.displayName || '', 80);
    const kind = String(request.data?.kind || 'company');
    const logoUrl = request.data?.logoUrl
      ? String(request.data.logoUrl).slice(0, 500)
      : null;

    if (!isValidEmail(email)) {
      throw new HttpsError('invalid-argument', 'Geçerli e-posta gerekli');
    }
    if (password.length < 6) {
      throw new HttpsError('invalid-argument', 'Şifre en az 6 karakter');
    }
    if (!displayName) {
      throw new HttpsError('invalid-argument', 'İsim gerekli');
    }
    if (kind !== 'company' && kind !== 'community') {
      throw new HttpsError('invalid-argument', 'kind company|community olmalı');
    }

    const { getAuth } = require('firebase-admin/auth');
    let userRecord;
    try {
      userRecord = await getAuth().createUser({
        email,
        password,
        displayName,
        emailVerified: false,
      });
    } catch (e) {
      if (e?.code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'Bu e-posta zaten kayıtlı');
      }
      throw new HttpsError('internal', e?.message || 'Auth oluşturulamadı');
    }

    const uid = userRecord.uid;
    const isCompany = kind === 'company';
    const usernameBase = displayName
      .toLowerCase()
      .replace(/[^a-z0-9]+/gi, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 18);
    const username = `${usernameBase || kind}_${uid.slice(0, 6)}`.toLowerCase();

    const profile = {
      email,
      firstName: displayName,
      lastName: isCompany ? '' : 'Topluluğu',
      fullName: isCompany ? displayName : `${displayName} Topluluğu`,
      role: isCompany ? 'company' : 'community',
      isCommunity: !isCompany,
      hasGoldBadge: !isCompany,
      hasBlueBadge: false,
      isSuperAdmin: false,
      stableId: uid,
      username,
      usernameStatus: 'ok',
      city: 'Gaziantep',
      university: isCompany ? '—' : 'Gaziantep Üniversitesi',
      bio: isCompany
        ? 'Firma hesabı · admin tarafından açıldı'
        : `${displayName} resmi topluluk hesabı`,
      communityLogoUrl: isCompany ? null : logoUrl || 'assets/logos/mt_circle.png',
      createdAt: new Date().toISOString(),
      createdByAdmin: request.auth.uid,
      managedAccount: true,
    };

    await db.collection('users').doc(uid).set(profile, { merge: true });
    try {
      await db.collection('handles').doc(username).set({
        authUid: uid,
        userId: uid,
        username,
        createdAt: new Date().toISOString(),
      });
    } catch (_) {}

    try {
      await sendMail({
        to: email,
        subject: isCompany
          ? 'KampüsteyimAPP · Firma hesabın hazır'
          : 'KampüsteyimAPP · Topluluk hesabın hazır',
        html: brandedEmail({
          title: isCompany ? 'Firma hesabın hazır' : 'Topluluk hesabın hazır',
          greeting: `Merhaba ${escapeHtml(displayName)},`,
          bodyHtml: `<p>KampüsteyimAPP ${
            isCompany ? 'firma' : 'topluluk'
          } hesabın açıldı.</p>
            <p><b>E-posta:</b> ${escapeHtml(email)}<br/>
            <b>Geçici şifre:</b> ${escapeHtml(password)}</p>
            <p>İlk girişten sonra şifreni değiştirmeni öneririz.</p>`,
          ctaLabel: 'KampüsteyimAPP’e git',
          ctaUrl: BRAND_HOME,
          footerNote: 'Bu hesap admin tarafından oluşturuldu.',
        }),
      });
    } catch (e) {
      console.warn('[adminCreateManagedAccount] mail', e?.message || e);
    }

    return { ok: true, uid, stableId: uid, username, kind };
  },
);

/**
 * Yeni öğrenci kaydı → admin’lere mail + inbox
 */
exports.notifyRegistrationPending = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const {
      uid,
      email,
      firstName,
      lastName,
      studentNo,
      university,
      studentIdDocUrl,
      studentIdFrontUrl,
      studentIdBackUrl,
      studentVerificationType,
    } = request.data || {};
    if (!uid || !email) {
      throw new HttpsError('invalid-argument', 'uid ve email zorunlu');
    }

    const typeLabel =
      studentVerificationType === 'card'
        ? 'Öğrenci kartı (ön/arka)'
        : studentVerificationType === 'document'
          ? 'Öğrenci belgesi (PDF)'
          : 'Belge';

    const links = [];
    if (studentIdFrontUrl) {
      links.push(
        `<p><a href="${escapeHtml(String(studentIdFrontUrl))}">Ön yüz</a></p>`,
      );
    }
    if (studentIdBackUrl) {
      links.push(
        `<p><a href="${escapeHtml(String(studentIdBackUrl))}">Arka yüz</a></p>`,
      );
    }
    if (studentIdDocUrl) {
      links.push(
        `<p><a href="${escapeHtml(String(studentIdDocUrl))}">PDF / belge</a></p>`,
      );
    }

    const admins = await db.collection('users').limit(400).get();
    let mailed = 0;
    for (const doc of admins.docs) {
      const u = doc.data() || {};
      const isAdmin =
        u.isSuperAdmin === true ||
        u.role === 'admin' ||
        (u.staffRoleId && String(u.staffRoleId).length > 0);
      if (!isAdmin) continue;
      const to = String(u.email || '').trim();
      if (!to.includes('@') || to.includes('@invalid.local')) continue;
      try {
        await sendMail({
          to,
          subject: 'KampüsteyimAPP · Yeni öğrenci kaydı onayı',
          html: brandedEmail({
            title: 'Yeni kayıt onayı',
            greeting: 'Merhaba,',
            bodyHtml: `<p><b>${escapeHtml(firstName || '')} ${escapeHtml(
              lastName || '',
            )}</b> (${escapeHtml(studentNo || '')}) kayıt oldu.</p>
              <p>Üniversite: ${escapeHtml(university || '')}<br/>
              E-posta: ${escapeHtml(email)}<br/>
              Doğrulama: ${escapeHtml(typeLabel)}</p>
              <p>Kart / belge bilgileri form ile eşleşmeli; admin panelinden incele.</p>
              ${links.join('')}`,
            ctaLabel: 'Admin paneli',
            ctaUrl: BRAND_HOME + '/admin',
            footerNote: 'Bu otomatik bir bilgilendirme mailidir.',
          }),
        });
        mailed += 1;
      } catch (e) {
        console.warn('[notifyRegistrationPending]', e?.message || e);
      }
      try {
        await db.collection('users').doc(doc.id).collection('notifications').add({
          title: 'Yeni kayıt onayı',
          body: `${firstName || ''} ${lastName || ''} · ${studentNo || ''}`,
          emoji: '🧾',
          type: 'admin_broadcast',
          actorId: uid,
          targetId: uid,
          read: false,
          createdAt: new Date().toISOString(),
        });
      } catch (_) {}
    }
    return { ok: true, mailed };
  },
);

/**
 * Admin: öğrenci kaydını onayla / reddet → kullanıcıya mail + push
 */
exports.reviewStudentRegistration = onCall(
  { region: 'europe-west1', timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const { userId, approve, reason } = request.data || {};
    if (!userId) throw new HttpsError('invalid-argument', 'userId zorunlu');
    const status = approve === true ? 'approved' : 'rejected';

    let userDoc = await db.collection('users').doc(String(userId)).get();
    if (!userDoc.exists) {
      const q = await db
        .collection('users')
        .where('stableId', '==', String(userId))
        .limit(1)
        .get();
      if (q.empty) throw new HttpsError('not-found', 'Kullanıcı yok');
      userDoc = q.docs[0];
    }
    const u = userDoc.data() || {};
    await userDoc.ref.set(
      {
        accountStatus: status,
        registrationReviewedAt: new Date().toISOString(),
        registrationReviewedBy: request.auth.uid,
        registrationRejectReason: status === 'rejected' ? String(reason || '') : null,
      },
      { merge: true },
    );

    const title =
      status === 'approved' ? 'Hesabın onaylandı' : 'Kayıt başvurun reddedildi';
    const body =
      status === 'approved'
        ? 'Öğrenci belgen doğrulandı. KampüsteyimAPP’e hoş geldin!'
        : `Başvurun reddedildi.${reason ? ` Sebep: ${reason}` : ''}`;

    await db.collection('users').doc(userDoc.id).collection('notifications').add({
      title,
      body,
      emoji: status === 'approved' ? '✅' : '❌',
      type: 'admin_broadcast',
      read: false,
      createdAt: new Date().toISOString(),
    });

    const tokens = u.fcmTokens || [];
    if (tokens.length) {
      try {
        await sendFcmToUser(
          userDoc.id,
          tokens,
          buildCampusPushPayload({
            title: `KampüsteyimAPP · ${title}`,
            body,
            type: 'admin_broadcast',
            data: { toUserId: userDoc.id },
          }),
        );
      } catch (_) {}
    }

    const email = String(u.email || '').trim();
    if (email.includes('@') && !email.includes('@invalid.local')) {
      try {
        await sendMail({
          to: email,
          subject: `KampüsteyimAPP · ${title}`,
          html: brandedEmail({
            title,
            greeting: `Merhaba ${escapeHtml(u.firstName || '')},`,
            bodyHtml: `<p>${escapeHtml(body)}</p>`,
            ctaLabel: 'KampüsteyimAPP’e git',
            ctaUrl: BRAND_HOME,
            footerNote: 'Bu otomatik bir bilgilendirme mailidir.',
          }),
        });
      } catch (e) {
        console.warn('[reviewStudentRegistration] mail', e?.message || e);
      }
    }

    return { ok: true, status };
  },
);

