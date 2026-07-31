const { onCall, HttpsError, onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, FieldPath } = require('firebase-admin/firestore');
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
    host: secrets.smtp_host || 'smtp.kampusteyim.app',
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
  'https://ayskampuss.web.app/kampusteyim_icon.png';
/** Uygulama (SPA) — e-posta CTA ve derin linkler */
const BRAND_HOME = 'https://app.kampusteyim.app';
/** Tanıtım sitesi */
const BRAND_MARKETING = 'https://kampusteyim.app';
const BRAND_LABEL = 'KampüsteyimAPP';

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
              <img src="${BRAND_LOGO}" alt="KampüsteyimAPP" width="64" height="64" style="display:inline-block;border-radius:16px;background:#ffffff;padding:4px;"/>
              <p style="margin:14px 0 0;color:#ffffff;font-size:20px;font-weight:800;letter-spacing:0.2px;">KampüsteyimAPP</p>
              <p style="margin:4px 0 0;color:#A8C5E2;font-size:13px;">AYS Tech · Kampüs sosyal ağı</p>
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
              <p style="margin:0 0 14px;font-size:12px;color:#94A3B8;line-height:1.5;text-align:center;">
                Bu mail KampüsteyimAPP platformundan gönderildi.<br/>
                AYS Tech · Kayra Çatalkaya
              </p>
              <p style="margin:0;text-align:center;">
                <a href="${BRAND_HOME}" style="display:inline-block;background:#0EA5E9;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:10px;font-weight:700;font-size:13px;">
                  ${BRAND_LABEL}’i aç
                </a>
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
    case 'follow_request':
    case 'follow_accepted':
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

/** Plus CV tema kartelası (client `kCvThemePalette` ile senkron). */
const CV_ACCENT_DEFAULT = 0xff3db8a8;
const CV_ACCENT_PALETTE = new Set([
  0xff3db8a8, // Teal
  0xff0f766e, // Koyu teal
  0xff047857, // Zümrüt
  0xff166534, // Orman yeşili
  0xff1e3a5f, // Kurumsal lacivert
  0xff1d4ed8, // Klasik mavi
  0xff2563eb, // Royal blue
  0xff0e7490, // Çelik cyan
  0xff334155, // Slate
  0xff475569, // Çelik gri
  0xff1f2937, // Antrasit
  0xff0f172a, // Midnight
  0xff3730a3, // İndigo
  0xff5b21b6, // Mor
  0xff7f1d1d, // Bordo
  0xff9f1239, // Şarap
  0xffb45309, // Bakır
  0xff92400e, // Kahve
]);

function normalizeCvAccentArgb(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  let v = Math.trunc(n);
  if (v < 0) v = v >>> 0;
  // RGB only → opaque ARGB
  if (v >= 0 && v <= 0xffffff) {
    v = (0xff000000 + v) >>> 0;
  } else {
    v = v >>> 0;
  }
  return v;
}

/**
 * Plus + cvTheme açıksa whitelist’ten accent; değilse varsayılan teal.
 */
function resolveCvAccentArgb({ requested, isPlus, features }) {
  const themeOk = isPlus && (features?.cvTheme !== false);
  if (!themeOk) return CV_ACCENT_DEFAULT;
  const argb = normalizeCvAccentArgb(requested);
  if (argb == null || !CV_ACCENT_PALETTE.has(argb)) {
    return CV_ACCENT_DEFAULT;
  }
  return argb;
}

/**
 * Callable: generateAtsCv
 * data: { cvData, languageCode, languageName, userEmail, userName, studentNo, accentArgb? }
 */
