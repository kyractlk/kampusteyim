/**
 * Puan marketi + Sil Süpür + eSIM ödül katalogu.
 */
const { onCall, HttpsError, onRequest } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const esim = require('./esim_access');

const CONFIG_PATH = 'app_config/points';
const CATALOG = 'points_catalog';
const USER_POINTS = 'user_points';
const LEDGER = 'points_ledger';
const REWARDS = 'user_rewards';
const SPINS = 'sil_supur_plays';

const DEFAULT_CONFIG = {
  enabled: true,
  tlPerPoint: 0.1,
  usdTryRate: 42,
  defaultMarginPercent: 35,
  earn: {
    post: 5,
    reel: 8,
    story: 3,
    likeReceived: 2,
    commentReceived: 3,
    repostReceived: 4,
  },
  silSupur: {
    enabled: true,
    weekday: 3, // 0=Pazar … 3=Çarşamba (Europe/Istanbul)
    hour: 12,
    minute: 0,
    freeSpinsPerWeek: 1,
    notifyTitle: 'Sil Süpür başladı!',
    notifyBody: 'Bu haftanın hediyeleri seni bekliyor. Hemen çevir!',
    segments: [
      { id: 'miss', label: 'Tekrar dene', weight: 40, type: 'none' },
      { id: 'pts30', label: '+30 puan', weight: 22, type: 'points', points: 30 },
      { id: 'pts80', label: '+80 puan', weight: 14, type: 'points', points: 80 },
      { id: 'pts150', label: '+150 puan', weight: 8, type: 'points', points: 150 },
    ],
  },
};

