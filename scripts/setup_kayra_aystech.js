/**
 * @aystech kurum hesabı + Kayra ilişkisi + gold tick.
 */
const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const EMAIL = 'hr@aystech.com';
const USERNAME = 'aystech';
const PASSWORD = process.env.AYSTECH_PASSWORD || 'aystech2026';
const LOGO_SRC = path.join(__dirname, '..', 'docs', 'marketing', 'shots', 'logo_ays.png');
const LOGO_DEST = 'branding/aystech_logo.png';
const KAYRA_UID = 'CY7B5QmMJFWQDhl8zFQqeAZIlyC2';

async function main() {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'ayskampuss',
    storageBucket: 'ayskampuss.firebasestorage.app',
  });
  const auth = admin.auth();
  const db = admin.firestore();
  const { FieldValue } = admin.firestore;

  const bucket = admin.storage().bucket();
  await bucket.upload(LOGO_SRC, {
    destination: LOGO_DEST,
    metadata: { contentType: 'image/png', cacheControl: 'public,max-age=86400' },
  });
  await bucket.file(LOGO_DEST).makePublic().catch(() => {});
  const logoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(LOGO_DEST)}?alt=media`;
  console.log('logo', logoUrl);

  let user;
  try {
    user = await auth.getUserByEmail(EMAIL);
    await auth.updateUser(user.uid, {
      displayName: 'AYS Tech',
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
      displayName: 'AYS Tech',
      emailVerified: true,
    });
    console.log('auth created', user.uid);
  }

  const official = await db.collection('app_config').doc('official_account').get();
  const officialId = String(official.data()?.uid || '').trim();
  const now = new Date().toISOString();

  await db.collection('users').doc(user.uid).set(
    {
      email: EMAIL,
      firstName: 'AYS Tech',
      lastName: '',
      fullName: 'AYS Tech',
      role: 'company',
      isCommunity: false,
      isSuperAdmin: false,
      hasGoldBadge: true,
      hasBlueBadge: false,
      accountStatus: 'approved',
      stableId: user.uid,
      authUid: user.uid,
      username: USERNAME,
      usernameStatus: 'ok',
      city: 'Gaziantep',
      university: '—',
      bio: 'AYS Tech · yazılım ve kampüs teknolojileri. KampüsteyimAPP’in geliştiricisi.',
      photoUrl: logoUrl,
      communityLogoUrl: logoUrl,
      createdByAdmin: 'setup_kayra_aystech',
      managedAccount: true,
      updatedAt: now,
      ...(officialId
        ? { following: FieldValue.arrayUnion(officialId) }
        : {}),
    },
    { merge: true },
  );
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
  if (officialId) {
    await db.collection('users').doc(officialId).set(
      { followers: FieldValue.arrayUnion(user.uid) },
      { merge: true },
    );
  }

  await db.collection('users').doc(KAYRA_UID).set(
    {
      hasGoldBadge: true,
      username: 'kayra',
      usernameStatus: 'ok',
      affiliatedCommunityId: user.uid,
      affiliatedCommunityName: 'AYS Tech',
      affiliatedCompanyId: user.uid,
      affiliatedCompanyName: 'AYS Tech',
      affiliatedOrgLogoUrl: logoUrl,
      panelOrgId: user.uid,
      panelOrgType: 'company',
      panelOrgName: 'AYS Tech',
      panelAccess: true,
      updatedAt: now,
    },
    { merge: true },
  );
  await db.collection('handles').doc('kayra').set(
    {
      authUid: KAYRA_UID,
      userId: KAYRA_UID,
      uid: KAYRA_UID,
      username: 'kayra',
      createdAt: now,
    },
    { merge: true },
  );

  const ays = (await db.collection('users').doc(user.uid).get()).data();
  const kayra = (await db.collection('users').doc(KAYRA_UID).get()).data();
  console.log('aystech', {
    uid: user.uid,
    email: ays.email,
    role: ays.role,
    username: ays.username,
    gold: ays.hasGoldBadge,
  });
  console.log('kayra', {
    username: kayra.username,
    gold: kayra.hasGoldBadge,
    aff: kayra.affiliatedCommunityName,
    affId: kayra.affiliatedCommunityId,
    panel: kayra.panelOrgName,
  });
  console.log('aystech password', PASSWORD);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