exports.generateAtsCv = onCall({ region: 'europe-west1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Giriş gerekli');
  }

  const uid = request.auth.uid;

  let isPlus = false;
  let plusFeatures = {};

  // CV-AI kota: KampüsteyimPlus free/plus limitleri (app_config/kampusteyim_plus)
  // Geriye dönük: cv_ai_limits.perUserDailyLimit hâlâ okunur (admin eski sekme).
  try {
    const [plusSnap, limSnap, userSnap] = await Promise.all([
      db.collection('app_config').doc('kampusteyim_plus').get(),
      db.collection('app_config').doc('cv_ai_limits').get(),
      db.collection('users').doc(uid).get(),
    ]);
    const plusCfg = plusSnap.exists ? plusSnap.data() || {} : {};
    const lim = limSnap.exists ? limSnap.data() || {} : {};
    const u = userSnap.exists ? userSnap.data() || {} : {};
    const exp = u.plusExpiresAt ? new Date(u.plusExpiresAt) : null;
    isPlus =
      u.plusActive === true && (!exp || exp.getTime() > Date.now());
    plusFeatures = plusCfg.features || {};

    let perUser = null;
    const freeLim = (plusCfg.rateLimitsFree || {}).cvAiDaily;
    const plusLim = (plusCfg.rateLimitsPlus || {}).cvAiDaily;
    if (isPlus && typeof plusLim === 'number') {
      perUser = plusLim;
    } else if (!isPlus && typeof freeLim === 'number') {
      perUser = freeLim;
    } else if (typeof lim.perUserDailyLimit === 'number') {
      perUser = lim.perUserDailyLimit;
    }

    const enabled = lim.enabled !== false;
    if (enabled && perUser != null && perUser >= 0 && Number.isFinite(perUser)) {
      if (perUser === 0) {
        // 0 = sınırsız
      } else {
        const day = new Date().toISOString().slice(0, 10);
        const usageRef = db
          .collection('users')
          .doc(uid)
          .collection('cv_ai_usage')
          .doc(day);
        const usage = await usageRef.get();
        const count = (usage.data() || {}).count || 0;
        if (count >= perUser) {
          throw new HttpsError(
            'resource-exhausted',
            isPlus
              ? `Günlük CV-AI Plus limitine ulaştın (${perUser}).`
              : `Günlük CV-AI limitine ulaştın (${perUser}). Plus ile daha fazla hak.`,
          );
        }
        await usageRef.set(
          {
            count: count + 1,
            updatedAt: new Date().toISOString(),
            limit: perUser,
            plus: isPlus,
          },
          { merge: true },
        );
      }
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.warn('[generateAtsCv] quota check', e?.message || e);
  }

  const {
    cvData,
    languageCode = 'tr',
    languageName = 'Turkish',
    userEmail,
    userName,
    studentNo,
    accentArgb: requestedAccent,
  } = request.data || {};

  if (!cvData) {
    throw new HttpsError('invalid-argument', 'cvData zorunlu');
  }

  const accentArgb = resolveCvAccentArgb({
    requested: requestedAccent,
    isPlus,
    features: plusFeatures,
  });

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
    accentArgb,
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
      last_accent_argb: accentArgb,
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
    accentArgb,
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
/**
 * `set(..., { merge: true })` noktalı anahtarları alan yolu olarak değil,
 * düz alan adı olarak yazar (yalnızca `update()` yol olarak yorumlar).
 * Bu yardımcı noktalı anahtarları iç içe map'e çevirir.
 */
function expandFieldPaths(patch) {
  const out = {};
  for (const [key, value] of Object.entries(patch || {})) {
    if (!key.includes('.')) {
      out[key] = value;
      continue;
    }
    const parts = key.split('.');
    let node = out;
    for (let i = 0; i < parts.length - 1; i += 1) {
      const part = parts[i];
      const next = node[part];
      if (typeof next !== 'object' || next === null || Array.isArray(next)) {
        node[part] = {};
      }
      node = node[part];
    }
    node[parts[parts.length - 1]] = value;
  }
  return out;
}

async function findUserDocByAnyId(userId) {
  const id = String(userId || '').trim();
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

  const handle = id.replace(/^@/, '').toLowerCase();
  if (handle) {
    try {
      const byUsername = await db
        .collection('users')
        .where('username', '==', handle)
        .limit(1)
        .get();
      if (!byUsername.empty) return byUsername.docs[0];
    } catch (_) {}

    try {
      const h = await db.collection('handles').doc(handle).get();
      if (h.exists) {
        const data = h.data() || {};
        const authUid = String(data.authUid || '').trim();
        const linkedId = String(data.userId || '').trim();
        if (authUid) {
          doc = await db.collection('users').doc(authUid).get();
          if (doc.exists) return doc;
        }
        if (linkedId) {
          doc = await db.collection('users').doc(linkedId).get();
          if (doc.exists) return doc;
          const byLinkedStable = await db
            .collection('users')
            .where('stableId', '==', linkedId)
            .limit(1)
            .get();
          if (!byLinkedStable.empty) return byLinkedStable.docs[0];
        }
      }
    } catch (_) {}
  }

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

    // members / campus — tüm kullanıcılar (sayfalı); uygulama kapalı olsa bile FCM gider.
    const pageSize = 400;
    let targeted = 0;
    let delivered = 0;
    let mailed = 0;
    let lastDoc = null;
    // Max ~20 sayfa = 8000 kullanıcı
    for (let page = 0; page < 20; page += 1) {
      let q = db.collection('users').orderBy(FieldPath.documentId()).limit(pageSize);
      if (lastDoc) q = q.startAfter(lastDoc);
      const snap = await q.get();
      if (snap.empty) break;
      lastDoc = snap.docs[snap.docs.length - 1];

      const batch = [];
      for (const doc of snap.docs) {
        const u = doc.data() || {};
        const role = String(u.role || 'student');
        if (role === 'company' || role === 'admin' || role === 'community') continue;
        if (u.isCommunity === true) continue;
        if (u.deleted === true) continue;
        if (doc.id === actorId || u.stableId === actorId) continue;
        if (audience === 'members') {
          if (String(u.affiliatedCommunityId || '') !== String(actorId)) continue;
        }
        batch.push(doc);
      }

      // Paralel gönder (8’li) — timeout’a takılmadan.
      for (let i = 0; i < batch.length; i += 8) {
        const chunk = batch.slice(i, i + 8);
        const results = await Promise.all(
          chunk.map((doc) =>
            deliverToUserDoc({
              doc,
              title: pushTitle,
              body: pushBody,
              emoji,
              type: notifType,
              actorId,
              targetId: targetId || null,
              sendEmail: !!sendEmail,
              emailSubject: `KampüsteyimAPP · ${actorName}`,
            }),
          ),
        );
        for (const r of results) {
          if (!r.skipped) targeted += 1;
          delivered += r.delivered || 0;
          mailed += r.mailed || 0;
        }
      }
      if (snap.size < pageSize) break;
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
 * Yerel Guard — yalnızca bariz küfür / ırkçılık / cinsiyetçilik.
 * Cümle içine gömülü harf kombinasyonları engellenmez; şüphe AI’da admin’e gider.
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

function compactLetters(text) {
  return String(text || '')
    .replace(/[^a-z]/g, '')
    .replace(/(.)\1{2,}/g, '$1$1');
}

/** Masum kelimeleri boşlukla sil — kısa kök false positive’ini azaltır. */
function maskInnocentWords(text) {
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
  let t = text;
  for (const s of safe) {
    if (t.includes(s)) t = t.split(s).join(' ');
  }
  return t;
}

function asWholeWord(text, stem) {
  const esc = stem.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`(?:^|[^a-z])${esc}(?:[^a-z]|$)`, 'i').test(text);
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
      'Gönderin bariz küfür / nefret / cinsiyetçi içerik içerdiği için AYS Tech Guard tarafından engellendi.',
  };
}

function localSafetyScan(rawText) {
  const scrubbed = String(rawText || '').replace(/@[\wğüşıöçĞÜŞİÖÇ0-9_]+/gi, ' ');
  const text = maskInnocentWords(normalizeForSafety(scrubbed));
  const compact = compactLetters(text);

  const clearStems = [
    'zenci',
    'nigger',
    'nigga',
    'heilhitler',
    'killall',
    'deathto',
    'faggot',
    'kike',
    'chink',
    'siktir',
    'sikerim',
    'sikeyim',
    'sikis',
    'sikiyon',
    'siktig',
    'amcik',
    'amina',
    'amini',
    'orospu',
    'orosbucocugu',
    'yarrak',
    'yarrag',
    'gotunu',
    'gotune',
    'serefsiz',
    'kahpe',
    'porno',
    'onlyfans',
    'fuckyou',
    'motherfucker',
  ];
  for (const stem of clearStems) {
    const s = stem.replace(/ğ/g, 'g');
    if (asWholeWord(text, s) || text.includes(s)) {
      const hate = /zenci|nigger|nigga|heil|killall|deathto|faggot|kike|chink/.test(s);
      return blockHit(
        [hate ? 'hate' : 'nsfw'],
        hate
          ? 'Nefret / ayrımcı içerik (yerel Guard).'
          : 'Küfür / uygunsuz içerik (yerel Guard).',
      );
    }
  }

  // Kısa kökler — YALNIZCA kelime sınırı (gömülü / ayrık harf YOK)
  for (const stem of ['sik', 'amk', 'pic']) {
    if (asWholeWord(text, stem)) {
      return blockHit(['nsfw'], 'Küfür (yerel Guard).');
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
      return blockHit(['hate'], 'Nefret / şiddet (yerel Guard).');
    }
  }

  return { hit: false };
}

/** Guard şüphesi → admin şikayet kuyruğu (ceza / silme YOK). */
async function createGuardAdminReport({
  postId,
  authorId,
  content,
  summary,
  labels,
  confidence,
}) {
  if (!postId) return null;
  const id = `r_guard_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  await db.collection('reports').doc(id).set({
    targetType: 'post',
    targetId: String(postId),
    targetOwnerId: authorId ? String(authorId) : null,
    reporterId: 'ays_guard',
    reporterName: 'AYS Tech Guard',
    reporterEmail: '',
    reason: 'AYS Tech Guard şüphesi — admin incelemesi',
    details: String(summary || '').slice(0, 2000),
    createdAt: new Date().toISOString(),
    status: 'open',
    snapshotTitle: 'Guard otomatik şikayet',
    snapshotBody: String(content || '').slice(0, 4000),
    snapshotAuthor: authorId ? String(authorId) : '',
    snapshotUrl: '',
    aiDecision: 'needs_admin',
    aiSummary: String(summary || '').slice(0, 2000),
    aiConfidence: Number(confidence) || 0,
    aiActed: false,
    aiAdminNote: 'Bot şüpheli buldu; engellemedi. İnsan admin kararı bekleniyor.',
    aiLabels: Array.isArray(labels) ? labels.map(String) : ['other'],
    fromGuard: true,
  });
  await db.collection('moderation_actions').add({
    userId: authorId || null,
    postId: String(postId),
    type: 'flag_admin',
    decision: 'flag',
    action: 'none',
    confidence: Number(confidence) || 0,
    summary: String(summary || ''),
    labels: Array.isArray(labels) ? labels.map(String) : [],
    actorId: 'ays_guard',
    auto: true,
    reportId: id,
    createdAt: new Date().toISOString(),
  });
  return id;
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
  fileNames,
}) {
  const text = String(content || '');
  const files = Array.isArray(fileNames)
    ? fileNames.map((f) => String(f || '').trim()).filter(Boolean).slice(0, 20)
    : [];
  const urls = [
    ...(String(text).match(/https?:\/\/[^\s<>\]]+/gi) || []),
    ...(String(text).match(/www\.[^\s<>\]]+/gi) || []),
    ...(Array.isArray(mediaUrls) ? mediaUrls.map(String) : []),
  ];

  const safeHost = (u) => {
    try {
      const h = new URL(u.startsWith('http') ? u : `https://${u}`).hostname;
      return (
        h.includes('kampusteyim.app') ||
        h.includes('ayskampuss.web.app') ||
        h.includes('ayskampuss.firebaseapp.com') ||
        h.includes('gaunengineering.com.tr') ||
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
  const riskyFiles = files.filter((n) =>
    /\.(exe|bat|cmd|scr|js|vbs|msi|apk|dmg)$/i.test(n),
  );

  // 1) Yerel kural — OpenAI kotası olmasa da çalışır
  const local = localSafetyScan(`${text}\n${files.join(' ')}`);
  let ai = {
    decision: 'allow',
    action: 'none',
    confidence: 0.5,
    summary: '',
    labels: [],
    message: '',
  };

  if (riskyFiles.length > 0) {
    ai = {
      decision: 'block',
      action: 'postBan',
      confidence: 0.99,
      summary: 'Tehlikeli dosya uzantısı',
      labels: ['malware'],
      message: 'Bu dosya türü kampüste paylaşılamaz.',
    };
  } else if (local.hit) {
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
              'You are AYS Tech Guard for KampüsteyimAPP (Turkish campus). Return ONLY JSON: {"decision":"allow"|"flag"|"block","action":"none"|"postBan","confidence":0-1,"summary":"Turkish short reason","labels":["safe"|"spam"|"phishing"|"malware"|"nsfw"|"hate"|"sexism"|"harassment"|"scam"|"other"],"message":"Turkish user-facing message"}. POLICY: (1) BLOCK only CLEAR, unambiguous swearing / racism / sexism / explicit NSFW / malware (confidence>=0.9, action postBan). (2) Do NOT block words hidden inside other words or gibberish mid-string (e.g. psikoloji, mühendislik, asdsadasikasa). Do NOT invent swears from letter fragments. (3) If suspicious but not clearly a swear/hate/sexism: decision=flag (admin report only) — NEVER block or punish the user. (4) Doubt → flag, not block. (5) Innocent campus talk, mentions, jokes without clear slurs → allow. Official links ok: ayskampuss, aystech, gantep.edu.tr.',
            },
            {
              role: 'user',
              content: JSON.stringify({
                content: text.slice(0, 4000),
                textPreview: maskInnocentWords(normalizeForSafety(text)).slice(0, 800),
                urls: urls.slice(0, 20),
                riskyUrls: riskyUrls.slice(0, 20),
                fileNames: files.slice(0, 20),
                authorId,
                postId,
                policy: 'clear_swear_hate_sexism_only_else_flag_admin',
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
          decision: 'flag',
          action: 'none',
          confidence: 0.7,
          summary: 'Birden fazla harici bağlantı — admin incelemesi (AI kota/hata).',
          labels: ['other'],
          message: '',
        };
      }
    }
  }

  // riskyFiles zaten block set ettiyse AI üzerine yazmasın
  if (riskyFiles.length > 0) {
    ai = {
      decision: 'block',
      action: 'postBan',
      confidence: 0.99,
      summary: 'Tehlikeli dosya uzantısı',
      labels: ['malware'],
      message: 'Bu dosya türü kampüste paylaşılamaz.',
    };
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

  // Yalnızca bariz küfür/nefret/cinsiyetçilik → block. Şüphe → admin report.
  const blocked = decision === 'block' && confidence >= 0.9;
  const flagAdmin =
    !blocked &&
    (decision === 'flag' ||
      decision === 'warn' ||
      (decision === 'block' && confidence < 0.9)) &&
    confidence >= 0.55;

  let appliedType = 'none';
  if (flagAdmin) {
    try {
      await createGuardAdminReport({
        postId,
        authorId: authorId || uid,
        content: text,
        summary: summary || message || 'Şüpheli içerik',
        labels: Array.isArray(ai.labels) ? ai.labels : ['other'],
        confidence,
      });
      appliedType = 'flag_admin';
    } catch (e) {
      console.error('createGuardAdminReport', e?.message || e);
    }
  } else if (blocked || (action !== 'none' && decision === 'block' && confidence >= 0.9)) {
    const user = await findUserDoc();
    const type =
      action === 'mute' ? 'mute' : action === 'warn' ? 'warn' : 'postBan';
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
    warning: null,
    flagged: flagAdmin,
    action: appliedType,
    decision: flagAdmin ? 'flag' : decision,
    confidence,
    message: blocked
      ? message ||
        'Gönderin AYS Tech Guard tarafından engellendi (bariz küfür/nefret/cinsiyetçilik).'
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
    const { postId, authorId, content, mediaUrls, fileNames } = request.data || {};
    const result = await runGuardPostReview({
      postId,
      authorId,
      authUid: request.auth.uid,
      content,
      mediaUrls,
      fileNames,
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
    const fileNames = Array.isArray(data.media)
      ? data.media
          .filter((m) => m && (m.type === 'file' || m.fileName))
          .map((m) => String(m.fileName || m.url || ''))
          .filter(Boolean)
      : [];

    console.log('[guardOnPostCreated]', postId, data.authorId);
    const result = await runGuardPostReview({
      postId,
      authorId: data.authorId || data.author_id,
      authUid: data.authUid || null,
      content: data.content || '',
      mediaUrls: media,
      fileNames,
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

const MT_LOGO = 'https://ayskampuss.web.app/mt-logo.png';
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
          <a href="${BRAND_HOME}" style="display:inline-block;background:#0EA5E9;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:10px;font-weight:700;font-size:13px;">
            KampüsteyimAPP’i aç
          </a>
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

/**
 * Cloud Functions için sunucu tarafı RBAC kontrolü.
 * Süper admin ve staffRoleId taşımayan eski admin hesapları geriye uyumlu
 * olarak tam yetkilidir; personel hesapları staff_roles kataloğundan doğrulanır.
 */
async function assertAdminPermission(uid, permission) {
  const admin = await assertPlatformAdmin(uid);
  if (admin.isSuperAdmin === true) return admin;
  const roleId = String(admin.staffRoleId || '').trim();
  if (!roleId && admin.role === 'admin') return admin;
  if (!roleId) {
    throw new HttpsError('permission-denied', 'Bu işlem için yetkin yok');
  }
  const roleSnap = await db.collection('staff_roles').doc(roleId).get();
  const role = roleSnap.data() || {};
  const permissions = Array.isArray(role.permissions) ? role.permissions : [];
  if (role.isSuper === true || permissions.includes(String(permission))) {
    return admin;
  }
  throw new HttpsError('permission-denied', 'Bu işlem için yetkin yok');
}

/**
 * E-posta ile Auth veya Firestore’da herhangi bir hesap var mı?
 * (öğrenci / firma / topluluk — tür fark etmez)
 */
async function findAccountByEmail(emailRaw) {
  const email = String(emailRaw || '').trim().toLowerCase();
  if (!isValidEmail(email)) return null;
  const { getAuth } = require('firebase-admin/auth');
  try {
    const rec = await getAuth().getUserByEmail(email);
    return {
      source: 'auth',
      uid: rec.uid,
      email,
    };
  } catch (e) {
    if (e?.code !== 'auth/user-not-found') {
      console.warn('[findAccountByEmail] auth', e?.code || e?.message || e);
    }
  }
  // Firestore: email alanı (küçük harf)
  const q = await db
    .collection('users')
    .where('email', '==', email)
    .limit(5)
    .get();
  if (!q.empty) {
    const doc = q.docs[0];
    const d = doc.data() || {};
    return {
      source: 'firestore',
      uid: doc.id,
      email,
      role: d.role || '',
      isCommunity: d.isCommunity === true,
    };
  }
  return null;
}

/**
 * Belge doğrulaması kapalıysa pending öğrenci hesaplarını onayla.
 */
async function approvePendingWhenVerificationDisabled() {
  const cfgSnap = await db
    .collection('app_config')
    .doc('registration_security')
    .get();
  const cfg = cfgSnap.exists ? cfgSnap.data() || {} : {};
  if (cfg.requireStudentVerification !== false) {
    return { skipped: true, reason: 'verification_required', approved: 0 };
  }

  const snap = await db
    .collection('users')
    .where('accountStatus', '==', 'pending')
    .limit(400)
    .get();

  let approved = 0;
  const batchSize = 400;
  let batch = db.batch();
  let n = 0;
  const now = new Date().toISOString();

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (d.isCommunity === true || d.role === 'company' || d.role === 'community') {
      continue;
    }
    if (d.isSuperAdmin === true || d.role === 'admin') continue;
    batch.set(
      doc.ref,
      {
        accountStatus: 'approved',
        registrationAutoApprovedAt: now,
        registrationAutoApproveReason: 'verification_disabled',
        updatedAt: now,
      },
      { merge: true },
    );
    approved += 1;
    n += 1;
    if (n >= batchSize) {
      await batch.commit();
      batch = db.batch();
      n = 0;
    }
  }
  if (n > 0) await batch.commit();
  return { skipped: false, approved };
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

function emailDocId(email) {
  return crypto.createHash('sha256').update(String(email).trim().toLowerCase()).digest('hex');
}

/**
 * Kayıt öncesi e-posta OTP — auth gerekmez.
 * data: { email }
 */
exports.sendRegistrationEmailCode = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    const email = String(request.data?.email || '').trim().toLowerCase();
    if (!isValidEmail(email)) {
      throw new HttpsError('invalid-argument', 'Geçerli e-posta gir');
    }

    const { getAuth } = require('firebase-admin/auth');
    try {
      await getAuth().getUserByEmail(email);
      throw new HttpsError(
        'already-exists',
        'Bu e-posta zaten kayıtlı. Giriş yap veya şifre sıfırla.',
      );
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      // user-not-found → devam
    }

    const id = emailDocId(email);
    const ref = db.collection('registration_email_otps').doc(id);
    const prev = await ref.get();
    const prevData = prev.exists ? prev.data() || {} : {};
    const lastSent = prevData.lastSentAt ? new Date(prevData.lastSentAt).getTime() : 0;
    if (lastSent && Date.now() - lastSent < 55 * 1000) {
      throw new HttpsError(
        'resource-exhausted',
        'Yeni kod için yaklaşık 1 dakika bekle.',
      );
    }
    const hourAgo = Date.now() - 60 * 60 * 1000;
    const sentHour = Array.isArray(prevData.sentLog)
      ? prevData.sentLog.filter((t) => new Date(t).getTime() > hourAgo)
      : [];
    if (sentHour.length >= 8) {
      throw new HttpsError(
        'resource-exhausted',
        'Bu e-posta için saatlik kod limitine ulaşıldı.',
      );
    }

    const code = makeDeletionCode();
    const codeHash = crypto.createHash('sha256').update(code).digest('hex');
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
    const sentLog = [...sentHour, new Date().toISOString()];
    await ref.set(
      {
        email,
        codeHash,
        attempts: 0,
        verified: false,
        ticket: null,
        expiresAt: expiresAt.toISOString(),
        lastSentAt: new Date().toISOString(),
        sentLog,
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );

    const html = brandedEmail({
      title: 'E-posta doğrulama kodu',
      greeting: 'Merhaba,',
      bodyHtml: `
        <p>KampüsteyimAPP kaydını tamamlamak için doğrulama kodun:</p>
        <p style="font-size:28px;font-weight:800;letter-spacing:6px;color:#0B1F3A;text-align:center;margin:20px 0;">
          ${code}
        </p>
        <p>Kod <b>15 dakika</b> geçerlidir. Bu talebi sen oluşturmadıysan maili yok say.</p>
      `,
      footerNote: 'AYS Tech · Kayıt güvenliği',
    });
    await sendMail({
      to: email,
      subject: 'KampüsteyimAPP · E-posta doğrulama kodu',
      html,
    });

    return {
      ok: true,
      emailHint: `Kod ${maskEmail(email)} adresine gönderildi`,
      expiresInSec: 15 * 60,
    };
  },
);

/**
 * Kayıt OTP doğrula → kısa ömürlü ticket.
 * data: { email, code }
 */
exports.verifyRegistrationEmailCode = onCall(
  { region: 'europe-west1', timeoutSeconds: 20 },
  async (request) => {
    const email = String(request.data?.email || '').trim().toLowerCase();
    const code = String(request.data?.code || '').trim();
    if (!isValidEmail(email) || !/^\d{6}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'E-posta ve 6 haneli kod gerekli');
    }

    const id = emailDocId(email);
    const ref = db.collection('registration_email_otps').doc(id);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Önce doğrulama kodu iste');
    }
    const d = snap.data() || {};
    if (d.expiresAt && new Date(d.expiresAt).getTime() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'Kodun süresi dolmuş. Yeni kod iste.');
    }
    const attempts = Number(d.attempts || 0);
    if (attempts >= 8) {
      throw new HttpsError('resource-exhausted', 'Çok fazla deneme. Yeni kod iste.');
    }

    const codeHash = crypto.createHash('sha256').update(code).digest('hex');
    if (codeHash !== d.codeHash) {
      await ref.set({ attempts: attempts + 1 }, { merge: true });
      throw new HttpsError('permission-denied', 'Kod hatalı');
    }

    const ticket = crypto.randomBytes(24).toString('hex');
    const ticketExpires = new Date(Date.now() + 30 * 60 * 1000);
    await ref.set(
      {
        verified: true,
        ticket,
        ticketExpiresAt: ticketExpires.toISOString(),
        codeHash: null,
        attempts: 0,
        verifiedAt: new Date().toISOString(),
      },
      { merge: true },
    );

    return {
      ok: true,
      ticket,
      email,
      expiresInSec: 30 * 60,
    };
  },
);

/**
 * Kayıt sonrası ticket tüket + Auth emailVerified.
 * data: { ticket }
 */
exports.consumeRegistrationEmailTicket = onCall(
  { region: 'europe-west1', timeoutSeconds: 20 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Giriş gerekli');
    }
    const uid = request.auth.uid;
    const ticket = String(request.data?.ticket || '').trim();
    if (ticket.length < 20) {
      throw new HttpsError('invalid-argument', 'Doğrulama bileti gerekli');
    }

    const { getAuth } = require('firebase-admin/auth');
    const authUser = await getAuth().getUser(uid);
    const email = String(authUser.email || '').trim().toLowerCase();
    if (!email) {
      throw new HttpsError('failed-precondition', 'Hesap e-postası yok');
    }

    const id = emailDocId(email);
    const ref = db.collection('registration_email_otps').doc(id);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'E-posta doğrulaması bulunamadı');
    }
    const d = snap.data() || {};
    if (d.ticket !== ticket || d.verified !== true) {
      throw new HttpsError('permission-denied', 'Doğrulama bileti geçersiz');
    }
    if (d.ticketExpiresAt && new Date(d.ticketExpiresAt).getTime() < Date.now()) {
      throw new HttpsError('deadline-exceeded', 'Doğrulama süresi dolmuş');
    }
    if (d.consumed === true) {
      throw new HttpsError('failed-precondition', 'Doğrulama zaten kullanılmış');
    }
    if (String(d.email || '').toLowerCase() !== email) {
      throw new HttpsError('permission-denied', 'E-posta eşleşmiyor');
    }

    await getAuth().updateUser(uid, { emailVerified: true });
    await ref.set(
      {
        consumed: true,
        consumedAt: new Date().toISOString(),
        consumedBy: uid,
        ticket: null,
      },
      { merge: true },
    );
    await db.collection('users').doc(uid).set(
      {
        emailVerified: true,
        emailVerifiedAt: new Date().toISOString(),
      },
      { merge: true },
    );

    return { ok: true };
  },
);

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

    // Aynı e-posta ile öğrenci / firma / topluluk — ikinci hesap yok
    const existing = await findAccountByEmail(email);
    if (existing) {
      throw new HttpsError(
        'already-exists',
        'Bu e-posta ile zaten bir hesap var. Aynı e-posta ile ikinci hesap açılamaz.',
      );
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
        throw new HttpsError(
          'already-exists',
          'Bu e-posta ile zaten bir hesap var. Aynı e-posta ile ikinci hesap açılamaz.',
        );
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
      accountStatus: 'approved',
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
      type: 'registration_review',
      read: false,
      createdAt: new Date().toISOString(),
    });

    // Token’ları taze oku (onay anında dizi boş/eski olabilir)
    let tokens = [];
    try {
      const fresh = await userDoc.ref.get();
      tokens = (fresh.data() || {}).fcmTokens || u.fcmTokens || [];
    } catch (_) {
      tokens = u.fcmTokens || [];
    }
    let push = { successCount: 0, failureCount: 0 };
    try {
      push = await sendFcmToUser(
        userDoc.id,
        tokens,
        buildCampusPushPayload({
          title: `KampüsteyimAPP · ${title}`,
          body,
          type: 'registration_review',
          data: {
            toUserId: userDoc.id,
            status,
            route: status === 'approved' ? '/home' : '/pending-approval',
          },
        }),
      );
    } catch (e) {
      console.warn('[reviewStudentRegistration] push', e?.message || e);
    }
    if (!tokens.length) {
      console.warn(
        '[reviewStudentRegistration] no FCM tokens for',
        userDoc.id,
        '— inbox yazıldı, cihaz token kaydı yok',
      );
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

    return { ok: true, status, push };
  },
);