function sanitizePlainText(v, max = 200) {
  return String(v || '')
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

function asNum(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function mergeConfig(raw) {
  const d = raw && typeof raw === 'object' ? raw : {};
  return {
    ...DEFAULT_CONFIG,
    ...d,
    earn: { ...DEFAULT_CONFIG.earn, ...(d.earn || {}) },
    silSupur: {
      ...DEFAULT_CONFIG.silSupur,
      ...(d.silSupur || {}),
      segments:
        Array.isArray(d.silSupur?.segments) && d.silSupur.segments.length
          ? d.silSupur.segments
          : DEFAULT_CONFIG.silSupur.segments,
    },
  };
}

function istanbulParts(date = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Istanbul',
    weekday: 'short',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = Object.fromEntries(
    fmt.formatToParts(date).filter((p) => p.type !== 'literal').map((p) => [p.type, p.value]),
  );
  const map = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return {
    weekday: map[parts.weekday] ?? date.getUTCDay(),
    hour: Number(parts.hour),
    minute: Number(parts.minute),
    ymd: `${parts.year}-${parts.month}-${parts.day}`,
  };
}

function weekKeyIstanbul(date = new Date()) {
  // ISO-ish week key in Istanbul calendar date
  const { ymd, weekday } = istanbulParts(date);
  const [y, m, d] = ymd.split('-').map(Number);
  const utc = Date.UTC(y, m - 1, d);
  const day = weekday === 0 ? 7 : weekday; // Mon=1..Sun=7
  const thursday = new Date(utc + (4 - day) * 86400000);
  const yearStart = Date.UTC(thursday.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((thursday - yearStart) / 86400000 + 1) / 7);
  return `${thursday.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

async function collectSegments(db, cfg) {
  let segments = [...(cfg.silSupur.segments || [])];
  const cat = await db.collection(CATALOG)
    .where('silSupurEligible', '==', true)
    .where('active', '==', true)
    .limit(50)
    .get()
    .catch(() => null);
  if (cat) {
    cat.forEach((doc) => {
      const d = doc.data() || {};
      const w = asNum(d.silSupurWeight);
      if (w <= 0) return;
      if ((d.type || '') === 'esim' && d.esim?.packageCode) {
        segments.push({
          id: `cat_${doc.id}`,
          label: d.title || 'eSIM',
          weight: w,
          type: 'esim',
          packageCode: d.esim.packageCode,
          slug: d.esim.slug,
          title: d.title,
          catalogId: doc.id,
          locationCodes: d.locationCodes || null,
        });
      } else {
        segments.push({
          id: `cat_${doc.id}`,
          label: d.title || 'Hediye',
          weight: w,
          type: d.type === 'points' ? 'points' : 'gift',
          points: d.pointsCost ? asNum(d.pointsCost) : undefined,
          title: d.title,
          catalogId: doc.id,
          imageUrl: d.imageUrl || null,
        });
      }
    });
  }
  return segments;
}

function pickWeighted(segments) {
  const list = (segments || []).filter((s) => asNum(s.weight) > 0);
  const total = list.reduce((a, s) => a + asNum(s.weight), 0);
  if (!total) return { id: 'miss', label: 'Tekrar dene', type: 'none', weight: 1 };
  let r = Math.random() * total;
  for (const s of list) {
    r -= asNum(s.weight);
    if (r <= 0) return s;
  }
  return list[list.length - 1];
}

module.exports = function createPointsRewards({
  db,
  FieldValue,
  assertPlatformAdmin,
  assertAdminPermission,
  sendMail,
  brandedEmail,
  escapeHtml,
  dispatchPushToUser,
}) {
  async function readConfig() {
    const snap = await db.doc(CONFIG_PATH).get();
    return mergeConfig(snap.exists ? snap.data() : {});
  }

  /** Admin → Market durumu: kapalıysa KP / Sil Süpür / eSIM marketi de kapalı. */
  async function marketInAppOn() {
    const snap = await db.doc('app_config/payments').get();
    return snap.exists && snap.data()?.marketInAppVisible === true;
  }

  async function pointsSystemLive(cfg) {
    if (cfg && cfg.enabled === false) return false;
    return marketInAppOn();
  }

  async function sendEsimReadyMail({
    uid, title, locationCodes, qrCodeUrl, ac, shortUrl, paidWith,
  }) {
    const userSnap = await db.collection('users').doc(uid).get();
    const u = userSnap.exists ? userSnap.data() || {} : {};
    const email = String(u.email || '').trim();
    const name = u.firstName || u.fullName || '';
    const countries = String(locationCodes || '').replace(/,/g, ', ');
    const lpa = String(ac || '').trim();
    const apple = lpa
      ? `https://esimsetup.apple.com/esim_qrcode_provisioning?carddata=${encodeURIComponent(lpa)}`
      : '';
    const android = lpa
      ? `https://esimsetup.android.com/esim_qrcode_provisioning?carddata=${encodeURIComponent(lpa)}`
      : '';
    const qr = qrCodeUrl || shortUrl || '';
    const tag = paidWith === 'sil_supur' ? 'Sil Süpür hediyesi' : 'Kampüsteyim Puan (KP) ile alındı';
    const bodyHtml = `
      <p>KampüsteyimAPP eSIM’in hazır.</p>
      <p><b>${escapeHtml(title)}</b><br/><span style="color:#64748B">${escapeHtml(tag)}</span></p>
      ${countries ? `<p><b>Geçerli ülkeler / bölgeler:</b> ${escapeHtml(countries)}</p>` : ''}
      ${qr ? `<p><img src="${escapeHtml(qr)}" alt="eSIM QR" style="max-width:220px;border-radius:12px"/></p>` : ''}
      ${lpa ? `<p><b>Kurulum kodu (LPA)</b><br/><code style="font-size:12px;word-break:break-all">${escapeHtml(lpa)}</code></p>` : ''}
      ${android ? `<p><a href="${escapeHtml(android)}">Android Quick Install</a></p>` : ''}
      <p>iPhone: iOS 17.4+ Quick Install (aşağıdaki buton). Android: Play Services destekliyorsa sistem kurulumu açılır; değilse QR / LPA kullan.</p>
      <p style="font-size:13px;color:#64748B">Kurulumdan sonra mobil veri için uluslararası dolaşımı aç.</p>
    `;
    await db.collection('users').doc(uid).collection('notifications').add({
      title: 'eSIM’in hazır',
      body: String(title || ''),
      emoji: '📶',
      type: 'esim_reward',
      link: '/points/rewards',
      read: false,
      createdAt: new Date().toISOString(),
    });
    if (typeof dispatchPushToUser === 'function') {
      await dispatchPushToUser(uid, {
        title: 'eSIM’in hazır',
        body: String(title || ''),
        type: 'esim_reward',
        link: '/points/rewards',
        emoji: '📶',
      });
    }
    if (!email.includes('@') || email.includes('@invalid.local')) return;
    await sendMail({
      to: email,
      subject: `KampüsteyimAPP · eSIM’in hazır: ${title}`,
      html: brandedEmail({
        title: 'eSIM’in hazır',
        greeting: name ? `Merhaba ${name},` : 'Merhaba,',
        bodyHtml,
        ctaLabel: apple ? 'iPhone’da Quick Install' : 'eSIMlerime git',
        ctaUrl: apple || 'https://app.kampusteyim.app/points/rewards',
      }),
    });
  }

  async function getBalanceTx(tx, uid) {
    const ref = db.doc(`${USER_POINTS}/${uid}`);
    const snap = await tx.get(ref);
    const balance = snap.exists ? asNum(snap.data().balance) : 0;
    return { ref, balance };
  }

  async function applyLedgerTx(tx, {
    uid,
    delta,
    reason,
    idempotencyKey,
    meta = {},
  }) {
    const key = sanitizePlainText(idempotencyKey, 120);
    if (!key) throw new HttpsError('invalid-argument', 'idempotencyKey gerekli');
    const ledgerRef = db.doc(`${LEDGER}/${key}`);
    const existing = await tx.get(ledgerRef);
    if (existing.exists) {
      return { balance: asNum(existing.data().balanceAfter), duplicate: true };
    }
    const { ref, balance } = await getBalanceTx(tx, uid);
    const next = balance + asNum(delta);
    tx.set(ref, {
      uid,
      balance: next,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(ledgerRef, {
      uid,
      delta: asNum(delta),
      balanceAfter: next,
      reason: sanitizePlainText(reason, 80),
      meta,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { balance: next, duplicate: false };
  }

  async function fulfillEsimReward({
    uid,
    packageCode,
    slug,
    title,
    source,
    catalogId,
    spinId,
    paidWith,
    locationCodes,
  }) {
    const rewardRef = db.collection(REWARDS).doc();
    const txnId = `ays_${uid.slice(0, 8)}_${Date.now()}`.slice(0, 50);
    await rewardRef.set({
      uid,
      type: 'esim',
      source: source || 'market',
      catalogId: catalogId || null,
      spinId: spinId || null,
      paidWith: paidWith || 'points',
      title: title || 'eSIM',
      packageCode,
      slug: slug || null,
      locationCodes: locationCodes || null,
      status: 'provisioning',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      const { orderNo, profile } = await esim.orderAndWaitProfile(db, {
        packageCode,
        transactionId: txnId,
      });
      const patch = {
        status: profile?.iccid ? 'ready' : 'ordered',
        orderNo,
        transactionId: txnId,
        esimTranNo: profile?.esimTranNo || null,
        iccid: profile?.iccid || null,
        qrCodeUrl: profile?.qrCodeUrl || null,
        shortUrl: profile?.shortUrl || null,
        ac: profile?.ac || null,
        smdpStatus: profile?.smdpStatus || null,
        esimStatus: profile?.esimStatus || null,
        totalVolume: profile?.totalVolume || null,
        totalDuration: profile?.totalDuration || null,
        expiredTime: profile?.expiredTime || null,
        updatedAt: FieldValue.serverTimestamp(),
      };
      await rewardRef.set(patch, { merge: true });
      await sendEsimReadyMail({
        uid,
        title: title || 'eSIM',
        locationCodes,
        qrCodeUrl: patch.qrCodeUrl,
        ac: patch.ac,
        shortUrl: patch.shortUrl,
        paidWith: paidWith || 'points',
      }).catch(() => {});
      return { rewardId: rewardRef.id, ...patch };
    } catch (e) {
      await rewardRef.set({
        status: 'failed',
        error: String(e.message || e).slice(0, 300),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      throw e;
    }
  }

  const getPointsConfig = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const cfg = await readConfig();
    const marketOn = await marketInAppOn();
    const live = cfg.enabled !== false && marketOn;
    const balSnap = await db.doc(`${USER_POINTS}/${request.auth.uid}`).get();
    const balance = balSnap.exists ? asNum(balSnap.data().balance) : 0;
    const weekKey = weekKeyIstanbul();
    const spins = await db.collection(SPINS)
      .where('uid', '==', request.auth.uid)
      .where('weekKey', '==', weekKey)
      .limit(10)
      .get();
    const segments = await collectSegments(db, cfg);
    return {
      config: {
        enabled: live,
        marketInAppVisible: marketOn,
        tlPerPoint: asNum(cfg.tlPerPoint, 0.1),
        usdTryRate: asNum(cfg.usdTryRate, 42),
        defaultMarginPercent: asNum(cfg.defaultMarginPercent, 35),
        earn: cfg.earn,
        silSupur: {
          enabled: live && cfg.silSupur.enabled !== false,
          weekday: asNum(cfg.silSupur.weekday, 3),
          hour: asNum(cfg.silSupur.hour, 12),
          minute: asNum(cfg.silSupur.minute, 0),
          freeSpinsPerWeek: asNum(cfg.silSupur.freeSpinsPerWeek, 1),
          notifyTitle: cfg.silSupur.notifyTitle,
          notifyBody: cfg.silSupur.notifyBody,
          segments: segments.map((s) => ({
            id: s.id,
            label: s.label,
            weight: asNum(s.weight),
            type: s.type,
            points: s.points != null ? asNum(s.points) : null,
            title: s.title || null,
            packageCode: s.packageCode || null,
            slug: s.slug || null,
          })),
        },
      },
      balance,
      weekKey,
      spinsUsedThisWeek: spins.size,
      spinsLeft: Math.max(0, asNum(cfg.silSupur.freeSpinsPerWeek, 1) - spins.size),
    };
  });

  const adminGetPointsConfig = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const cfg = await readConfig();
    let balanceUsd = null;
    try {
      const b = await esim.queryBalance(db);
      balanceUsd = asNum(b.balance) / 10000;
    } catch (_) {
      balanceUsd = null;
    }
    return { config: cfg, esimBalanceUsd: balanceUsd };
  });

  const adminSavePointsConfig = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const incoming = request.data?.config;
    if (!incoming || typeof incoming !== 'object') {
      throw new HttpsError('invalid-argument', 'config gerekli');
    }
    const merged = mergeConfig(incoming);
    await db.doc(CONFIG_PATH).set({
      ...merged,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    }, { merge: true });
    return { ok: true, config: merged };
  });

  const listPointsCatalog = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const admin = request.data?.admin === true;
    if (admin) {
      await assertPlatformAdmin(request.auth.uid);
      await assertAdminPermission(request.auth.uid, 'manage_points');
    } else if (!(await marketInAppOn())) {
      return { items: [] };
    }
    let q = db.collection(CATALOG).orderBy('sort', 'asc');
    const snap = await q.limit(200).get().catch(async () => db.collection(CATALOG).limit(200).get());
    const items = [];
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (!admin && d.active === false) return;
      items.push({
        id: doc.id,
        type: d.type || 'gift',
        title: d.title || '',
        description: d.description || '',
        imageUrl: d.imageUrl || null,
        pointsCost: asNum(d.pointsCost),
        cashPriceTl: d.cashPriceTl != null ? asNum(d.cashPriceTl) : null,
        active: d.active !== false,
        silSupurEligible: d.silSupurEligible === true,
        silSupurWeight: asNum(d.silSupurWeight),
        sort: asNum(d.sort),
        locationLabel: d.locationLabel || null,
        locationCodes: d.locationCodes || d.esim?.location || null,
        costUsd: d.costUsd != null ? asNum(d.costUsd) : null,
        marginPercent: d.marginPercent != null ? asNum(d.marginPercent) : null,
        esim: d.esim || null,
        stock: d.stock != null ? asNum(d.stock) : null,
      });
    });
    return { items };
  });

  const upsertPointsCatalogItem = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const raw = request.data || {};
    const id = sanitizePlainText(raw.id, 60) || db.collection(CATALOG).doc().id;
    const payload = {
      type: sanitizePlainText(raw.type || 'gift', 20) || 'gift',
      title: sanitizePlainText(raw.title, 120),
      description: sanitizePlainText(raw.description, 800),
      imageUrl: sanitizePlainText(raw.imageUrl, 500) || null,
      pointsCost: Math.max(0, Math.floor(asNum(raw.pointsCost))),
      cashPriceTl: raw.cashPriceTl == null ? null : Math.max(0, asNum(raw.cashPriceTl)),
      active: raw.active !== false,
      silSupurEligible: raw.silSupurEligible === true,
      silSupurWeight: Math.max(0, asNum(raw.silSupurWeight)),
      sort: asNum(raw.sort),
      locationLabel: sanitizePlainText(raw.locationLabel, 120) || null,
      locationCodes: sanitizePlainText(raw.locationCodes, 400) || null,
      costUsd: raw.costUsd == null || raw.costUsd === '' ? null : Math.max(0, asNum(raw.costUsd)),
      marginPercent: raw.marginPercent == null || raw.marginPercent === ''
        ? null
        : Math.max(0, asNum(raw.marginPercent)),
      esim: raw.type === 'esim' || raw.esim
        ? {
            packageCode: sanitizePlainText(raw.esim?.packageCode || raw.packageCode, 40),
            slug: sanitizePlainText(raw.esim?.slug || raw.slug, 60) || null,
          }
        : null,
      stock: raw.stock == null || raw.stock === '' ? null : Math.floor(asNum(raw.stock)),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    };
    if (!payload.title) throw new HttpsError('invalid-argument', 'Başlık gerekli');
    if (payload.type === 'esim' && !payload.esim?.packageCode) {
      throw new HttpsError('invalid-argument', 'eSIM packageCode gerekli');
    }
    await db.doc(`${CATALOG}/${id}`).set(payload, { merge: true });
    return { id, ...payload };
  });

  const deletePointsCatalogItem = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const id = sanitizePlainText(request.data?.id, 60);
    if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
    await db.doc(`${CATALOG}/${id}`).delete();
    return { ok: true };
  });

  const redeemPointsCatalogItem = onCall(
    { region: 'europe-west1', timeoutSeconds: 120 },
    async (request) => {
      if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const cfg = await readConfig();
      if (!(await pointsSystemLive(cfg))) {
        throw new HttpsError('failed-precondition', 'Market kapalı');
      }
      const id = sanitizePlainText(request.data?.id, 60);
      if (!id) throw new HttpsError('invalid-argument', 'Ürün id gerekli');
      const itemSnap = await db.doc(`${CATALOG}/${id}`).get();
      if (!itemSnap.exists) throw new HttpsError('not-found', 'Ürün yok');
      const item = itemSnap.data() || {};
      if (item.active === false) throw new HttpsError('failed-precondition', 'Ürün pasif');
      const cost = Math.max(0, Math.floor(asNum(item.pointsCost)));
      if (cost <= 0) throw new HttpsError('failed-precondition', 'Geçersiz puan');

      const redeemKey = `redeem_${uid}_${id}_${Date.now()}`;
      let balanceAfter = 0;
      await db.runTransaction(async (tx) => {
        const { ref, balance } = await getBalanceTx(tx, uid);
        if (balance < cost) {
          throw new HttpsError('failed-precondition', 'Yetersiz puan');
        }
        const res = await applyLedgerTx(tx, {
          uid,
          delta: -cost,
          reason: 'market_redeem',
          idempotencyKey: redeemKey,
          meta: { catalogId: id, title: item.title },
        });
        balanceAfter = res.balance;
        if (item.stock != null) {
          const stock = asNum(item.stock);
          if (stock <= 0) throw new HttpsError('resource-exhausted', 'Stok yok');
          tx.update(itemSnap.ref, { stock: stock - 1, updatedAt: FieldValue.serverTimestamp() });
        }
        // silence unused
        void ref;
      });

      if ((item.type || 'gift') === 'esim') {
        const fulfilled = await fulfillEsimReward({
          uid,
          packageCode: item.esim?.packageCode,
          slug: item.esim?.slug,
          title: item.title,
          source: 'market',
          catalogId: id,
          paidWith: 'points',
          locationCodes: item.locationCodes || item.esim?.location || null,
        });
        return { ok: true, balance: balanceAfter, reward: fulfilled };
      }

      const giftRef = db.collection(REWARDS).doc();
      await giftRef.set({
        uid,
        type: item.type || 'gift',
        source: 'market',
        catalogId: id,
        paidWith: 'points',
        title: item.title,
        description: item.description || '',
        imageUrl: item.imageUrl || null,
        status: 'claimed',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { ok: true, balance: balanceAfter, rewardId: giftRef.id };
    },
  );

  const playSilSupur = onCall(
    { region: 'europe-west1', timeoutSeconds: 120 },
    async (request) => {
      if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const cfg = await readConfig();
      if (!(await pointsSystemLive(cfg)) || cfg.silSupur.enabled === false) {
        throw new HttpsError('failed-precondition', 'Sil Süpür kapalı');
      }
      const today = istanbulParts();
      if (today.weekday !== asNum(cfg.silSupur.weekday, 3)) {
        throw new HttpsError(
          'failed-precondition',
          'Sil Süpür yalnızca ayarlanan günde oynanır',
        );
      }
      const weekKey = weekKeyIstanbul();
      const used = await db.collection(SPINS)
        .where('uid', '==', uid)
        .where('weekKey', '==', weekKey)
        .limit(20)
        .get();
      const free = asNum(cfg.silSupur.freeSpinsPerWeek, 1);
      if (used.size >= free) {
        throw new HttpsError('resource-exhausted', 'Bu haftaki hakkın bitti');
      }

      const segments = await collectSegments(db, cfg);
      const win = pickWeighted(segments);
      const spinRef = db.collection(SPINS).doc();
      await spinRef.set({
        uid,
        weekKey,
        segmentId: win.id,
        label: win.label,
        type: win.type,
        createdAt: FieldValue.serverTimestamp(),
      });

      let reward = null;
      let balance = null;

      if (win.type === 'points') {
        const pts = Math.max(0, Math.floor(asNum(win.points)));
        await db.runTransaction(async (tx) => {
          const res = await applyLedgerTx(tx, {
            uid,
            delta: pts,
            reason: 'sil_supur',
            idempotencyKey: `spin_${spinRef.id}`,
            meta: { spinId: spinRef.id, label: win.label },
          });
          balance = res.balance;
        });
        reward = { type: 'points', points: pts, balance };
      } else if (win.type === 'esim') {
        reward = await fulfillEsimReward({
          uid,
          packageCode: win.packageCode,
          slug: win.slug,
          title: win.title || win.label,
          source: 'sil_supur',
          catalogId: win.catalogId || null,
          spinId: spinRef.id,
          paidWith: 'sil_supur',
          locationCodes: win.locationCodes || null,
        });
      } else if (win.type === 'gift') {
        const giftRef = db.collection(REWARDS).doc();
        await giftRef.set({
          uid,
          type: 'gift',
          source: 'sil_supur',
          catalogId: win.catalogId || null,
          spinId: spinRef.id,
          paidWith: 'sil_supur',
          title: win.title || win.label,
          imageUrl: win.imageUrl || null,
          status: 'claimed',
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        reward = { type: 'gift', rewardId: giftRef.id, title: win.title || win.label };
      } else {
        reward = { type: 'none' };
      }

      await spinRef.set({ reward }, { merge: true });
      return {
        ok: true,
        spinId: spinRef.id,
        segment: {
          id: win.id,
          label: win.label,
          type: win.type,
        },
        reward,
        spinsLeft: Math.max(0, free - used.size - 1),
      };
    },
  );

  const listMyRewards = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const type = sanitizePlainText(request.data?.type, 20); // esim | gift | ''
    let q = db.collection(REWARDS).where('uid', '==', uid).orderBy('createdAt', 'desc').limit(50);
    const snap = await q.get().catch(async () =>
      db.collection(REWARDS).where('uid', '==', uid).limit(50).get(),
    );
    const items = [];
    snap.forEach((doc) => {
      const d = doc.data() || {};
      if (type && (d.type || '') !== type) return;
      items.push({
        id: doc.id,
        ...d,
        createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
        updatedAt: d.updatedAt?.toDate?.()?.toISOString?.() || null,
      });
    });
    return { items };
  });

  const refreshMyEsim = onCall({ region: 'europe-west1', timeoutSeconds: 60 }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const rewardId = sanitizePlainText(request.data?.rewardId, 60);
    if (!rewardId) throw new HttpsError('invalid-argument', 'rewardId gerekli');
    const ref = db.doc(`${REWARDS}/${rewardId}`);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.uid !== uid) {
      throw new HttpsError('not-found', 'Ödül bulunamadı');
    }
    const d = snap.data() || {};
    if (d.type !== 'esim') throw new HttpsError('failed-precondition', 'eSIM değil');
    const q = await esim.queryEsim(db, {
      orderNo: d.orderNo || '',
      iccid: d.iccid || '',
      esimTranNo: d.esimTranNo || null,
    });
    const profile = (q.esimList || [])[0] || null;
    const usageRow = (q.usage?.esimUsageList || [])[0] || null;
    const patch = {
      esimStatus: profile?.esimStatus || d.esimStatus,
      smdpStatus: profile?.smdpStatus || d.smdpStatus,
      eid: profile?.eid || d.eid || null,
      activateTime: profile?.activateTime || d.activateTime || null,
      expiredTime: profile?.expiredTime || d.expiredTime || null,
      totalVolume: profile?.totalVolume ?? d.totalVolume,
      totalDuration: profile?.totalDuration ?? d.totalDuration,
      orderUsage: profile?.orderUsage ?? usageRow?.dataUsage ?? d.orderUsage,
      qrCodeUrl: profile?.qrCodeUrl || d.qrCodeUrl,
      shortUrl: profile?.shortUrl || d.shortUrl,
      ac: profile?.ac || d.ac,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (profile?.iccid && d.status === 'ordered') patch.status = 'ready';
    if (profile?.esimStatus === 'IN_USE') patch.status = 'active';
    await ref.set(patch, { merge: true });
    return { ok: true, reward: { id: rewardId, ...d, ...patch } };
  });

  const topupMyEsim = onCall({ region: 'europe-west1', timeoutSeconds: 90 }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const uid = request.auth.uid;
    const rewardId = sanitizePlainText(request.data?.rewardId, 60);
    const packageCode = sanitizePlainText(request.data?.packageCode, 40);
    const pointsCost = Math.max(0, Math.floor(asNum(request.data?.pointsCost)));
    if (!rewardId || !packageCode) {
      throw new HttpsError('invalid-argument', 'rewardId ve packageCode gerekli');
    }
    if (!(await pointsSystemLive(await readConfig()))) {
      throw new HttpsError('failed-precondition', 'Market kapalı');
    }
    const ref = db.doc(`${REWARDS}/${rewardId}`);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.uid !== uid) {
      throw new HttpsError('not-found', 'Ödül bulunamadı');
    }
    const d = snap.data() || {};
    if (!d.esimTranNo) throw new HttpsError('failed-precondition', 'eSIM henüz hazır değil');

    if (pointsCost > 0) {
      await db.runTransaction(async (tx) => {
        const res = await applyLedgerTx(tx, {
          uid,
          delta: -pointsCost,
          reason: 'esim_topup',
          idempotencyKey: `topup_${uid}_${rewardId}_${Date.now()}`,
          meta: { rewardId, packageCode },
        });
        if (res.balance < 0) throw new HttpsError('failed-precondition', 'Yetersiz puan');
      });
    }

    const top = await esim.topupEsim(db, {
      esimTranNo: d.esimTranNo,
      packageCode,
      transactionId: `top_${uid.slice(0, 6)}_${Date.now()}`.slice(0, 50),
    });
    await ref.set({
      totalVolume: top.totalVolume ?? d.totalVolume,
      totalDuration: top.totalDuration ?? d.totalDuration,
      expiredTime: top.expiredTime || d.expiredTime,
      lastTopUpEsimTranNo: top.topUpEsimTranNo || null,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, topup: top };
  });

  /** Etkileşim puanı — beğeni/yorum/repost alındı veya geri alındı. */
  const applyEngagementPoints = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const actorId = request.auth.uid;
    const cfg = await readConfig();
    if (!(await pointsSystemLive(cfg))) return { ok: true, skipped: true, reason: 'market_off' };

    const kind = sanitizePlainText(request.data?.kind, 40); // like_received | like_removed | ...
    const targetUid = sanitizePlainText(request.data?.targetUid, 80);
    const contentId = sanitizePlainText(request.data?.contentId, 80);
    if (!kind || !targetUid || !contentId) {
      throw new HttpsError('invalid-argument', 'kind, targetUid, contentId gerekli');
    }
    if (actorId === targetUid) return { ok: true, skipped: true, reason: 'self' };

    const earn = cfg.earn || {};
    const map = {
      like_received: asNum(earn.likeReceived, 2),
      like_removed: -asNum(earn.likeReceived, 2),
      comment_received: asNum(earn.commentReceived, 3),
      comment_removed: -asNum(earn.commentReceived, 3),
      repost_received: asNum(earn.repostReceived, 4),
      repost_removed: -asNum(earn.repostReceived, 4),
      post_created: asNum(earn.post, 5),
      reel_created: asNum(earn.reel, 8),
      story_created: asNum(earn.story, 3),
    };
    if (!(kind in map)) throw new HttpsError('invalid-argument', 'Geçersiz kind');
    const delta = map[kind];
    if (!delta) return { ok: true, skipped: true };

    const beneficiary = kind.endsWith('_created') ? actorId : targetUid;
    // Toggle etkileşimler (like/repost): tek anahtar — geri alınca silinir ki tekrar verilebilsin.
    const toggleBase = kind
      .replace('_received', '')
      .replace('_removed', '');
    const isToggle = ['like', 'repost', 'comment'].includes(toggleBase);
    const addKey = isToggle
      ? `${toggleBase}_rx_${beneficiary}_${contentId}_${actorId}`.slice(0, 120)
      : `${kind}_${beneficiary}_${contentId}_${actorId}`.slice(0, 120);

    let balance = 0;
    await db.runTransaction(async (tx) => {
      if (isToggle && kind.endsWith('_removed')) {
        const ledgerRef = db.doc(`${LEDGER}/${addKey}`);
        const existing = await tx.get(ledgerRef);
        if (!existing.exists) {
          balance = (await getBalanceTx(tx, beneficiary)).balance;
          return;
        }
        const granted = asNum(existing.data().delta);
        tx.delete(ledgerRef);
        const { ref, balance: prev } = await getBalanceTx(tx, beneficiary);
        balance = prev - granted;
        tx.set(ref, {
          uid: beneficiary,
          balance,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
      }
      const res = await applyLedgerTx(tx, {
        uid: beneficiary,
        delta,
        reason: kind,
        idempotencyKey: addKey,
        meta: { actorId, contentId },
      });
      balance = res.balance;
    });
    return { ok: true, balance, delta, beneficiary };
  });

  const adminAdjustPoints = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const uid = sanitizePlainText(request.data?.uid, 80);
    const delta = Math.floor(asNum(request.data?.delta));
    const note = sanitizePlainText(request.data?.note, 200) || 'admin_adjust';
    if (!uid || !delta) throw new HttpsError('invalid-argument', 'uid ve delta gerekli');
    let balance = 0;
    await db.runTransaction(async (tx) => {
      const res = await applyLedgerTx(tx, {
        uid,
        delta,
        reason: 'admin_adjust',
        idempotencyKey: `admin_${uid}_${Date.now()}_${delta}`,
        meta: { by: request.auth.uid, note },
      });
      balance = res.balance;
    });
    return { ok: true, balance };
  });

  const adminSetEsimSecrets = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    try {
      await esim.setCredentials(db, {
        accessCode: request.data?.accessCode,
        secretKey: request.data?.secretKey,
        updatedBy: request.auth.uid,
      });
      return { ok: true };
    } catch (e) {
      throw new HttpsError('invalid-argument', e.message || 'Kayıt başarısız');
    }
  });

  const adminListEsimPackages = onCall({ region: 'europe-west1', timeoutSeconds: 60 }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const locationCode = sanitizePlainText(request.data?.locationCode || 'ALL', 12);

    const mapList = (obj) => (obj.packageList || []).map((p) => ({
      packageCode: p.packageCode,
      slug: p.slug,
      name: p.name,
      priceUsd: asNum(p.price) / 10000,
      volumeGb: asNum(p.volume) / 1073741824,
      duration: p.duration,
      durationUnit: p.durationUnit,
      location: p.location,
      supportTopUpType: p.supportTopUpType,
      dataType: p.dataType,
    }));

    const isEu30 = (p) => {
      const loc = String(p.location || '').split(',').map((s) => s.trim());
      const slug = String(p.slug || '');
      const name = String(p.name || '');
      return loc.includes('TR') &&
        (/EU-30/i.test(slug) || /Europe\(30/i.test(name) || /30\+ areas/i.test(name));
    };

    let list = [];
    if (locationCode === 'ALL' || locationCode === 'SHOP') {
      const [tr, rg] = await Promise.all([
        esim.listPackages(db, { locationCode: 'TR' }),
        esim.listPackages(db, { locationCode: '!RG' }),
      ]);
      const seen = new Set();
      for (const p of [...mapList(tr), ...mapList(rg)]) {
        if (seen.has(p.packageCode)) continue;
        seen.add(p.packageCode);
        const loc = String(p.location || '');
        if (loc === 'TR' || isEu30(p)) list.push(p);
      }
      list.sort((a, b) => a.priceUsd - b.priceUsd);
      return { items: list };
    }

    const fetchCode = locationCode === 'EU30' ? '!RG' : locationCode;
    const obj = await esim.listPackages(db, { locationCode: fetchCode });
    list = mapList(obj);
    const filtered = list.filter((p) => {
      const loc = String(p.location || '');
      if (locationCode === 'TR') return loc === 'TR';
      if (locationCode === 'EU30' || locationCode === '!RG') return isEu30(p);
      return loc === 'TR' || loc.split(',').includes('TR');
    });
    filtered.sort((a, b) => a.priceUsd - b.priceUsd);
    return { items: filtered.length ? filtered : list };
  });

  const adminSeedDefaultCatalog = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    await assertAdminPermission(request.auth.uid, 'manage_points');
    const seeds = [
      {
        id: 'esim_tr_1_7',
        type: 'esim',
        title: 'Türkiye 1GB · 7 Gün',
        description: 'Sadece TR. Top-up destekli.',
        pointsCost: 120,
        locationLabel: 'Türkiye',
        silSupurEligible: true,
        silSupurWeight: 6,
        sort: 10,
        esim: { packageCode: 'CKH265', slug: 'TR_1_7' },
      },
      {
        id: 'esim_tr_5_30',
        type: 'esim',
        title: 'Türkiye 5GB · 30 Gün',
        description: 'Kampüs için ideal TR paketi.',
        pointsCost: 450,
        locationLabel: 'Türkiye',
        silSupurEligible: true,
        silSupurWeight: 3,
        sort: 20,
        esim: { packageCode: 'CKH267', slug: 'TR_5_30' },
      },
      {
        id: 'esim_eu30_1_7',
        type: 'esim',
        title: 'Avrupa+TR 1GB · 7 Gün',
        description: '34 ülkede geçerli (TR dahil).',
        pointsCost: 220,
        locationLabel: 'Avrupa + Türkiye (EU-30)',
        silSupurEligible: true,
        silSupurWeight: 4,
        sort: 30,
        esim: { packageCode: 'PV048NCRG', slug: 'EU-30_1_7' },
      },
      {
        id: 'esim_eu30_5_30',
        type: 'esim',
        title: 'Avrupa+TR 5GB · 30 Gün',
        description: 'EU-30 bölgesi, TR dahil.',
        pointsCost: 980,
        locationLabel: 'Avrupa + Türkiye (EU-30)',
        silSupurEligible: false,
        silSupurWeight: 0,
        sort: 40,
        esim: { packageCode: 'P87F6RTKY', slug: 'EU-30_5_30' },
      },
    ];
    const batch = db.batch();
    for (const s of seeds) {
      batch.set(db.doc(`${CATALOG}/${s.id}`), {
        ...s,
        active: true,
        cashPriceTl: null,
        imageUrl: null,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await db.doc(CONFIG_PATH).set(mergeConfig({}), { merge: true });
    await batch.commit();
    return { ok: true, count: seeds.length };
  });

  /** Çarşamba (veya ayar günü) Sil Süpür bildirimi. */
  const silSupurNotifyTick = onSchedule(
    {
      region: 'europe-west1',
      schedule: 'every 60 minutes',
      timeZone: 'Europe/Istanbul',
    },
    async () => {
      const cfg = await readConfig();
      if (!(await pointsSystemLive(cfg)) || cfg.silSupur?.enabled === false) return;
      const parts = istanbulParts();
      if (parts.weekday !== asNum(cfg.silSupur.weekday, 3)) return;
      if (parts.hour !== asNum(cfg.silSupur.hour, 12)) return;
      // minute window 0-59 of that hour — run once via marker
      const markerId = `sil_supur_notify_${weekKeyIstanbul()}`;
      const marker = db.doc(`app_jobs/${markerId}`);
      const exists = await marker.get();
      if (exists.exists) return;
      await marker.set({ at: FieldValue.serverTimestamp() });

      const title = cfg.silSupur.notifyTitle || 'Sil Süpür başladı!';
      const body = cfg.silSupur.notifyBody || 'Bu haftanın hediyeleri seni bekliyor.';
      // Broadcast via existing users scan (bounded)
      const users = await db.collection('users')
        .select('email', 'firstName', 'fullName', 'fcmTokens')
        .limit(4000)
        .get();
      const link = '/points/sil-supur';
      let sent = 0;
      const dayName = ['Pazar', 'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi'][
        asNum(cfg.silSupur.weekday, 3)
      ];
      for (const u of users.docs) {
        try {
          const ud = u.data() || {};
          if (typeof dispatchPushToUser === 'function') {
            await dispatchPushToUser(u.id, {
              title,
              body,
              type: 'sil_supur',
              link,
              emoji: '🎰',
            });
            sent += 1;
          }
          await db.collection('users').doc(u.id).collection('notifications').add({
            title,
            body,
            emoji: '🎰',
            type: 'sil_supur',
            link,
            read: false,
            createdAt: new Date().toISOString(),
          });
          const email = String(ud.email || '').trim();
          if (email.includes('@') && !email.includes('@invalid.local') && typeof sendMail === 'function') {
            const name = ud.firstName || ud.fullName || '';
            await sendMail({
              to: email,
              subject: `KampüsteyimAPP · ${title}`,
              html: brandedEmail({
                title,
                greeting: name ? `Merhaba ${name},` : 'Merhaba,',
                bodyHtml: `<p>${escapeHtml(body)}</p><p>Sil Süpür her <b>${escapeHtml(dayName)}</b> açık. Uygulamada Puan Marketi → Sil Süpür’den çevirebilirsin.</p>`,
                ctaLabel: 'Sil Süpür’ü aç',
                ctaUrl: 'https://app.kampusteyim.app/points/sil-supur',
              }),
            });
          }
        } catch (_) {
          /* continue */
        }
      }
      await marker.set({ sent, at: FieldValue.serverTimestamp() }, { merge: true });
    },
  );

  const esimWebhook = onRequest({ region: 'europe-west1' }, async (req, res) => {
    try {
      const payload = req.body || {};
      const notifyType = payload.notifyType || payload.type;
      const content = payload.content || {};
      if (notifyType === 'CHECK_HEALTH') {
        res.status(200).json({ ok: true });
        return;
      }
      const orderNo = content.orderNo || '';
      if (orderNo) {
        const q = await db.collection(REWARDS).where('orderNo', '==', orderNo).limit(5).get();
        for (const doc of q.docs) {
          const patch = {
            esimStatus: content.esimStatus || content.orderStatus || null,
            smdpStatus: content.smdpStatus || null,
            updatedAt: FieldValue.serverTimestamp(),
            lastWebhook: notifyType,
          };
          if (content.iccid) patch.iccid = content.iccid;
          if (notifyType === 'ORDER_STATUS' && content.orderStatus === 'GOT_RESOURCE') {
            patch.status = 'ready';
          }
          if (content.esimStatus === 'IN_USE') patch.status = 'active';
          await doc.ref.set(patch, { merge: true });
        }
      }
      res.status(200).json({ ok: true });
    } catch (e) {
      res.status(500).json({ ok: false, error: String(e.message || e) });
    }
  });

  return {
    getPointsConfig,
    adminGetPointsConfig,
    adminSavePointsConfig,
    adminSetEsimSecrets,
    listPointsCatalog,
    upsertPointsCatalogItem,
    deletePointsCatalogItem,
    redeemPointsCatalogItem,
    playSilSupur,
    listMyRewards,
    refreshMyEsim,
    topupMyEsim,
    applyEngagementPoints,
    adminAdjustPoints,
    adminListEsimPackages,
    adminSeedDefaultCatalog,
    silSupurNotifyTick,
    esimWebhook,
  };
};
