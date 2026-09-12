/**
 * eSIM Access API proxy — sipariş, top-up, sorgu, webhook.
 * Credentials: app_secrets/esim_access { accessCode, secretKey }
 */
const crypto = require('crypto');

const BASE = 'https://api.esimaccess.com/api/v1/open';

function sanitizePlainText(v, max = 200) {
  return String(v || '')
    .replace(/[\u0000-\u001F\u007F]/g, '')
    .trim()
    .slice(0, max);
}

async function loadCreds(db) {
  const snap = await db.doc('app_secrets/esim_access').get();
  const d = snap.exists ? snap.data() || {} : {};
  const accessCode = sanitizePlainText(d.accessCode || d.access_code, 80);
  const secretKey = sanitizePlainText(d.secretKey || d.secret_key || accessCode, 80);
  if (!accessCode) {
    const err = new Error('eSIM Access kimlik bilgisi yok (app_secrets/esim_access)');
    err.code = 'failed-precondition';
    throw err;
  }
  return { accessCode, secretKey };
}

function signHeaders(accessCode, secretKey, bodyStr) {
  const timestamp = Date.now().toString();
  const requestId = crypto.randomUUID();
  const signStr = timestamp + requestId + accessCode + bodyStr;
  const signature = crypto
    .createHmac('sha256', secretKey)
    .update(signStr)
    .digest('hex')
    .toLowerCase();
  return {
    'Content-Type': 'application/json',
    'RT-AccessCode': accessCode,
    'RT-Timestamp': timestamp,
    'RT-RequestID': requestId,
    'RT-Signature': signature,
  };
}

async function apiCall(db, endpoint, body = {}) {
  const { accessCode, secretKey } = await loadCreds(db);
  const bodyStr = JSON.stringify(body ?? {});
  const res = await fetch(`${BASE}${endpoint}`, {
    method: 'POST',
    headers: signHeaders(accessCode, secretKey, bodyStr),
    body: bodyStr,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.success === false) {
    const err = new Error(data.errorMsg || data.errorMessage || `eSIM API ${res.status}`);
    err.code = data.errorCode || 'internal';
    err.payload = data;
    throw err;
  }
  return data.obj != null ? data.obj : data;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function orderAndWaitProfile(db, { packageCode, transactionId, count = 1 }) {
  const order = await apiCall(db, '/esim/order', {
    transactionId: sanitizePlainText(transactionId, 50),
    packageInfoList: [{ packageCode: sanitizePlainText(packageCode, 40), count }],
  });
  const orderNo = order.orderNo;
  let profile = null;
  for (let i = 0; i < 10; i++) {
    await sleep(2500);
    const q = await apiCall(db, '/esim/query', {
      orderNo,
      iccid: '',
      pager: { pageNum: 1, pageSize: 20 },
    });
    const list = q.esimList || [];
    if (list[0]?.iccid) {
      profile = list[0];
      break;
    }
  }
  return { orderNo, transactionId, profile };
}

async function topupEsim(db, { esimTranNo, packageCode, transactionId }) {
  return apiCall(db, '/esim/topup', {
    esimTranNo: sanitizePlainText(esimTranNo, 40),
    iccid: '',
    packageCode: sanitizePlainText(packageCode, 40),
    transactionId: sanitizePlainText(transactionId, 50),
  });
}

async function queryEsim(db, { orderNo, iccid, esimTranNo }) {
  if (esimTranNo) {
    const usage = await apiCall(db, '/esim/usage/query', {
      esimTranNoList: [sanitizePlainText(esimTranNo, 40)],
    });
    const q = await apiCall(db, '/esim/query', {
      orderNo: orderNo || '',
      iccid: iccid || '',
      pager: { pageNum: 1, pageSize: 20 },
    });
    return { ...q, usage };
  }
  return apiCall(db, '/esim/query', {
    orderNo: orderNo || '',
    iccid: iccid || '',
    pager: { pageNum: 1, pageSize: 20 },
  });
}

async function listPackages(db, filters = {}) {
  return apiCall(db, '/package/list', {
    locationCode: filters.locationCode || '',
    type: filters.type || '',
    packageCode: filters.packageCode || '',
    slug: filters.slug || '',
    iccid: filters.iccid || '',
    dataType: filters.dataType || '',
  });
}

async function queryBalance(db) {
  return apiCall(db, '/balance/query', {});
}

async function setCredentials(db, { accessCode, secretKey, updatedBy }) {
  const code = sanitizePlainText(accessCode, 80);
  const secret = sanitizePlainText(secretKey || accessCode, 80);
  if (!code) throw new Error('accessCode gerekli');
  await db.doc('app_secrets/esim_access').set(
    {
      accessCode: code,
      secretKey: secret,
      updatedAt: new Date().toISOString(),
      updatedBy: updatedBy || null,
    },
    { merge: true },
  );
  return { ok: true };
}

module.exports = {
  apiCall,
  orderAndWaitProfile,
  topupEsim,
  queryEsim,
  listPackages,
  queryBalance,
  setCredentials,
  BASE,
};