/**
 * Host odadan çıktıktan 1 saat sonra açık odaları otomatik kapatır.
 * hostLeftAt alanı client'ta markHostLeft ile yazılır.
 */
exports.studyRoomHostTimeout = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: 'europe-west1',
    timeoutSeconds: 120,
  },
  async () => {
    const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    // Tek alan sorgusu — composite index gerekmez.
    const snap = await db
      .collection('study_rooms')
      .where('hostLeftAt', '<=', cutoff)
      .limit(100)
      .get();

    if (snap.empty) {
      console.log('[studyRoomHostTimeout] none');
      return null;
    }

    let closed = 0;
    for (const doc of snap.docs) {
      const d = doc.data() || {};
      const status = String(d.status || '');
      if (status === 'ended' || !d.hostLeftAt) continue;
      const leftMs = new Date(d.hostLeftAt).getTime();
      if (Number.isNaN(leftMs) || Date.now() - leftMs < 60 * 60 * 1000) continue;

      const nowIso = new Date().toISOString();
      await doc.ref.set(
        {
          status: 'ended',
          endedAt: nowIso,
          chatOpen: false,
          endReason: 'host_left_timeout',
          hostLeftAt: FieldValue.delete(),
        },
        { merge: true },
      );
      await doc.ref.collection('events').add({
        type: 'ended',
        actorId: 'system',
        reason: 'host_left_timeout',
        at: nowIso,
      });
      closed += 1;
    }
    console.log('[studyRoomHostTimeout] closed', closed);
    return null;
  },
);

/**
 * Landing formları: topluluk / şirket hesabı / reklam başvuruları.
 * Public POST → Firestore lead_applications + admin mail.
 */
exports.submitLeadApplication = onRequest(
  {
    region: 'europe-west1',
    cors: true,
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ ok: false, error: 'POST gerekli' });
      return;
    }

    try {
      const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
      const type = String(body.type || '').trim(); // community | company | advertising | support
      const allowed = new Set(['community', 'company', 'advertising', 'support']);
      if (!allowed.has(type)) {
        res.status(400).json({ ok: false, error: 'Geçersiz başvuru tipi' });
        return;
      }

      const name = sanitizePlainText(body.name || body.contactName || '', 80);
      const email = String(body.email || '').trim().toLowerCase();
      const phone = sanitizePlainText(body.phone || '', 40);
      const orgName = sanitizePlainText(body.orgName || body.companyName || body.communityName || '', 120);
      const city = sanitizePlainText(body.city || '', 60);
      const university = sanitizePlainText(body.university || '', 160);
      const message = sanitizePlainText(body.message || '', 2000);
      const website = sanitizePlainText(body.website || '', 200);
      const interest = sanitizePlainText(body.interest || '', 80); // company: account|ads|both

      if (!name || name.length < 2) {
        res.status(400).json({ ok: false, error: 'Ad soyad gerekli' });
        return;
      }
      if (!isValidEmail(email)) {
        res.status(400).json({ ok: false, error: 'Geçerli e-posta gerekli' });
        return;
      }
      if (type === 'support' && !phone) {
        res.status(400).json({ ok: false, error: 'Destek için telefon gerekli' });
        return;
      }
      if (type === 'community' && (!city || !university || !orgName)) {
        res.status(400).json({
          ok: false,
          error: 'Topluluk için il, üniversite ve topluluk adı gerekli',
        });
        return;
      }
      if (
        (type === 'company' || type === 'advertising') &&
        !orgName &&
        type !== 'support'
      ) {
        res.status(400).json({ ok: false, error: 'Şirket / marka adı gerekli' });
        return;
      }

      const recent = await db
        .collection('lead_applications')
        .where('email', '==', email)
        .limit(5)
        .get();
      const recentCount = recent.docs.filter((d) => {
        const t = new Date(d.data()?.createdAt || 0).getTime();
        return Date.now() - t < 10 * 60 * 1000;
      }).length;
      if (recentCount >= 2) {
        res.status(429).json({
          ok: false,
          error: 'Çok fazla deneme. Birkaç dakika sonra tekrar dene.',
        });
        return;
      }

      const nowIso = new Date().toISOString();
      const doc = {
        type,
        status: 'open',
        name,
        email,
        phone,
        orgName,
        city,
        university,
        website,
        interest,
        message,
        source: 'landing',
        userAgent: String(req.get('user-agent') || '').slice(0, 240),
        createdAt: nowIso,
        updatedAt: nowIso,
      };
      const ref = await db.collection('lead_applications').add(doc);

      const typeLabel =
        type === 'community'
          ? 'Topluluk başvurusu'
          : type === 'advertising'
            ? 'Reklam / iş ortaklığı'
            : type === 'support'
              ? 'Destek talebi'
              : 'Şirket hesabı / reklam';

      try {
        const admins = await db.collection('users').limit(400).get();
        const adminEmails = [];
        for (const d of admins.docs) {
          const u = d.data() || {};
          if (u.isSuperAdmin === true || u.role === 'admin') {
            const e = String(u.email || '').trim();
            if (e.includes('@') && !e.includes('@invalid.local')) adminEmails.push(e);
          }
        }
        const unique = [...new Set(adminEmails)].slice(0, 12);
        await Promise.all(
          unique.map((to) =>
            sendMail({
              to,
              subject: `KampüsteyimAPP · Yeni ${typeLabel}`,
              html: brandedEmail({
                title: typeLabel,
                greeting: 'Merhaba,',
                bodyHtml: `
                  <p><b>${escapeHtml(orgName || name)}</b> landing üzerinden başvuru bıraktı.</p>
                  <ul>
                    <li>İletişim: ${escapeHtml(name)} · ${escapeHtml(email)}${phone ? ` · ${escapeHtml(phone)}` : ''}</li>
                    ${city ? `<li>İl: ${escapeHtml(city)}</li>` : ''}
                    ${university ? `<li>Üniversite: ${escapeHtml(university)}</li>` : ''}
                    ${interest ? `<li>İstek: ${escapeHtml(interest)}</li>` : ''}
                    ${website ? `<li>Web: ${escapeHtml(website)}</li>` : ''}
                    ${message ? `<li>Mesaj: ${escapeHtml(message)}</li>` : ''}
                  </ul>
                `,
                ctaLabel: 'Admin paneli',
                ctaUrl: `${BRAND_HOME}/admin`,
              }),
            }).catch(() => {}),
          ),
        );
      } catch (e) {
        console.warn('[submitLeadApplication] admin mail', e?.message || e);
      }

      res.status(200).json({ ok: true, id: ref.id });
    } catch (e) {
      console.error('[submitLeadApplication]', e);
      res.status(500).json({ ok: false, error: 'Başvuru kaydedilemedi' });
    }
  },
);

