/**
 * PayTR + Shopier + IBAN — tam entegrasyon.
 * Public ayarlar: app_config/payments
 * Gizli anahtarlar: app_secrets/payments (yalnızca Admin SDK)
 */
const crypto = require('crypto');

const DEFAULT_OK = 'https://app.kampusteyim.app/market?pay=ok';
const DEFAULT_FAIL = 'https://app.kampusteyim.app/market?pay=fail';
const DEFAULT_PAYTR_CB =
  'https://europe-west1-ayskampuss.cloudfunctions.net/paytrCallback';
const DEFAULT_PAYTR_PAY =
  'https://europe-west1-ayskampuss.cloudfunctions.net/paytrPayPage';
const DEFAULT_SHOPIER_CB =
  'https://europe-west1-ayskampuss.cloudfunctions.net/shopierCallback';
const DEFAULT_SHOPIER_PAY =
  'https://europe-west1-ayskampuss.cloudfunctions.net/shopierPayPage';

function paymentsModule({
  db,
  onCall,
  onRequest,
  onSchedule,
  HttpsError,
  assertPlatformAdmin,
  assertAdminPermission,
  sanitizePlainText,
  fulfillEventOrder,
  fulfillAdOrder,
  applyDiscountAmount,
  applyMarketCampaign,
  recordCampaignUse,
  sendMail,
}) {
  const PAYMENTS_DOC = 'app_config/payments';
  const SECRETS_DOC = 'app_secrets/payments';
  const ORDERS = 'payment_orders';

  async function readPublicPayments() {
    const snap = await db.doc(PAYMENTS_DOC).get();
    const d = snap.exists ? snap.data() || {} : {};
    return {
      activeProvider: String(d.activeProvider || 'iban').toLowerCase(),
      enabledProviders: Array.isArray(d.enabledProviders)
        ? d.enabledProviders.map((x) => String(x).toLowerCase())
        : ['iban', 'paytr', 'shopier'],
      iban: String(d.iban || '').trim(),
      ibanHolder: String(d.ibanHolder || '').trim(),
      ibanBank: String(d.ibanBank || '').trim(),
      ibanNote: String(
        d.ibanNote ||
          'Havale/EFT açıklamasına yalnızca sistemin verdiği kodu yazın.',
      ).trim(),
      paytrMerchantId: String(d.paytrMerchantId || '').trim(),
      paytrTestMode: d.paytrTestMode !== false,
      shopierWebsiteIndex: Number(d.shopierWebsiteIndex || 1),
      currency: String(d.currency || 'TL'),
      plusProductName: String(d.plusProductName || 'KampüsteyimPlus').trim(),
      plusAmount: Number(d.plusAmount || 0),
      plusDays: Number(d.plusDays || 30),
      plusMonthOptions: Array.isArray(d.plusMonthOptions) && d.plusMonthOptions.length
        ? d.plusMonthOptions
            .map((x) => Number(x))
            .filter((n) => Number.isFinite(n) && n >= 1 && n <= 24)
            .map((n) => Math.floor(n))
        : [1, 3, 6, 12],
      // Fallback / panel URL’leri — admin düzenler
      okUrl: String(d.okUrl || DEFAULT_OK).trim() || DEFAULT_OK,
      failUrl: String(d.failUrl || DEFAULT_FAIL).trim() || DEFAULT_FAIL,
      paytrCallbackUrl:
        String(d.paytrCallbackUrl || DEFAULT_PAYTR_CB).trim() || DEFAULT_PAYTR_CB,
      shopierCallbackUrl:
        String(d.shopierCallbackUrl || DEFAULT_SHOPIER_CB).trim() ||
        DEFAULT_SHOPIER_CB,
      shopierPayPageUrl:
        String(d.shopierPayPageUrl || DEFAULT_SHOPIER_PAY).trim() ||
        DEFAULT_SHOPIER_PAY,
      paytrPayPageUrl:
        String(d.paytrPayPageUrl || DEFAULT_PAYTR_PAY).trim() || DEFAULT_PAYTR_PAY,
      /** Uygulama içi Market sekmesi — admin kapatabilir */
      marketInAppVisible: d.marketInAppVisible !== false,
      /** Merch için PayTR açık mı (kapalıysa IBAN) */
      merchPaytrEnabled: d.merchPaytrEnabled !== false,
      sellerName: String(d.sellerName || 'AYS Tech').trim(),
      sellerEmail: String(d.sellerEmail || 'payments@kampusteyim.app').trim(),
      sellerPhone: String(d.sellerPhone || '+90 555 140 55 01').trim(),
      sellerAddress: String(
        d.sellerAddress || 'PTT Mah. No:8, Yüreğir / Adana',
      ).trim(),
      updatedAt: d.updatedAt || null,
    };
  }

  async function readSecrets() {
    const snap = await db.doc(SECRETS_DOC).get();
    const d = snap.exists ? snap.data() || {} : {};
    return {
      paytrMerchantKey: String(d.paytrMerchantKey || '').trim(),
      paytrMerchantSalt: String(d.paytrMerchantSalt || '').trim(),
      shopierApiKey: String(d.shopierApiKey || '').trim(),
      shopierApiSecret: String(d.shopierApiSecret || '').trim(),
    };
  }

  async function readPaymentsConfig() {
    const [pub, sec] = await Promise.all([readPublicPayments(), readSecrets()]);
    return { ...pub, ...sec };
  }

  function randomCode(len = 8) {
    return crypto.randomBytes(8).toString('hex').slice(0, len).toUpperCase();
  }

  function makeIbanReference(orderId, product) {
    const p = String(product || 'plus').toLowerCase();
    const prefix =
      p === 'event' ? 'KEVT' : p === 'merch' ? 'KMERCH' : p === 'ad' ? 'KAD' : 'KPLUS';
    return `${prefix}-${String(orderId).slice(0, 8).toUpperCase()}-${randomCode(4)}`;
  }

  /** Market merch katalogu — tutarlar sunucuda kilitli. */
  const MERCH_CATALOG = {
    tshirt: {
      sku: 'tshirt',
      name: 'Logo Tişört',
      amount: 349,
      sizes: ['S', 'M', 'L', 'XL'],
      short: 'Beyaz pamuk · göğüs logo baskı · unisex',
    },
    hoodie: {
      sku: 'hoodie',
      name: 'Campus Hoodie',
      amount: 799,
      sizes: ['S', 'M', 'L', 'XL'],
      short: 'Siyah sweatshirt · büyük logo · kışlık',
    },
    cap: {
      sku: 'cap',
      name: 'Navy Şapka',
      amount: 249,
      sizes: ['Tek beden'],
      short: 'Lacivert baseball · önde logo · ayarlı',
    },
    tote: {
      sku: 'tote',
      name: 'Kampüs Tote',
      amount: 199,
      sizes: ['Tek beden'],
      short: 'Bej kanvas · logo baskı · ders / stand',
    },
  };

  async function createOrderDoc({ uid, email, amount, product, provider, meta }) {
    const ref = db.collection(ORDERS).doc();
    const now = new Date().toISOString();
    const prod = product || 'plus';
    const data = {
      id: ref.id,
      uid,
      email: String(email || '').toLowerCase(),
      amount: Number(amount) || 0,
      currency: 'TRY',
      product: prod,
      provider,
      status: 'pending',
      ibanReference: makeIbanReference(ref.id, prod),
      meta: meta || {},
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(data);
    return data;
  }

  function buildPlusPlans(cfg) {
    const months = (cfg.plusMonthOptions || [1, 3, 6, 12]).filter(
      (n, i, a) => a.indexOf(n) === i,
    );
    const unit = Number(cfg.plusAmount) || 0;
    const unitDays = Number(cfg.plusDays) || 30;
    return months.map((m) => ({
      months: m,
      label: m === 1 ? '1 Ay' : `${m} Ay`,
      amount: Math.round(unit * m * 100) / 100,
      days: unitDays * m,
      popular: m === 3,
    }));
  }

  function daysForPlusOrder(order, cfg) {
    const fromMeta = Number(order?.meta?.plusDays);
    if (Number.isFinite(fromMeta) && fromMeta > 0) return Math.floor(fromMeta);
    return Number(cfg.plusDays) > 0 ? Number(cfg.plusDays) : 30;
  }

  async function activatePlusFromOrder(order, days) {
    if (!order?.uid) return;
    const exp = new Date();
    exp.setDate(exp.getDate() + (Number(days) > 0 ? Number(days) : 30));
    await db.collection('users').doc(order.uid).set(
      {
        plusActive: true,
        plusSource: order.provider || 'store',
        plusStartsAt: new Date().toISOString(),
        plusExpiresAt: exp.toISOString(),
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
  }

      async function fulfillPaidOrder(order, cfgOrDays) {
    if (!order) return;
    if (order.meta?.campaignId && typeof recordCampaignUse === 'function') {
      try {
        await recordCampaignUse({
          campaignId: order.meta.campaignId,
          uid: order.uid,
          orderId: order.id,
          code: order.meta.discountCode || order.meta.campaignCode,
        });
      } catch (e) {
        console.error('[recordCampaignUse]', e);
      }
    }
    if (order.product === 'plus') {
      const days =
        typeof cfgOrDays === 'object' && cfgOrDays
          ? daysForPlusOrder(order, cfgOrDays)
          : Number(cfgOrDays) > 0
            ? Number(cfgOrDays)
            : daysForPlusOrder(order, { plusDays: 30 });
      await activatePlusFromOrder(order, days);
      return;
    }
    if (order.product === 'event' && typeof fulfillEventOrder === 'function') {
      await fulfillEventOrder(order);
      return;
    }
    if (order.product === 'ad' && typeof fulfillAdOrder === 'function') {
      await fulfillAdOrder(order);
    }
  }

  const updatePaymentsConfig = onCall(
    { region: 'europe-west1', timeoutSeconds: 30 },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const data = request.data || {};
      const nowIso = new Date().toISOString();
      const pub = { updatedAt: nowIso, updatedBy: request.auth.uid };
      const sec = { updatedAt: nowIso, updatedBy: request.auth.uid };

      const putPub = (k, max = 400) => {
        if (data[k] == null) return;
        pub[k] = sanitizePlainText(data[k], max);
      };
      putPub('activeProvider', 20);
      putPub('iban', 64);
      putPub('ibanHolder', 120);
      putPub('ibanBank', 120);
      putPub('ibanNote', 400);
      putPub('paytrMerchantId', 80);
      putPub('plusProductName', 120);
      putPub('currency', 8);
      putPub('okUrl', 400);
      putPub('failUrl', 400);
      putPub('paytrCallbackUrl', 400);
      putPub('shopierCallbackUrl', 400);
      putPub('shopierPayPageUrl', 400);
      putPub('paytrPayPageUrl', 400);
      putPub('sellerName', 120);
      putPub('sellerEmail', 120);
      putPub('sellerPhone', 40);
      putPub('sellerAddress', 200);

      if (Array.isArray(data.enabledProviders)) {
        pub.enabledProviders = data.enabledProviders
          .map((x) => String(x).toLowerCase())
          .filter((x) => ['paytr', 'shopier', 'iban'].includes(x));
      }
      if (typeof data.paytrTestMode === 'boolean') pub.paytrTestMode = data.paytrTestMode;
      if (typeof data.marketInAppVisible === 'boolean') {
        pub.marketInAppVisible = data.marketInAppVisible;
      }
      if (typeof data.merchPaytrEnabled === 'boolean') {
        pub.merchPaytrEnabled = data.merchPaytrEnabled;
      }
      if (data.shopierWebsiteIndex != null) {
        pub.shopierWebsiteIndex = Number(data.shopierWebsiteIndex) || 1;
      }
      if (data.plusAmount != null) pub.plusAmount = Number(data.plusAmount) || 0;
      if (data.plusDays != null) pub.plusDays = Number(data.plusDays) || 30;
      if (Array.isArray(data.plusMonthOptions)) {
        pub.plusMonthOptions = data.plusMonthOptions
          .map((x) => Number(x))
          .filter((n) => Number.isFinite(n) && n >= 1 && n <= 24)
          .map((n) => Math.floor(n));
        if (!pub.plusMonthOptions.length) pub.plusMonthOptions = [1, 3, 6, 12];
      }

      if (pub.activeProvider && !['paytr', 'shopier', 'iban'].includes(pub.activeProvider)) {
        throw new HttpsError('invalid-argument', 'Geçersiz provider');
      }

      // Secrets — boş string gelirse dokunma (maskeli alan)
      const putSec = (k, max = 200) => {
        if (data[k] == null) return;
        const v = sanitizePlainText(data[k], max);
        if (v) sec[k] = v;
      };
      putSec('paytrMerchantKey');
      putSec('paytrMerchantSalt');
      putSec('shopierApiKey');
      putSec('shopierApiSecret');

      await db.doc(PAYMENTS_DOC).set(pub, { merge: true });
      if (Object.keys(sec).length > 2) {
        await db.doc(SECRETS_DOC).set(sec, { merge: true });
      }

      const cfg = await readPaymentsConfig();
      return {
        ok: true,
        config: adminSafeConfig(cfg),
      };
    },
  );

  function adminSafeConfig(cfg) {
    return {
      ...cfg,
      paytrMerchantKey: cfg.paytrMerchantKey ? '••••••••' : '',
      paytrMerchantSalt: cfg.paytrMerchantSalt ? '••••••••' : '',
      shopierApiKey: cfg.shopierApiKey ? '••••••••' : '',
      shopierApiSecret: cfg.shopierApiSecret ? '••••••••' : '',
      paytrKeySet: Boolean(cfg.paytrMerchantKey),
      paytrSaltSet: Boolean(cfg.paytrMerchantSalt),
      shopierKeySet: Boolean(cfg.shopierApiKey),
      shopierSecretSet: Boolean(cfg.shopierApiSecret),
      defaults: {
        okUrl: DEFAULT_OK,
        failUrl: DEFAULT_FAIL,
        paytrCallbackUrl: DEFAULT_PAYTR_CB,
        paytrPayPageUrl: DEFAULT_PAYTR_PAY,
        shopierCallbackUrl: DEFAULT_SHOPIER_CB,
        shopierPayPageUrl: DEFAULT_SHOPIER_PAY,
      },
    };
  }

  const getPaymentsAdmin = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const cfg = await readPaymentsConfig();
      return { ok: true, config: adminSafeConfig(cfg) };
    },
  );

  const getPaymentsPublic = onCall(
    { region: 'europe-west1' },
    async () => {
      const cfg = await readPaymentsConfig();
      return {
        ok: true,
        activeProvider: cfg.activeProvider,
        enabledProviders: cfg.enabledProviders,
        iban: cfg.iban,
        ibanHolder: cfg.ibanHolder,
        ibanBank: cfg.ibanBank,
        ibanNote: cfg.ibanNote,
        plusProductName: cfg.plusProductName,
        plusAmount: cfg.plusAmount,
        plusDays: cfg.plusDays,
        plusMonthOptions: cfg.plusMonthOptions || [1, 3, 6, 12],
        plusPlans: buildPlusPlans(cfg),
        marketUrl: 'https://app.kampusteyim.app/market',
        currency: cfg.currency,
        okUrl: cfg.okUrl,
        failUrl: cfg.failUrl,
        paytrReady: Boolean(
          cfg.paytrMerchantId && cfg.paytrMerchantKey && cfg.paytrMerchantSalt,
        ),
        paytrTestMode: cfg.paytrTestMode !== false,
        shopierReady: Boolean(cfg.shopierApiKey && cfg.shopierApiSecret),
        ibanReady: Boolean(cfg.iban && cfg.ibanHolder),
        marketInAppVisible: cfg.marketInAppVisible !== false,
        merchPaytrEnabled: cfg.merchPaytrEnabled !== false,
        seller: {
          name: cfg.sellerName,
          email: cfg.sellerEmail,
          phone: cfg.sellerPhone,
          address: cfg.sellerAddress,
        },
        merch: Object.values(MERCH_CATALOG).map((m) => ({
          sku: m.sku,
          name: m.name,
          amount: m.amount,
          sizes: m.sizes,
          short: m.short,
        })),
      };
    },
  );

  const createPaymentOrder = onCall(
    { region: 'europe-west1', timeoutSeconds: 45 },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const product = sanitizePlainText(request.data?.product || 'plus', 40) || 'plus';
      const amountIn = Number(request.data?.amount);
      const cfg = await readPaymentsConfig();
      let provider = sanitizePlainText(
        request.data?.provider || cfg.activeProvider,
        20,
      ).toLowerCase();
      // Merch: PayTR açıksa kart; değilse IBAN (kargo + manuel onay).
      if (product === 'merch') {
        const paytrOk =
          cfg.merchPaytrEnabled !== false &&
          Boolean(cfg.paytrMerchantId && cfg.paytrMerchantKey && cfg.paytrMerchantSalt) &&
          (cfg.enabledProviders || []).includes('paytr');
        if (provider === 'paytr' && !paytrOk) {
          provider = 'iban';
        }
        if (!provider || (provider === 'paytr' && !paytrOk)) {
          provider = paytrOk && cfg.activeProvider === 'paytr' ? 'paytr' : 'iban';
        }
        if (provider === 'paytr' && !paytrOk) provider = 'iban';
        if (provider === 'iban' && (!cfg.iban || !cfg.ibanHolder)) {
          if (paytrOk) provider = 'paytr';
          else throw new HttpsError('failed-precondition', 'IBAN yapılandırılmamış');
        }
      } else if (!cfg.enabledProviders.includes(provider)) {
        throw new HttpsError('failed-precondition', 'Bu ödeme yöntemi kapalı');
      }

      const userSnap = await db.collection('users').doc(uid).get();
      const user = userSnap.data() || {};
      const email = String(user.email || request.auth.token.email || '').toLowerCase();
      if (!email || !email.includes('@')) {
        throw new HttpsError('failed-precondition', 'Hesap e-postası gerekli');
      }

      let amount =
        Number.isFinite(amountIn) && amountIn > 0 ? amountIn : cfg.plusAmount;
      const monthsRaw = Number(request.data?.months);
      const months =
        product === 'plus' &&
        Number.isFinite(monthsRaw) &&
        monthsRaw >= 1 &&
        monthsRaw <= 24
          ? Math.floor(monthsRaw)
          : 1;
      const plusDaysForOrder =
        product === 'plus' ? (Number(cfg.plusDays) || 30) * months : null;
      if (product === 'plus') {
        // Sunucu fiyatı — istemci tutarı ezemez (tek kaynak: plusAmount × ay).
        amount = Math.round((Number(cfg.plusAmount) || 0) * months * 100) / 100;
      }
      const eventId = sanitizePlainText(request.data?.eventId || '', 80);
      const tierLabel = sanitizePlainText(request.data?.tierLabel || '', 80);
      const discountCode = sanitizePlainText(
        request.data?.discountCode || '',
        32,
      ).toUpperCase();
      const merchSku = sanitizePlainText(
        request.data?.sku || '',
        40,
      ).toLowerCase();
      const merchSize = sanitizePlainText(request.data?.size || '', 40);
      const shipCity = sanitizePlainText(request.data?.city || '', 80);
      const shipName = sanitizePlainText(request.data?.shipName || '', 80);
      const userName = sanitizePlainText(
        `${user.firstName || ''} ${user.lastName || ''}`.trim() ||
          user.username ||
          '',
        80,
      );

      let merchItem = null;
      if (product === 'merch') {
        merchItem = MERCH_CATALOG[merchSku] || null;
        if (!merchItem) {
          throw new HttpsError('invalid-argument', 'Geçersiz ürün (sku)');
        }
        if (!merchItem.sizes.includes(merchSize)) {
          throw new HttpsError('invalid-argument', 'Geçersiz beden');
        }
        if (!shipCity || !shipName) {
          throw new HttpsError(
            'invalid-argument',
            'Teslimat için alıcı adı ve şehir gerekli',
          );
        }
        amount = Number(merchItem.amount) || 0;
      }

      let campaignMeta = null;
      if (
        (product === 'plus' || product === 'merch') &&
        discountCode &&
        typeof applyMarketCampaign === 'function'
      ) {
        const disc = await applyMarketCampaign({
          code: discountCode,
          product,
          baseAmount: amount,
          uid,
        });
        amount = disc.amount;
        campaignMeta = {
          campaignId: disc.campaignId,
          campaignCode: disc.code,
          campaignLabel: disc.label,
          discountAmount: disc.discountAmount,
          baseAmountBeforeDiscount: Number(
            product === 'plus'
              ? Math.round((Number(cfg.plusAmount) || 0) * months * 100) / 100
              : merchItem
                ? merchItem.amount
                : amount + (disc.discountAmount || 0),
          ),
        };
      }

      // Etkinlik: tutar sunucuda doğrulanır; ödeyen = katılımcı
      if (product === 'event') {
        if (!eventId) {
          throw new HttpsError('invalid-argument', 'eventId gerekli');
        }
        const evSnap = await db.collection('events').doc(eventId).get();
        if (!evSnap.exists) throw new HttpsError('not-found', 'Etkinlik yok');
        const ev = evSnap.data() || {};
        if (String(ev.status || 'approved') !== 'approved') {
          throw new HttpsError('failed-precondition', 'Etkinlik onaylı değil');
        }
        const tiers = Array.isArray(ev.priceTiers) ? ev.priceTiers : [];
        let base = 0;
        if (tiers.length) {
          const tier =
            tiers.find((t) => String(t.label || '') === tierLabel) || tiers[0];
          base = Number(tier?.amount) || 0;
        } else {
          base = Number(amountIn) || 0;
        }
        if (!(base > 0)) {
          throw new HttpsError(
            'failed-precondition',
            'Ücretsiz etkinlik — ödeme gerekmez, başvuru yap',
          );
        }
        if (typeof applyDiscountAmount === 'function' && discountCode) {
          const disc = await applyDiscountAmount(eventId, discountCode, base);
          amount = disc.amount;
        } else {
          amount = base;
        }
        if (!(amount > 0)) {
          throw new HttpsError('invalid-argument', 'Ödenecek tutar 0');
        }
      } else if (!(amount > 0) && !campaignMeta) {
        throw new HttpsError(
          'invalid-argument',
          'Tutar gerekli (admin’den Plus tutarı girin)',
        );
      } else if (amount < 0) {
        throw new HttpsError('invalid-argument', 'Geçersiz tutar');
      }

      const order = await createOrderDoc({
        uid,
        email,
        amount,
        product,
        provider,
        meta: {
          eventId: eventId || null,
          tierLabel: tierLabel || null,
          discountCode: discountCode || null,
          attendeeUid: uid,
          userName,
          months: product === 'plus' ? months : null,
          plusDays: plusDaysForOrder,
          source: sanitizePlainText(request.data?.source || 'app', 40) || 'app',
          sku: merchItem ? merchItem.sku : null,
          merchName: merchItem ? merchItem.name : null,
          size: merchItem ? merchSize : null,
          city: product === 'merch' ? shipCity || null : null,
          shipName: product === 'merch' ? shipName || userName || null : null,
          discountCode: discountCode || null,
          ...(campaignMeta || {}),
        },
      });

      // %100 indirim → ücretsiz tamamla
      if (amount <= 0 && (product === 'plus' || product === 'merch')) {
        await db.collection(ORDERS).doc(order.id).set(
          {
            status: 'paid',
            paidAt: new Date().toISOString(),
            provider: 'campaign',
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        const paidOrder = { ...order, status: 'paid', provider: 'campaign' };
        if (product === 'plus') {
          await fulfillPaidOrder(paidOrder, cfg);
        } else if (campaignMeta?.campaignId && typeof recordCampaignUse === 'function') {
          await recordCampaignUse({
            campaignId: campaignMeta.campaignId,
            uid,
            orderId: order.id,
            code: campaignMeta.campaignCode,
          });
        }
        return {
          ok: true,
          provider: 'free',
          orderId: order.id,
          amount: 0,
          discountAmount: campaignMeta?.discountAmount || 0,
          message:
            product === 'plus'
              ? 'Kampanya uygulandı — Plus hesabına tanımlandı.'
              : 'Kampanya uygulandı — sipariş ücretsiz oluşturuldu.',
        };
      }

      if (provider === 'iban') {
        if (!cfg.iban || !cfg.ibanHolder) {
          throw new HttpsError('failed-precondition', 'IBAN yapılandırılmamış');
        }
        return {
          ok: true,
          provider: 'iban',
          orderId: order.id,
          amount: order.amount,
          iban: cfg.iban,
          ibanHolder: cfg.ibanHolder,
          ibanBank: cfg.ibanBank,
          transferDescription: order.ibanReference,
          note: cfg.ibanNote,
        };
      }

      if (provider === 'paytr') {
        if (!cfg.paytrMerchantId || !cfg.paytrMerchantKey || !cfg.paytrMerchantSalt) {
          throw new HttpsError('failed-precondition', 'PayTR yapılandırılmamış');
        }
        const merchantOid = order.id.replace(/[^a-zA-Z0-9]/g, '').slice(0, 64);
        const basketTitle = merchItem
          ? `${merchItem.name} (${merchSize})`
          : product === 'plus'
            ? `${cfg.plusProductName || 'KampüsteyimPlus'} · ${months} ay`
            : product === 'event'
              ? `Etkinlik bileti${tierLabel ? ` · ${tierLabel}` : ''}`
              : product === 'ad'
                ? 'Reklam yayını'
                : cfg.plusProductName || product;
        const paymentAmount = String(Math.round(amount * 100));
        const userIp = String(
          request.rawRequest?.headers?.['x-forwarded-for'] ||
            request.rawRequest?.ip ||
            '127.0.0.1',
        )
          .split(',')[0]
          .trim();
        const userBasket = Buffer.from(
          JSON.stringify([[basketTitle, amount.toFixed(2), 1]]),
        ).toString('base64');
        const noInstallment = '0';
        const maxInstallment = '0';
        const currency = 'TL';
        const testMode = cfg.paytrTestMode ? '1' : '0';
        const hashStr =
          cfg.paytrMerchantId +
          userIp +
          merchantOid +
          email +
          paymentAmount +
          userBasket +
          noInstallment +
          maxInstallment +
          currency +
          testMode;
        const paytrToken = crypto
          .createHmac('sha256', cfg.paytrMerchantKey)
          .update(hashStr + cfg.paytrMerchantSalt)
          .digest('base64');

        const form = {
          merchant_id: cfg.paytrMerchantId,
          user_ip: userIp,
          merchant_oid: merchantOid,
          email,
          payment_amount: paymentAmount,
          paytr_token: paytrToken,
          user_basket: userBasket,
          debug_on: testMode,
          no_installment: noInstallment,
          max_installment: maxInstallment,
          user_name: sanitizePlainText(
            `${user.firstName || ''} ${user.lastName || ''}`.trim() ||
              shipName ||
              'Kampusteyim',
            60,
          ),
          user_address: sanitizePlainText(
            shipCity || user.city || 'Turkiye',
            100,
          ) || 'Turkiye',
          user_phone: sanitizePlainText(user.phone || '05000000000', 20) || '05000000000',
          merchant_ok_url: cfg.okUrl,
          merchant_fail_url: cfg.failUrl,
          timeout_limit: '30',
          currency,
          test_mode: testMode,
          lang: 'tr',
        };

        await db.collection(ORDERS).doc(order.id).set(
          { merchantOid, updatedAt: new Date().toISOString() },
          { merge: true },
        );

        const body = new URLSearchParams(form);
        const res = await fetch('https://www.paytr.com/odeme/api/get-token', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body,
        });
        const json = await res.json().catch(() => ({}));
        if (json.status !== 'success' || !json.token) {
          console.error('[paytr] token', json);
          throw new HttpsError(
            'internal',
            'PayTR token alınamadı: ' + (json.reason || json.err_msg || 'bilinmeyen'),
          );
        }
        const iframeUrl = 'https://www.paytr.com/odeme/guvenli/' + json.token;
        const payUrl =
          (cfg.paytrPayPageUrl || DEFAULT_PAYTR_PAY).replace(/\/$/, '') +
          '?orderId=' +
          encodeURIComponent(order.id);
        await db.collection(ORDERS).doc(order.id).set(
          {
            paytrIframeToken: json.token,
            paytrIframeUrl: iframeUrl,
            payTitle: basketTitle,
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        return {
          ok: true,
          provider: 'paytr',
          orderId: order.id,
          token: json.token,
          iframeUrl,
          payUrl,
          amount,
          title: basketTitle,
          testMode: cfg.paytrTestMode !== false,
          okUrl: cfg.okUrl,
          failUrl: cfg.failUrl,
        };
      }

      if (provider === 'shopier') {
        if (!cfg.shopierApiKey || !cfg.shopierApiSecret) {
          throw new HttpsError('failed-precondition', 'Shopier yapılandırılmamış');
        }
        const randomNr = randomCode(10);
        const args = {
          API_key: cfg.shopierApiKey,
          website_index: String(cfg.shopierWebsiteIndex || 1),
          platform_order_id: order.id,
          product_name: cfg.plusProductName || product,
          product_type: '1',
          buyer_name: sanitizePlainText(user.firstName || 'Kampusteyim', 50),
          buyer_surname: sanitizePlainText(user.lastName || 'User', 50),
          buyer_email: email,
          buyer_account_age: '0',
          buyer_id_nr: String(uid).replace(/[^a-zA-Z0-9]/g, '').slice(0, 11) || '0',
          buyer_phone: sanitizePlainText(user.phone || '05000000000', 20),
          billing_address: sanitizePlainText(user.city || 'Turkiye', 100),
          billing_city: sanitizePlainText(user.city || 'Gaziantep', 40),
          billing_country: 'TR',
          billing_postcode: '27000',
          shipping_address: sanitizePlainText(user.city || 'Turkiye', 100),
          shipping_city: sanitizePlainText(user.city || 'Gaziantep', 40),
          shipping_country: 'TR',
          shipping_postcode: '27000',
          total_order_value: amount.toFixed(2),
          currency: '0',
          platform: '0',
          is_in_frame: '0',
          current_language: '0',
          modul_version: '1.0.4',
          random_nr: randomNr,
        };
        const signature = crypto
          .createHmac('sha256', cfg.shopierApiSecret)
          .update(randomNr + order.id + amount.toFixed(2) + '0')
          .digest('base64');
        args.signature = signature;

        await db.collection(ORDERS).doc(order.id).set(
          {
            shopierRandom: randomNr,
            shopierForm: args,
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );

        const payUrl =
          cfg.shopierPayPageUrl.replace(/\/$/, '') +
          '?orderId=' +
          encodeURIComponent(order.id);
        return {
          ok: true,
          provider: 'shopier',
          orderId: order.id,
          payUrl,
          amount,
          okUrl: cfg.okUrl,
          failUrl: cfg.failUrl,
        };
      }

      throw new HttpsError('invalid-argument', 'Bilinmeyen provider');
    },
  );

  /** Shopier otomatik form POST sayfası */
  const shopierPayPage = onRequest(
    { region: 'europe-west1', cors: true },
    async (req, res) => {
      try {
        const orderId = String(req.query.orderId || '').trim();
        if (!orderId) {
          res.status(400).send('orderId gerekli');
          return;
        }
        const snap = await db.collection(ORDERS).doc(orderId).get();
        if (!snap.exists) {
          res.status(404).send('Sipariş bulunamadı');
          return;
        }
        const order = snap.data() || {};
        const form = order.shopierForm;
        if (!form || typeof form !== 'object') {
          res.status(400).send('Shopier formu yok');
          return;
        }
        const fields = Object.keys(form)
          .map(
            (k) =>
              `<input type="hidden" name="${escapeHtml(k)}" value="${escapeHtml(
                String(form[k]),
              )}" />`,
          )
          .join('\n');
        res.set('Content-Type', 'text/html; charset=utf-8');
        res.set('Cache-Control', 'no-store');
        res.status(200).send(`<!DOCTYPE html><html lang="tr"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Shopier ödeme</title>
<style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0B1F3A;color:#fff;margin:0}
.card{text-align:center;padding:2rem}.spin{width:28px;height:28px;border:3px solid rgba(255,255,255,.25);border-top-color:#00D4C8;border-radius:50%;margin:0 auto 1rem;animation:s 0.8s linear infinite}
@keyframes s{to{transform:rotate(360deg)}}</style></head><body>
<div class="card"><div class="spin"></div><p>Shopier ödeme sayfasına yönlendiriliyorsunuz…</p>
<form id="f" method="POST" action="https://www.shopier.com/ShowProduct/api_pay4.php">
${fields}
</form></div>
<script>document.getElementById('f').submit();</script>
</body></html>`);
      } catch (e) {
        console.error('[shopierPayPage]', e);
        res.status(500).send('Hata');
      }
    },
  );

  /** Markalı PayTR iframe ödeme sayfası */
  const paytrPayPage = onRequest(
    { region: 'europe-west1', cors: true },
    async (req, res) => {
      try {
        const orderId = String(req.query.orderId || '').trim();
        if (!orderId) {
          res.status(400).send('orderId gerekli');
          return;
        }
        const [snap, cfg] = await Promise.all([
          db.collection(ORDERS).doc(orderId).get(),
          readPublicPayments(),
        ]);
        if (!snap.exists) {
          res.status(404).send('Sipariş bulunamadı');
          return;
        }
        const order = snap.data() || {};
        const token = String(order.paytrIframeToken || '').trim();
        if (!token) {
          res.status(400).send('PayTR oturumu yok veya süresi dolmuş');
          return;
        }
        const title = escapeHtml(
          order.payTitle ||
            order.meta?.merchName ||
            (order.product === 'plus' ? 'Kampüsteyim Plus' : 'Ödeme'),
        );
        const amountStr = Number(order.amount || 0).toLocaleString('tr-TR', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        });
        const testBadge =
          cfg.paytrTestMode !== false
            ? '<span class="badge">TEST MODU</span>'
            : '';
        const iframeSrc = escapeHtml(
          'https://www.paytr.com/odeme/guvenli/' + token,
        );
        const ok = escapeHtml(cfg.okUrl || DEFAULT_OK);
        const fail = escapeHtml(cfg.failUrl || DEFAULT_FAIL);
        res.set('Content-Type', 'text/html; charset=utf-8');
        res.set('Cache-Control', 'no-store');
        res.set(
          'Content-Security-Policy',
          "frame-src https://www.paytr.com https://*.paytr.com; default-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://fonts.gstatic.com",
        );
        res.status(200).send(`<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Güvenli ödeme · KampüsteyimAPP</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;600;700;800&family=Fraunces:opsz,wght@9..144,700&display=swap" rel="stylesheet"/>
<style>
:root{--navy:#0B1F3A;--cyan:#00D4C8;--ink:#0f172a;--muted:#64748b;--line:#e2e8f0;--bg:#f4f7fb}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;font-family:"DM Sans",system-ui,sans-serif;background:
  radial-gradient(900px 420px at 10% -10%,rgba(0,212,200,.18),transparent 55%),
  radial-gradient(700px 380px at 100% 0%,rgba(11,31,58,.12),transparent 50%),
  var(--bg);color:var(--ink)}
.wrap{max-width:920px;margin:0 auto;padding:1.25rem 1rem 2.5rem}
.top{display:flex;align-items:center;justify-content:space-between;gap:1rem;margin-bottom:1.25rem}
.brand{display:flex;align-items:center;gap:.65rem;font-weight:800;color:var(--navy);text-decoration:none}
.brand span{color:var(--cyan)}
.badge{font-size:.68rem;font-weight:800;letter-spacing:.04em;background:#fef3c7;color:#92400e;padding:.28rem .55rem;border-radius:999px}
.grid{display:grid;gap:1rem}
@media(min-width:860px){.grid{grid-template-columns:300px 1fr}}
.card{background:#fff;border:1px solid var(--line);border-radius:18px;box-shadow:0 16px 40px rgba(15,23,42,.06)}
.summary{padding:1.25rem}
.summary h1{font-family:Fraunces,serif;font-size:1.45rem;margin:0 0 .35rem;line-height:1.2}
.summary p{margin:0;color:var(--muted);font-size:.92rem;line-height:1.45}
.amount{margin-top:1rem;padding:1rem;border-radius:14px;background:linear-gradient(135deg,rgba(11,31,58,.96),#12345a);color:#fff}
.amount .lbl{font-size:.75rem;opacity:.75;font-weight:600}
.amount .val{font-size:1.65rem;font-weight:800;margin-top:.15rem}
.meta{margin-top:.9rem;font-size:.82rem;color:var(--muted);line-height:1.5}
.meta a{color:var(--navy);font-weight:700}
.pay{padding:.85rem;min-height:520px}
.pay iframe{width:100%;min-height:520px;border:0;border-radius:12px;background:#fff}
.foot{margin-top:1rem;text-align:center;font-size:.78rem;color:var(--muted)}
.links{display:flex;flex-wrap:wrap;gap:.75rem;justify-content:center;margin-top:.55rem}
.links a{color:var(--navy);font-weight:700;text-decoration:none}
</style>
</head>
<body>
  <div class="wrap">
    <div class="top">
      <a class="brand" href="https://app.kampusteyim.app/market">Kampüsteyim<span>APP</span></a>
      ${testBadge}
    </div>
    <div class="grid">
      <aside class="card summary">
        <h1>${title}</h1>
        <p>Ödemen PayTR güvencesiyle işlenir. Kart bilgilerin Kampüsteyim sunucularında saklanmaz.</p>
        <div class="amount">
          <div class="lbl">Ödenecek tutar</div>
          <div class="val">${amountStr} TL</div>
        </div>
        <div class="meta">
          Sipariş: <strong>${escapeHtml(orderId)}</strong><br/>
          Satıcı: ${escapeHtml(cfg.sellerName || 'AYS Tech')}<br/>
          <a href="${ok}">Başarılı dönüş</a> · <a href="${fail}">İptal / hata</a>
        </div>
      </aside>
      <section class="card pay">
        <iframe src="${iframeSrc}" id="paytriframe" title="PayTR güvenli ödeme" allow="payment *"></iframe>
      </section>
    </div>
    <div class="foot">
      256-bit SSL · PayTR · KampüsteyimAPP Market
      <div class="links">
        <a href="https://app.kampusteyim.app/sales.html">Satış sözleşmesi</a>
        <a href="https://app.kampusteyim.app/shipping.html">Kargo</a>
        <a href="https://app.kampusteyim.app/returns.html">İade</a>
        <a href="https://app.kampusteyim.app/privacy.html">Gizlilik</a>
      </div>
    </div>
  </div>
</body>
</html>`);
      } catch (e) {
        console.error('[paytrPayPage]', e);
        res.status(500).send('Ödeme sayfası açılamadı');
      }
    },
  );

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  /** Plus bitimine 3 gün kala e-posta (günde 1 kez) */
  const plusExpiryReminders = onSchedule
    ? onSchedule(
        {
          region: 'europe-west1',
          schedule: 'every day 09:00',
          timeZone: 'Europe/Istanbul',
          timeoutSeconds: 120,
        },
        async () => {
          if (typeof sendMail !== 'function') return;
          const now = Date.now();
          const in3 = now + 3 * 24 * 60 * 60 * 1000;
          const snap = await db
            .collection('users')
            .where('plusActive', '==', true)
            .limit(400)
            .get();
          let sent = 0;
          for (const doc of snap.docs) {
            const u = doc.data() || {};
            const exp = Date.parse(String(u.plusExpiresAt || ''));
            if (!Number.isFinite(exp) || exp < now || exp > in3) continue;
            if (u.plusExpiryMailAt) {
              const last = Date.parse(String(u.plusExpiryMailAt));
              if (Number.isFinite(last) && now - last < 2 * 24 * 60 * 60 * 1000) {
                continue;
              }
            }
            const email = String(u.email || '').toLowerCase();
            if (!email.includes('@') || email.includes('@invalid.local')) continue;
            const days = Math.max(1, Math.ceil((exp - now) / (24 * 60 * 60 * 1000)));
            const name = escapeHtml(
              String(u.firstName || u.username || 'Kampüsteyim').trim(),
            );
            try {
              await sendMail({
                to: email,
                subject: `Plus üyeliğin ${days} gün içinde bitiyor`,
                html: `<div style="font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#0f172a">
<h2 style="margin:0 0 8px">Merhaba ${name},</h2>
<p style="line-height:1.5;color:#475569">KampüsteyimPlus üyeliğin <strong>${days} gün</strong> içinde sona eriyor.
Ayrıcalıklarını kesintisiz sürdürmek için markette yenileyebilirsin.</p>
<p><a href="https://app.kampusteyim.app/market#plus" style="display:inline-block;background:#0B1F3A;color:#fff;text-decoration:none;padding:12px 18px;border-radius:10px;font-weight:700">Plus’ı yenile</a></p>
<p style="font-size:12px;color:#94a3b8">KampüsteyimAPP · AYS Tech</p>
</div>`,
              });
              await doc.ref.set(
                { plusExpiryMailAt: new Date().toISOString() },
                { merge: true },
              );
              sent += 1;
            } catch (e) {
              console.error('[plusExpiryReminders]', doc.id, e);
            }
          }
          console.log('[plusExpiryReminders] sent=', sent);
        },
      )
    : null;

  const confirmIbanTransfer = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const orderId = String(request.data?.orderId || '').trim();
      if (!orderId) throw new HttpsError('invalid-argument', 'orderId gerekli');
      const ref = db.collection(ORDERS).doc(orderId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Sipariş yok');
      const order = snap.data() || {};
      if (order.uid !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Bu sipariş sana ait değil');
      }
      await ref.set(
        {
          status: 'awaiting_review',
          userConfirmedAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return {
        ok: true,
        message:
          order.product === 'ad'
            ? 'Ödeme bildirimin alındı. Kontrol edilince reklamın yayın onayına geçer.'
            : order.product === 'event'
              ? 'Ödeme bildirimin alındı. Kontrol edilince etkinlik siparişin onaylanır.'
              : order.product === 'merch'
                ? 'Ödeme tamamlandı olarak bildirildi. Kontrol sonrası kargo hazırlığı başlar.'
                : 'Bildirim alındı. Kod eşleşince Plus hesabın aktif edilir.',
      };
    },
  );

  const adminReviewPaymentOrder = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const orderId = String(request.data?.orderId || '').trim();
      const approve = request.data?.approve !== false;
      if (!orderId) throw new HttpsError('invalid-argument', 'orderId gerekli');
      const ref = db.collection(ORDERS).doc(orderId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Sipariş yok');
      const order = snap.data() || {};
      const product = String(order.product || 'plus').toLowerCase();
      // Plus onayları manage_plus; reklam/etkinlik review_payments ister.
      if (product === 'plus') {
        await assertAdminPermission(request.auth.uid, 'manage_plus');
      } else {
        await assertAdminPermission(request.auth.uid, 'review_payments');
      }
      const cfg = await readPublicPayments();
      if (approve) {
        await ref.set(
          {
            status: 'paid',
            paidAt: new Date().toISOString(),
            reviewedBy: request.auth.uid,
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );
        if (product === 'plus' || product === 'event' || product === 'ad') {
          await fulfillPaidOrder(order, cfg);
        } else if (
          product === 'merch' &&
          order.meta?.campaignId &&
          typeof recordCampaignUse === 'function'
        ) {
          await recordCampaignUse({
            campaignId: order.meta.campaignId,
            uid: order.uid,
            orderId: order.id || orderId,
            code: order.meta.discountCode || order.meta.campaignCode,
          });
        }
      } else {
        await ref.set(
          {
            status: 'rejected',
            reviewedBy: request.auth.uid,
            updatedAt: new Date().toISOString(),
          },
          { merge: true },
        );
      }
      return { ok: true };
    },
  );

  const paytrCallback = onRequest(
    { region: 'europe-west1', cors: false },
    async (req, res) => {
      try {
        const cfg = await readPaymentsConfig();
        const merchantOid = String(req.body?.merchant_oid || '');
        const status = String(req.body?.status || '');
        const totalAmount = String(req.body?.total_amount || '');
        const hash = String(req.body?.hash || '');
        const token = crypto
          .createHmac('sha256', cfg.paytrMerchantKey)
          .update(merchantOid + cfg.paytrMerchantSalt + status + totalAmount)
          .digest('base64');
        if (token !== hash) {
          res.status(400).send('PAYTR notification failed: bad hash');
          return;
        }
        const q = await db
          .collection(ORDERS)
          .where('merchantOid', '==', merchantOid)
          .limit(1)
          .get();
        if (!q.empty) {
          const doc = q.docs[0];
          const order = doc.data() || {};
          if (status === 'success') {
            await doc.ref.set(
              {
                status: 'paid',
                paidAt: new Date().toISOString(),
                updatedAt: new Date().toISOString(),
                providerPayload: { totalAmount },
              },
              { merge: true },
            );
            if (order.product === 'plus' || order.product === 'event' || order.product === 'ad') {
              await fulfillPaidOrder(order, cfg);
            } else if (
              order.product === 'merch' &&
              order.meta?.campaignId &&
              typeof recordCampaignUse === 'function'
            ) {
              await recordCampaignUse({
                campaignId: order.meta.campaignId,
                uid: order.uid,
                orderId: order.id || doc.id,
                code: order.meta.discountCode || order.meta.campaignCode,
              });
            }
          } else {
            await doc.ref.set(
              { status: 'failed', updatedAt: new Date().toISOString() },
              { merge: true },
            );
          }
        }
        res.send('OK');
      } catch (e) {
        console.error('[paytrCallback]', e);
        res.status(500).send('ERR');
      }
    },
  );

  const shopierCallback = onRequest(
    { region: 'europe-west1', cors: false },
    async (req, res) => {
      const cfg = await readPaymentsConfig();
      try {
        const body = req.method === 'GET' ? req.query || {} : req.body || {};
        const orderId = String(body.platform_order_id || body.orderid || '');
        const status = String(body.status || body.payment_status || '');
        const randomNr = String(body.random_nr || '');
        const signature = String(body.signature || '');
        if (signature && randomNr && orderId) {
          const expected = crypto
            .createHmac('sha256', cfg.shopierApiSecret)
            .update(
              randomNr +
                orderId +
                String(body.total_order_value || '') +
                String(body.currency || '0'),
            )
            .digest('base64');
          if (expected !== signature) {
            console.warn('[shopier] signature mismatch', orderId);
          }
        }
        if (!orderId) {
          res.redirect(302, cfg.failUrl);
          return;
        }
        const ref = db.collection(ORDERS).doc(orderId);
        const snap = await ref.get();
        if (!snap.exists) {
          res.redirect(302, cfg.failUrl);
          return;
        }
        const order = snap.data() || {};
        const ok =
          /success|1|paid/i.test(status) ||
          Boolean(body.payment_id) ||
          String(body.status) === '1';
        if (ok) {
          await ref.set(
            {
              status: 'paid',
              paidAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              providerPayload: body,
            },
            { merge: true },
          );
          if (order.product === 'plus' || order.product === 'event' || order.product === 'ad') {
            await fulfillPaidOrder(order, cfg);
          }
          res.redirect(302, cfg.okUrl);
        } else {
          await ref.set(
            { status: 'failed', updatedAt: new Date().toISOString() },
            { merge: true },
          );
          res.redirect(302, cfg.failUrl);
        }
      } catch (e) {
        console.error('[shopierCallback]', e);
        res.redirect(302, cfg.failUrl || DEFAULT_FAIL);
      }
    },
  );

  const adminReviewEvent = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const eventId = String(request.data?.eventId || '').trim();
      const status = String(request.data?.status || '').trim();
      if (!eventId || !['approved', 'rejected', 'pending'].includes(status)) {
        throw new HttpsError('invalid-argument', 'Geçersiz');
      }
      await db.collection('events').doc(eventId).set(
        {
          status,
          reviewedAt: new Date().toISOString(),
          reviewedBy: request.auth.uid,
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return { ok: true };
    },
  );

  const adminDeleteEvent = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const eventId = String(request.data?.eventId || '').trim();
      if (!eventId) throw new HttpsError('invalid-argument', 'eventId gerekli');
      const ref = db.collection('events').doc(eventId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Etkinlik bulunamadı');
      await ref.delete();
      return { ok: true, deletedId: eventId };
    },
  );

  return {
    updatePaymentsConfig,
    getPaymentsAdmin,
    getPaymentsPublic,
    createPaymentOrder,
    confirmIbanTransfer,
    adminReviewPaymentOrder,
    paytrCallback,
    shopierCallback,
    shopierPayPage,
    paytrPayPage,
    plusExpiryReminders,
    adminReviewEvent,
    adminDeleteEvent,
  };
}

module.exports = { paymentsModule };
