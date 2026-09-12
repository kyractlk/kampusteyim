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
  findUserDocByAnyId,
  expandFieldPaths,
  sendMail,
  companyBrandedEmail,
  loadCompanyMailBrand,
  escapeHtml,
  brandHome,
  sendFcmToUser,
  buildCampusPushPayload,
  userAllowsPush,
}) {
  const TICKETS = 'event_tickets';
  const SHORT_CODES = 'ticket_short_codes';
  const SHORT_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const WITHDRAWALS = 'withdrawal_requests';
  const ADS = 'ad_campaigns';
  const DISCOUNTS = 'event_discounts';
  const LEDGER = 'organizer_ledger';
  const QR_SECRET = process.env.TICKET_QR_SECRET || 'kampusteyim-kt1-ticket-v1';
  const APP_HOME = brandHome || 'https://app.kampusteyim.app';

  async function notifyUser({
    uid,
    title,
    body,
    emoji = '🔔',
    type = 'community',
    targetId,
    link,
  }) {
    const to = String(uid || '').trim();
    if (!to) return;
    try {
      const userDoc = await db.collection('users').doc(to).get();
      if (!userDoc.exists) return;
      const userData = userDoc.data() || {};
      await db.collection('users').doc(to).collection('notifications').add({
        title,
        body,
        emoji,
        type,
        targetId: targetId || null,
        link: link || null,
        read: false,
        createdAt: nowIso(),
      });
      const tokens = userData.fcmTokens || [];
      if (
        tokens.length &&
        typeof sendFcmToUser === 'function' &&
        typeof buildCampusPushPayload === 'function' &&
        (!userAllowsPush || userAllowsPush(userData, type))
      ) {
        await sendFcmToUser(
          to,
          tokens,
          buildCampusPushPayload({
            title,
            body,
            type,
            data: {
              targetId: targetId || '',
              link: link || '',
            },
          }),
        );
      }
    } catch (e) {
      console.error('[commerce] notifyUser', e);
    }
  }

  function nowIso() {
    return new Date().toISOString();
  }

  function citiesAreNationwide(cities) {
    return (cities || []).some((c) => {
      const s = String(c || '')
        .toLowerCase()
        .replace(/ı/g, 'i')
        .replace(/ş/g, 's')
        .replace(/ğ/g, 'g')
        .replace(/ü/g, 'u')
        .replace(/ö/g, 'o')
        .replace(/ç/g, 'c');
      return (
        s.includes('turkiye geneli') ||
        s.includes('tum turkiye') ||
        s === 'turkiye' ||
        s === '*'
      );
    });
  }

  function normalizeTicketEntry(tierOrTicket) {
    const type =
      String(tierOrTicket?.entryType || '').toLowerCase() === 'multi'
        ? 'multi'
        : 'single';
    let limit = Number(tierOrTicket?.entryLimit);
    if (type === 'single' || !Number.isFinite(limit) || limit < 1) limit = 1;
    if (type === 'multi' && limit < 2) limit = 2;
    if (limit > 99) limit = 99;
    return {
      entryType: type,
      entryLimit: type === 'multi' ? Math.floor(limit) : 1,
    };
  }

  function signTicketId(id) {
    return crypto
      .createHmac('sha256', QR_SECRET)
      .update(String(id))
      .digest('hex')
      .slice(0, 20);
  }

  function buildQrPayload(id) {
    const tid = String(id || '').trim();
    return tid ? `KT1.${tid}.${signTicketId(tid)}` : '';
  }

  function hmacEqual(a, b) {
    const left = Buffer.from(String(a || ''), 'utf8');
    const right = Buffer.from(String(b || ''), 'utf8');
    if (left.length !== right.length) return false;
    return crypto.timingSafeEqual(left, right);
  }

  function parseQrPayload(raw) {
    const s = String(raw || '').trim();
    const m = s.match(/^KT1\.([A-Za-z0-9_-]+)\.([a-f0-9]{16,64})$/i);
    if (m) {
      if (!hmacEqual(signTicketId(m[1]), m[2].toLowerCase())) return '';
      return m[1];
    }
    const compact = s.replace(/\s+/g, '').toUpperCase();
    if (new RegExp(`^[${SHORT_ALPHABET}]{6}$`).test(compact)) return compact;
    if (/^[A-Za-z0-9_-]{8,64}$/.test(s)) return s;
    return '';
  }

  function randomShortCode() {
    let out = '';
    for (let i = 0; i < 6; i += 1) {
      out += SHORT_ALPHABET[crypto.randomInt(SHORT_ALPHABET.length)];
    }
    return out;
  }

  async function allocateShortCode(ticketId) {
    const tid = String(ticketId || '').trim();
    if (!tid) throw new Error('ticketId gerekli');
    for (let i = 0; i < 32; i += 1) {
      const code = randomShortCode();
      const ref = db.collection(SHORT_CODES).doc(code);
      try {
        await db.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (snap.exists) {
            const err = new Error('taken');
            err.code = 'taken';
            throw err;
          }
          tx.set(ref, { ticketId: tid, createdAt: nowIso() });
        });
        return code;
      } catch (e) {
        if (e && (e.code === 'taken' || String(e.message || '') === 'taken')) {
          continue;
        }
        throw e;
      }
    }
    throw new Error('short-code-exhausted');
  }

  async function resolveTicketSnap(raw) {
    const parsed = parseQrPayload(raw);
    if (!parsed) return null;
    const code = String(parsed).toUpperCase();
    if (new RegExp(`^[${SHORT_ALPHABET}]{6}$`).test(code)) {
      const map = await db.collection(SHORT_CODES).doc(code).get();
      if (map.exists) {
        const tid = String(map.data()?.ticketId || '').trim();
        if (tid) {
          const byId = await db.collection(TICKETS).doc(tid).get();
          if (byId.exists) return byId;
        }
      }
      const q = await db
        .collection(TICKETS)
        .where('shortCode', '==', code)
        .limit(1)
        .get();
      if (!q.empty) return q.docs[0];
    }
    const snap = await db.collection(TICKETS).doc(parsed).get();
    return snap.exists ? snap : null;
  }

  function ticketIsUsed(ticket) {
    const st = String(ticket?.status || 'active');
    const usedNow = Number(ticket?.entriesUsed);
    if (Number.isFinite(usedNow) && usedNow > 0) return true;
    return st === 'used' || st === 'checked_in' || Boolean(ticket?.checkedInAt);
  }

  async function resolveCommerceOwner(uid) {
    const snap = await db.collection('users').doc(uid).get();
    const user = snap.data() || {};
    if (
      user.panelAccess === true &&
      user.panelOrgId &&
      ['company', 'community'].includes(String(user.panelOrgType || ''))
    ) {
      return { ownerId: String(user.panelOrgId), actor: user };
    }
    return { ownerId: uid, actor: user };
  }

  async function sendTicketEmail(ticket, event, organizerId) {
    const to = String(ticket.userEmail || '').trim();
    if (!to || !to.includes('@') || typeof sendMail !== 'function') return;
    const esc =
      typeof escapeHtml === 'function'
        ? escapeHtml
        : (v) =>
            String(v ?? '')
              .replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/"/g, '&quot;');
    let brand = {
      companyName: String(
        event.communityName || event.organizerCompanyName || 'Organizatör',
      ),
      logoUrl: String(event.communityLogoUrl || ''),
      signature: {},
    };
    try {
      if (typeof loadCompanyMailBrand === 'function') {
        brand = await loadCompanyMailBrand(organizerId);
      }
    } catch (_) {}
    if (
      !brand.companyName ||
      brand.companyName === 'Firma' ||
      brand.companyName === 'Topluluk'
    ) {
      const fromEvent = String(
        event.communityName || event.organizerCompanyName || '',
      ).trim();
      if (fromEvent) brand.companyName = fromEvent;
    }
    if (!brand.logoUrl && event.communityLogoUrl) {
      brand.logoUrl = String(event.communityLogoUrl);
    }
    if (!brand.signature || typeof brand.signature !== 'object') {
      brand.signature = {};
    }
    if (!String(brand.signature.contactName || '').trim()) {
      brand.signature.contactName = brand.companyName;
    }
    if (!String(brand.signature.logoUrl || '').trim() && brand.logoUrl) {
      brand.signature.logoUrl = brand.logoUrl;
    }
    const qr = ticket.qrPayload || buildQrPayload(ticket.id);
    const qrImg = `https://api.qrserver.com/v1/create-qr-code/?size=280x280&ecc=M&data=${encodeURIComponent(qr)}`;
    const eventUrl = `${APP_HOME}/event/${encodeURIComponent(ticket.eventId)}`;
    const ticketsUrl = `${APP_HOME}/tickets`;
    const starts = ticket.startsAt
      ? esc(String(ticket.startsAt)).replace('T', ' ').slice(0, 16)
      : '';
    const bodyHtml = `
      <p>Biletin hazır. Kapıda aşağıdaki QR kodunu göster.</p>
      <p style="text-align:center;margin:22px 0;">
        <img src="${qrImg}" alt="Bilet QR" width="220" height="220" style="display:inline-block;border:1px solid #E2E8F0;border-radius:16px;padding:8px;background:#fff;"/>
      </p>
      <p><strong>${esc(ticket.eventTitle || 'Etkinlik')}</strong></p>
      ${starts ? `<p>Tarih: ${starts}</p>` : ''}
      ${ticket.tierLabel ? `<p>Bilet: ${esc(ticket.tierLabel)}</p>` : ''}
      <p>Giriş: ${
        String(ticket.entryType || '') === 'multi'
          ? `çoklu · ${Number(ticket.entryLimit) || 2} kez okutulabilir`
          : 'tek giriş'
      }</p>
      ${
        ticket.shortCode
          ? `<p>Kısa kod: <strong style="letter-spacing:2px;font-size:18px;">${esc(ticket.shortCode)}</strong></p>`
          : ''
      }
      <p style="color:#64748B;font-size:13px;">Bilet kişiye özeldir. ${
        event && event.refundsAllowed === true
          ? 'Bu etkinlikte iade, organizatör bakiyesinden net tutar düşülerek yapılabilir (platform komisyonu iade edilmez).'
          : 'Bu etkinlikte iade / iptal yoktur.'
      }</p>
    `;
    const html =
      typeof companyBrandedEmail === 'function'
        ? companyBrandedEmail({
            companyName: brand.companyName,
            logoUrl: brand.logoUrl,
            signature: brand.signature,
            title: 'Biletin hazır',
            greeting: ticket.userName ? `Merhaba ${ticket.userName},` : 'Merhaba,',
            bodyHtml,
            ctaLabel: 'Biletimi aç',
            ctaUrl: ticketsUrl,
            footerNote: `Etkinlik sayfası: ${eventUrl}`,
          })
        : `<div>${bodyHtml}</div>`;
    const attachments = [];
    try {
      const res = await fetch(qrImg);
      if (res.ok) {
        attachments.push({
          filename: 'bilet-qr.png',
          content: Buffer.from(await res.arrayBuffer()),
          cid: 'ticketqr',
        });
      }
    } catch (_) {}
    await sendMail({
      to,
      subject: `${brand.companyName || 'KampüsteyimAPP'} · ${ticket.eventTitle || 'Biletin'}`,
      html,
      attachments,
    });
  }

  function eventNeedsPaidTicket(event) {
    if (event?.paymentRequired === true) return true;
    const tiers = Array.isArray(event?.priceTiers) ? event.priceTiers : [];
    return tiers.some((t) => Number(t?.price ?? t?.amount ?? 0) > 0);
  }

  async function assertCanReviewEvent(uid, event) {
    const orgId = String(
      event.communityId || event.organizerCompanyId || '',
    ).trim();
    if (!orgId) {
      throw new HttpsError('failed-precondition', 'Etkinlik organizatörü yok');
    }
    if (uid === orgId) return { orgId };
    const userSnap = await db.collection('users').doc(uid).get();
    const u = userSnap.data() || {};
    if (
      u.panelAccess === true &&
      String(u.panelOrgId || '') === orgId &&
      ['company', 'community'].includes(String(u.panelOrgType || ''))
    ) {
      return { orgId };
    }
    throw new HttpsError('permission-denied', 'Bu başvuruyu onaylayamazsınız');
  }

  /** Ücretsiz / onaylı başvuru → bilet + QR mail (ödeme fulfillment ile aynı bilet formatı). */
  async function issueComplimentaryEventTicket({
    eventId,
    event,
    eventRef,
    uid,
    userName,
    applicationId,
    organizerId,
  }) {
    const existing = await db
      .collection(TICKETS)
      .where('eventId', '==', eventId)
      .where('uid', '==', uid)
      .limit(1)
      .get();
    if (!existing.empty) {
      const doc = existing.docs[0];
      return {
        ticket: { id: doc.id, ...doc.data() },
        ticketRef: doc.ref,
        created: false,
      };
    }

    const buyer = await db.collection('users').doc(uid).get();
    const bd = buyer.data() || {};
    const email = String(bd.email || '').trim();
    const displayName =
      String(userName || '').trim() ||
      String(bd.fullName || `${bd.firstName || ''} ${bd.lastName || ''}`).trim() ||
      uid;

    const ticketRef = db.collection(TICKETS).doc();
    let shortCode = '';
    try {
      shortCode = await allocateShortCode(ticketRef.id);
    } catch (e) {
      console.error('[issueComplimentary] shortCode', e);
    }
    const qrKey = shortCode || ticketRef.id;
    const ticket = {
      id: ticketRef.id,
      eventId,
      eventTitle: String(event.title || ''),
      uid,
      payerUid: null,
      userEmail: email,
      userName: displayName,
      orderId: null,
      applicationId: applicationId || null,
      tierLabel: 'Onaylı katılım',
      amountPaid: 0,
      discountCode: null,
      status: 'active',
      organizerId,
      city: String(event.city || ''),
      startsAt: event.startsAt || null,
      createdAt: nowIso(),
      ibanReference: null,
      shortCode: shortCode || null,
      qrPayload: buildQrPayload(qrKey),
      refundsAllowed: event.refundsAllowed === true,
      entryType: 'single',
      entryLimit: 1,
      entriesUsed: 0,
      entries: [],
      complimentary: true,
    };
    await ticketRef.set(ticket);
    return { ticket, ticketRef, created: true };
  }

  async function resolveAdOwner(uid) {
    const userSnap = await db.collection('users').doc(uid).get();
    const user = userSnap.data() || {};
    const role = String(user.role || '');
    let ownerId = uid;
    let ownerType =
      role === 'community' ? 'community' : role === 'company' ? 'company' : '';
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
    return { ownerId, ownerType, user };
  }

  async function assertAdOwner(uid, ad) {
    const ctx = await resolveAdOwner(uid);
    if (String(ad.ownerId || '') !== ctx.ownerId) {
      throw new HttpsError('permission-denied', 'Bu kampanya size ait değil');
    }
    return ctx;
  }

  function safeUrl(value, max = 500) {
    const url = sanitizePlainText(value || '', max);
    return /^https:\/\//i.test(url) ? url : '';
  }

  /** Reklam kartında yayıncı hesabı gibi gösterilecek profil özeti. */
  function ownerProfileSnapshot(ownerId, org = {}, ownerType = '') {
    const displayName = String(
      org.companyName ||
        org.displayName ||
        `${org.firstName || ''} ${org.lastName || ''}`.trim() ||
        org.username ||
        ownerId,
    ).trim();
    const username = String(org.username || '')
      .trim()
      .replace(/^@/, '')
      .toLowerCase();
    const photoUrl =
      safeUrl(org.communityLogoUrl || '', 500) ||
      safeUrl(org.photoUrl || '', 500) ||
      '';
    return {
      ownerId: String(ownerId || ''),
      ownerType: String(ownerType || org.role || ''),
      ownerName: displayName,
      ownerUsername: username,
      ownerPhotoUrl: photoUrl,
      ownerHandle: username ? `@${username}` : displayName,
      isCommunity:
        ownerType === 'community' || String(org.role || '') === 'community',
    };
  }

  function normalizeAdVariants(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object') return out;
    for (const key of ['feed', 'reels', 'stories', 'email', 'push', 'master']) {
      const value = safeUrl(raw[key], 500);
      if (value) out[key] = value;
    }
    return out;
  }

  function adPublicStatus(ad) {
    const status = String(ad.status || '');
    if (!['active', 'approved'].includes(status)) return status;
    const now = Date.now();
    const start = Date.parse(ad.scheduleStart || '');
    const end = Date.parse(ad.scheduleEnd || '');
    if (Number.isFinite(start) && now < start) return 'scheduled';
    if (Number.isFinite(end) && now > end) return 'completed';
    return 'active';
  }

  async function getOrganizerSettings(uid) {
    const snap = await db.collection('users').doc(uid).get();
    const u = snap.data() || {};
    // Eski kayıtlarda ayarlar `organizerSettings.x` adlı düz alanlarda duruyor.
    const legacy = (key) => u[`organizerSettings.${key}`];
    const nested = u.organizerSettings || {};
    const s = new Proxy(
      {},
      {
        get: (_, key) =>
          nested[key] !== undefined ? nested[key] : legacy(key),
      },
    );
    const wallet = u.organizerWallet || {};
    const balance =
      wallet.balance !== undefined
        ? wallet.balance
        : u['organizerWallet.balance'];
    return {
      user: u,
      payoutIban: String(s.payoutIban || '').trim(),
      payoutIbanHolder: String(s.payoutIbanHolder || '').trim(),
      payoutBank: String(s.payoutBank || '').trim(),
      commissionPercent: Number(
        s.commissionPercent != null ? s.commissionPercent : 10,
      ),
      minWithdrawal: Number(s.minWithdrawal != null ? s.minWithdrawal : 500),
      balance: Number(balance || 0),
      isEventOrganizer: u.isEventOrganizer === true,
      isCompany: u.role === 'company',
      isCommunity: u.role === 'community' || u.isCommunity === true,
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
    const organizerId = String(
      event.organizerCompanyId || event.communityId || '',
    ).trim();
    if (!organizerId) {
      console.error('[fulfillEvent] no organizer', eventId);
      return { ok: false };
    }

    const amount = Number(order.amount) || 0;
    const org = await getOrganizerSettings(organizerId);
    const commissionPct = Math.max(0, Math.min(100, org.commissionPercent));
    const commission = Math.round(amount * (commissionPct / 100) * 100) / 100;
    const net = Math.round((amount - commission) * 100) / 100;

    const label = String(tierLabel || 'Bilet');
    const tiersPreview = Array.isArray(event.priceTiers) ? event.priceTiers : [];
    const sourceTier =
      tiersPreview.find((t) => String(t.label || '') === label) ||
      tiersPreview[0] ||
      {};
    const entry = normalizeTicketEntry(sourceTier);

    const ticketRef = db.collection(TICKETS).doc();
    let shortCode = '';
    try {
      shortCode = await allocateShortCode(ticketRef.id);
    } catch (e) {
      console.error('[fulfillEvent] shortCode', e);
    }
    const qrKey = shortCode || ticketRef.id;
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
      shortCode: shortCode || null,
      qrPayload: buildQrPayload(qrKey),
      refundsAllowed: event.refundsAllowed === true,
      entryType: entry.entryType,
      entryLimit: entry.entryLimit,
      entriesUsed: 0,
      entries: [],
    };
    await ticketRef.set(ticket);

    // Başvuru / kontenjan + market stok
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

    const tiers = Array.isArray(event.priceTiers)
      ? event.priceTiers.map((t) => ({ ...t }))
      : [];
    const ti = tiers.findIndex((t) => String(t.label || '') === String(label));
    if (ti >= 0) {
      tiers[ti].soldCount = (Number(tiers[ti].soldCount) || 0) + 1;
    }
    await eventRef.set(
      {
        applications: apps,
        applicantCount: apps.length,
        priceTiers: tiers.length ? tiers : event.priceTiers || [],
        updatedAt: nowIso(),
      },
      { merge: true },
    );

    try {
      const slug =
        String(label)
          .toLowerCase()
          .replace(/[^a-z0-9ğüşıöç]+/gi, '-')
          .replace(/^-|-$/g, '')
          .slice(0, 32) || 'bilet';
      await db
        .collection('market_products')
        .doc(`evt_${eventId}_${slug}`)
        .set(
          {
            soldCount: FieldValue.increment(1),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
    } catch (e) {
      console.error('[fulfillEvent] market stock', e);
    }

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
      const orgRef = db.collection('users').doc(organizerId);
      const orgSnap = await orgRef.get();
      if (orgSnap.exists) {
        await orgRef.set(
          expandFieldPaths({
            'organizerWallet.balance': FieldValue.increment(net),
            'organizerWallet.currency': 'TRY',
            'organizerWallet.updatedAt': nowIso(),
            updatedAt: nowIso(),
          }),
          { merge: true },
        );
      }
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

    try {
      if (!ticket.userEmail) {
        const buyer = await db.collection('users').doc(uid).get();
        const bd = buyer.data() || {};
        ticket.userEmail = String(bd.email || '');
        ticket.userName =
          ticket.userName ||
          String(bd.fullName || `${bd.firstName || ''} ${bd.lastName || ''}`).trim();
        if (ticket.userEmail) {
          await ticketRef.set(
            { userEmail: ticket.userEmail, userName: ticket.userName },
            { merge: true },
          );
        }
      }
      await sendTicketEmail(ticket, event, organizerId);
      await ticketRef.set({ ticketEmailSentAt: nowIso() }, { merge: true });
    } catch (e) {
      console.error('[fulfillEvent] ticket email', e);
    }

    const eventTitle = String(event?.title || event?.name || 'Etkinlik').trim();
    await notifyUser({
      uid,
      title: 'Biletin hazır',
      body: `${eventTitle} biletin uygulamada. Biletlerim’den açabilirsin.`,
      emoji: '🎫',
      type: 'ticket',
      targetId: ticketRef.id,
      link: `${APP_HOME}/tickets`,
    });
    if (organizerId && organizerId !== uid) {
      await notifyUser({
        uid: organizerId,
        title: 'Yeni bilet satışı',
        body: `${eventTitle} · bir bilet satıldı`,
        emoji: '🎟️',
        type: 'sale',
        targetId: ticketRef.id,
        link: `${APP_HOME}/notifications`,
      });
    }

    return { ok: true, ticketId: ticketRef.id, net, commission };
  }

  /**
   * Tam iade: bilet iptal, kontenjan aç, organizatörden NET tutarı geri al
   * (komisyon platformda kalır — 10 TL bilet, %20 komisyon → işletmeciden 8 TL).
   */
  async function reverseEventFulfillment(order) {
    if (!order || String(order.product || '') !== 'event') {
      return { ok: false, skipped: true };
    }
    if (order.eventFulfillmentReversedAt) {
      return { ok: true, already: true };
    }
    const ticketId = String(order.ticketId || '').trim();
    const eventId = String(order.meta?.eventId || order.eventId || '').trim();
    const organizerId = String(order.organizerId || '').trim();
    const uid = String(order.uid || '').trim();
    const gross = Number(order.amount) || 0;
    const storedNet = Number(order.netToOrganizer);
    const commission = Number(order.commission);
    const clawback = Number.isFinite(storedNet)
      ? storedNet
      : Math.round(
          (gross -
            (Number.isFinite(commission)
              ? commission
              : 0)) *
            100,
        ) / 100;

    if (ticketId) {
      const tref = db.collection(TICKETS).doc(ticketId);
      const tsnap = await tref.get();
      if (tsnap.exists) {
        const t = tsnap.data() || {};
        if (ticketIsUsed(t) && order.forceUsedRefund !== true) {
          return { ok: false, blocked: true, code: 'USED_TICKET_NO_REFUND' };
        }
        if (t.status !== 'refunded' && t.status !== 'cancelled') {
          await tref.set(
            {
              status: 'refunded',
              refundedAt: nowIso(),
              previousStatus: t.status || 'active',
              forceUsedRefund: order.forceUsedRefund === true,
              updatedAt: nowIso(),
            },
            { merge: true },
          );
        }
      }
    }

    if (eventId) {
      const eventRef = db.collection('events').doc(eventId);
      const eventSnap = await eventRef.get();
      if (eventSnap.exists) {
        const event = eventSnap.data() || {};
        const label = String(order.meta?.tierLabel || order.tierLabel || 'Bilet');
        const apps = Array.isArray(event.applications)
          ? event.applications.map((a) => ({ ...a }))
          : [];
        const nextApps = apps.filter((a) => {
          if (ticketId && String(a.ticketId || '') === ticketId) return false;
          if (!ticketId && uid && String(a.userId || '') === uid && a.paid === true) {
            return false;
          }
          return true;
        });
        const tiers = Array.isArray(event.priceTiers)
          ? event.priceTiers.map((t) => ({ ...t }))
          : [];
        const ti = tiers.findIndex((t) => String(t.label || '') === label);
        if (ti >= 0) {
          tiers[ti].soldCount = Math.max(0, (Number(tiers[ti].soldCount) || 0) - 1);
        }
        await eventRef.set(
          {
            applications: nextApps,
            applicantCount: nextApps.length,
            priceTiers: tiers.length ? tiers : event.priceTiers || [],
            updatedAt: nowIso(),
          },
          { merge: true },
        );
        try {
          const slug =
            String(label)
              .toLowerCase()
              .replace(/[^a-z0-9ğüşıöç]+/gi, '-')
              .replace(/^-|-$/g, '')
              .slice(0, 32) || 'bilet';
          const pref = db.collection('market_products').doc(`evt_${eventId}_${slug}`);
          const psnap = await pref.get();
          if (psnap.exists) {
            const sold = Math.max(0, (Number(psnap.data()?.soldCount) || 0) - 1);
            await pref.set({ soldCount: sold, updatedAt: nowIso() }, { merge: true });
          }
        } catch (e) {
          console.warn('[reverseEvent] market stock', e?.message || e);
        }
      }
    }

    if (organizerId && clawback > 0) {
      const orgRef = db.collection('users').doc(organizerId);
      const orgSnap = await orgRef.get();
      if (orgSnap.exists) {
        await orgRef.set(
          expandFieldPaths({
            'organizerWallet.balance': FieldValue.increment(-clawback),
            'organizerWallet.currency': 'TRY',
            'organizerWallet.updatedAt': nowIso(),
            updatedAt: nowIso(),
          }),
          { merge: true },
        );
      }
      await db.collection(LEDGER).add({
        organizerId,
        type: 'refund',
        eventId: eventId || null,
        ticketId: ticketId || null,
        orderId: order.id,
        gross,
        commission: Number.isFinite(commission) ? commission : 0,
        net: -clawback,
        buyerUid: uid || null,
        createdAt: nowIso(),
      });
    }

    if (order.id) {
      await db.collection('payment_orders').doc(order.id).set(
        {
          eventFulfillmentReversedAt: nowIso(),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
    }
    if (uid) {
      await notifyUser({
        uid,
        title: 'İade alındı',
        body: 'Etkinlik biletin iptal edildi, iade işleme alındı.',
        emoji: '↩️',
        type: 'refund',
        targetId: ticketId || '',
        link: `${APP_HOME}/tickets`,
      });
    }
    return { ok: true, clawback };
  }

  async function reverseMerchFulfillment(order) {
    if (!order || String(order.product || '') !== 'merch') {
      return { ok: false, skipped: true };
    }
    if (order.merchFulfillmentReversedAt) {
      return { ok: true, already: true };
    }
    const sku = String(order.meta?.sku || order.sku || '').trim();
    if (!sku) return { ok: true, skipped: true };
    try {
      let ref = db.collection('market_products').doc(sku);
      let snap = await ref.get();
      if (!snap.exists) {
        const q = await db
          .collection('market_products')
          .where('sku', '==', sku)
          .limit(1)
          .get();
        if (!q.empty) {
          ref = q.docs[0].ref;
          snap = q.docs[0];
        }
      }
      if (!snap.exists) return { ok: true, skipped: true };
      const d = snap.data() || {};
      const sold = Math.max(0, (Number(d.soldCount) || 0) - 1);
      const stockRaw = Number(d.stock);
      const patch = { soldCount: sold, updatedAt: nowIso() };
      if (Number.isFinite(stockRaw)) patch.stock = stockRaw + 1;
      await ref.set(patch, { merge: true });
      if (order.id) {
        await db.collection('payment_orders').doc(order.id).set(
          {
            merchFulfillmentReversedAt: nowIso(),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
      }
      return { ok: true };
    } catch (e) {
      console.warn('[reverseMerch]', e?.message || e);
      return { ok: false, error: e?.message || String(e) };
    }
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
          ...expandFieldPaths({
            'organizerSettings.payoutIban': iban,
            'organizerSettings.payoutIbanHolder': holder,
            'organizerSettings.payoutBank': bank,
          }),
          // Noktalı anahtarla düz alan olarak yazılmış eski kayıtları temizle.
          'organizerSettings.payoutIban': FieldValue.delete(),
          'organizerSettings.payoutIbanHolder': FieldValue.delete(),
          'organizerSettings.payoutBank': FieldValue.delete(),
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
      // AppUser.id stableId olabilir; gerçek dokümanı çöz (aksi halde
      // users/{stableId} altında hayalet doküman oluşur).
      let userSnap = (await findUserDocByAnyId(rawKey)) || { exists: false };
      if (userSnap.exists) companyId = userSnap.id;
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
      await db
        .collection('users')
        .doc(companyId)
        .set(expandFieldPaths(patch), { merge: true });
      return { ok: true, companyId };
    },
  );

  const getOrganizerDashboard = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const { ownerId } = await resolveCommerceOwner(uid);
      const org = await getOrganizerSettings(ownerId);
      if (!org.isCompany && !org.isEventOrganizer && !org.isCommunity) {
        throw new HttpsError('permission-denied', 'Firma hesabı gerekli');
      }

      const [ticketsSnap, ledgerSnap, withdrawSnap, adsSnap, discountsSnap] =
        await Promise.all([
          db.collection(TICKETS).where('organizerId', '==', ownerId).limit(200).get(),
          db
            .collection(LEDGER)
            .where('organizerId', '==', ownerId)
            .orderBy('createdAt', 'desc')
            .limit(100)
            .get(),
          db
            .collection(WITHDRAWALS)
            .where('companyId', '==', ownerId)
            .orderBy('createdAt', 'desc')
            .limit(40)
            .get(),
          db.collection(ADS).where('ownerId', '==', ownerId).limit(40).get(),
          db.collection(DISCOUNTS).where('organizerId', '==', ownerId).limit(80).get(),
        ]);

      const tickets = ticketsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
      const byEvent = {};
      for (const t of tickets) {
        const eid = t.eventId || 'unknown';
        if (!byEvent[eid]) {
          byEvent[eid] = {
            eventId: eid,
            eventTitle: t.eventTitle || eid,
            count: 0,
            revenue: 0,
            refundedCount: 0,
            refundedRevenue: 0,
            buyers: [],
          };
        }
        const st = String(t.status || 'active');
        const refunded = st === 'refunded' || st === 'cancelled';
        const amount = Number(t.amountPaid) || 0;
        if (refunded) {
          byEvent[eid].refundedCount += 1;
          byEvent[eid].refundedRevenue += amount;
        } else {
          byEvent[eid].count += 1;
          byEvent[eid].revenue += amount;
        }
        byEvent[eid].buyers.push({
          uid: t.uid,
          email: t.userEmail,
          name: t.userName,
          amount: t.amountPaid,
          tierLabel: t.tierLabel,
          ticketId: t.id,
          status: st,
          checkedInAt: t.checkedInAt || null,
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
        expandFieldPaths({
          'organizerWallet.balance': FieldValue.increment(-amount),
          'organizerWallet.currency': 'TRY',
          'organizerWallet.updatedAt': nowIso(),
        }),
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
            expandFieldPaths({
              'organizerWallet.balance': FieldValue.increment(amount),
              'organizerWallet.currency': 'TRY',
              'organizerWallet.updatedAt': nowIso(),
            }),
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
        status: 'paid_review',
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
      const { ownerId, ownerType } = await resolveAdOwner(uid);
      const orgSnap = await db.collection('users').doc(ownerId).get();
      const org = orgSnap.data() || {};
      const profile = ownerProfileSnapshot(ownerId, org, ownerType);
      const ownerName = profile.ownerName;

      const title = sanitizePlainText(request.data?.title || '', 120);
      const body = sanitizePlainText(request.data?.body || '', 800);
      const imageUrl = safeUrl(request.data?.imageUrl, 500);
      const imageVariants = normalizeAdVariants(request.data?.imageVariants);
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
          'En az bir hedef il seçmelisin',
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
        ownerUsername: profile.ownerUsername,
        ownerPhotoUrl: profile.ownerPhotoUrl,
        ownerHandle: profile.ownerHandle,
        companyId: ownerType === 'company' ? ownerId : null,
        companyName: ownerType === 'company' ? ownerName : null,
        communityId: ownerType === 'community' ? ownerId : null,
        title,
        body,
        imageUrl,
        imageVariants,
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
        emailHeadline: sanitizePlainText(
          request.data?.emailHeadline || title,
          160,
        ),
        emailBody: sanitizePlainText(request.data?.emailBody || body, 1200),
        ctaLabel: sanitizePlainText(request.data?.ctaLabel || 'Detayları Gör', 50),
        status:
          ownerType === 'company' || adKind === 'sponsor_paid'
            ? 'pending_quote'
            : 'pending_review',
        paymentStatus:
          ownerType === 'company' || adKind === 'sponsor_paid'
            ? 'unquoted'
            : 'not_required',
        metrics: {
          impressions: 0,
          reach: 0,
          clicks: 0,
          emailSent: 0,
          emailOpened: 0,
          emailClicks: 0,
          pushSent: 0,
        },
        metricsByPlacement: {},
        deliveryLocations: {},
        statusHistory: [
          {
            status:
              ownerType === 'company' || adKind === 'sponsor_paid'
                ? 'pending_quote'
                : 'pending_review',
            at: nowIso(),
            by: uid,
          },
        ],
        createdBy: uid,
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      if (row.linkType === 'job' && row.linkJobId) {
        const postId = String(row.linkJobId).startsWith('job_')
          ? row.linkJobId
          : `job_${row.linkJobId}`;
        row.linkUrl = `https://app.kampusteyim.app/post/${encodeURIComponent(postId)}`;
      } else if (row.linkType === 'event' && row.linkEventId) {
        row.linkUrl = `https://app.kampusteyim.app/event/${encodeURIComponent(
          row.linkEventId,
        )}`;
      }
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
      const adSnap = await db.collection(ADS).doc(id).get();
      if (!adSnap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = adSnap.data() || {};
      if (['active', 'completed', 'cancelled'].includes(String(ad.status || ''))) {
        throw new HttpsError('failed-precondition', 'Bu kampanyaya teklif verilemez');
      }
      await db.collection(ADS).doc(id).set(
        {
          status: 'quoted',
          paymentStatus: 'offer_pending',
          quotedAmount: amount,
          quotedBy: request.auth.uid,
          quotedAt: nowIso(),
          quoteNote: sanitizePlainText(request.data?.quoteNote || '', 500),
          statusHistory: FieldValue.arrayUnion({
            status: 'quoted',
            at: nowIso(),
            by: request.auth.uid,
          }),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return {
        ok: true,
        amount,
        status: 'quoted',
      };
    },
  );

  const acceptAdQuote = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const id = String(request.data?.adId || request.data?.id || '').trim();
      if (!id) throw new HttpsError('invalid-argument', 'adId gerekli');
      const ref = db.collection(ADS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = snap.data() || {};
      await assertAdOwner(uid, ad);
      if (ad.status !== 'quoted' || !(Number(ad.quotedAmount) > 0)) {
        throw new HttpsError('failed-precondition', 'Kabul edilebilir teklif yok');
      }

      const paymentsSnap = await db.doc('app_config/payments').get();
      const pay = paymentsSnap.data() || {};
      if (!pay.iban || !pay.ibanHolder) {
        throw new HttpsError('failed-precondition', 'Platform IBAN bilgisi eksik');
      }
      const orderRef = db.collection('payment_orders').doc();
      const code = `KADS-${orderRef.id.slice(0, 8).toUpperCase()}-${crypto
        .randomBytes(2)
        .toString('hex')
        .toUpperCase()}`;
      const amount = Number(ad.quotedAmount);
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
      await ref.set(
        {
          status: 'awaiting_payment',
          paymentStatus: 'awaiting_transfer',
          offerAcceptedAt: nowIso(),
          offerAcceptedBy: uid,
          ibanReference: code,
          paymentOrderId: orderRef.id,
          payoutIban: String(pay.iban || ''),
          payoutIbanHolder: String(pay.ibanHolder || ''),
          payoutBank: String(pay.ibanBank || ''),
          statusHistory: FieldValue.arrayUnion({
            status: 'awaiting_payment',
            at: nowIso(),
            by: uid,
          }),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return {
        ok: true,
        orderId: orderRef.id,
        amount,
        ibanReference: code,
        iban: pay.iban,
        ibanHolder: pay.ibanHolder,
        ibanBank: pay.ibanBank || '',
      };
    },
  );

  const declineAdQuote = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const id = String(request.data?.adId || request.data?.id || '').trim();
      const ref = db.collection(ADS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = snap.data() || {};
      await assertAdOwner(uid, ad);
      if (ad.status !== 'quoted') {
        throw new HttpsError('failed-precondition', 'Reddedilebilir teklif yok');
      }
      await ref.set(
        {
          status: 'quote_declined',
          paymentStatus: 'offer_declined',
          quoteDeclineReason: sanitizePlainText(request.data?.reason || '', 300),
          statusHistory: FieldValue.arrayUnion({
            status: 'quote_declined',
            at: nowIso(),
            by: uid,
          }),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return { ok: true };
    },
  );

  const getMyAdCampaigns = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const { ownerId } = await resolveAdOwner(request.auth.uid);
      const snap = await db.collection(ADS).where('ownerId', '==', ownerId).limit(100).get();
      const ads = snap.docs
        .map((d) => {
          const data = d.data() || {};
          return { id: d.id, ...data, displayStatus: adPublicStatus(data) };
        })
        .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
      return { ok: true, ads };
    },
  );

  const updateAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const id = String(request.data?.adId || request.data?.id || '').trim();
      const ref = db.collection(ADS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = snap.data() || {};
      await assertAdOwner(uid, ad);
      const status = adPublicStatus(ad);
      if (
        ['awaiting_payment', 'paid_review', 'completed', 'cancelled'].includes(status)
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Bu aşamada kampanya düzenlenemez',
        );
      }
      const active = ['active', 'scheduled', 'paused', 'approved'].includes(status);
      const patch = {
        updatedAt: nowIso(),
        editedBy: uid,
        editedAt: nowIso(),
      };
      const textFields = {
        title: 120,
        body: 800,
        linkUrl: 400,
        pushTitle: 80,
        pushBody: 200,
        emailSubject: 120,
        emailHeadline: 160,
        emailBody: 1200,
        ctaLabel: 50,
      };
      for (const [key, max] of Object.entries(textFields)) {
        if (request.data?.[key] != null) {
          patch[key] =
            key === 'linkUrl'
              ? safeUrl(request.data[key], max)
              : sanitizePlainText(request.data[key], max);
        }
      }
      if (request.data?.imageUrl != null) {
        patch.imageUrl = safeUrl(request.data.imageUrl, 500);
      }
      if (request.data?.imageVariants != null) {
        patch.imageVariants = normalizeAdVariants(request.data.imageVariants);
      }
      // Aktif kampanyada fiyatı etkileyen hedef/mecralar değişmez.
      if (!active) {
        if (Array.isArray(request.data?.placements)) {
          patch.placements = request.data.placements
            .map((x) => String(x).toLowerCase())
            .filter((x) => ['feed', 'reels', 'stories', 'push', 'email'].includes(x));
        }
        if (Array.isArray(request.data?.targetCities)) {
          patch.targetCities = request.data.targetCities
            .map((x) => sanitizePlainText(x, 80))
            .filter(Boolean);
        }
        if (Array.isArray(request.data?.targetUniversities)) {
          patch.targetUniversities = request.data.targetUniversities
            .map((x) => sanitizePlainText(x, 120))
            .filter(Boolean);
        }
        for (const key of ['scheduleStart', 'scheduleEnd', 'preferredHours']) {
          if (request.data?.[key] != null) {
            patch[key] = sanitizePlainText(request.data[key], 120);
          }
        }
        if (ad.status === 'quoted' || ad.status === 'quote_declined') {
          patch.status = 'pending_quote';
          patch.paymentStatus = 'requote_required';
          patch.quotedAmount = FieldValue.delete();
          patch.statusHistory = FieldValue.arrayUnion({
            status: 'pending_quote',
            at: nowIso(),
            by: uid,
          });
        }
      }
      await ref.set(patch, { merge: true });
      return { ok: true, status: patch.status || ad.status };
    },
  );

  const deleteAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const id = String(request.data?.adId || request.data?.id || '').trim();
      const ref = db.collection(ADS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) return { ok: true, alreadyDeleted: true };
      const ad = snap.data() || {};
      await assertAdOwner(uid, ad);
      const status = adPublicStatus(ad);
      if (['active', 'scheduled', 'paused', 'approved'].includes(status)) {
        await ref.set(
          {
            status: 'cancelled',
            cancelledAt: nowIso(),
            cancelledBy: uid,
            statusHistory: FieldValue.arrayUnion({
              status: 'cancelled',
              at: nowIso(),
              by: uid,
            }),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
        return { ok: true, cancelled: true };
      }
      if (['awaiting_payment', 'paid_review'].includes(status)) {
        throw new HttpsError(
          'failed-precondition',
          'Ödeme sürecindeki kampanya silinemez',
        );
      }
      await ref.delete();
      return { ok: true, deleted: true };
    },
  );

  const adminDeleteAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const id = String(request.data?.adId || request.data?.id || '').trim();
      if (!id) throw new HttpsError('invalid-argument', 'adId gerekli');
      await db.collection(ADS).doc(id).delete();
      return { ok: true };
    },
  );

  const trackAdEvent = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) return { ok: true, ignored: true };
      const id = String(request.data?.adId || '').trim();
      const event = String(request.data?.event || '').toLowerCase();
      const placement = String(request.data?.placement || 'feed').toLowerCase();
      if (!id || !['impression', 'click'].includes(event)) {
        throw new HttpsError('invalid-argument', 'Geçersiz reklam olayı');
      }
      if (!['feed', 'reels', 'stories', 'push', 'email'].includes(placement)) {
        throw new HttpsError('invalid-argument', 'Geçersiz yerleşim');
      }
      const ref = db.collection(ADS).doc(id);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = snap.data() || {};
      if (!['active', 'approved'].includes(String(ad.status || ''))) {
        return { ok: true, ignored: true };
      }
      const metric = event === 'click' ? 'clicks' : 'impressions';
      const patch = {
        [`metrics.${metric}`]: FieldValue.increment(1),
        [`metricsByPlacement.${placement}.${metric}`]: FieldValue.increment(1),
        lastMetricAt: nowIso(),
      };
      const city = sanitizePlainText(request.data?.city || '', 80)
        .toLowerCase()
        .replace(/[^a-z0-9çğıöşü]+/gi, '_')
        .slice(0, 50);
      const university = sanitizePlainText(request.data?.university || '', 120)
        .toLowerCase()
        .replace(/[^a-z0-9çğıöşü]+/gi, '_')
        .slice(0, 70);
      const locationKey = university || city;
      if (locationKey) {
        patch[`deliveryLocations.${locationKey}.${metric}`] = FieldValue.increment(1);
      }
      const authUid = String(request.auth.uid || '');
      if (event === 'impression' && authUid) {
        const reachId = crypto
          .createHash('sha256')
          .update(`${id}:${authUid}`)
          .digest('hex');
        const reachRef = db.collection('ad_reach').doc(reachId);
        const reachSnap = await reachRef.get();
        if (!reachSnap.exists) {
          patch['metrics.reach'] = FieldValue.increment(1);
          patch[`metricsByPlacement.${placement}.reach`] = FieldValue.increment(1);
          await reachRef.set({
            adId: id,
            ownerId: ad.ownerId,
            firstPlacement: placement,
            createdAt: nowIso(),
          });
        }
      }
      await ref.set(expandFieldPaths(patch), { merge: true });
      return { ok: true };
    },
  );

  const adminReviewAdCampaign = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const id = String(request.data?.id || '').trim();
      if (!id) throw new HttpsError('invalid-argument', 'id gerekli');
      const currentSnap = await db.collection(ADS).doc(id).get();
      if (!currentSnap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const currentAd = currentSnap.data() || {};
      const status = String(request.data?.status || '').trim();
      if (
        ![
          'active',
          'paused',
          'completed',
          'rejected',
          'pending_review',
          'pending_quote',
          'paid_review',
          'cancelled',
          // legacy
          'approved',
          'pending',
          'ended',
        ].includes(status)
      ) {
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
      if (status === 'active' || status === 'approved') {
        patch.activatedAt = adPublicStatus({ ...currentAd, ...patch }) === 'scheduled'
          ? null
          : nowIso();
      }
      patch.statusHistory = FieldValue.arrayUnion({
        status,
        at: nowIso(),
        by: request.auth.uid,
      });
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
        'emailHeadline',
        'emailBody',
        'ctaLabel',
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
        .where('status', 'in', ['active', 'approved'])
        .limit(100)
        .get();
      const now = Date.now();
      const candidates = [];
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
        const nationwide = citiesAreNationwide(cities);
        const cityOk =
          nationwide ||
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
        candidates.push(a);
      }

      const ownerIds = [
        ...new Set(
          candidates
            .map((a) => String(a.ownerId || a.companyId || a.communityId || ''))
            .filter(Boolean),
        ),
      ];
      const ownerMap = {};
      if (ownerIds.length) {
        const refs = ownerIds.map((id) => db.collection('users').doc(id));
        const ownerSnaps = await db.getAll(...refs);
        for (const s of ownerSnaps) {
          if (!s.exists) continue;
          ownerMap[s.id] = s.data() || {};
        }
      }

      const list = [];
      for (const a of candidates) {
        const ownerId = String(a.ownerId || a.companyId || a.communityId || '');
        const live = ownerMap[ownerId] || {};
        const profile = ownerProfileSnapshot(
          ownerId,
          {
            companyName: a.ownerName || a.companyName,
            username: a.ownerUsername,
            photoUrl: a.ownerPhotoUrl,
            communityLogoUrl: a.ownerPhotoUrl,
            ...live,
          },
          a.ownerType,
        );
        list.push({
          id: a.id,
          title: a.title,
          body: a.body,
          imageUrl: a.imageUrl,
          imageVariants: a.imageVariants || {},
          placements: a.placements,
          linkType: a.linkType,
          linkEventId: a.linkEventId,
          linkJobId: a.linkJobId,
          linkUrl: a.linkUrl,
          companyName: profile.ownerName,
          ownerId: profile.ownerId,
          ownerType: profile.ownerType || a.ownerType,
          ownerName: profile.ownerName,
          ownerUsername: profile.ownerUsername,
          ownerPhotoUrl: profile.ownerPhotoUrl,
          ownerHandle: profile.ownerHandle,
          isCommunity: profile.isCommunity,
          adKind: a.adKind,
          scheduleEnd: a.scheduleEnd,
          badge: 'Sponsorlu',
        });
      }
      for (let i = list.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [list[i], list[j]] = [list[j], list[i]];
      }
      return { ok: true, ads: list };
    },
  );

  const approveEventApplication = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const eventId = sanitizePlainText(request.data?.eventId || '', 120);
      const applicationId = sanitizePlainText(
        request.data?.applicationId || '',
        120,
      );
      if (!eventId || !applicationId) {
        throw new HttpsError('invalid-argument', 'eventId ve applicationId gerekli');
      }

      const eventRef = db.collection('events').doc(eventId);
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw new HttpsError('not-found', 'Etkinlik bulunamadı');
      }
      const event = eventSnap.data() || {};
      const { orgId: organizerId } = await assertCanReviewEvent(
        request.auth.uid,
        event,
      );

      const apps = Array.isArray(event.applications)
        ? event.applications.map((a) => ({ ...a }))
        : [];
      const idx = apps.findIndex(
        (a) => a && String(a.id || '') === applicationId,
      );
      if (idx < 0) {
        throw new HttpsError('not-found', 'Başvuru bulunamadı');
      }
      const app = apps[idx];
      const applicantUid = String(app.userId || '').trim();
      if (!applicantUid) {
        throw new HttpsError('failed-precondition', 'Başvuru kullanıcısı eksik');
      }

      const prevStatus = String(app.status || 'pending');
      if (prevStatus === 'rejected' || prevStatus === 'cancelled') {
        throw new HttpsError(
          'failed-precondition',
          'Bu başvuru onaylanamaz',
        );
      }

      apps[idx] = {
        ...app,
        status: 'approved',
        reviewedAt: nowIso(),
        reviewedBy: request.auth.uid,
      };

      const capacity = Number(event.capacity) || 0;
      const held = apps.filter((a) => {
        const st = String(a?.status || '');
        return st === 'pending' || st === 'approved';
      }).length;

      await eventRef.set(
        {
          applications: apps,
          applicantCount: held,
          updatedAt: nowIso(),
        },
        { merge: true },
      );

      let ticketId = String(app.ticketId || '').trim();
      let emailed = false;
      let ticketCreated = false;

      const needsPaid = eventNeedsPaidTicket(event);
      if (!needsPaid) {
        const issued = await issueComplimentaryEventTicket({
          eventId,
          event,
          eventRef,
          uid: applicantUid,
          userName: app.userName,
          applicationId,
          organizerId,
        });
        ticketId = issued.ticket.id;
        ticketCreated = issued.created;

        apps[idx] = {
          ...apps[idx],
          ticketId,
          paid: false,
          amountPaid: 0,
        };
        await eventRef.set(
          { applications: apps, updatedAt: nowIso() },
          { merge: true },
        );

        try {
          let ticket = { ...issued.ticket };
          if (!ticket.userEmail) {
            const buyer = await db.collection('users').doc(applicantUid).get();
            const bd = buyer.data() || {};
            ticket.userEmail = String(bd.email || '');
            ticket.userName =
              ticket.userName ||
              String(
                bd.fullName || `${bd.firstName || ''} ${bd.lastName || ''}`,
              ).trim();
            if (ticket.userEmail) {
              await issued.ticketRef.set(
                { userEmail: ticket.userEmail, userName: ticket.userName },
                { merge: true },
              );
            }
          }
          if (!ticket.ticketEmailSentAt) {
            await sendTicketEmail(ticket, event, organizerId);
            await issued.ticketRef.set(
              { ticketEmailSentAt: nowIso() },
              { merge: true },
            );
            emailed = true;
          }
        } catch (e) {
          console.error('[approveEventApplication] ticket email', e);
        }

        const eventTitle = String(event.title || 'Etkinlik').trim();
        await notifyUser({
          uid: applicantUid,
          title: 'Biletin hazır',
          body: `${eventTitle} başvurun onaylandı. Biletin uygulamada ve e-postanda.`,
          emoji: '🎫',
          type: 'ticket',
          targetId: ticketId,
          link: `${APP_HOME}/tickets`,
        });
      } else {
        await notifyUser({
          uid: applicantUid,
          title: 'Başvuru onaylandı',
          body: `${String(event.title || 'Etkinlik')} başvurun onaylandı.`,
          emoji: '✅',
          type: 'event',
          targetId: eventId,
          link: `${APP_HOME}/event/${encodeURIComponent(eventId)}`,
        });
      }

      if (capacity > 0 && held >= capacity && organizerId) {
        await notifyUser({
          uid: organizerId,
          title: 'Kadro doldu',
          body: `${String(event.title || 'Etkinlik')} kontenjanı doldu.`,
          emoji: '📋',
          type: 'event',
          targetId: eventId,
          link: `${APP_HOME}/notifications`,
        });
      }

      return {
        ok: true,
        eventId,
        applicationId,
        ticketId: ticketId || null,
        ticketCreated,
        emailed,
        paidEvent: needsPaid,
      };
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
      const tickets = [];
      let backfilled = 0;
      for (const d of snap.docs) {
        const t = { id: d.id, ...d.data() };
        if (!t.shortCode && backfilled < 8) {
          try {
            const code = await allocateShortCode(d.id);
            t.shortCode = code;
            if (!t.qrPayload) t.qrPayload = buildQrPayload(code);
            await d.ref.set(
              { shortCode: code, qrPayload: t.qrPayload, updatedAt: nowIso() },
              { merge: true },
            );
            backfilled += 1;
          } catch (e) {
            console.error('[getMyTickets] shortCode', d.id, e);
          }
        }
        t.qrPayload = t.qrPayload || buildQrPayload(t.shortCode || d.id);
        t.displayCode = t.shortCode || '';
        tickets.push(t);
      }
      return { ok: true, tickets };
    },
  );

  const renameTicketAttendee = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const ticketId = String(request.data?.ticketId || '').trim();
      const userName = sanitizePlainText(request.data?.userName || '', 80);
      if (!ticketId || userName.length < 2) {
        throw new HttpsError('invalid-argument', 'Bilet ve yeni isim gerekli');
      }
      const snap = await db.collection(TICKETS).doc(ticketId).get();
      if (!snap.exists) throw new HttpsError('not-found', 'Bilet bulunamadı');
      const ticket = snap.data() || {};
      if (String(ticket.uid || '') !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Bu bilet sana ait değil');
      }
      const st = String(ticket.status || 'active');
      if (st === 'refunded' || st === 'cancelled') {
        throw new HttpsError('failed-precondition', 'İade edilmiş bilet güncellenemez');
      }
      if (ticketIsUsed(ticket)) {
        throw new HttpsError(
          'failed-precondition',
          'Giriş yapılmış bilette isim değiştirilemez',
        );
      }
      await snap.ref.set(
        { userName, updatedAt: nowIso() },
        { merge: true },
      );
      return { ok: true, ticketId, userName };
    },
  );

  const checkInTicket = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const { ownerId } = await resolveCommerceOwner(request.auth.uid);
      const org = await getOrganizerSettings(ownerId);
      if (!org.isCompany && !org.isEventOrganizer && !org.isCommunity) {
        throw new HttpsError('permission-denied', 'Organizatör yetkisi gerekli');
      }
      const snap = await resolveTicketSnap(
        request.data?.payload || request.data?.ticketId || request.data?.code || '',
      );
      if (!snap) {
        return {
          ok: false,
          invalid: true,
          message: 'Geçersiz · bilet bulunamadı',
        };
      }
      const ticket = snap.data() || {};
      const ticketId = snap.id;
      if (String(ticket.organizerId || '') !== ownerId) {
        return {
          ok: false,
          invalid: true,
          message: 'Geçersiz · bu etkinliğe ait değil',
        };
      }
      const st = String(ticket.status || 'active');
      if (st === 'refunded' || st === 'cancelled') {
        return {
          ok: false,
          invalid: true,
          already: true,
          ticketId,
          eventTitle: ticket.eventTitle || '',
          userName: ticket.userName || '',
          shortCode: ticket.shortCode || '',
          message: 'Geçersiz · iade edilmiş',
        };
      }
      const entry = normalizeTicketEntry(ticket);
      const usedNow = Number(ticket.entriesUsed);
      const used = Number.isFinite(usedNow)
        ? usedNow
        : st === 'used' || st === 'checked_in' || Boolean(ticket.checkedInAt)
          ? entry.entryLimit
          : 0;
      const remainingNow = Math.max(0, entry.entryLimit - used);
      if (used >= entry.entryLimit || remainingNow <= 0) {
        return {
          ok: false,
          invalid: true,
          already: true,
          ticketId,
          eventId: ticket.eventId || '',
          eventTitle: ticket.eventTitle || '',
          userName: ticket.userName || '',
          userEmail: ticket.userEmail || '',
          tierLabel: ticket.tierLabel || '',
          shortCode: ticket.shortCode || '',
          status: 'used',
          entryType: entry.entryType,
          entryLimit: entry.entryLimit,
          entriesUsed: used,
          remaining: 0,
          message: 'Geçersiz · giriş hakkı doldu',
        };
      }
      const confirm = request.data?.confirm === true;
      if (used >= 1 && remainingNow > 0 && !confirm) {
        return {
          ok: false,
          needsConfirm: true,
          ticketId,
          eventId: ticket.eventId || '',
          eventTitle: ticket.eventTitle || '',
          userName: ticket.userName || '',
          userEmail: ticket.userEmail || '',
          tierLabel: ticket.tierLabel || '',
          shortCode: ticket.shortCode || '',
          entryType: entry.entryType,
          entryLimit: entry.entryLimit,
          entriesUsed: used,
          remaining: remainingNow,
          nextEntry: used + 1,
          message: `Çift giriş · ${used + 1}. okutmayı onaylıyor musun? (kalan ${remainingNow})`,
        };
      }
      const nextUsed = used + 1;
      const depleted = nextUsed >= entry.entryLimit;
      const entries = Array.isArray(ticket.entries) ? [...ticket.entries] : [];
      entries.push({
        at: nowIso(),
        by: request.auth.uid,
        n: nextUsed,
      });
      await snap.ref.set(
        {
          status: depleted ? 'used' : 'active',
          entriesUsed: nextUsed,
          entryType: entry.entryType,
          entryLimit: entry.entryLimit,
          entries,
          checkedInAt: nowIso(),
          checkedInBy: request.auth.uid,
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return {
        ok: true,
        already: false,
        invalid: false,
        ticketId,
        eventId: ticket.eventId || '',
        eventTitle: ticket.eventTitle || '',
        userName: ticket.userName || '',
        userEmail: ticket.userEmail || '',
        tierLabel: ticket.tierLabel || '',
        shortCode: ticket.shortCode || '',
        status: depleted ? 'used' : 'active',
        entryType: entry.entryType,
        entryLimit: entry.entryLimit,
        entriesUsed: nextUsed,
        remaining: Math.max(0, entry.entryLimit - nextUsed),
        checkedInAt: nowIso(),
        message: depleted
          ? 'Giriş onaylandı · hak doldu'
          : `Giriş ${nextUsed}/${entry.entryLimit} · kalan ${entry.entryLimit - nextUsed}`,
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
    acceptAdQuote,
    declineAdQuote,
    getMyAdCampaigns,
    updateAdCampaign,
    deleteAdCampaign,
    adminDeleteAdCampaign,
    trackAdEvent,
    adminReviewAdCampaign,
    getActiveAds,
    getMyTickets,
    renameTicketAttendee,
    checkInTicket,
    reverseEventFulfillment,
    reverseMerchFulfillment,
    approveEventApplication,
  };
}

module.exports = { commerceModule };