const PROMO_DOC = 'app_config/promo';
const PROMO_STATS = 'app_config/promo_stats';
const DEFAULT_QR_LANDING = `${BRAND_MARKETING}/get.html`;
const DEFAULT_APP_STORE_URL = 'https://apps.apple.com/tr/app/id6793663176';
const DOWNLOAD_SECTION_URL = `${BRAND_MARKETING}/#indir`;

function isAppStoreLink(url) {
  return /^https?:\/\/(?:[a-z0-9-]+\.)*(?:apps\.apple\.com|itunes\.apple\.com)\//i.test(
    String(url || '').trim(),
  );
}

function isPlayStoreLink(url) {
  const u = String(url || '').trim();
  return /^https?:\/\/play\.google\.com\//i.test(u) || /^market:\/\//i.test(u);
}

/// QR/badge yönlendirmesi asla mağaza dışı bir siteye düşmesin diye
/// admin linkleri mağaza formatına göre doğrulanır.
function resolveStoreUrls(cfg) {
  return {
    ios: isAppStoreLink(cfg.appStoreUrl) ? cfg.appStoreUrl : DEFAULT_APP_STORE_URL,
    android: isPlayStoreLink(cfg.playStoreUrl) ? cfg.playStoreUrl : '',
  };
}

function resolveRedirectUrl(platform, cfg) {
  const store = resolveStoreUrls(cfg);
  if (platform === 'ios') return store.ios;
  if (platform === 'android') return store.android || DOWNLOAD_SECTION_URL;
  return DOWNLOAD_SECTION_URL;
}

async function readPromoConfig() {
  const snap = await db.doc(PROMO_DOC).get();
  const d = snap.exists ? snap.data() || {} : {};
  return {
    playStoreUrl: String(d.playStoreUrl || '').trim(),
    appStoreUrl: String(d.appStoreUrl || '').trim(),
    qrTargetUrl: String(d.qrTargetUrl || DEFAULT_QR_LANDING).trim() || DEFAULT_QR_LANDING,
    updatedAt: d.updatedAt || null,
  };
}

/** Public: landing indir butonları + QR hedefi */
exports.getPromoPublic = onRequest(
  { region: 'europe-west1', cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    try {
      const cfg = await readPromoConfig();
      const statsSnap = await db.doc(PROMO_STATS).get();
      const s = statsSnap.exists ? statsSnap.data() || {} : {};
      const store = resolveStoreUrls(cfg);
      res.set('Cache-Control', 'public, max-age=60, s-maxage=300');
      res.status(200).json({
        ok: true,
        ...cfg,
        iosUrl: store.ios,
        androidUrl: store.android,
        androidReady: Boolean(store.android),
        downloadSectionUrl: DOWNLOAD_SECTION_URL,
        stats: {
          total: Number(s.total || 0),
          ios: Number(s.ios || 0),
          android: Number(s.android || 0),
          other: Number(s.other || 0),
        },
      });
    } catch (e) {
      console.error('[getPromoPublic]', e);
      res.status(500).json({ ok: false, error: 'Okunamadı' });
    }
  },
);

/** QR /get sayfası: tarama logla + platform yönlendir */
exports.trackPromoScan = onRequest(
  { region: 'europe-west1', cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST' && req.method !== 'GET') {
      res.status(405).json({ ok: false, error: 'GET/POST' });
      return;
    }
    try {
      const body =
        req.method === 'GET'
          ? req.query || {}
          : typeof req.body === 'string'
            ? JSON.parse(req.body || '{}')
            : req.body || {};
      let platform = String(body.platform || '').toLowerCase();
      const ua = String(req.get('user-agent') || body.ua || '');
      if (!platform) {
        if (/iphone|ipad|ipod|macintosh.*mobile/i.test(ua)) platform = 'ios';
        else if (/android/i.test(ua)) platform = 'android';
        else platform = 'other';
      }
      if (!['ios', 'android', 'other'].includes(platform)) platform = 'other';

      const cfg = await readPromoConfig();
      const nowIso = new Date().toISOString();
      await db.collection('promo_scans').add({
        platform,
        ua: ua.slice(0, 240),
        source: String(body.source || 'qr').slice(0, 40),
        createdAt: nowIso,
      });
      const inc = {
        total: FieldValue.increment(1),
        [platform]: FieldValue.increment(1),
        updatedAt: nowIso,
      };
      await db.doc(PROMO_STATS).set(inc, { merge: true });

      const store = resolveStoreUrls(cfg);
      const redirectUrl = resolveRedirectUrl(platform, cfg);

      if (req.method === 'GET' && String(body.redirect || '1') !== '0') {
        res.set('Cache-Control', 'no-store');
        res.redirect(302, redirectUrl);
        return;
      }
      res.status(200).json({
        ok: true,
        platform,
        redirectUrl,
        iosUrl: store.ios,
        androidUrl: store.android,
        androidReady: Boolean(store.android),
        downloadSectionUrl: DOWNLOAD_SECTION_URL,
        playStoreUrl: cfg.playStoreUrl,
        appStoreUrl: cfg.appStoreUrl,
      });
    } catch (e) {
      console.error('[trackPromoScan]', e);
      res.status(500).json({ ok: false, error: 'Kayıt başarısız' });
    }
  },
);

/** Admin: Play / App Store linklerini kaydet */
exports.updatePromoConfig = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const playStoreUrl = sanitizePlainText(request.data?.playStoreUrl || '', 400);
    const appStoreUrl = sanitizePlainText(request.data?.appStoreUrl || '', 400);
    const qrTargetUrl = sanitizePlainText(
      request.data?.qrTargetUrl || DEFAULT_QR_LANDING,
      400,
    );
    const nowIso = new Date().toISOString();
    await db.doc(PROMO_DOC).set(
      {
        playStoreUrl,
        appStoreUrl,
        qrTargetUrl: qrTargetUrl || DEFAULT_QR_LANDING,
        updatedAt: nowIso,
        updatedBy: request.auth.uid,
      },
      { merge: true },
    );
    return { ok: true, playStoreUrl, appStoreUrl, qrTargetUrl: qrTargetUrl || DEFAULT_QR_LANDING };
  },
);

/** KampüsteyimPlus — ücretsiz deneme (bir kez). */
exports.startPlusTrial = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const userRef = db.collection('users').doc(uid);
    const [userSnap, cfgSnap] = await Promise.all([
      userRef.get(),
      db.collection('app_config').doc('kampusteyim_plus').get(),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'Kullanıcı bulunamadı');
    }
    const u = userSnap.data() || {};
    if (u.plusTrialUsed === true) {
      throw new HttpsError(
        'failed-precondition',
        'Ücretsiz denemeyi zaten kullandın.',
      );
    }
    const exp = u.plusExpiresAt ? new Date(u.plusExpiresAt) : null;
    if (u.plusActive === true && (!exp || exp.getTime() > Date.now())) {
      return { ok: true, message: 'Plus zaten aktif', already: true };
    }
    const cfg = cfgSnap.exists ? cfgSnap.data() || {} : {};
    let trialDays = typeof cfg.trialDays === 'number' ? cfg.trialDays : 60;
    if (!Number.isFinite(trialDays) || trialDays < 1) trialDays = 60;
    if (trialDays > 365) trialDays = 365;
    const startsAt = new Date();
    const expiresAt = new Date(startsAt.getTime() + trialDays * 86400000);
    await userRef.set(
      {
        plusActive: true,
        plusSource: 'trial',
        plusStartsAt: startsAt.toISOString(),
        plusExpiresAt: expiresAt.toISOString(),
        plusTrialUsed: true,
        updatedAt: startsAt.toISOString(),
      },
      { merge: true },
    );
    return {
      ok: true,
      trialDays,
      plusExpiresAt: expiresAt.toISOString(),
    };
  },
);

/** Admin: Plus ver / kaldır */
exports.adminSetPlus = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const userId = String(request.data?.userId || '').trim();
    const action = String(request.data?.action || '').trim();
    if (!userId) throw new HttpsError('invalid-argument', 'userId zorunlu');
    let userDoc = await findUserDocByAnyId(userId);
    if (!userDoc && userId.includes('@')) {
      const q = await db
        .collection('users')
        .where('email', '==', userId.toLowerCase())
        .limit(1)
        .get();
      if (!q.empty) userDoc = q.docs[0];
    }
    if (!userDoc || !userDoc.exists) throw new HttpsError('not-found', 'Kullanıcı yok');
    const userRef = userDoc.ref;

    if (action === 'revoke') {
      await userRef.set(
        {
          plusActive: false,
          plusSource: '',
          plusExpiresAt: FieldValue.delete(),
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return { ok: true, action: 'revoke' };
    }

    if (action === 'grant') {
      let days = Number(request.data?.days);
      if (!Number.isFinite(days) || days < 1) days = 60;
      if (days > 730) days = 730;
      const startsAt = new Date();
      const expiresAt = new Date(startsAt.getTime() + days * 86400000);
      await userRef.set(
        {
          plusActive: true,
          plusSource: 'admin',
          plusStartsAt: startsAt.toISOString(),
          plusExpiresAt: expiresAt.toISOString(),
          updatedAt: startsAt.toISOString(),
        },
        { merge: true },
      );
      return { ok: true, action: 'grant', days, plusExpiresAt: expiresAt.toISOString() };
    }

    throw new HttpsError('invalid-argument', 'action: grant | revoke');
  },
);

/**
 * Belge doğrulaması kapanınca pending’leri otomatik onayla.
 */
exports.onRegistrationSecurityWritten = onDocumentWritten(
  {
    document: 'app_config/registration_security',
    region: 'europe-west1',
  },
  async (event) => {
    const after = event.data?.after?.data() || {};
    const before = event.data?.before?.data() || {};
    // Yalnızca zorunluluk true→false (veya false iken kaydet) iken flush
    if (after.requireStudentVerification === false) {
      const res = await approvePendingWhenVerificationDisabled();
      console.log('[onRegistrationSecurityWritten]', res);
      return res;
    }
    if (
      before.requireStudentVerification === false &&
      after.requireStudentVerification === true
    ) {
      return { skipped: true, reason: 'verification_reenabled' };
    }
    return null;
  },
);

/** Admin: pending flush (belge kapalıysa) */
exports.adminSyncRegistrationGate = onCall(
  { region: 'europe-west1', timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    return approvePendingWhenVerificationDisabled();
  },
);

/**
 * Admin: badge / kurum ilişkisi — yalnızca ilgili alanlar (diğer profil alanlarına dokunmaz).
 * action:
 *  - community_on | community_off
 *  - link_org (orgId, grantBlue?, grantGold?)
 *  - unlink_org
 *  - set_flags (hasGoldBadge?, hasBlueBadge?)
 */
