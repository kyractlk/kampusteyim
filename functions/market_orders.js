/**
 * Market siparişleri — merch / etkinlik bileti listeleme + durum + müşteri maili
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');

const FULFILLMENT = {
  awaiting_payment: 'Ödeme bekleniyor',
  preparing: 'Hazırlanıyor',
  packed: 'Paketlendi',
  shipped: 'Kargoya verildi',
  delivered: 'Teslim edildi',
  return_pending: 'İade sürecinde',
  refunded: 'İade edildi',
  cancelled: 'İptal edildi',
};

const ALLOWED = new Set(Object.keys(FULFILLMENT));

function sanitizePlainText(v, max = 200) {
  return String(v || '')
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

function deriveFulfillment(order) {
  const existing = String(order.fulfillmentStatus || '').trim();
  if (ALLOWED.has(existing)) return existing;
  const st = String(order.status || '').toLowerCase();
  const product = String(order.product || '').toLowerCase();
  if (st === 'paid') {
    // Dijital Plus → teslim edilmiş say
    return product === 'plus' ? 'delivered' : 'preparing';
  }
  if (st === 'rejected' || st === 'failed' || st === 'cancelled') {
    return 'cancelled';
  }
  return 'awaiting_payment';
}

function publicOrder(doc) {
  const d = doc.data ? doc.data() : doc;
  const id = doc.id || d.id;
  const meta = d.meta || {};
  const product = String(d.product || 'merch').toLowerCase();
  const fulfillmentStatus = deriveFulfillment(d);
  const months = Number(meta.months) || null;
  let title = meta.merchName || meta.eventTitle || '';
  if (!title && product === 'plus') {
    title =
      meta.plusProductName ||
      (months ? `KampüsteyimPlus · ${months} ay` : 'KampüsteyimPlus');
  }
  return {
    id,
    uid: d.uid || '',
    email: d.email || '',
    amount: Number(d.amount) || 0,
    currency: d.currency || 'TRY',
    product,
    provider: d.provider || '',
    status: d.status || 'pending',
    fulfillmentStatus,
    fulfillmentLabel: FULFILLMENT[fulfillmentStatus] || fulfillmentStatus,
    trackingNo: d.trackingNo || '',
    adminNote: d.adminNote || '',
    ibanReference: d.ibanReference || '',
    createdAt: d.createdAt || null,
    updatedAt: d.updatedAt || null,
    paidAt: d.paidAt || null,
    refundStatus: d.refundStatus || null,
    refundedAmount: Number(d.refundedAmount) || 0,
    merchName: title,
    sku: meta.sku || (product === 'plus' ? 'plus' : null),
    size: meta.size || null,
    months,
    shipName: meta.shipName || meta.userName || '',
    shipAddress: meta.shipAddress || '',
    shipDistrict: meta.shipDistrict || '',
    shipCity: meta.city || '',
    shipPhone: meta.shipPhone || '',
    eventId: meta.eventId || null,
    tierLabel: meta.tierLabel || null,
  };
}

module.exports = function createMarketOrders({
  db,
  assertPlatformAdmin,
  sendMail,
  brandedEmail,
  escapeHtml,
}) {
  const ORDERS = 'payment_orders';

  const listMarketOrders = onCall(
    { region: 'europe-west1', timeoutSeconds: 60 },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Giriş gerekli');
      }
      await assertPlatformAdmin(request.auth.uid);
      const filterStatus = sanitizePlainText(
        request.data?.fulfillmentStatus || '',
        40,
      );
      const snap = await db
        .collection(ORDERS)
        .orderBy('createdAt', 'desc')
        .limit(200)
        .get()
        .catch(async () =>
          db.collection(ORDERS).limit(200).get(),
        );
      let items = snap.docs
        .map((doc) => publicOrder(doc))
        .filter(
          (o) =>
            o.product === 'merch' ||
            o.product === 'event' ||
            o.product === 'plus',
        );
      if (filterStatus && ALLOWED.has(filterStatus)) {
        items = items.filter((o) => o.fulfillmentStatus === filterStatus);
      }
      return { ok: true, items };
    },
  );

  const updateMarketOrderStatus = onCall(
    { region: 'europe-west1', timeoutSeconds: 45 },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Giriş gerekli');
      }
      await assertPlatformAdmin(request.auth.uid);
      const orderId = sanitizePlainText(request.data?.orderId || '', 80);
      const fulfillmentStatus = sanitizePlainText(
        request.data?.fulfillmentStatus || '',
        40,
      );
      const trackingNo = sanitizePlainText(request.data?.trackingNo || '', 80);
      const adminNote = sanitizePlainText(request.data?.adminNote || '', 400);
      const notify = request.data?.notify !== false;

      if (!orderId) throw new HttpsError('invalid-argument', 'orderId gerekli');
      if (!ALLOWED.has(fulfillmentStatus)) {
        throw new HttpsError('invalid-argument', 'Geçersiz sipariş durumu');
      }

      const ref = db.collection(ORDERS).doc(orderId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Sipariş yok');
      const order = snap.data() || {};
      const product = String(order.product || '').toLowerCase();
      if (!['merch', 'event', 'plus'].includes(product)) {
        throw new HttpsError(
          'failed-precondition',
          'Bu sipariş market siparişi değil',
        );
      }

      const now = new Date().toISOString();
      const patch = {
        fulfillmentStatus,
        updatedAt: now,
        fulfillmentUpdatedAt: now,
        fulfillmentUpdatedBy: request.auth.uid,
      };
      if (trackingNo) patch.trackingNo = trackingNo;
      if (adminNote) patch.adminNote = adminNote;
      if (fulfillmentStatus === 'cancelled' && order.status !== 'paid') {
        patch.status = 'cancelled';
      }
      await ref.set(patch, { merge: true });

      let mailSent = false;
      const email = String(order.email || '').toLowerCase();
      if (
        notify &&
        email.includes('@') &&
        !email.includes('@invalid.local') &&
        typeof sendMail === 'function'
      ) {
        const meta = order.meta || {};
        const productLabel =
          product === 'event'
            ? `Etkinlik bileti${meta.tierLabel ? ` · ${meta.tierLabel}` : ''}`
            : product === 'plus'
              ? meta.plusProductName ||
                (meta.months
                  ? `KampüsteyimPlus · ${meta.months} ay`
                  : 'KampüsteyimPlus')
              : meta.merchName
                ? `${meta.merchName}${meta.size ? ` (${meta.size})` : ''}`
                : 'Market siparişi';
        const statusLabel = FULFILLMENT[fulfillmentStatus];
        const trackLine = trackingNo
          ? `<p style="margin:12px 0 0;font-size:15px;color:#1a2332;"><strong>Kargo takip:</strong> ${escapeHtml(trackingNo)}</p>`
          : '';
        const noteLine = adminNote
          ? `<p style="margin:8px 0 0;font-size:14px;color:#4b5563;">${escapeHtml(adminNote)}</p>`
          : '';
        const html =
          typeof brandedEmail === 'function'
            ? brandedEmail({
                title: 'Sipariş durumu güncellendi',
                greeting: 'Merhaba,',
                bodyHtml: `
                  <p style="margin:0 0 12px;font-size:15px;color:#1a2332;line-height:1.55;">
                    <strong>${escapeHtml(productLabel)}</strong> siparişinin durumu güncellendi.
                  </p>
                  <p style="margin:0;padding:14px 16px;background:#F0F7FF;border-radius:12px;font-size:16px;font-weight:800;color:#0B1F3A;">
                    ${escapeHtml(statusLabel)}
                  </p>
                  <p style="margin:12px 0 0;font-size:13px;color:#6b7280;">Sipariş no: ${escapeHtml(orderId)}</p>
                  ${trackLine}
                  ${noteLine}
                `,
                ctaLabel: 'Market’e git',
                ctaUrl: 'https://app.kampusteyim.app/market',
                footerNote:
                  'Bu mail sipariş durumun değiştiği için otomatik gönderildi.',
              })
            : `<p>${escapeHtml(statusLabel)}</p>`;
        try {
          await sendMail({
            to: email,
            subject: `Siparişin: ${statusLabel} · Kampüsteyim`,
            html,
          });
          mailSent = true;
          await ref.set(
            { lastFulfillmentMailAt: now, lastFulfillmentMailStatus: fulfillmentStatus },
            { merge: true },
          );
        } catch (e) {
          console.error('[updateMarketOrderStatus] mail', e);
        }
      }

      const updated = publicOrder({ id: orderId, data: () => ({ ...order, ...patch }) });
      return { ok: true, order: updated, mailSent };
    },
  );

  return { listMarketOrders, updateMarketOrderStatus, FULFILLMENT };
};
