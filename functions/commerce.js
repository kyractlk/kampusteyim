/**
 * Organizatör cüzdanı, etkinlik biletleri, çekim, reklam, indirim.
 */
const crypto = require('crypto');

function commerceModule({
  db,
  onCall,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  FieldValue,
}) {
  const TICKETS = 'event_tickets';
  const WITHDRAWALS = 'withdrawal_requests';
  const ADS = 'ad_campaigns';
  const DISCOUNTS = 'event_discounts';
  const LEDGER = 'organizer_ledger';

  function nowIso() {
    return new Date().toISOString();
  }

  async function getOrganizerSettings(uid) {
    const snap = await db.collection('users').doc(uid).get();
    const u = snap.data() || {};
    const s = u.organizerSettings || {};
    return {
      user: u,
      payoutIban: String(s.payoutIban || '').trim(),
      payoutIbanHolder: String(s.payoutIbanHolder || '').trim(),
      payoutBank: String(s.payoutBank || '').trim(),
      commissionPercent: Number(
        s.commissionPercent != null ? s.commissionPercent : 10,
      ),
      minWithdrawal: Number(s.minWithdrawal != null ? s.minWithdrawal : 500),
      balance: Number((u.organizerWallet || {}).balance || 0),
      isEventOrganizer: u.isEventOrganizer === true,
      isCompany: u.role === 'company',
      name: String(u.companyName || u.displayName || u.username || uid),
    };
  }

  /** Ödeme onayınca: bilet + uygulama + organizatör bakiyesi */
  async function fulfillEventOrder(order) {
    if (!order || order.product !== 'event') return { ok: false };
    if (order.fulfilledAt) return { ok: true, already: true };

    const eventId = String(order.meta?.eventId || order.eventId || '').trim();
    const tierLabel = String(order.meta?.tierLabel || order.tierLabel || '').trim();
    const discountCode = String(
      order.meta?.discountCode || order.discountCode || '',
    )
      .trim()
      .toUpperCase();
    const uid = String(order.uid || '').trim();
    if (!eventId || !uid) {
      console.error('[fulfillEvent] missing eventId/uid', order.id);
      return { ok: false };
    }

    // Satın alan hesap = katılımcı hesap (zorunlu)
    if (order.meta?.attendeeUid && order.meta.attendeeUid !== uid) {
      console.error('[fulfillEvent] attendee mismatch', order.id);
      return { ok: false };
    }

    const eventRef = db.collection('events').doc(eventId);
    const eventSnap = await eventRef.get();
    if (!eventSnap.exists) return { ok: false };
    const event = eventSnap.data() || {};
    const organizerId = String(event.organizerCompanyId || '').trim();
    if (!organizerId) {
      console.error('[fulfillEvent] no organizer', eventId);
      return { ok: false };
    }

    const amount = Number(order.amount) || 0;
    const org = await getOrganizerSettings(organizerId);
    const commissionPct = Math.max(0, Math.min(100, org.commissionPercent));
    const commission = Math.round(amount * (commissionPct / 100) * 100) / 100;
    const net = Math.round((amount - commission) * 100) / 100;

    const ticketRef = db.collection(TICKETS).doc();
    const ticket = {
      id: ticketRef.id,
      eventId,
      eventTitle: String(event.title || ''),
      uid, // bilet sahibi = ödeyen
      payerUid: uid,
      userEmail: String(order.email || ''),
      userName: String(order.meta?.userName || ''),
      orderId: order.id,
      tierLabel,
      amountPaid: amount,
      discountCode: discountCode || null,
      status: 'active',
      organizerId,
      city: String(event.city || ''),
      startsAt: event.startsAt || null,
      createdAt: nowIso(),
      ibanReference: order.ibanReference || null,
    };
    await ticketRef.set(ticket);

    // Başvuru / kontenjan
    const apps = Array.isArray(event.applications) ? [...event.applications] : [];
    const existingIdx = apps.findIndex((a) => a && a.userId === uid);
    const appRow = {
      userId: uid,
      userName: ticket.userName || ticket.userEmail || uid,
      createdAt: nowIso(),
      status: 'approved',
      ticketId: ticketRef.id,
      paid: true,
      amountPaid: amount,
    };
    if (existingIdx >= 0) apps[existingIdx] = { ...apps[existingIdx], ...appRow };
    else apps.push(appRow);
    await eventRef.set(
      {
        applications: apps,
        applicantCount: apps.length,
        updatedAt: nowIso(),
      },
      { merge: true },
    );

    // İndirim kullanım sayacı
    if (discountCode) {
      const dq = await db
        .collection(DISCOUNTS)
        .where('eventId', '==', eventId)
        .where('code', '==', discountCode)
        .limit(1)
        .get();
      if (!dq.empty) {
        await dq.docs[0].ref.set(
          { usedCount: FieldValue.increment(1), updatedAt: nowIso() },
          { merge: true },
        );
      }
    }

    // Organizatör bakiyesi + ledger
    if (net > 0) {
      await db.collection('users').doc(organizerId).set(
        {
          'organizerWallet.balance': FieldValue.increment(net),
          'organizerWallet.currency': 'TRY',
          'organizerWallet.updatedAt': nowIso(),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      await db.collection(LEDGER).add({
        organizerId,
        type: 'sale',
        eventId,
        ticketId: ticketRef.id,
        orderId: order.id,
        gross: amount,
        commission,
        commissionPercent: commissionPct,
        net,
        buyerUid: uid,
        createdAt: nowIso(),
      });
    }

    await db.collection('payment_orders').doc(order.id).set(
      {
        fulfilledAt: nowIso(),
        ticketId: ticketRef.id,
        organizerId,
        commission,
        netToOrganizer: net,
        updatedAt: nowIso(),
      },
      { merge: true },
    );

    return { ok: true, ticketId: ticketRef.id, net, commission };
  }

  const saveOrganizerPayoutIban = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const org = await getOrganizerSettings(uid);
      if (!org.isCompany) {
        throw new HttpsError('permission-denied', 'Sadece firma hesapları');
      }
      const iban = sanitizePlainText(request.data?.payoutIban || '', 64);
      const holder = sanitizePlainText(request.data?.payoutIbanHolder || '', 120);
      const bank = sanitizePlainText(request.data?.payoutBank || '', 120);
      if (!iban || !holder) {
        throw new HttpsError('invalid-argument', 'IBAN ve hesap sahibi gerekli');
      }
      await db.collection('users').doc(uid).set(
        {
          'organizerSettings.payoutIban': iban,
          'organizerSettings.payoutIbanHolder': holder,
          'organizerSettings.payoutBank': bank,
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return { ok: true };
    },
  );

  const adminSetOrganizerCommerce = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const rawKey = String(
        request.data?.companyId || request.data?.companyKey || '',
      ).trim();
      if (!rawKey) throw new HttpsError('invalid-argument', 'companyId gerekli');

      let companyId = rawKey;
      let userSnap = await db.collection('users').doc(rawKey).get();
      if (!userSnap.exists && rawKey.includes('@')) {
        const q = await db
          .collection('users')
          .where('email', '==', rawKey.toLowerCase())
          .limit(1)
          .get();
        if (!q.empty) {
          userSnap = q.docs[0];
          companyId = userSnap.id;
        }
      }
      if (!userSnap.exists) {
        const qName = rawKey.toLowerCase();
        const scan = await db.collection('users').limit(400).get();
        const hit = scan.docs.find((d) => {
          const m = d.data() || {};
          const name = `${m.firstName || ''} ${m.lastName || ''} ${m.displayName || ''} ${m.companyName || ''}`
            .trim()
            .toLowerCase();
          return (
            name.includes(qName) &&
            (m.role === 'company' ||
              m.isCompany === true ||
              m.role === 'community' ||
              m.isCommunity === true)
          );
        });
        if (hit) {
          userSnap = hit;
          companyId = hit.id;
        }
      }
      if (!userSnap.exists) {
        throw new HttpsError('not-found', 'Firma / org bulunamadı');
      }

      const patch = { updatedAt: nowIso() };
      if (request.data?.commissionPercent != null) {
        patch['organizerSettings.commissionPercent'] = Math.max(
          0,
          Math.min(100, Number(request.data.commissionPercent) || 0),
        );
      }
      if (request.data?.minWithdrawal != null) {
        patch['organizerSettings.minWithdrawal'] = Math.max(
          0,
          Number(request.data.minWithdrawal) || 0,
        );
      }
      if (typeof request.data?.isEventOrganizer === 'boolean') {
        patch.isEventOrganizer = request.data.isEventOrganizer;
      }
      await db.collection('users').doc(companyId).set(patch, { merge: true });
      return { ok: true, companyId };
    },
  );

  const getOrganizerDashboard = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const org = await getOrganizerSettings(uid);
      if (!org.isCompany) {
        throw new HttpsError('permission-denied', 'Firma hesabı gerekli');
      }

      const [ticketsSnap, ledgerSnap, withdrawSnap, adsSnap, discountsSnap] =
        await Promise.all([
          db.collection(TICKETS).where('organizerId', '==', uid).limit(200).get(),
          db
            .collection(LEDGER)
            .where('organizerId', '==', uid)
            .orderBy('createdAt', 'desc')
            .limit(100)
            .get(),
          db
            .collection(WITHDRAWALS)
            .where('companyId', '==', uid)
            .orderBy('createdAt', 'desc')
            .limit(40)
            .get(),
          db.collection(ADS).where('ownerId', '==', uid).limit(40).get(),
          db.collection(DISCOUNTS).where('organizerId', '==', uid).limit(80).get(),
        ]);

      const tickets = ticketsSnap.docs.map((d) => d.data());
      const byEvent = {};
      for (const t of tickets) {
        const eid = t.eventId || 'unknown';
        if (!byEvent[eid]) {
          byEvent[eid] = {
            eventId: eid,
            eventTitle: t.eventTitle || eid,
            count: 0,
            revenue: 0,
            buyers: [],
          };
        }
        byEvent[eid].count += 1;
        byEvent[eid].revenue += Number(t.amountPaid) || 0;
        byEvent[eid].buyers.push({
          uid: t.uid,
          email: t.userEmail,
          name: t.userName,
          amount: t.amountPaid,
          tierLabel: t.tierLabel,
          ticketId: t.id,
          createdAt: t.createdAt,
        });
      }

      return {
        ok: true,
        settings: {
          payoutIban: org.payoutIban,
          payoutIbanHolder: org.payoutIbanHolder,
          payoutBank: org.payoutBank,
          commissionPercent: org.commissionPercent,
          minWithdrawal: org.minWithdrawal,
          balance: org.balance,
          isEventOrganizer: org.isEventOrganizer,
          hasPayoutIban: Boolean(org.payoutIban && org.payoutIbanHolder),
        },
        salesByEvent: Object.values(byEvent),
        tickets,
        ledger: ledgerSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
        withdrawals: withdrawSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
        ads: adsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
        discounts: discountsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
      };
    },
  );

  const requestWithdrawal = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const org = await getOrganizerSettings(uid);
      if (!org.isCompany || !org.isEventOrganizer) {
        throw new HttpsError('permission-denied', 'Organizatör yetkisi gerekli');
      }
      if (!org.payoutIban || !org.payoutIbanHolder) {
        throw new HttpsError(
          'failed-precondition',
          'Önce çekim IBAN’ını kaydetmelisin',
        );
      }
      const amount = Number(request.data?.amount);
      if (!(amount > 0)) {
        throw new HttpsError('invalid-argument', 'Tutar gerekli');
      }
      if (amount < org.minWithdrawal) {
        throw new HttpsError(
          'failed-precondition',
          `Minimum çekim tutarı ${org.minWithdrawal} TL`,
        );
      }
      if (amount > org.balance + 1e-9) {
        throw new HttpsError('failed-precondition', 'Yetersiz bakiye');
      }

      const ref = db.collection(WITHDRAWALS).doc();
      const row = {
        id: ref.id,
        companyId: uid,
        companyName: org.name,
        amount,
        status: 'pending',
        payoutIban: org.payoutIban,
        payoutIbanHolder: org.payoutIbanHolder,
        payoutBank: org.payoutBank,
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      await ref.set(row);
      await db.collection('users').doc(uid).set(
        {
          'organizerWallet.balance': FieldValue.increment(-amount),
          'organizerWallet.currency': 'TRY',
          'organizerWallet.updatedAt': nowIso(),
        },
        { merge: true },
      );
      await db.collection(LEDGER).add({
        organizerId: uid,
        type: 'withdrawal_hold',
        withdrawalId: ref.id,
        net: -amount,
        createdAt: nowIso(),
      });
      return { ok: true, id: ref.id };
    },
  );

  const adminReviewWithdrawal = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const id = String(request.data?.id || '').trim();
      const approve = request.data?.approve !== false;
      if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
      const ref = db.collection(WITHDRAWALS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Talep yok');
      const w = snap.data() || {};
      if (w.status !== 'pending') {
        throw new HttpsError('failed-precondition', 'Zaten sonuçlanmış');
      }
      if (approve) {
        await ref.set(
          {
            status: 'paid',
            reviewedBy: request.auth.uid,
            reviewedAt: nowIso(),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
        await db.collection(LEDGER).add({
          organizerId: w.companyId,
          type: 'withdrawal_paid',
          withdrawalId: id,
          net: -Number(w.amount) || 0,
          createdAt: nowIso(),
        });
      } else {
        const amount = Number(w.amount) || 0;
        await ref.set(
          {
            status: 'rejected',
            reviewedBy: request.auth.uid,
            reviewedAt: nowIso(),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
        if (amount > 0) {
          await db.collection('users').doc(w.companyId).set(
            {
              'organizerWallet.balance': FieldValue.increment(amount),
              'organizerWallet.currency': 'TRY',
              'organizerWallet.updatedAt': nowIso(),
            },
            { merge: true },
          );
          await db.collection(LEDGER).add({
            organizerId: w.companyId,
            type: 'withdrawal_refund',
            withdrawalId: id,
            net: amount,
            createdAt: nowIso(),
          });
        }
      }
      return { ok: true };
    },
  );

  const createEventDiscount = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const org = await getOrganizerSettings(uid);
      if (!org.isEventOrganizer) {
        throw new HttpsError('permission-denied', 'Organizatör yetkisi gerekli');
      }
      const eventId = String(request.data?.eventId || '').trim();
      const code = sanitizePlainText(request.data?.code || '', 32)
        .toUpperCase()
        .replace(/\s+/g, '');
      const type = String(request.data?.type || 'percent'); // percent | fixed
      const value = Number(request.data?.value);
      const maxUses = Number(request.data?.maxUses) || 0;
      if (!eventId || !code || !(value > 0)) {
        throw new HttpsError('invalid-argument', 'Eksik alan');
      }
      const ev = await db.collection('events').doc(eventId).get();
      if (!ev.exists || String(ev.data()?.organizerCompanyId) !== uid) {
        throw new HttpsError('permission-denied', 'Bu etkinlik sana ait değil');
      }
      const ref = db.collection(DISCOUNTS).doc();
      await ref.set({
        id: ref.id,
        eventId,
        organizerId: uid,
        code,
        type: type === 'fixed' ? 'fixed' : 'percent',
        value,
        maxUses: maxUses > 0 ? maxUses : null,
        usedCount: 0,
        active: true,
        createdAt: nowIso(),
      });
      return { ok: true, id: ref.id };
    },
  );

  async function applyDiscountAmount(eventId, code, baseAmount) {
    if (!code) return { amount: baseAmount, discount: null };
    const q = await db
      .collection(DISCOUNTS)
      .where('eventId', '==', eventId)
      .where('code', '==', String(code).toUpperCase())
      .limit(1)
      .get();
    if (q.empty) throw new HttpsError('not-found', 'İndirim kodu geçersiz');
    const d = q.docs[0].data() || {};
    if (d.active === false) {
      throw new HttpsError('failed-precondition', 'İndirim pasif');
    }
    if (d.maxUses != null && Number(d.usedCount || 0) >= Number(d.maxUses)) {
      throw new HttpsError('resource-exhausted', 'İndirim kotası doldu');
    }
    let amount = baseAmount;
    if (d.type === 'fixed') {
      amount = Math.max(0, baseAmount - Number(d.value));
    } else {
      amount = Math.max(
        0,
        Math.round(baseAmount * (1 - Number(d.value) / 100) * 100) / 100,
      );
    }
    return { amount, discount: { code: d.code, id: q.docs[0].id } };
  }

  async function fulfillAdOrder(order) {
    if (!order || order.product !== 'ad') return { ok: false };
    if (order.fulfilledAt) return { ok: true, already: true };
    const adId = String(order.meta?.adId || order.adId || '').trim();
    if (!adId) return { ok: false };
    await db.collection(ADS).doc(adId).set(
      {
        status: 'approved',
        paymentStatus: 'paid',
        paidAt: nowIso(),
        updatedAt: nowIso(),
      },
      { merge: true },
    );
    await db.collection('payment_orders').doc(order.id).set(
      { fulfilledAt: nowIso(), updatedAt: nowIso() },
      { merge: true },
    );
    return { ok: true, adId };
  }

  const submitAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const userSnap = await db.collection('users').doc(uid).get();
      const user = userSnap.data() || {};
      const role = String(user.role || '');
      let ownerId = uid;
      let ownerType = role === 'community' ? 'community' : role === 'company' ? 'company' : '';
      // Panel staff
      if (
        user.panelAccess === true &&
        user.panelOrgId &&
        ['company', 'community'].includes(String(user.panelOrgType || ''))
      ) {
        ownerId = String(user.panelOrgId);
        ownerType = String(user.panelOrgType);
      }
      if (!['company', 'community'].includes(ownerType)) {
        throw new HttpsError('permission-denied', 'Firma veya topluluk gerekli');
      }
      const orgSnap = await db.collection('users').doc(ownerId).get();
      const org = orgSnap.data() || {};
      const ownerName = String(
        org.companyName ||
          org.displayName ||
          `${org.firstName || ''} ${org.lastName || ''}`.trim() ||
          org.username ||
          ownerId,
      );

      const title = sanitizePlainText(request.data?.title || '', 120);
      const body = sanitizePlainText(request.data?.body || '', 800);
      const imageUrl = sanitizePlainText(request.data?.imageUrl || '', 500);
      const placements = Array.isArray(request.data?.placements)
        ? request.data.placements
            .map((x) => String(x).toLowerCase())
            .filter((x) =>
              ['feed', 'reels', 'stories', 'push', 'email'].includes(x),
            )
        : [];
      const targetCities = Array.isArray(request.data?.targetCities)
        ? request.data.targetCities.map((x) => sanitizePlainText(x, 80)).filter(Boolean)
        : [];
      const targetUniversities = Array.isArray(request.data?.targetUniversities)
        ? request.data.targetUniversities
            .map((x) => sanitizePlainText(x, 120))
            .filter(Boolean)
        : [];
      if (!title || placements.length === 0) {
        throw new HttpsError('invalid-argument', 'Başlık ve yerleşim gerekli');
      }
      if (targetCities.length === 0 && targetUniversities.length === 0) {
        throw new HttpsError(
          'invalid-argument',
          'En az bir il veya üniversite seçmelisin',
        );
      }
      let adKind = String(request.data?.adKind || 'standard').toLowerCase();
      if (
        !['standard', 'sponsor_promo', 'event_promo', 'sponsor_paid'].includes(
          adKind,
        )
      ) {
        adKind = 'standard';
      }
      if (ownerType === 'company' && adKind !== 'standard') {
        adKind = 'standard';
      }
      const linkType = String(request.data?.linkType || 'none');
      const ref = db.collection(ADS).doc();
      const row = {
        id: ref.id,
        ownerType,
        ownerId,
        ownerName,
        companyId: ownerType === 'company' ? ownerId : null,
        companyName: ownerType === 'company' ? ownerName : null,
        communityId: ownerType === 'community' ? ownerId : null,
        title,
        body,
        imageUrl,
        adKind,
        placements,
        targetCities,
        targetUniversities,
        linkType: ['event', 'job', 'url', 'none', 'sponsor'].includes(linkType)
          ? linkType
          : 'none',
        linkEventId: sanitizePlainText(request.data?.linkEventId || '', 80),
        linkJobId: sanitizePlainText(request.data?.linkJobId || '', 80),
        linkUrl: sanitizePlainText(request.data?.linkUrl || '', 400),
        scheduleStart: sanitizePlainText(request.data?.scheduleStart || '', 40),
        scheduleEnd: sanitizePlainText(request.data?.scheduleEnd || '', 40),
        preferredHours: sanitizePlainText(request.data?.preferredHours || '', 120),
        pushTitle: sanitizePlainText(request.data?.pushTitle || '', 80),
        pushBody: sanitizePlainText(request.data?.pushBody || '', 200),
        emailSubject: sanitizePlainText(request.data?.emailSubject || '', 120),
        status: adKind === 'sponsor_paid' ? 'pending_quote' : 'pending',
        paymentStatus: adKind === 'sponsor_paid' ? 'unquoted' : 'n/a',
        createdBy: uid,
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      await ref.set(row);
      return { ok: true, id: ref.id, status: row.status };
    },
  );

  const quoteAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const id = String(request.data?.adId || request.data?.id || '').trim();
      const amount = Number(request.data?.quotedAmount);
      if (!id || !(amount > 0)) {
        throw new HttpsError('invalid-argument', 'adId ve tutar gerekli');
      }
      const paymentsSnap = await db.doc('app_config/payments').get();
      const pay = paymentsSnap.data() || {};
      const orderRef = db.collection('payment_orders').doc();
      const code = `KADS-${orderRef.id.slice(0, 8).toUpperCase()}-${crypto
        .randomBytes(2)
        .toString('hex')
        .toUpperCase()}`;
      const adSnap = await db.collection(ADS).doc(id).get();
      if (!adSnap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = adSnap.data() || {};
      await orderRef.set({
        id: orderRef.id,
        uid: ad.ownerId,
        email: '',
        amount,
        currency: 'TRY',
        product: 'ad',
        provider: 'iban',
        status: 'pending',
        ibanReference: code,
        meta: { adId: id, attendeeUid: ad.ownerId },
        createdAt: nowIso(),
        updatedAt: nowIso(),
      });
      await db.collection(ADS).doc(id).set(
        {
          status: 'awaiting_payment',
          paymentStatus: 'quoted',
          quotedAmount: amount,
          ibanReference: code,
          paymentOrderId: orderRef.id,
          payoutIban: String(pay.iban || ''),
          payoutIbanHolder: String(pay.ibanHolder || ''),
          payoutBank: String(pay.ibanBank || ''),
          quotedBy: request.auth.uid,
          quotedAt: nowIso(),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return {
        ok: true,
        orderId: orderRef.id,
        ibanReference: code,
        amount,
        iban: pay.iban || '',
        ibanHolder: pay.ibanHolder || '',
        ibanBank: pay.ibanBank || '',
      };
    },
  );

  const adminReviewAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const id = String(request.data?.id || '').trim();
      if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
      const status = String(request.data?.status || '').trim();
      if (!['approved', 'rejected', 'pending', 'ended'].includes(status)) {
        throw new HttpsError('invalid-argument', 'Geçersiz status');
      }
      const patch = {
        status,
        reviewedBy: request.auth.uid,
        reviewedAt: nowIso(),
        updatedAt: nowIso(),
        adminNote: sanitizePlainText(request.data?.adminNote || '', 400),
      };
      if (status === 'ended') {
        patch.endedAt = nowIso();
        patch.endedBy = request.auth.uid;
      }
      const editable = [
        'title',
        'body',
        'imageUrl',
        'placements',
        'linkType',
        'linkEventId',
        'linkJobId',
        'linkUrl',
        'scheduleStart',
        'scheduleEnd',
        'preferredHours',
        'pushTitle',
        'pushBody',
        'emailSubject',
        'targetCities',
        'targetUniversities',
      ];
      for (const k of editable) {
        if (request.data?.[k] != null) {
          if (
            (k === 'placements' ||
              k === 'targetCities' ||
              k === 'targetUniversities') &&
            Array.isArray(request.data[k])
          ) {
            patch[k] = request.data[k].map((x) => String(x));
          } else {
            patch[k] = sanitizePlainText(request.data[k], 800);
          }
        }
      }
      await db.collection(ADS).doc(id).set(patch, { merge: true });
      return { ok: true };
    },
  );

  const getActiveAds = onCall(
    { region: 'europe-west1' },
    async (request) => {
      const placement = String(request.data?.placement || '').toLowerCase();
      const viewerCity = String(request.data?.city || '').toLowerCase().trim();
      const viewerUni = String(request.data?.university || '')
        .toLowerCase()
        .trim();
      const snap = await db
        .collection(ADS)
        .where('status', '==', 'approved')
        .limit(100)
        .get();
      const now = Date.now();
      const list = [];
      for (const doc of snap.docs) {
        const a = { id: doc.id, ...doc.data() };
        if (a.endedAt) continue;
        const placements = Array.isArray(a.placements) ? a.placements : [];
        if (placement && !placements.includes(placement)) continue;
        if (a.scheduleStart) {
          const t = Date.parse(a.scheduleStart);
          if (Number.isFinite(t) && now < t) continue;
        }
        if (a.scheduleEnd) {
          const t = Date.parse(a.scheduleEnd);
          if (Number.isFinite(t) && now > t) continue;
        }
        const cities = (a.targetCities || []).map((x) => String(x).toLowerCase());
        const unis = (a.targetUniversities || []).map((x) =>
          String(x).toLowerCase(),
        );
        if (cities.length === 0 && unis.length === 0) continue;
        const cityOk =
          !cities.length ||
          cities.some(
            (c) => viewerCity && (viewerCity.includes(c) || c.includes(viewerCity)),
          );
        const uniOk =
          !unis.length ||
          unis.some(
            (u) => viewerUni && (viewerUni.includes(u) || u.includes(viewerUni)),
          );
        if (cities.length && unis.length) {
          if (!(cityOk && uniOk)) continue;
        } else if (cities.length && !cityOk) continue;
        else if (unis.length && !uniOk) continue;

        list.push({
          id: a.id,
          title: a.title,
          body: a.body,
          imageUrl: a.imageUrl,
          placements: a.placements,
          linkType: a.linkType,
          linkEventId: a.linkEventId,
          linkJobId: a.linkJobId,
          linkUrl: a.linkUrl,
          companyName: a.ownerName || a.companyName,
          ownerType: a.ownerType,
          adKind: a.adKind,
          scheduleEnd: a.scheduleEnd,
          badge: 'REKLAM',
        });
      }
      for (let i = list.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [list[i], list[j]] = [list[j], list[i]];
      }
      return { ok: true, ads: list };
    },
  );

  const getMyTickets = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const snap = await db
        .collection(TICKETS)
        .where('uid', '==', uid)
        .orderBy('createdAt', 'desc')
        .limit(100)
        .get();
      return {
        ok: true,
        tickets: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
      };
    },
  );

  return {
    fulfillEventOrder,
    fulfillAdOrder,
    applyDiscountAmount,
    saveOrganizerPayoutIban,
    adminSetOrganizerCommerce,
    getOrganizerDashboard,
    requestWithdrawal,
    adminReviewWithdrawal,
    createEventDiscount,
    submitAdCampaign,
    quoteAdCampaign,
    adminReviewAdCampaign,
    getActiveAds,
    getMyTickets,
  };
}

module.exports = { commerceModule };
