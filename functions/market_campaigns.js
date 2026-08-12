/**
 * Market / Plus kampanya kodları ve üye çekleri.
 * Koleksiyon: market_campaigns
 * Kullanım: market_campaign_uses/{campaignId_uid_n}
 */
function marketCampaignsModule({
  db,
  onCall,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  FieldValue,
}) {
  const COL = 'market_campaigns';
  const USES = 'market_campaign_uses';

  function nowIso() {
    return new Date().toISOString();
  }

  function normalizeCode(raw) {
    return sanitizePlainText(raw || '', 32)
      .toUpperCase()
      .replace(/\s+/g, '');
  }

  function publicCampaignView(d, id) {
    return {
      id,
      code: d.code,
      label: d.label || d.code,
      type: d.type === 'fixed' ? 'fixed' : 'percent',
      value: Number(d.value) || 0,
      appliesTo: Array.isArray(d.appliesTo) ? d.appliesTo : ['plus', 'merch'],
      maxUses: d.maxUses == null ? null : Number(d.maxUses),
      usedCount: Number(d.usedCount || 0),
      maxUsesPerUser: Number(d.maxUsesPerUser || 1),
      minAmount: Number(d.minAmount || 0),
      expiresAt: d.expiresAt || null,
      active: d.active !== false,
      assignedOnly: Array.isArray(d.assignedUserIds) && d.assignedUserIds.length > 0,
      assignedCount: Array.isArray(d.assignedUserIds) ? d.assignedUserIds.length : 0,
      createdAt: d.createdAt || null,
    };
  }

  async function findCampaignByCode(code) {
    const q = await db
      .collection(COL)
      .where('code', '==', code)
      .limit(1)
      .get();
    if (q.empty) return null;
    return { id: q.docs[0].id, ref: q.docs[0].ref, data: q.docs[0].data() || {} };
  }

  async function countUserUses(campaignId, uid) {
    const q = await db
      .collection(USES)
      .where('campaignId', '==', campaignId)
      .where('uid', '==', uid)
      .limit(50)
      .get();
    return q.size;
  }

  /**
   * @returns {{ amount, discountAmount, campaignId, code, label, type, value }}
   */
  async function applyMarketCampaign({ code, product, baseAmount, uid }) {
    const codeU = normalizeCode(code);
    if (!codeU) {
      return {
        amount: baseAmount,
        discountAmount: 0,
        campaignId: null,
        code: null,
      };
    }
    const found = await findCampaignByCode(codeU);
    if (!found) throw new HttpsError('not-found', 'Kampanya kodu geçersiz');
    const d = found.data;
    if (d.active === false) {
      throw new HttpsError('failed-precondition', 'Kampanya pasif');
    }
    if (d.expiresAt) {
      const exp = Date.parse(String(d.expiresAt));
      if (Number.isFinite(exp) && exp < Date.now()) {
        throw new HttpsError('failed-precondition', 'Kampanya süresi dolmuş');
      }
    }
    const applies = Array.isArray(d.appliesTo) ? d.appliesTo : ['plus', 'merch'];
    if (!applies.includes(product)) {
      throw new HttpsError(
        'failed-precondition',
        'Bu kod bu ürün için geçerli değil',
      );
    }
    const assigned = Array.isArray(d.assignedUserIds) ? d.assignedUserIds : [];
    if (assigned.length > 0 && !assigned.includes(uid)) {
      throw new HttpsError(
        'permission-denied',
        'Bu kod sana tanımlı değil',
      );
    }
    const maxUses = d.maxUses == null ? null : Number(d.maxUses);
    const used = Number(d.usedCount || 0);
    if (maxUses != null && maxUses > 0 && used >= maxUses) {
      throw new HttpsError('resource-exhausted', 'Kampanya kotası doldu');
    }
    const perUser = Number(d.maxUsesPerUser || 1);
    if (perUser > 0) {
      const mine = await countUserUses(found.id, uid);
      if (mine >= perUser) {
        throw new HttpsError(
          'resource-exhausted',
          'Bu kodu daha önce kullandın',
        );
      }
    }
    const minAmount = Number(d.minAmount || 0);
    if (minAmount > 0 && baseAmount < minAmount) {
      throw new HttpsError(
        'failed-precondition',
        `Minimum tutar ${minAmount} TL`,
      );
    }

    let amount = baseAmount;
    const value = Number(d.value) || 0;
    if (d.type === 'fixed') {
      amount = Math.max(0, Math.round((baseAmount - value) * 100) / 100);
    } else {
      amount = Math.max(
        0,
        Math.round(baseAmount * (1 - value / 100) * 100) / 100,
      );
    }
    const discountAmount = Math.round((baseAmount - amount) * 100) / 100;
    return {
      amount,
      discountAmount,
      campaignId: found.id,
      code: d.code,
      label: d.label || d.code,
      type: d.type === 'fixed' ? 'fixed' : 'percent',
      value,
    };
  }

  async function recordCampaignUse({ campaignId, uid, orderId, code }) {
    if (!campaignId || !uid) return;
    const useRef = db.collection(USES).doc();
    await useRef.set({
      id: useRef.id,
      campaignId,
      uid,
      orderId: orderId || null,
      code: code || null,
      createdAt: nowIso(),
    });
    await db.collection(COL).doc(campaignId).set(
      {
        usedCount: FieldValue.increment(1),
        updatedAt: nowIso(),
      },
      { merge: true },
    );
  }

  const upsertMarketCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const data = request.data || {};
      const id = String(data.id || '').trim();
      const code = normalizeCode(data.code);
      if (!code) throw new HttpsError('invalid-argument', 'Kod gerekli');
      const type = String(data.type || 'percent') === 'fixed' ? 'fixed' : 'percent';
      const value = Number(data.value);
      if (!(value > 0)) throw new HttpsError('invalid-argument', 'Değer > 0 olmalı');
      if (type === 'percent' && value > 100) {
        throw new HttpsError('invalid-argument', 'Yüzde en fazla 100');
      }
      let appliesTo = Array.isArray(data.appliesTo)
        ? data.appliesTo.map((x) => String(x).toLowerCase()).filter((x) =>
            ['plus', 'merch'].includes(x),
          )
        : ['plus', 'merch'];
      if (!appliesTo.length) appliesTo = ['plus', 'merch'];

      const payload = {
        code,
        label: sanitizePlainText(data.label || code, 80) || code,
        type,
        value,
        appliesTo,
        maxUses:
          data.maxUses == null || data.maxUses === ''
            ? null
            : Math.max(0, Math.floor(Number(data.maxUses) || 0)) || null,
        maxUsesPerUser: Math.max(
          0,
          Math.floor(Number(data.maxUsesPerUser ?? 1) || 1),
        ),
        minAmount: Math.max(0, Number(data.minAmount) || 0),
        expiresAt: data.expiresAt
          ? sanitizePlainText(data.expiresAt, 40)
          : null,
        active: data.active !== false,
        updatedAt: nowIso(),
        updatedBy: request.auth.uid,
      };

      if (id) {
        const ref = db.collection(COL).doc(id);
        const snap = await ref.get();
        if (!snap.exists) throw new HttpsError('not-found', 'Kampanya yok');
        // Kod değişiyorsa çakışma kontrolü
        if (snap.data()?.code !== code) {
          const other = await findCampaignByCode(code);
          if (other && other.id !== id) {
            throw new HttpsError('already-exists', 'Bu kod zaten var');
          }
        }
        await ref.set(payload, { merge: true });
        const fresh = await ref.get();
        return { ok: true, campaign: publicCampaignView(fresh.data() || {}, id) };
      }

      const existing = await findCampaignByCode(code);
      if (existing) {
        throw new HttpsError('already-exists', 'Bu kod zaten var');
      }
      const ref = db.collection(COL).doc();
      await ref.set({
        id: ref.id,
        ...payload,
        usedCount: 0,
        assignedUserIds: [],
        createdAt: nowIso(),
        createdBy: request.auth.uid,
      });
      return { ok: true, campaign: publicCampaignView(payload, ref.id) };
    },
  );

  const listMarketCampaigns = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const snap = await db.collection(COL).limit(120).get();
      const items = snap.docs
        .map((d) => publicCampaignView(d.data() || {}, d.id))
        .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
      return { ok: true, items };
    },
  );

  const assignMarketCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const campaignId = String(request.data?.campaignId || '').trim();
      const targetUid = String(request.data?.uid || '').trim();
      const remove = request.data?.remove === true;
      if (!campaignId || !targetUid) {
        throw new HttpsError('invalid-argument', 'campaignId ve uid gerekli');
      }
      const ref = db.collection(COL).doc(campaignId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Kampanya yok');
      await ref.set(
        {
          assignedUserIds: remove
            ? FieldValue.arrayRemove(targetUid)
            : FieldValue.arrayUnion(targetUid),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return { ok: true };
    },
  );

  const setMarketCampaignActive = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const campaignId = String(request.data?.campaignId || '').trim();
      if (!campaignId) throw new HttpsError('invalid-argument', 'campaignId gerekli');
      await db.collection(COL).doc(campaignId).set(
        {
          active: request.data?.active !== false,
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return { ok: true };
    },
  );

  /** Üyenin kendine tanımlı / genel aktif kodları (preview için) */
  const getMyMarketCampaigns = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const snap = await db
        .collection(COL)
        .where('active', '==', true)
        .limit(80)
        .get();
      const mine = [];
      for (const doc of snap.docs) {
        const d = doc.data() || {};
        const assigned = Array.isArray(d.assignedUserIds) ? d.assignedUserIds : [];
        const isMine = assigned.includes(uid);
        const isPublic = assigned.length === 0;
        if (!isMine && !isPublic) continue;
        if (d.expiresAt) {
          const exp = Date.parse(String(d.expiresAt));
          if (Number.isFinite(exp) && exp < Date.now()) continue;
        }
        // Public kodları "Kodlarım"da gösterme — sadece atanmış çekler
        if (!isMine) continue;
        const uses = await countUserUses(doc.id, uid);
        const perUser = Number(d.maxUsesPerUser || 1);
        mine.push({
          ...publicCampaignView(d, doc.id),
          myUses: uses,
          remainingForMe: perUser > 0 ? Math.max(0, perUser - uses) : null,
          assignedToMe: true,
        });
      }
      return { ok: true, items: mine };
    },
  );

  const previewMarketCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const code = normalizeCode(request.data?.code);
      const product = sanitizePlainText(request.data?.product || 'plus', 20);
      const baseAmount = Number(request.data?.amount);
      if (!code || !(baseAmount >= 0)) {
        throw new HttpsError('invalid-argument', 'code ve amount gerekli');
      }
      const result = await applyMarketCampaign({
        code,
        product,
        baseAmount,
        uid: request.auth.uid,
      });
      return { ok: true, ...result };
    },
  );

  return {
    applyMarketCampaign,
    recordCampaignUse,
    upsertMarketCampaign,
    listMarketCampaigns,
    assignMarketCampaign,
    setMarketCampaignActive,
    getMyMarketCampaigns,
    previewMarketCampaign,
  };
}

module.exports = { marketCampaignsModule };
