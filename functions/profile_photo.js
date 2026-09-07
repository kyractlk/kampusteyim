const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getStorage } = require('firebase-admin/storage');
const { getFirestore } = require('firebase-admin/firestore');
const crypto = require('crypto');
const sharp = require('sharp');

const SIZE = 1024;
const OUT_NAME = 'avatar_fit.png';
const BUCKET = 'ayskampuss.firebasestorage.app';

function profileUidFromPath(name) {
  const m = String(name || '').match(/^users\/([^/]+)\/profile\//);
  return m ? m[1] : '';
}

function isProcessableProfilePath(name) {
  const n = String(name || '');
  if (!profileUidFromPath(n)) return false;
  if (n.endsWith(`/${OUT_NAME}`)) return false;
  return true;
}

function storagePathFromUrl(raw) {
  try {
    const u = new URL(String(raw || ''));
    if (!u.hostname.includes('firebasestorage.googleapis.com')) return '';
    const m = u.pathname.match(/\/o\/(.+)$/);
    if (!m) return '';
    return decodeURIComponent(m[1]);
  } catch (_) {
    return '';
  }
}

async function fitProfileBuffer(buf) {
  return sharp(buf)
    .rotate()
    .resize(SIZE, SIZE, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png({ compressionLevel: 8 })
    .toBuffer();
}

function publicDownloadUrl(bucketName, path, token) {
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}`
  );
}

async function writeFittedAvatar({ bucket, uid, sourceBuf }) {
  const outPath = `users/${uid}/profile/${OUT_NAME}`;
  const fitted = await fitProfileBuffer(sourceBuf);
  const token = crypto.randomUUID();
  const dest = bucket.file(outPath);
  await dest.save(fitted, {
    resumable: false,
    metadata: {
      contentType: 'image/png',
      cacheControl: 'public,max-age=3600',
      metadata: {
        processed: '1',
        firebaseStorageDownloadTokens: token,
      },
    },
  });
  return publicDownloadUrl(bucket.name, outPath, token);
}

async function pointUserToAvatar(uid, fittedUrl, previousUrl) {
  const db = getFirestore();
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  const patch = {
    photoUrl: fittedUrl,
    updatedAt: new Date().toISOString(),
  };
  if (snap.exists) {
    const d = snap.data() || {};
    const logo = String(d.communityLogoUrl || '');
    if (!logo || logo === previousUrl) {
      patch.communityLogoUrl = fittedUrl;
    }
  }
  await ref.set(patch, { merge: true });
}

exports.processProfilePhoto = onDocumentWritten(
  {
    document: 'users/{userId}',
    region: 'europe-west1',
    memory: '1GiB',
    timeoutSeconds: 120,
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const uid = event.params.userId;
    const d = after.data() || {};
    const url = String(d.photoUrl || '');
    if (!url || url.includes(OUT_NAME)) return;
    const objectPath = storagePathFromUrl(url);
    if (!isProcessableProfilePath(objectPath)) return;
    const pathUid = profileUidFromPath(objectPath);
    if (pathUid && pathUid !== uid) return;

    const bucket = getStorage().bucket(BUCKET);
    const [buf] = await bucket.file(objectPath).download();
    const fittedUrl = await writeFittedAvatar({
      bucket,
      uid,
      sourceBuf: buf,
    });
    await pointUserToAvatar(uid, fittedUrl, url);
    console.log('[processProfilePhoto]', uid, objectPath, '→', fittedUrl);
  },
);

exports._profilePhotoHelpers = {
  isProcessableProfilePath,
  profileUidFromPath,
  storagePathFromUrl,
  fitProfileBuffer,
  writeFittedAvatar,
  pointUserToAvatar,
};