exports.adminSetUserBadges = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);

    const userId = String(request.data?.userId || '').trim();
    const action = String(request.data?.action || '').trim();
    if (!userId) throw new HttpsError('invalid-argument', 'userId zorunlu');
    if (!action) throw new HttpsError('invalid-argument', 'action zorunlu');

    const userDoc = await findUserDocByAnyId(userId);
    if (!userDoc) throw new HttpsError('not-found', 'Kullanıcı yok');
    const userRef = userDoc.ref;
    const u = userDoc.data() || {};
    if (u.isSuperAdmin === true && action === 'community_on') {
      throw new HttpsError(
        'failed-precondition',
        'Süper admin topluluk hesabına çevrilemez',
      );
    }

    const now = new Date().toISOString();
    let patch = { updatedAt: now, badgesUpdatedAt: now };

    if (action === 'community_on') {
      const logoUrl = request.data?.logoUrl
        ? String(request.data.logoUrl).slice(0, 500)
        : u.communityLogoUrl || 'assets/logos/ays_circle.png';
      patch = {
        ...patch,
        isCommunity: true,
        role: 'community',
        hasGoldBadge: true,
        hasBlueBadge: false,
        communityLogoUrl: logoUrl,
        affiliatedCommunityId: FieldValue.delete(),
        affiliatedCommunityName: FieldValue.delete(),
        affiliatedOrgLogoUrl: FieldValue.delete(),
        staffRoleId: FieldValue.delete(),
        isSuperAdmin: false,
        accountStatus: 'approved',
      };
    } else if (action === 'community_off') {
      patch = {
        ...patch,
        isCommunity: false,
        role: 'student',
        hasGoldBadge: false,
        communityLogoUrl: FieldValue.delete(),
      };
    } else if (action === 'link_org') {
      const orgId = String(request.data?.orgId || '').trim();
      if (!orgId) throw new HttpsError('invalid-argument', 'orgId zorunlu');
      const orgDoc = await findUserDocByAnyId(orgId);
      if (!orgDoc) throw new HttpsError('not-found', 'Kurum yok');
      if (orgDoc.id === userDoc.id) {
        throw new HttpsError(
          'failed-precondition',
          'Kullanıcı kendi kurumuna bağlanamaz',
        );
      }
      const org = orgDoc.data() || {};
      const isOrg =
        org.isCommunity === true ||
        org.role === 'company' ||
        org.role === 'community' ||
        org.hasGoldBadge === true;
      if (!isOrg) {
        throw new HttpsError('failed-precondition', 'Hedef bir kurum hesabı değil');
      }
      const grantBlue = request.data?.grantBlueBadge === true;
      const grantGold = request.data?.grantGoldBadge === true;
      const logo = org.communityLogoUrl || org.photoUrl || null;
      const orgName =
        String(org.fullName || '').trim() ||
        `${String(org.firstName || '').trim()} ${String(org.lastName || '').trim()}`.trim() ||
        String(org.firstName || '').trim() ||
        'Kurum';
      const resolvedOrgId = orgDoc.id;
      patch = {
        ...patch,
        affiliatedCommunityId: resolvedOrgId,
        affiliatedCommunityName: orgName,
        affiliatedOrgLogoUrl: logo,
      };
      if (grantBlue) patch.hasBlueBadge = true;
      if (grantGold) patch.hasGoldBadge = true;
    } else if (action === 'unlink_org') {
      patch = {
        ...patch,
        hasBlueBadge: false,
        affiliatedCommunityId: FieldValue.delete(),
        affiliatedCommunityName: FieldValue.delete(),
        affiliatedOrgLogoUrl: FieldValue.delete(),
      };
    } else if (action === 'set_flags') {
      if (typeof request.data?.hasGoldBadge === 'boolean') {
        patch.hasGoldBadge = request.data.hasGoldBadge;
      }
      if (typeof request.data?.hasBlueBadge === 'boolean') {
        patch.hasBlueBadge = request.data.hasBlueBadge;
      }
    } else {
      throw new HttpsError(
        'invalid-argument',
        'action: community_on|community_off|link_org|unlink_org|set_flags',
      );
    }

    await userRef.set(patch, { merge: true });
    const after = (await userRef.get()).data() || {};
    return {
      ok: true,
      action,
      userId: userDoc.id,
      hasGoldBadge: after.hasGoldBadge === true,
      hasBlueBadge: after.hasBlueBadge === true,
      isCommunity: after.isCommunity === true,
      affiliatedCommunityId: after.affiliatedCommunityId || null,
      affiliatedCommunityName: after.affiliatedCommunityName || null,
      affiliatedOrgLogoUrl: after.affiliatedOrgLogoUrl || null,
    };
  },
);

/**
 * Admin: rol / yetki bayrakları — doğru Firestore dokümanına yazar.
 * action: organizer | staff_role | revoke_staff | panel_access
 */
exports.adminSetUserRoleFlags = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');

    const userId = String(request.data?.userId || '').trim();
    const action = String(request.data?.action || '').trim();
    if (!userId) throw new HttpsError('invalid-argument', 'userId zorunlu');
    if (!action) throw new HttpsError('invalid-argument', 'action zorunlu');

    const staffActions = new Set(['staff_role', 'revoke_staff']);
    await assertAdminPermission(
      request.auth.uid,
      staffActions.has(action) ? 'manage_admins' : 'manage_users',
    );

    const userDoc = await findUserDocByAnyId(userId);
    if (!userDoc) throw new HttpsError('not-found', 'Kullanıcı yok');
    const userRef = userDoc.ref;
    const u = userDoc.data() || {};

    const now = new Date().toISOString();
    const patch = { updatedAt: now, roleUpdatedAt: now, roleUpdatedBy: request.auth.uid };

    if (action === 'organizer') {
      patch.isEventOrganizer = request.data?.value === true;
    } else if (action === 'panel_access') {
      patch.panelAccess = request.data?.value === true;
    } else if (action === 'staff_role') {
      const roleId = String(request.data?.roleId || '').trim();
      if (!roleId) throw new HttpsError('invalid-argument', 'roleId zorunlu');
      const roleSnap = await db.collection('staff_roles').doc(roleId).get();
      if (!roleSnap.exists) throw new HttpsError('not-found', 'Rol yok');
      const role = roleSnap.data() || {};
      if (u.isSuperAdmin === true && role.isSuper !== true) {
        throw new HttpsError('failed-precondition', 'Süper admin rolü düşürülemez');
      }
      patch.role = 'admin';
      patch.staffRoleId = roleId;
      patch.isSuperAdmin = role.isSuper === true;
    } else if (action === 'revoke_staff') {
      if (u.isSuperAdmin === true) {
        throw new HttpsError('failed-precondition', 'Süper admin kaldırılamaz');
      }
      patch.role = u.isCommunity === true ? 'community' : 'student';
      patch.staffRoleId = FieldValue.delete();
      patch.isSuperAdmin = false;
    } else {
      throw new HttpsError(
        'invalid-argument',
        'action: organizer|panel_access|staff_role|revoke_staff',
      );
    }

    await userRef.set(patch, { merge: true });
    const after = (await userRef.get()).data() || {};
    return {
      ok: true,
      action,
      userId: userDoc.id,
      role: after.role || '',
      staffRoleId: after.staffRoleId || null,
      isSuperAdmin: after.isSuperAdmin === true,
      isEventOrganizer: after.isEventOrganizer === true,
      panelAccess: after.panelAccess === true,
    };
  },
);

/**
 * Admin: kullanıcı kısıtlaması — doğru Firestore dokümanına yazar.
 * type: none | warn | mute | postBan | fullBan
 */
exports.adminSetUserRestriction = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);

    const userId = String(request.data?.userId || '').trim();
    const type = String(request.data?.type || 'none').trim();
    const reason = sanitizePlainText(request.data?.reason || '', 500);
    const untilRaw = request.data?.until;
    if (!userId) throw new HttpsError('invalid-argument', 'userId zorunlu');

    const allowed = new Set(['none', 'warn', 'mute', 'postBan', 'fullBan']);
    if (!allowed.has(type)) {
      throw new HttpsError(
        'invalid-argument',
        'type: none|warn|mute|postBan|fullBan',
      );
    }

    const userDoc = await findUserDocByAnyId(userId);
    if (!userDoc) throw new HttpsError('not-found', 'Kullanıcı yok');

    const now = new Date().toISOString();
    const patch = {
      restrictionType: type,
      restrictionReason: type === 'none' ? '' : reason,
      updatedAt: now,
      restrictionUpdatedBy: request.auth.uid,
      restrictionUpdatedAt: now,
    };

    if (type === 'none') {
      patch.restrictionUntil = FieldValue.delete();
      patch.restrictionClearedBy = request.auth.uid;
      patch.restrictionClearedAt = now;
    } else {
      patch.restrictionClearedBy = FieldValue.delete();
      patch.restrictionClearedAt = FieldValue.delete();
      if (untilRaw) {
        const until = new Date(String(untilRaw));
        if (!Number.isNaN(until.getTime())) {
          patch.restrictionUntil = until.toISOString();
        } else {
          patch.restrictionUntil = FieldValue.delete();
        }
      } else {
        patch.restrictionUntil = FieldValue.delete();
      }
    }

    await userDoc.ref.set(patch, { merge: true });
    const after = (await userDoc.ref.get()).data() || {};

    return {
      ok: true,
      userId: userDoc.id,
      restrictionType: after.restrictionType || 'none',
      restrictionReason: after.restrictionReason || '',
      restrictionUntil: after.restrictionUntil || null,
    };
  },
);

// ─── Stories / Reels feed hızlandırma ───────────────────────────────

const STORY_ARRAY_CAP = 120;
const REEL_ARRAY_CAP = 120;

function capStringArray(arr, max = STORY_ARRAY_CAP) {
  if (!Array.isArray(arr)) return null;
  if (arr.length <= max) return null;
  return arr.slice(-max).map(String);
}

function leanStoryPayload(id, s) {
  const data = s || {};
  return {
    id,
    authorId: String(data.authorId || ''),
    authorName: String(data.authorName || ''),
    authorHandle: String(data.authorHandle || ''),
    mediaUrl: String(data.mediaUrl || ''),
    mediaType: String(data.mediaType || 'image'),
    createdAt: String(data.createdAt || ''),
    expiresAt: String(data.expiresAt || ''),
    likedBy: Array.isArray(data.likedBy)
      ? data.likedBy.slice(-80).map(String)
      : [],
    viewedBy: Array.isArray(data.viewedBy)
      ? data.viewedBy.slice(-80).map(String)
      : [],
    hiddenFrom: Array.isArray(data.hiddenFrom)
      ? data.hiddenFrom.map(String)
      : [],
    archived: data.archived === true,
    deletedAt: data.deletedAt || null,
    reportCount: Number(data.reportCount || 0),
  };
}

function leanReelPayload(id, r) {
  const data = r || {};
  return {
    id,
    authorId: String(data.authorId || ''),
    authorName: String(data.authorName || ''),
    authorHandle: String(data.authorHandle || ''),
    authorPhotoUrl: data.authorPhotoUrl || null,
    mediaUrl: String(data.mediaUrl || ''),
    mediaType: String(data.mediaType || 'video'),
    caption: String(data.caption || ''),
    hashtags: Array.isArray(data.hashtags) ? data.hashtags.map(String) : [],
    mentionedUserIds: Array.isArray(data.mentionedUserIds)
      ? data.mentionedUserIds.map(String)
      : [],
    createdAt: String(data.createdAt || ''),
    likedBy: Array.isArray(data.likedBy)
      ? data.likedBy.slice(-80).map(String)
      : [],
    viewedBy: Array.isArray(data.viewedBy)
      ? data.viewedBy.slice(-80).map(String)
      : [],
    commentCount: Number(data.commentCount || 0),
    reportCount: Number(data.reportCount || 0),
    sourcePostId: data.sourcePostId || null,
    authorVerified: data.authorVerified === true,
    deletedAt: data.deletedAt || null,
  };
}

function buildVisibleAuthorSet(uid, userDoc, followingIds) {
  const visible = new Set([String(uid)]);
  if (userDoc) {
    visible.add(String(userDoc.id));
    const d = userDoc.data() || {};
    if (d.stableId) visible.add(String(d.stableId));
  }
  for (const f of followingIds || []) {
    if (f) visible.add(String(f));
  }
  return visible;
}

async function batchDeleteDocs(docs) {
  if (!docs.length) return 0;
  let deleted = 0;
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    const slice = docs.slice(i, i + 400);
    for (const doc of slice) batch.delete(doc.ref);
    await batch.commit();
    deleted += slice.length;
  }
  return deleted;
}

/** Hikâye / reel doc boyutunu küçült (viewedBy/likedBy şişmesin). */
async function trimFeedArrays(ref, data, caps = {}) {
  const maxView = caps.view || STORY_ARRAY_CAP;
  const maxLike = caps.like || STORY_ARRAY_CAP;
  const patch = {};
  const viewed = capStringArray(data.viewedBy, maxView);
  const liked = capStringArray(data.likedBy, maxLike);
  if (viewed) patch.viewedBy = viewed;
  if (liked) patch.likedBy = liked;
  if (Object.keys(patch).length === 0) return false;
  await ref.set(patch, { merge: true });
  return true;
}

exports.onStoryWrittenTrim = onDocumentWritten(
  { document: 'stories/{storyId}', region: 'europe-west1' },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data() || {};
    await trimFeedArrays(after.ref, data);
  },
);

exports.onReelWrittenTrim = onDocumentWritten(
  { document: 'reels/{reelId}', region: 'europe-west1' },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data() || {};
    await trimFeedArrays(after.ref, data);
  },
);

