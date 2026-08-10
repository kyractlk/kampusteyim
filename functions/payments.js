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
const DEFAULT_SHOPIER_CB =
  'https://europe-west1-ayskampuss.cloudfunctions.net/shopierCallback';
const DEFAULT_SHOPIER_PAY =
  'https://europe-west1-ayskampuss.cloudfunctions.net/shopierPayPage';

function paymentsModule({
  db,
  onCall,
  onRequest,
  HttpsError,
  assertPlatformAdmin,
  assertAdminPermission,
  sanitizePlainText,
  fulfillEventOrder,
  fulfillAdOrder,
  applyDiscountAmount,
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

      if (Array.isArray(data.enabledProviders)) {
        pub.enabledProviders = data.enabledProviders
          .map((x) => String(x).toLowerCase())
          .filter((x) => ['paytr', 'shopier', 'iban'].includes(x));
      }
      if (typeof data.paytrTestMode === 'boolean') pub.paytrTestMode = data.paytrTestMode;
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
        shopierReady: Boolean(cfg.shopierApiKey && cfg.shopierApiSecret),
        ibanReady: Boolean(cfg.iban && cfg.ibanHolder),
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
      // Merch: şimdilik yalnızca IBAN / havale (kargo + manuel onay).
      if (product === 'merch') {
        provider = 'iban';
        if (!cfg.iban || !cfg.ibanHolder) {
          throw new HttpsError('failed-precondition', 'IBAN yapılandırılmamış');
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
        amount = Number(merchItem.amount) || 0;
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
      } else if (!(amount > 0)) {
        throw new HttpsError(
          'invalid-argument',
          'Tutar gerekli (admin’den Plus tutarı girin)',
        );
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
        },
      });

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
        const paymentAmount = String(Math.round(amount * 100));
        const userIp = String(
          request.rawRequest?.headers?.['x-forwarded-for'] ||
            request.rawRequest?.ip ||
            '127.0.0.1',
        )
          .split(',')[0]
          .trim();
        const userBasket = Buffer.from(
          JSON.stringify([[cfg.plusProductName || product, amount.toFixed(2), 1]]),
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
            `${user.firstName || ''} ${user.lastName || ''}`.trim() || 'Kampusteyim',
            60,
          ),
          user_address: sanitizePlainText(user.city || 'Turkiye', 100) || 'Turkiye',
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
        return {
          ok: true,
          provider: 'paytr',
          orderId: order.id,
          token: json.token,
          iframeUrl: 'https://www.paytr.com/odeme/guvenli/' + json.token,
          amount,
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

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

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
    adminReviewEvent,
    adminDeleteEvent,
  };
}

module.exports = { paymentsModule };
