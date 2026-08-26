/**
 * Market ürünleri — merch + etkinlik bileti (stok / bitiş tarihi).
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');

function sanitizePlainText(v, max = 200) {
  return String(v || '')
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

function slugPart(s) {
  return sanitizePlainText(s, 40)
    .toLowerCase()
    .replace(/[^a-z0-9ğüşıöç]+/gi, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 32) || 'bilet';
}

function productAvailability(p) {
  const sold = Number(p.soldCount) || 0;
  const stock = Number(p.stock);
  const endsRaw = p.saleEndsAt || p.startsAt || null;
  const ends = endsRaw ? new Date(endsRaw) : null;
  if (ends && !Number.isNaN(ends.getTime()) && ends.getTime() < Date.now()) {
    return {
      available: false,
      reason: 'expired',
      label: 'Stok bitti',
      remaining: 0,
    };
  }
  if (Number.isFinite(stock) && stock >= 0 && sold >= stock) {
    return {
      available: false,
      reason: 'sold_out',
      label: 'Stok bitti',
      remaining: 0,
    };
  }
  return {
    available: true,
    reason: null,
    label: null,
    remaining: Number.isFinite(stock) ? Math.max(0, stock - sold) : null,
  };
}

function publicProduct(doc) {
  const d = doc.data ? doc.data() : doc;
  const id = doc.id || d.id;
  const avail = productAvailability(d);
  return {
    id,
    type: d.type || 'merch',
    sku: d.sku || id,
    name: d.name || '',
    short: d.short || '',
    amount: Number(d.amount) || 0,
    sizes: Array.isArray(d.sizes) ? d.sizes : [],
    stock: Number.isFinite(Number(d.stock)) ? Number(d.stock) : null,
    soldCount: Number(d.soldCount) || 0,
    remaining: avail.remaining,
    available: d.type === 'plus' ? true : avail.available,
    statusLabel: d.type === 'plus' ? null : (avail.available ? null : avail.label),
    saleEndsAt: d.saleEndsAt || null,
    eventId: d.eventId || null,
    tierLabel: d.tierLabel || null,
    eventTitle: d.eventTitle || null,
    startsAt: d.startsAt || null,
    city: d.city || '',
    imageUrl: d.imageUrl || null,
    active: d.active !== false,
    plusDays: Number.isFinite(Number(d.plusDays)) ? Number(d.plusDays) : null,
    installmentsEnabled: d.installmentsEnabled !== false,
    cashPriceInstallments: d.cashPriceInstallments === true,
  };
}

module.exports = function createMarketProducts({
  db,
  assertPlatformAdmin,
}) {
  const COL = 'market_products';

  async function upsertEventTicketProduct({ eventId, event, tier }) {
    const label = sanitizePlainText(tier.label || 'Bilet', 80) || 'Bilet';
    const id = `evt_${sanitizePlainText(eventId, 40)}_${slugPart(label)}`;
    const stockRaw = Number(tier.stock);
    const stock = Number.isFinite(stockRaw) && stockRaw >= 0
      ? Math.floor(stockRaw)
      : Math.max(0, Number(event.capacity) || 0);
    const saleEndsAt =
      tier.saleEndsAt ||
      event.applicationDeadline ||
      event.startsAt ||
      null;
    const payload = {
      id,
      type: 'event_ticket',
      sku: id,
      name: `${sanitizePlainText(event.title || 'Etkinlik', 80)} · ${label}`,
      short: sanitizePlainText(event.city || event.location || '', 120),
      amount: Number(tier.amount) || 0,
      stock,
      soldCount: Number(tier.soldCount) || 0,
      saleEndsAt: saleEndsAt ? String(saleEndsAt) : null,
      eventId: String(eventId),
      tierLabel: label,
      eventTitle: sanitizePlainText(event.title || '', 120),
      startsAt: event.startsAt ? String(event.startsAt) : null,
      city: sanitizePlainText(event.city || '', 80),
      active: String(event.status || 'approved') === 'approved',
      updatedAt: new Date().toISOString(),
    };
    await db.collection(COL).doc(id).set(payload, { merge: true });
    return id;
  }

  async function syncEventTicketsForEvent(eventId, event) {
    const tiers = Array.isArray(event?.priceTiers) ? event.priceTiers : [];
    const ids = [];
    for (const tier of tiers) {
      if (!(Number(tier?.amount) > 0)) continue;
      ids.push(await upsertEventTicketProduct({ eventId, event, tier }));
    }
    return ids;
  }

  async function listPublicEventTickets() {
    const snap = await db
      .collection(COL)
      .where('type', '==', 'event_ticket')
      .where('active', '==', true)
      .limit(100)
      .get()
      .catch(async () => {
        // index yoksa fallback
        const all = await db.collection(COL).where('type', '==', 'event_ticket').limit(100).get();
        return all;
      });
    return snap.docs
      .map((d) => publicProduct(d))
      .filter((p) => p.active !== false)
      .sort((a, b) => String(a.startsAt || '').localeCompare(String(b.startsAt || '')));
  }

  async function assertEventTicketAvailable(eventId, tierLabel) {
    const q = await db
      .collection(COL)
      .where('eventId', '==', String(eventId))
      .where('tierLabel', '==', String(tierLabel || 'Bilet'))
      .limit(1)
      .get();
    let doc = q.empty ? null : q.docs[0];
    if (!doc) {
      // id tabanlı fallback
      const id = `evt_${eventId}_${slugPart(tierLabel || 'Bilet')}`;
      const snap = await db.collection(COL).doc(id).get();
      if (snap.exists) doc = snap;
    }
    if (!doc || !doc.exists) {
      // Ürün henüz yoksa etkinlikten kontrol (geriye uyum)
      return { ok: true, productId: null };
    }
    const p = doc.data() || {};
    const avail = productAvailability(p);
    if (!avail.available) {
      throw new HttpsError('failed-precondition', avail.label || 'Stok bitti');
    }
    return { ok: true, productId: doc.id, remaining: avail.remaining };
  }

  async function incrementTicketSold(eventId, tierLabel) {
    const idGuess = `evt_${eventId}_${slugPart(tierLabel || 'Bilet')}`;
    const ref = db.collection(COL).doc(idGuess);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const d = snap.data() || {};
      const sold = (Number(d.soldCount) || 0) + 1;
      const stock = Number(d.stock);
      if (Number.isFinite(stock) && sold > stock) {
        throw new HttpsError('failed-precondition', 'Stok bitti');
      }
      tx.set(
        ref,
        { soldCount: sold, updatedAt: new Date().toISOString() },
        { merge: true },
      );
    });
    // Event tier soldCount
    const evRef = db.collection('events').doc(eventId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(evRef);
      if (!snap.exists) return;
      const ev = snap.data() || {};
      const tiers = Array.isArray(ev.priceTiers) ? [...ev.priceTiers] : [];
      const i = tiers.findIndex(
        (t) => String(t.label || '') === String(tierLabel || ''),
      );
      if (i < 0) return;
      tiers[i] = {
        ...tiers[i],
        soldCount: (Number(tiers[i].soldCount) || 0) + 1,
      };
      tx.set(evRef, { priceTiers: tiers, updatedAt: new Date().toISOString() }, { merge: true });
    });
  }

  async function seedDefaultMerchIfEmpty() {
    const existing = await db.collection(COL).where('type', '==', 'merch').limit(1).get();
    if (!existing.empty) return 0;
    const defaults = [
      {
        id: 'tshirt',
        sku: 'tshirt',
        name: 'Logo Tişört',
        amount: 349,
        sizes: ['S', 'M', 'L', 'XL'],
        short: 'Beyaz pamuk · göğüs logo baskı · unisex',
        stock: 200,
      },
      {
        id: 'hoodie',
        sku: 'hoodie',
        name: 'Campus Hoodie',
        amount: 799,
        sizes: ['S', 'M', 'L', 'XL'],
        short: 'Siyah sweatshirt · büyük logo · kışlık',
        stock: 100,
      },
      {
        id: 'cap',
        sku: 'cap',
        name: 'Navy Şapka',
        amount: 249,
        sizes: ['Tek beden'],
        short: 'Lacivert baseball · önde logo · ayarlı',
        stock: 150,
      },
      {
        id: 'tote',
        sku: 'tote',
        name: 'Kampüs Tote',
        amount: 199,
        sizes: ['Tek beden'],
        short: 'Bej kanvas · logo baskı · ders / stand',
        stock: 200,
      },
    ];
    const now = new Date().toISOString();
    const batch = db.batch();
    for (const m of defaults) {
      batch.set(
        db.collection(COL).doc(m.id),
        {
          ...m,
          type: 'merch',
          soldCount: 0,
          active: true,
          updatedAt: now,
          createdAt: now,
        },
        { merge: true },
      );
    }
    await batch.commit();
    return defaults.length;
  }

  async function listPublicMerchProducts() {
    await seedDefaultMerchIfEmpty().catch((e) =>
      console.error('[seedDefaultMerch]', e),
    );
    const snap = await db
      .collection(COL)
      .where('type', '==', 'merch')
      .limit(100)
      .get()
      .catch(async () => db.collection(COL).limit(100).get());
    return snap.docs
      .map((d) => publicProduct(d))
      .filter((p) => p.type === 'merch' && p.active !== false && p.available);
  }

  async function resolveMerchBySku(sku) {
    const id = sanitizePlainText(sku, 64);
    if (!id) return null;
    let snap = await db.collection(COL).doc(id).get();
    if (!snap.exists) {
      const q = await db
        .collection(COL)
        .where('sku', '==', id)
        .limit(1)
        .get();
      if (!q.empty) snap = q.docs[0];
    }
    if (!snap.exists) return null;
    const p = publicProduct(snap);
    if (p.type !== 'merch' || p.active === false) return null;
    return {
      sku: p.sku || p.id,
      name: p.name,
      amount: p.amount,
      sizes: p.sizes?.length ? p.sizes : ['Tek beden'],
      short: p.short || '',
      installmentsEnabled: d.installmentsEnabled !== false,
      cashPriceInstallments: d.cashPriceInstallments === true,
    };
  }

  async function ensurePlusProduct() {
    const ref = db.collection(COL).doc('plus');
    const snap = await ref.get();
    const paySnap = await db.doc('app_config/payments').get();
    const pay = paySnap.exists ? paySnap.data() || {} : {};
    const now = new Date().toISOString();
    if (snap.exists) {
      // Eksik alanları payments’tan doldur
      const d = snap.data() || {};
      const patch = { updatedAt: now };
      if (!(Number(d.amount) > 0) && Number(pay.plusAmount) > 0) {
        patch.amount = Number(pay.plusAmount);
      }
      if (!d.name && pay.plusProductName) {
        patch.name = String(pay.plusProductName);
      }
      if (!(Number(d.plusDays) > 0) && Number(pay.plusDays) > 0) {
        patch.plusDays = Number(pay.plusDays) || 30;
      }
      if (Object.keys(patch).length > 1) await ref.set(patch, { merge: true });
      return;
    }
    await ref.set(
      {
        id: 'plus',
        type: 'plus',
        sku: 'plus',
        name: String(pay.plusProductName || 'KampüsteyimPlus').trim(),
        short: 'Dijital üyelik · aylık planlar',
        amount: Number(pay.plusAmount) > 0 ? Number(pay.plusAmount) : 99,
        plusDays: Number(pay.plusDays) > 0 ? Number(pay.plusDays) : 30,
        stock: null,
        soldCount: 0,
        sizes: [],
        active: true,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
  }

  const listMarketProducts = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    try {
      await seedDefaultMerchIfEmpty();
      await ensurePlusProduct();
    } catch (e) {
      console.error('[listMarketProducts] seed', e);
    }
    const snap = await db.collection(COL).orderBy('updatedAt', 'desc').limit(200).get().catch(
      async () => db.collection(COL).limit(200).get(),
    );
    return {
      ok: true,
      items: snap.docs.map((d) => publicProduct(d)),
    };
  });

  const upsertMarketProduct = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const data = request.data || {};
    const type = sanitizePlainText(data.type || 'merch', 20) || 'merch';
    if (!['merch', 'event_ticket', 'plus'].includes(type)) {
      throw new HttpsError('invalid-argument', 'Geçersiz ürün tipi');
    }
    let id = sanitizePlainText(data.id || data.sku || '', 64);
    if (type === 'plus') {
      id = 'plus';
    } else if (!id) {
      id =
        type === 'event_ticket'
          ? `evt_${Date.now()}`
          : `merch_${Date.now()}`;
    }
    const amount = Number(data.amount);
    if (!(amount > 0)) throw new HttpsError('invalid-argument', 'Tutar gerekli');
    const stock = Number(data.stock);
    const plusDaysRaw = Number(data.plusDays);
    const plusDays =
      type === 'plus'
        ? Number.isFinite(plusDaysRaw) && plusDaysRaw > 0
          ? Math.floor(plusDaysRaw)
          : 30
        : null;
    const payload = {
      id,
      type,
      sku: type === 'plus' ? 'plus' : sanitizePlainText(data.sku || id, 64) || id,
      name:
        sanitizePlainText(data.name || '', 120) ||
        (type === 'plus' ? 'KampüsteyimPlus' : 'Ürün'),
      short: sanitizePlainText(data.short || '', 200),
      amount,
      sizes: Array.isArray(data.sizes)
        ? data.sizes.map((s) => sanitizePlainText(s, 20)).filter(Boolean)
        : type === 'merch'
          ? ['S', 'M', 'L', 'XL']
          : [],
      stock:
        type === 'plus'
          ? null
          : Number.isFinite(stock) && stock >= 0
            ? Math.floor(stock)
            : null,
      soldCount: Number(data.soldCount) || 0,
      saleEndsAt: data.saleEndsAt ? String(data.saleEndsAt) : null,
      eventId: sanitizePlainText(data.eventId || '', 80) || null,
      tierLabel: sanitizePlainText(data.tierLabel || '', 80) || null,
      eventTitle: sanitizePlainText(data.eventTitle || '', 120) || null,
      startsAt: data.startsAt ? String(data.startsAt) : null,
      city: sanitizePlainText(data.city || '', 80),
      imageUrl: sanitizePlainText(data.imageUrl || '', 400) || null,
      active: data.active !== false,
      updatedAt: new Date().toISOString(),
      updatedBy: request.auth.uid,
    };
    if (type === 'plus') {
      payload.plusDays = plusDays;
      payload.short =
        payload.short ||
        `Dijital üyelik · 1 ay = ${plusDays} gün`;
    }
    if (typeof data.installmentsEnabled === 'boolean') {
      payload.installmentsEnabled = data.installmentsEnabled;
    } else if (type === 'plus' || type === 'merch') {
      payload.installmentsEnabled = data.installmentsEnabled !== false;
    }
    if (typeof data.cashPriceInstallments === 'boolean') {
      payload.cashPriceInstallments = data.cashPriceInstallments;
    }
    if (type === 'event_ticket' && !payload.eventId) {
      throw new HttpsError('invalid-argument', 'Etkinlik bileti için eventId gerekli');
    }
    await db.collection(COL).doc(id).set(payload, { merge: true });
    // Plus ürünü → ödeme ayarlarıyla senkron
    if (type === 'plus') {
      await db.doc('app_config/payments').set(
        {
          plusProductName: payload.name,
          plusAmount: payload.amount,
          plusDays: payload.plusDays,
          updatedAt: new Date().toISOString(),
          updatedBy: request.auth.uid,
        },
        { merge: true },
      );
    }
    return { ok: true, id, item: publicProduct({ id, data: () => payload }) };
  });

  const deleteMarketProduct = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const id = sanitizePlainText(request.data?.id || '', 64);
    if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
    if (id === 'plus') {
      throw new HttpsError(
        'failed-precondition',
        'KampüsteyimPlus ürünü silinemez; düzenleyebilirsin',
      );
    }
    await db.collection(COL).doc(id).delete();
    return { ok: true };
  });

  /** Etkinlik kaydı sonrası market ürününü senkronla (organizer / admin). */
  const syncEventMarketTickets = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    const eventId = sanitizePlainText(request.data?.eventId || '', 80);
    if (!eventId) throw new HttpsError('invalid-argument', 'eventId gerekli');
    const snap = await db.collection('events').doc(eventId).get();
    if (!snap.exists) throw new HttpsError('not-found', 'Etkinlik yok');
    const event = snap.data() || {};
    const uid = request.auth.uid;
    const isOrg = String(event.organizerCompanyId || '') === uid;
    if (!isOrg) await assertPlatformAdmin(uid);
    const ids = await syncEventTicketsForEvent(eventId, event);
    return { ok: true, productIds: ids };
  });

  return {
    listMarketProducts,
    upsertMarketProduct,
    deleteMarketProduct,
    syncEventMarketTickets,
    syncEventTicketsForEvent,
    listPublicEventTickets,
    assertEventTicketAvailable,
    incrementTicketSold,
    listPublicMerchProducts,
    resolveMerchBySku,
    seedDefaultMerchIfEmpty,
    productAvailability,
    publicProduct,
  };
};