/** Süresi dolmuş hikâyeleri sil — limit(200) sorgusunda taze içerik kalsın. */
exports.purgeExpiredStories = onSchedule(
  { schedule: 'every 30 minutes', region: 'europe-west1', timeoutSeconds: 120 },
  async () => {
    const now = new Date().toISOString();
    const snap = await db
      .collection('stories')
      .where('expiresAt', '<', now)
      .limit(450)
      .get();
    const toDelete = snap.docs.filter((d) => {
      const s = d.data() || {};
      if (s.archived === true) return false;
      return true;
    });
    const n = await batchDeleteDocs(toDelete);
    if (n > 0) console.log('[purgeExpiredStories]', n);
  },
);

/** Soft-delete reels’leri kalıcı sil. */
exports.purgeDeletedReels = onSchedule(
  { schedule: 'every 6 hours', region: 'europe-west1', timeoutSeconds: 120 },
  async () => {
    const cutoff = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();
    const snap = await db
      .collection('reels')
      .where('deletedAt', '<', cutoff)
      .limit(450)
      .get();
    const n = await batchDeleteDocs(snap.docs);
    if (n > 0) console.log('[purgeDeletedReels]', n);
  },
);

/** Callable: takip edilen + kendi hikâyeleri (hafif payload). */
exports.getStoriesFeed = onCall(
  { region: 'europe-west1', timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const userDoc = await findUserDocByAnyId(uid);
    const followingIds = Array.isArray(request.data?.followingIds)
      ? request.data.followingIds.map(String)
      : [];
    const limitN = Math.min(Math.max(Number(request.data?.limit) || 200, 20), 250);
    const visibleAuthors = buildVisibleAuthorSet(uid, userDoc, followingIds);
    const now = new Date().toISOString();

    const snap = await db
      .collection('stories')
      .orderBy('createdAt', 'desc')
      .limit(limitN)
      .get();

    const items = [];
    for (const doc of snap.docs) {
      const s = doc.data() || {};
      if (s.deletedAt) continue;
      if (s.archived !== true && s.expiresAt && String(s.expiresAt) < now) continue;
      const authorId = String(s.authorId || '');
      if (!visibleAuthors.has(authorId)) continue;
      if (Array.isArray(s.hiddenFrom) && s.hiddenFrom.map(String).includes(uid)) {
        continue;
      }
      items.push(leanStoryPayload(doc.id, s));
    }

    return { ok: true, items, fetchedAt: now, count: items.length };
  },
);

/** Callable: reels feed — gizli hesap filtresi + hafif payload. */
exports.getReelsFeed = onCall(
  { region: 'europe-west1', timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const userDoc = await findUserDocByAnyId(uid);
    const followingIds = Array.isArray(request.data?.followingIds)
      ? request.data.followingIds.map(String)
      : [];
    const limitN = Math.min(Math.max(Number(request.data?.limit) || 120, 20), 180);
    const visibleAuthors = buildVisibleAuthorSet(uid, userDoc, followingIds);
    const authorCache = new Map();

    async function canSeeAuthor(authorId) {
      const aid = String(authorId || '');
      if (!aid) return false;
      if (visibleAuthors.has(aid) || aid === uid) return true;
      let cached = authorCache.get(aid);
      if (!cached) {
        const doc = await findUserDocByAnyId(aid);
        cached = doc?.data() || {};
        authorCache.set(aid, cached);
      }
      if (cached.isPrivateAccount !== true) return true;
      const stable = String(cached.stableId || '');
      return visibleAuthors.has(stable) || visibleAuthors.has(aid);
    }

    const snap = await db
      .collection('reels')
      .orderBy('createdAt', 'desc')
      .limit(limitN)
      .get();

    const items = [];
    for (const doc of snap.docs) {
      const r = doc.data() || {};
      if (r.deletedAt) continue;
      if (!(await canSeeAuthor(r.authorId))) continue;
      items.push(leanReelPayload(doc.id, r));
    }

    return { ok: true, items, fetchedAt: new Date().toISOString(), count: items.length };
  },
);

/** Admin/manuel: feed temizliğini hemen çalıştır. */
exports.syncFeedCaches = onCall(
  { region: 'europe-west1', timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const now = new Date().toISOString();
    const storySnap = await db
      .collection('stories')
      .where('expiresAt', '<', now)
      .limit(450)
      .get();
    const stories = storySnap.docs.filter((d) => d.data()?.archived !== true);
    const reelCutoff = new Date(Date.now() - 2 * 24 * 3600 * 1000).toISOString();
    const reelSnap = await db
      .collection('reels')
      .where('deletedAt', '<', reelCutoff)
      .limit(450)
      .get();
    const purgedStories = await batchDeleteDocs(stories);
    const purgedReels = await batchDeleteDocs(reelSnap.docs);
    return {
      ok: true,
      purgedStories,
      purgedReels,
      at: now,
    };
  },
);

/** Yeni hikâye → takipçilere push (uygulama kapalı olsa bile). */
exports.onStoryCreatedPush = onDocumentCreated(
  { document: 'stories/{storyId}', region: 'europe-west1', timeoutSeconds: 120 },
  async (event) => {
    const s = event.data?.data();
    if (!s || s.deletedAt || s.archived === true) return null;
    const authorId = String(s.authorId || '');
    if (!authorId) return null;
    const name = String(s.authorName || 'Birisi');
    return notifyFollowersOfActor({
      actorId: authorId,
      title: 'Yeni hikâye',
      body: `${name} yeni bir hikâye paylaştı`,
      emoji: '✨',
      type: 'activity',
      targetId: event.params.storyId,
      sendEmail: false,
    });
  },
);

/** Yeni reel → takipçilere push. */
exports.onReelCreatedPush = onDocumentCreated(
  { document: 'reels/{reelId}', region: 'europe-west1', timeoutSeconds: 120 },
  async (event) => {
    const r = event.data?.data();
    if (!r || r.deletedAt) return null;
    const authorId = String(r.authorId || '');
    if (!authorId) return null;
    const name = String(r.authorName || 'Birisi');
    return notifyFollowersOfActor({
      actorId: authorId,
      title: 'Yeni Reels',
      body: `${name} yeni bir Reels paylaştı`,
      emoji: '🎬',
      type: 'activity',
      targetId: event.params.reelId,
      sendEmail: false,
    });
  },
);


/** ===================== Landing CMS + Kampüs Elçiliği ===================== */

const LANDING_DOC = 'app_config/landing';

function defaultLandingConfig() {
  return {
    heroTitle: 'KampüsteyimAPP',
    heroSubtitle: 'Doğrulanmış kampüs sosyal ağı',
    instagramUrl: 'https://instagram.com/kampusteyimapp',
    aboutText:
      'KampüsteyimAPP; AYS Tech altyapısıyla üniversite öğrencilerini, firmaları ve resmi toplulukları tek doğrulanmış dijital çatı altında buluşturur. Kampüs Elçiliği programı, üniversitenizde resmi temsilci olarak topluluğu büyütmenizi sağlar.',
    benefits: [
      'Gold tick + Kampüs Elçisi unvanı',
      'Üniversitenizde görünürlük ve networking',
      'Etkinlik / stand / tanıtım süreçlerinde öncelik',
      'Resmi iletişim ve büyüme desteği',
    ],
    steps: [
      'Formu eksiksiz doldur',
      'Başvurun incelensin',
      'Onay sonrası elçi profilin aktifleşsin',
      'Stand ve tanıtımda QR ile büyüt',
    ],
    disclaimer:
      'Kampüs Elçiliği gönüllü bir temsil programıdır. Onay, AYS Tech / KampüsteyimAPP yönetiminin değerlendirmesine bağlıdır. Yanıltıcı bilgi başvuru reddine yol açabilir.',
    kvkkSummary:
      'Başvuruda paylaştığınız ad, iletişim, üniversite ve form yanıtları; elçilik değerlendirme ve iletişim amacıyla KVKK kapsamında işlenir. Veriler yalnızca bu amaçla kullanılır; talebiniz halinde silinebilir.',
    ambassadorPageEnabled: true,
  };
}

async function readLandingConfig() {
  const snap = await db.doc(LANDING_DOC).get();
  const d = snap.exists ? snap.data() || {} : {};
  const base = defaultLandingConfig();
  return {
    ...base,
    heroTitle: String(d.heroTitle || base.heroTitle).trim(),
    heroSubtitle: String(d.heroSubtitle || base.heroSubtitle).trim(),
    instagramUrl: String(d.instagramUrl || base.instagramUrl).trim(),
    aboutText: String(d.aboutText || base.aboutText).trim(),
    benefits: Array.isArray(d.benefits) && d.benefits.length
      ? d.benefits.map((x) => String(x)).filter(Boolean)
      : base.benefits,
    steps: Array.isArray(d.steps) && d.steps.length
      ? d.steps.map((x) => String(x)).filter(Boolean)
      : base.steps,
    disclaimer: String(d.disclaimer || base.disclaimer).trim(),
    kvkkSummary: String(d.kvkkSummary || base.kvkkSummary).trim(),
    ambassadorPageEnabled: d.ambassadorPageEnabled !== false,
    updatedAt: d.updatedAt || null,
  };
}

exports.getLandingPublic = onRequest(
  { region: 'europe-west1', cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    try {
      const landing = await readLandingConfig();
      const promo = await readPromoConfig();
      res.status(200).json({ ok: true, landing, promo });
    } catch (e) {
      console.error('[getLandingPublic]', e);
      res.status(500).json({ ok: false, error: 'Okunamadı' });
    }
  },
);

exports.updateLandingConfig = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertPlatformAdmin(request.auth?.uid);
    const data = request.data || {};
    const payload = {
      heroTitle: sanitizePlainText(data.heroTitle || '', 120),
      heroSubtitle: sanitizePlainText(data.heroSubtitle || '', 240),
      instagramUrl: sanitizePlainText(data.instagramUrl || '', 400),
      aboutText: sanitizePlainText(data.aboutText || '', 4000),
      benefits: Array.isArray(data.benefits)
        ? data.benefits.map((x) => sanitizePlainText(x, 200)).filter(Boolean).slice(0, 20)
        : [],
      steps: Array.isArray(data.steps)
        ? data.steps.map((x) => sanitizePlainText(x, 200)).filter(Boolean).slice(0, 20)
        : [],
      disclaimer: sanitizePlainText(data.disclaimer || '', 2000),
      kvkkSummary: sanitizePlainText(data.kvkkSummary || '', 4000),
      ambassadorPageEnabled: data.ambassadorPageEnabled !== false,
      updatedAt: new Date().toISOString(),
      updatedBy: request.auth.uid,
    };
    await db.doc(LANDING_DOC).set(payload, { merge: true });
    return { ok: true, ...payload };
  },
);

exports.adminUpsertEmbassy = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertPlatformAdmin(request.auth?.uid);
    const data = request.data || {};
    const id = String(data.id || '').trim();
    const ref = id
      ? db.collection('embassies').doc(id)
      : db.collection('embassies').doc();
    const payload = {
      name: sanitizePlainText(data.name || '', 120),
      university: sanitizePlainText(data.university || '', 160),
      city: sanitizePlainText(data.city || '', 80),
      description: sanitizePlainText(data.description || '', 2000),
      active: data.active !== false,
      updatedAt: new Date().toISOString(),
      updatedBy: request.auth.uid,
    };
    if (!payload.name || !payload.university) {
      throw new HttpsError('invalid-argument', 'Ad ve üniversite gerekli');
    }
    const existing = await ref.get();
    if (!existing.exists) payload.createdAt = new Date().toISOString();
    await ref.set(payload, { merge: true });
    return { ok: true, id: ref.id };
  },
);

exports.adminUpsertAmbassadorForm = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertPlatformAdmin(request.auth?.uid);
    const data = request.data || {};
    let slug = sanitizePlainText(data.slug || '', 80)
      .toLowerCase()
      .replace(/[^a-z0-9\-]+/g, '-')
      .replace(/^-+|-+$/g, '');
    if (!slug) slug = 'kampus-elcisi';
    const fields = Array.isArray(data.fields)
      ? data.fields
          .map((f) => ({
            id: sanitizePlainText(f.id || '', 40),
            label: sanitizePlainText(f.label || '', 120),
            type: sanitizePlainText(f.type || 'text', 20) || 'text',
            required: f.required !== false,
            options: Array.isArray(f.options)
              ? f.options.map((o) => sanitizePlainText(o, 80)).filter(Boolean).slice(0, 30)
              : [],
          }))
          .filter((f) => f.id && f.label)
          .slice(0, 40)
      : [];
    const q = await db.collection('ambassador_forms').where('slug', '==', slug).limit(1).get();
    const ref = q.empty ? db.collection('ambassador_forms').doc() : q.docs[0].ref;
    const payload = {
      title: sanitizePlainText(data.title || 'Kampüs Elçiliği Başvurusu', 160),
      slug,
      fields,
      active: data.active !== false,
      embassyId: sanitizePlainText(data.embassyId || '', 80) || null,
      updatedAt: new Date().toISOString(),
      updatedBy: request.auth.uid,
    };
    if (q.empty) payload.createdAt = new Date().toISOString();
    await ref.set(payload, { merge: true });
    return { ok: true, id: ref.id, slug };
  },
);

