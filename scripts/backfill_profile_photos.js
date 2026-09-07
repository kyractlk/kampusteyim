/**
 * Mevcut profil fotoğraflarını en-boy koruyarak kareye oturtur.
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
const {
  isProcessableProfilePath,
  profileUidFromPath,
  writeFittedAvatar,
  pointUserToAvatar,
} = require('../functions/profile_photo')._profilePhotoHelpers;

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'ayskampuss',
  storageBucket: 'ayskampuss.firebasestorage.app',
});

async function main() {
  const bucket = admin.storage().bucket();
  const [files] = await bucket.getFiles({ prefix: 'users/' });
  const byUser = new Map();
  for (const file of files) {
    const name = file.name;
    if (!isProcessableProfilePath(name)) continue;
    const uid = profileUidFromPath(name);
    const prev = byUser.get(uid);
    const updated = file.metadata?.updated || file.metadata?.timeCreated || '';
    if (!prev || updated > prev.updated) {
      byUser.set(uid, { file, updated });
    }
  }
  console.log('candidates', byUser.size);
  let ok = 0;
  let fail = 0;
  for (const [uid, { file }] of byUser) {
    try {
      const [buf] = await file.download();
      const url = await writeFittedAvatar({
        bucket,
        uid,
        sourceBuf: buf,
      });
      await pointUserToAvatar(uid, url, '');
      ok += 1;
      console.log('ok', uid, file.name);
    } catch (e) {
      fail += 1;
      console.warn('fail', uid, file.name, e?.message || e);
    }
  }
  console.log({ ok, fail });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
