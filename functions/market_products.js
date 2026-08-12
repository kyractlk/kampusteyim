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
    available: avail.available,
    statusLabel: avail.available ? null : avail.label,
    saleEndsAt: d.saleEndsAt || null,
    eventId: d.eventId || null,
    tierLabel: d.tierLabel || null,
    eventTitle: d.eventTitle || null,
    startsAt: d.startsAt || null,
    city: d.city || '',
    imageUrl: d.imageUrl || null,
    active: d.active !== false,
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

  const listMarketProducts = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
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
    if (!['merch', 'event_ticket'].includes(type)) {
      throw new HttpsError('invalid-argument', 'Geçersiz ürün tipi');
    }
    let id = sanitizePlainText(data.id || data.sku || '', 64);
    if (!id) {
      id =
        type === 'event_ticket'
          ? `evt_${Date.now()}`
          : `merch_${Date.now()}`;
    }
    const amount = Number(data.amount);
    if (!(amount > 0)) throw new HttpsError('invalid-argument', 'Tutar gerekli');
    const stock = Number(data.stock);
    const payload = {
      id,
      type,
      sku: sanitizePlainText(data.sku || id, 64) || id,
      name: sanitizePlainText(data.name || '', 120) || 'Ürün',
      short: sanitizePlainText(data.short || '', 200),
      amount,
      sizes: Array.isArray(data.sizes)
        ? data.sizes.map((s) => sanitizePlainText(s, 20)).filter(Boolean)
        : type === 'merch'
          ? ['S', 'M', 'L', 'XL']
          : [],
      stock: Number.isFinite(stock) && stock >= 0 ? Math.floor(stock) : null,
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
    if (type === 'event_ticket' && !payload.eventId) {
      throw new HttpsError('invalid-argument', 'Etkinlik bileti için eventId gerekli');
    }
    await db.collection(COL).doc(id).set(payload, { merge: true });
    return { ok: true, id, item: publicProduct({ id, data: () => payload }) };
  });

  const deleteMarketProduct = onCall({ region: 'europe-west1' }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
    await assertPlatformAdmin(request.auth.uid);
    const id = sanitizePlainText(request.data?.id || '', 64);
    if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
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
    productAvailability,
    publicProduct,
  };
};