exports.getAmbassadorFormPublic = onRequest(
  { region: 'europe-west1', cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    try {
      const landing = await readLandingConfig();
      if (!landing.ambassadorPageEnabled) {
        res.status(403).json({ ok: false, error: 'Elçilik başvuruları kapalı' });
        return;
      }
      const slug = String(req.query.slug || req.query.form || 'kampus-elcisi').trim();
      let snap = await db.collection('ambassador_forms').where('slug', '==', slug).limit(1).get();
      if (snap.empty) {
        snap = await db.collection('ambassador_forms').where('active', '==', true).limit(1).get();
      }
      if (snap.empty) {
        res.status(200).json({
          ok: true,
          landing,
          form: {
            id: '',
            title: 'Kampüs Elçiliği Başvurusu',
            slug: slug || 'kampus-elcisi',
            fields: [
              { id: 'fullName', label: 'Ad Soyad', type: 'text', required: true },
              { id: 'email', label: 'E-posta', type: 'email', required: true },
              { id: 'phone', label: 'Telefon', type: 'tel', required: true },
              { id: 'university', label: 'Üniversite', type: 'text', required: true },
              { id: 'city', label: 'Şehir', type: 'text', required: true },
              { id: 'motivation', label: 'Neden kampüs elçisi olmak istiyorsun?', type: 'textarea', required: true },
              { id: 'experience', label: 'Kulüp / etkinlik deneyimin', type: 'textarea', required: false },
              { id: 'instagram', label: 'Instagram', type: 'text', required: false },
            ],
            embassyId: null,
            isDefault: true,
          },
        });
        return;
      }
      const doc = snap.docs[0];
      const d = doc.data() || {};
      if (d.active === false) {
        res.status(403).json({ ok: false, error: 'Form pasif', landing });
        return;
      }
      res.status(200).json({
        ok: true,
        landing,
        form: {
          id: doc.id,
          title: d.title || '',
          slug: d.slug || slug,
          fields: Array.isArray(d.fields) ? d.fields : [],
          embassyId: d.embassyId || null,
        },
      });
    } catch (e) {
      console.error('[getAmbassadorFormPublic]', e);
      res.status(500).json({ ok: false, error: 'Okunamadı' });
    }
  },
);

exports.submitAmbassadorApplication = onRequest(
  { region: 'europe-west1', cors: true },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ ok: false, error: 'POST' });
      return;
    }
    try {
      const landing = await readLandingConfig();
      if (!landing.ambassadorPageEnabled) {
        res.status(403).json({ ok: false, error: 'Başvurular kapalı' });
        return;
      }
      const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
      const formId = sanitizePlainText(body.formId || '', 80);
      const formSlug = sanitizePlainText(body.formSlug || '', 80) || 'kampus-elcisi';
      const defaultFields = [
        { id: 'fullName', label: 'Ad Soyad', type: 'text', required: true },
        { id: 'email', label: 'E-posta', type: 'email', required: true },
        { id: 'phone', label: 'Telefon', type: 'tel', required: true },
        { id: 'university', label: 'Üniversite', type: 'text', required: true },
        { id: 'city', label: 'Şehir', type: 'text', required: true },
        { id: 'motivation', label: 'Neden kampüs elçisi olmak istiyorsun?', type: 'textarea', required: true },
        { id: 'experience', label: 'Kulüp / etkinlik deneyimin', type: 'textarea', required: false },
        { id: 'instagram', label: 'Instagram', type: 'text', required: false },
      ];
      let formSnap = null;
      if (formId) formSnap = await db.collection('ambassador_forms').doc(formId).get();
      if (!formSnap || !formSnap.exists) {
        const q = await db
          .collection('ambassador_forms')
          .where('slug', '==', formSlug)
          .limit(1)
          .get();
        if (!q.empty) formSnap = q.docs[0];
      }
      const form = formSnap && formSnap.exists
        ? formSnap.data() || {}
        : {
            title: 'Kampüs Elçiliği Başvurusu',
            slug: formSlug,
            fields: defaultFields,
            embassyId: null,
            active: true,
          };
      if (form.active === false) {
        res.status(403).json({ ok: false, error: 'Form pasif' });
        return;
      }
      const fields = Array.isArray(form.fields) && form.fields.length ? form.fields : defaultFields;
      const answersIn = body.answers && typeof body.answers === 'object' ? body.answers : {};
      const answers = {};
      for (const f of fields) {
        const id = String(f.id || '');
        const val = sanitizePlainText(answersIn[id] || body[id] || '', f.type === 'textarea' ? 4000 : 400);
        if (f.required && !val) {
          res.status(400).json({ ok: false, error: `${f.label || id} zorunlu` });
          return;
        }
        answers[id] = val;
      }
      const email = sanitizePlainText(answers.email || body.email || '', 120).toLowerCase();
      const name = sanitizePlainText(answers.fullName || answers.name || body.name || '', 120);
      if (!email || !email.includes('@')) {
        res.status(400).json({ ok: false, error: 'Geçerli e-posta gerekli' });
        return;
      }
      const recent = await db
        .collection('ambassador_applications')
        .where('email', '==', email)
        .orderBy('createdAt', 'descending')
        .limit(2)
        .get()
        .catch(() => ({ empty: true, docs: [] }));
      if (!recent.empty) {
        const last = recent.docs[0].data() || {};
        const t = Date.parse(last.createdAt || '') || 0;
        if (Date.now() - t < 10 * 60 * 1000) {
          res.status(429).json({ ok: false, error: 'Çok sık başvuru. Biraz sonra tekrar deneyin.' });
          return;
        }
      }
      const now = new Date().toISOString();
      const ref = await db.collection('ambassador_applications').add({
        formId: formSnap && formSnap.exists ? formSnap.id : 'default',
        formSlug: form.slug || formSlug,
        formTitle: form.title || 'Kampüs Elçiliği Başvurusu',
        embassyId: form.embassyId || null,
        name,
        email,
        phone: sanitizePlainText(answers.phone || body.phone || '', 40),
        university: sanitizePlainText(answers.university || body.university || '', 160),
        city: sanitizePlainText(answers.city || body.city || '', 80),
        answers,
        status: 'open',
        source: 'landing_elcilik',
        userAgent: String(req.get('user-agent') || '').slice(0, 240),
        createdAt: now,
        updatedAt: now,
        kvkkAccepted: body.kvkkAccepted === true,
        disclaimerAccepted: body.disclaimerAccepted === true,
      });
      res.status(200).json({ ok: true, id: ref.id });
    } catch (e) {
      console.error('[submitAmbassadorApplication]', e);
      res.status(500).json({ ok: false, error: 'Başvuru kaydedilemedi' });
    }
  },
);

exports.adminUpdateAmbassadorApplication = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertPlatformAdmin(request.auth?.uid);
    const id = String(request.data?.applicationId || '').trim();
    const status = String(request.data?.status || '').trim();
    if (!id || !['open', 'approved', 'rejected', 'done'].includes(status)) {
      throw new HttpsError('invalid-argument', 'Geçersiz durum');
    }
    await db.collection('ambassador_applications').doc(id).set(
      {
        status,
        updatedAt: new Date().toISOString(),
        reviewedBy: request.auth.uid,
      },
      { merge: true },
    );
    return { ok: true };
  },
);

exports.adminSetCampusAmbassador = onCall(
  { region: 'europe-west1' },
  async (request) => {
    await assertPlatformAdmin(request.auth?.uid);
    const userKey = String(request.data?.userKey || '').trim();
    const active = request.data?.active !== false;
    const embassyId = sanitizePlainText(request.data?.embassyId || '', 80) || null;
    const badgeTitle =
      sanitizePlainText(request.data?.badgeTitle || 'Kampüs Elçisi', 80) || 'Kampüs Elçisi';
    if (!userKey) throw new HttpsError('invalid-argument', 'Kullanıcı gerekli');

    let doc = await findUserDocByAnyId(userKey);
    if (!doc && userKey.includes('@')) {
      const q = await db.collection('users').where('email', '==', userKey.toLowerCase()).limit(1).get();
      if (!q.empty) doc = q.docs[0];
    }
    if (!doc || !doc.exists) {
      const qName = userKey.toLowerCase().replace(/^@/, '');
      const scan = await db.collection('users').limit(500).get();
      const hit = scan.docs.find((d) => {
        const m = d.data() || {};
        const name = `${m.firstName || ''} ${m.lastName || ''} ${m.displayName || ''}`
          .trim()
          .toLowerCase();
        const email = String(m.email || '').toLowerCase();
        const uname = String(m.username || '').toLowerCase();
        return (
          name.includes(qName) ||
          email === qName ||
          uname === qName ||
          uname.includes(qName)
        );
      });
      if (hit) doc = hit;
    }
    if (!doc || !doc.exists) throw new HttpsError('not-found', 'Kullanıcı bulunamadı');

    const payload = active
      ? {
          isCampusAmbassador: true,
          badgeTitle,
          embassyId,
          updatedAt: new Date().toISOString(),
        }
      : {
          isCampusAmbassador: false,
          badgeTitle: '',
          embassyId: null,
          updatedAt: new Date().toISOString(),
        };
    await doc.ref.set(payload, { merge: true });
    return { ok: true, userId: doc.id, active };
  },
);

const APP_VERSION_DOC = 'app_config/app_version';
const IOS_APP_ID = '6793663176';
const ANDROID_PACKAGE = 'com.aystech.kampusteyimapp';

function normalizeVersion(v) {
  return String(v || '')
    .trim()
    .replace(/^v/i, '')
    .split(/[^0-9.]+/)[0]
    .replace(/^\.+|\.+$/g, '');
}

