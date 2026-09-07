/**
 * Resmi KampüsteyimAPP hesabı + mevcut herkesi takip ettir.
 * Kullanıcı adı: kampusteyim  ·  e-posta: app@kampusteyim.app
 */
const fs = require('fs');
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const EMAIL = 'app@kampusteyim.app';
const USERNAME = 'kampusteyim';
const PASSWORD = process.env.OFFICIAL_PASSWORD || 'kampusteyim2026';
const LOGO_SRC = path.join(__dirname, '..', 'web', 'kampusteyim_icon.png');
const LOGO_DEST = 'branding/kampusteyim_app_logo.png';
const FALLBACK_LOGO = 'https://ayskampuss.web.app/kampusteyim_icon.png';

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'ayskampuss',
    storageBucket: 'ayskampuss.firebasestorage.app',
  });
  const auth = admin.auth();
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;

  let logoUrl = FALLBACK_LOGO;
  if (fs.existsSync(LOGO_SRC)) {
    const bucket = admin.storage().bucket();
    await bucket.upload(LOGO_SRC, {
      destination: LOGO_DEST,
      metadata: {
        contentType: 'image/png',
        cacheControl: 'public,max-age=86400',
      },
    });
    await bucket.file(LOGO_DEST).makePublic().catch(() => {});
    logoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(LOGO_DEST)}?alt=media`;
    console.log('logo', logoUrl);
  }

  let user;
  try {
    user = await auth.getUserByEmail(EMAIL);
    await auth.updateUser(user.uid, {
      displayName: 'KampüsteyimAPP',
      emailVerified: true,
      disabled: false,
      password: PASSWORD,
    });
    console.log('auth exists', user.uid);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({
      email: EMAIL,
      password: PASSWORD,
      displayName: 'KampüsteyimAPP',
      emailVerified: true,
      disabled: false,
    });
    console.log('auth created', user.uid);
  }

  const now = new Date().toISOString();
  const profile = {
    email: EMAIL,
    firstName: 'KampüsteyimAPP',
    lastName: '',
    fullName: 'KampüsteyimAPP',
    role: 'student',
    isCommunity: false,
    isSuperAdmin: false,
    hasGoldBadge: false,
    hasBlueBadge: false,
    isCampusAmbassador: true,
    badgeTitle: 'Kampüs Elçisi',
    accountStatus: 'approved',
    emailVerified: true,
    stableId: user.uid,
    authUid: user.uid,
    username: USERNAME,
    usernameStatus: 'ok',
    city: 'Gaziantep',
    university: 'KampüsteyimAPP',
    bio: 'KampüsteyimAPP resmi hesabı. Kampüs duyuruları, güncellemeler ve destek.',
    photoUrl: logoUrl,
    communityLogoUrl: logoUrl,
    createdByAdmin: 'seed_official_kampusteyim',
    managedAccount: true,
    officialAccount: true,
    updatedAt: now,
  };
  await db.collection('users').doc(user.uid).set(profile, { merge: true });
  await db.collection('handles').doc(USERNAME).set(
    {
      authUid: user.uid,
      userId: user.uid,
      uid: user.uid,
      username: USERNAME,
      createdAt: now,
    },
    { merge: true },
  );
  await db.collection('app_config').doc('official_account').set(
    {
      uid: user.uid,
      username: USERNAME,
      email: EMAIL,
      photoUrl: logoUrl,
      updatedAt: now,
    },
    { merge: true },
  );

  const officialSnap = await db.collection('users').doc(user.uid).get();
  const officialTokens = [user.uid];
  const stable = String(officialSnap.data()?.stableId || '').trim();
  if (stable && stable !== user.uid) officialTokens.push(stable);

  const snap = await db.collection('users').get();
  let followed = 0;
  let followerTokens = [];
  const flushOfficial = async () => {
    if (!followerTokens.length) return;
    await db.collection('users').doc(user.uid).set(
      { followers: FieldValue.arrayUnion(...followerTokens), updatedAt: new Date().toISOString() },
      { merge: true },
    );
    followerTokens = [];
  };

  for (const doc of snap.docs) {
    if (doc.id === user.uid) continue;
    const d = doc.data() || {};
    if (d.deleted === true || d.accountDeleted === true) continue;
    const meTokens = [doc.id];
    const sid = String(d.stableId || '').trim();
    if (sid && sid !== doc.id) meTokens.push(sid);
    await doc.ref.set(
      {
        following: FieldValue.arrayUnion(...officialTokens),
        updatedAt: new Date().toISOString(),
      },
      { merge: true },
    );
    followerTokens.push(...meTokens);
    followed += 1;
    if (followerTokens.length >= 400) await flushOfficial();
  }
  await flushOfficial();

  console.log('official', USERNAME, EMAIL, user.uid);
  console.log('password', PASSWORD);
  console.log('backfill followers', followed);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