function compareVersions(a, b) {
  const pa = normalizeVersion(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = normalizeVersion(b).split('.').map((n) => parseInt(n, 10) || 0);
  const len = Math.max(pa.length, pb.length, 3);
  for (let i = 0; i < len; i++) {
    const x = pa[i] || 0;
    const y = pb[i] || 0;
    if (x > y) return 1;
    if (x < y) return -1;
  }
  return 0;
}

async function fetchIosStoreVersion(appId) {
  const id = String(appId || IOS_APP_ID).replace(/\D/g, '') || IOS_APP_ID;
  const url = 'https://itunes.apple.com/lookup?id=' + id + '&country=tr';
  const res = await fetch(url, { headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error('itunes ' + res.status);
  const data = await res.json();
  const row = Array.isArray(data.results) ? data.results[0] : null;
  if (!row) return { version: '', trackViewUrl: '' };
  return {
    version: normalizeVersion(row.version),
    trackViewUrl: String(row.trackViewUrl || ''),
  };
}

async function fetchAndroidStoreVersion(packageName) {
  const pkg = String(packageName || ANDROID_PACKAGE).trim() || ANDROID_PACKAGE;
  const url =
    'https://play.google.com/store/apps/details?id=' +
    encodeURIComponent(pkg) +
    '&hl=en&gl=US';
  const res = await fetch(url, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    },
  });
  if (!res.ok) {
    return { version: '', available: false, status: res.status };
  }
  const html = await res.text();
  const patterns = [
    /\[\[\[["'](\d+(?:\.\d+){1,3})["']\]\]/,
    /Current Version<\/div><span[^>]*><div[^>]*><span[^>]*>([\d.]+)</,
    /"softwareVersion"\s*:\s*"([\d.]+)"/,
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m && m[1]) return { version: normalizeVersion(m[1]), available: true };
  }
  return { version: '', available: true };
}

async function readAppVersionConfig() {
  const snap = await db.doc(APP_VERSION_DOC).get();
  const d = snap.exists ? snap.data() || {} : {};
  const defaultTitle = 'Güncelleme gerekli';
  const defaultMessage =
    'KampüsteyimAPP’in yeni sürümü yayında. Devam etmek için uygulamayı mağazadan güncelle.';
  return {
    forceBelowMin: d.forceBelowMin !== false,
    softUpdateEnabled: d.softUpdateEnabled !== false,
    minVersion: normalizeVersion(d.minVersion || ''),
    latestIosOverride: normalizeVersion(d.latestIosOverride || ''),
    latestAndroidOverride: normalizeVersion(d.latestAndroidOverride || ''),
    title: String(d.title || defaultTitle).trim() || defaultTitle,
    message: String(d.message || defaultMessage).trim() || defaultMessage,
    iosAppId: String(d.iosAppId || IOS_APP_ID).replace(/\D/g, '') || IOS_APP_ID,
    androidPackage: String(d.androidPackage || ANDROID_PACKAGE).trim() || ANDROID_PACKAGE,
    cachedIosVersion: normalizeVersion(d.cachedIosVersion || ''),
    cachedAndroidVersion: normalizeVersion(d.cachedAndroidVersion || ''),
    cachedAt: d.cachedAt || null,
    updatedAt: d.updatedAt || null,
  };
}

async function refreshStoreVersions(cfg, { force = false } = {}) {
  const cachedAgeMs = cfg.cachedAt ? Date.now() - Date.parse(cfg.cachedAt) : Infinity;
  const useCache = !force && Number.isFinite(cachedAgeMs) && cachedAgeMs < 30 * 60 * 1000;
  let iosVersion = cfg.latestIosOverride || (useCache ? cfg.cachedIosVersion : '');
  let androidVersion =
    cfg.latestAndroidOverride || (useCache ? cfg.cachedAndroidVersion : '');
  let iosUrl = '';
  let androidAvailable = Boolean(androidVersion);

  const tasks = [];
  if (!cfg.latestIosOverride) {
    tasks.push(
      fetchIosStoreVersion(cfg.iosAppId)
        .then((r) => {
          if (r.version) iosVersion = r.version;
          iosUrl = r.trackViewUrl || '';
        })
        .catch((e) => console.warn('[appVersion] ios lookup', e && e.message ? e.message : e)),
    );
  }
  if (!cfg.latestAndroidOverride) {
    tasks.push(
      fetchAndroidStoreVersion(cfg.androidPackage)
        .then((r) => {
          if (r.version) {
            androidVersion = r.version;
            androidAvailable = true;
          } else {
            androidAvailable = r.available !== false;
          }
        })
        .catch((e) => console.warn('[appVersion] play lookup', e && e.message ? e.message : e)),
    );
  }
  await Promise.all(tasks);

  const nowIso = new Date().toISOString();
  await db
    .doc(APP_VERSION_DOC)
    .set(
      {
        cachedIosVersion: iosVersion || cfg.cachedIosVersion || '',
        cachedAndroidVersion: androidVersion || cfg.cachedAndroidVersion || '',
        cachedAt: nowIso,
      },
      { merge: true },
    )
    .catch(() => {});

  return {
    iosVersion: iosVersion || cfg.cachedIosVersion || '',
    androidVersion: androidVersion || cfg.cachedAndroidVersion || '',
    iosUrl,
    androidAvailable,
  };
}

/** Public: client version gate — also fetches store versions */
exports.getAppUpdateGate = onRequest(
  { region: 'europe-west1', cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    try {
      const q = req.method === 'GET' ? req.query || {} : req.body || {};
      const platform = String(q.platform || '').toLowerCase();
      const current = normalizeVersion(q.currentVersion || q.version || '');
      const cfg = await readAppVersionConfig();
      const store = await refreshStoreVersions(cfg, { force: String(q.refresh) === '1' });
      const promo = await readPromoConfig();
      const storeUrls = resolveStoreUrls(promo);

      const storeVersion =
        platform === 'ios'
          ? store.iosVersion
          : platform === 'android'
            ? store.androidVersion
            : store.iosVersion || store.androidVersion;

      const belowMin =
        Boolean(cfg.minVersion) &&
        Boolean(current) &&
        compareVersions(current, cfg.minVersion) < 0;
      const belowStore =
        Boolean(storeVersion) &&
        Boolean(current) &&
        compareVersions(current, storeVersion) < 0;

      const forceUpdate = Boolean(current) && cfg.forceBelowMin && belowMin;
      const softUpdate =
        Boolean(current) && !forceUpdate && cfg.softUpdateEnabled && belowStore;

      let storeUrl = DOWNLOAD_SECTION_URL;
      if (platform === 'ios') {
        storeUrl = storeUrls.ios || store.iosUrl || DEFAULT_APP_STORE_URL;
      } else if (platform === 'android') {
        storeUrl =
          storeUrls.android ||
          'https://play.google.com/store/apps/details?id=' + cfg.androidPackage;
      }

      res.set('Cache-Control', 'public, max-age=120');
      res.status(200).json({
        ok: true,
        platform: platform || 'unknown',
        currentVersion: current,
        minVersion: cfg.minVersion,
        storeVersion: storeVersion || '',
        iosStoreVersion: store.iosVersion || '',
        androidStoreVersion: store.androidVersion || '',
        forceUpdate,
        softUpdate,
        updateRequired: forceUpdate || softUpdate,
        title: cfg.title,
        message: cfg.message,
        storeUrl,
        appStoreUrl: storeUrls.ios || store.iosUrl || DEFAULT_APP_STORE_URL,
        playStoreUrl: storeUrls.android || '',
        androidReady: Boolean(storeUrls.android),
        softUpdateEnabled: cfg.softUpdateEnabled,
        forceBelowMin: cfg.forceBelowMin,
        cachedAt: cfg.cachedAt,
      });
    } catch (e) {
      console.error('[getAppUpdateGate]', e);
      res.status(500).json({ ok: false, error: 'Sürüm kontrolü başarısız' });
    }
  },
);

/** Admin: min version / force update / message */
exports.updateAppVersionConfig = onCall(
  { region: 'europe-west1', timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const data = request.data || {};
    const nowIso = new Date().toISOString();
    const patch = {
      updatedAt: nowIso,
      updatedBy: request.auth.uid,
    };
    if (data.minVersion != null) patch.minVersion = normalizeVersion(data.minVersion);
    if (data.latestIosOverride != null) {
      patch.latestIosOverride = normalizeVersion(data.latestIosOverride);
    }
    if (data.latestAndroidOverride != null) {
      patch.latestAndroidOverride = normalizeVersion(data.latestAndroidOverride);
    }
    if (data.title != null) {
      patch.title = sanitizePlainText(data.title, 120) || 'Güncelleme gerekli';
    }
    if (data.message != null) {
      patch.message = sanitizePlainText(data.message, 500);
    }
    if (typeof data.forceBelowMin === 'boolean') patch.forceBelowMin = data.forceBelowMin;
    if (typeof data.softUpdateEnabled === 'boolean') {
      patch.softUpdateEnabled = data.softUpdateEnabled;
    }
    if (data.iosAppId) {
      patch.iosAppId = String(data.iosAppId).replace(/\D/g, '') || IOS_APP_ID;
    }
    if (data.androidPackage) {
      patch.androidPackage =
        sanitizePlainText(data.androidPackage, 120) || ANDROID_PACKAGE;
    }

    await db.doc(APP_VERSION_DOC).set(patch, { merge: true });

    let store = null;
    if (data.refreshStore === true) {
      const cfg = await readAppVersionConfig();
      store = await refreshStoreVersions(Object.assign({}, cfg, patch), { force: true });
    }

    const cfg = await readAppVersionConfig();
    return {
      ok: true,
      config: cfg,
      store: store
        ? { iosVersion: store.iosVersion, androidVersion: store.androidVersion }
        : {
            iosVersion: cfg.cachedIosVersion,
            androidVersion: cfg.cachedAndroidVersion,
          },
    };
  },
);


// —— Payments (PayTR + Shopier + IBAN) + event review ——
// —— Payments (PayTR + Shopier + IBAN) + commerce (bilet / cüzdan / reklam) ——
exports.updateSmtpConfig = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const adminDoc = await assertPlatformAdmin(request.auth.uid);
    if (adminDoc.isSuperAdmin !== true && adminDoc.role !== 'admin') {
      throw new HttpsError('permission-denied', 'Yalnızca süper admin');
    }
    const host = sanitizePlainText(request.data?.smtp_host || 'smtp.kampusteyim.app', 120);
    const port = String(request.data?.smtp_port || '465').trim();
    const user = sanitizePlainText(request.data?.smtp_user || 'info@kampusteyim.app', 120);
    const pass = String(request.data?.smtp_pass || '').trim();
    const patch = {
      smtp_host: host,
      smtp_port: port,
      smtp_user: user,
      updated_at: new Date().toISOString(),
    };
    if (pass) patch.smtp_pass = pass;
    await db.collection('app_secrets').doc('runtime').set(patch, { merge: true });
    return { ok: true, smtp_user: user, smtp_host: host };
  },
);

/**
 * NFC beta probu: yalnız platform admini ham teknik kart raporu kaydedebilir.
 * İstemci Firestore'a doğrudan yazamaz; payload 32 KB ile sınırlıdır.
 */
exports.logNfcProbe = onCall(
  { region: 'europe-west1', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const probe = request.data?.probe;
    if (!probe || typeof probe !== 'object' || Array.isArray(probe)) {
      throw new HttpsError('invalid-argument', 'Geçerli NFC probe verisi gerekli');
    }
    const serialized = JSON.stringify(probe);
    if (Buffer.byteLength(serialized, 'utf8') > 32 * 1024) {
      throw new HttpsError('invalid-argument', 'NFC probe verisi çok büyük');
    }
    const parsed = JSON.parse(serialized);
    const ref = db.collection('nfc_probe_logs').doc();
    await ref.set({
      schemaVersion: 1,
      adminUid: request.auth.uid,
      adminEmail: sanitizePlainText(request.auth.token?.email || '', 160),
      probe: parsed,
      createdAt: FieldValue.serverTimestamp(),
      createdAtIso: new Date().toISOString(),
      source: 'kampusteyim_nfc_beta_android',
    });
    return { ok: true, logId: ref.id };
  },
);

const { commerceModule } = require('./commerce');
const _commerce = commerceModule({
  db,
  onCall,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  FieldValue,
  findUserDocByAnyId,
  expandFieldPaths,
});
exports.saveOrganizerPayoutIban = _commerce.saveOrganizerPayoutIban;
exports.adminSetOrganizerCommerce = _commerce.adminSetOrganizerCommerce;
exports.getOrganizerDashboard = _commerce.getOrganizerDashboard;
exports.requestWithdrawal = _commerce.requestWithdrawal;
exports.adminReviewWithdrawal = _commerce.adminReviewWithdrawal;
exports.createEventDiscount = _commerce.createEventDiscount;
exports.submitAdCampaign = _commerce.submitAdCampaign;
exports.quoteAdCampaign = _commerce.quoteAdCampaign;
exports.acceptAdQuote = _commerce.acceptAdQuote;
exports.declineAdQuote = _commerce.declineAdQuote;
exports.getMyAdCampaigns = _commerce.getMyAdCampaigns;
exports.updateAdCampaign = _commerce.updateAdCampaign;
exports.deleteAdCampaign = _commerce.deleteAdCampaign;
exports.adminDeleteAdCampaign = _commerce.adminDeleteAdCampaign;
exports.trackAdEvent = _commerce.trackAdEvent;
exports.adminReviewAdCampaign = _commerce.adminReviewAdCampaign;
exports.getActiveAds = _commerce.getActiveAds;
exports.getMyTickets = _commerce.getMyTickets;

const { orgGrowthModule } = require('./org_growth');
const _orgGrowth = orgGrowthModule({
  db,
  onCall,
  onRequest,
  onSchedule,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  escapeHtml,
  FieldValue,
  sendMail,
  sendFcmToUser,
  buildCampusPushPayload,
  userAllowsPush,
  expandFieldPaths,
});
exports.inviteOrgMember = _orgGrowth.inviteOrgMember;
exports.respondOrgInvite = _orgGrowth.respondOrgInvite;
exports.revokeOrgMember = _orgGrowth.revokeOrgMember;
exports.getOrgInvite = _orgGrowth.getOrgInvite;
exports.dispatchAdCampaignReach = _orgGrowth.dispatchAdCampaignReach;
exports.dispatchScheduledAdReach = _orgGrowth.dispatchScheduledAdReach;
exports.trackAdEmailOpen = _orgGrowth.trackAdEmailOpen;
exports.trackAdEmailClick = _orgGrowth.trackAdEmailClick;

const { paymentsModule } = require('./payments');
const _payments = paymentsModule({
  db,
  onCall,
  onRequest,
  HttpsError,
  assertPlatformAdmin,
  assertAdminPermission,
  sanitizePlainText,
  fulfillEventOrder: _commerce.fulfillEventOrder,
  fulfillAdOrder: _commerce.fulfillAdOrder,
  applyDiscountAmount: _commerce.applyDiscountAmount,
});
exports.updatePaymentsConfig = _payments.updatePaymentsConfig;
exports.getPaymentsAdmin = _payments.getPaymentsAdmin;
exports.getPaymentsPublic = _payments.getPaymentsPublic;
exports.createPaymentOrder = _payments.createPaymentOrder;
exports.confirmIbanTransfer = _payments.confirmIbanTransfer;
exports.adminReviewPaymentOrder = _payments.adminReviewPaymentOrder;
exports.paytrCallback = _payments.paytrCallback;
exports.shopierCallback = _payments.shopierCallback;
exports.shopierPayPage = _payments.shopierPayPage;
exports.adminReviewEvent = _payments.adminReviewEvent;
exports.adminDeleteEvent = _payments.adminDeleteEvent;
