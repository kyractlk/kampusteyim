/**
 * Org davetleri + reklam reach (push/mail).
 * commerce.js reklam koleksiyonunu kullanır.
 */
const crypto = require('crypto');

function orgGrowthModule({
  db,
  onCall,
  onRequest,
  onSchedule,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  escapeHtml,
  FieldValue,
  sendMail,
  sendFcmToUser,
  buildCampusPushPayload,
  userAllowsPush,
  expandFieldPaths,
}) {
  const INVITES = 'org_invites';
  const ADS = 'ad_campaigns';
  const BRAND_HOME = 'https://app.kampusteyim.app';
  const EMAIL_OPEN_URL =
    'https://europe-west1-ayskampuss.cloudfunctions.net/trackAdEmailOpen';
  const EMAIL_CLICK_URL =
    'https://europe-west1-ayskampuss.cloudfunctions.net/trackAdEmailClick';

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

  function openAppLandingHtml(path) {
    const safePath = String(path || '/home').replace(/[^a-zA-Z0-9/?=&._-]/g, '');
    return `<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex"/>
<meta name="theme-color" content="#0B1F3A"/>
<title>KampüsteyimAPP · Açılıyor…</title>
<link rel="icon" href="https://ayskampuss.web.app/kampusteyim_icon.png" type="image/png"/>
<script>
(function(){
  var PACKAGE='com.aystech.kampusteyimapp';
  var HOST='app.kampusteyim.app';
  var path=${JSON.stringify(safePath)};
  var ua=navigator.userAgent||'';
  var isIOS=/iphone|ipad|ipod/i.test(ua)||(/macintosh/i.test(ua)&&'ontouchend'in document);
  var isAndroid=/android/i.test(ua);
  window.__ktPath=path;
  window.__ktIOS=isIOS;
  window.__ktAndroid=isAndroid;
  window.__ktStore=isIOS?'https://apps.apple.com/tr/app/id6793663176':(isAndroid?('https://play.google.com/store/apps/details?id='+PACKAGE):'https://kampusteyim.app/#indir');
  if(!isIOS&&!isAndroid)return;
  location.href='kampusteyim://open'+path;
  if(isAndroid){
    setTimeout(function(){
      if(document.hidden)return;
      location.href='intent://'+HOST+path+'#Intent;scheme=https;package='+PACKAGE+';S.browser_fallback_url='+encodeURIComponent(window.__ktStore)+';end';
    },80);
  }
})();
</script>
<style>
body{margin:0;min-height:100svh;display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#fff;background:linear-gradient(155deg,#061426 0%,#0B1F3A 55%,#123456 100%);padding:1.5rem;text-align:center}
.card{max-width:22rem;width:100%}
.logo{width:72px;height:72px;border-radius:18px;margin:0 auto 1.1rem}
h1{font-size:1.45rem;font-weight:800;margin:0 0 .4rem}
h1 span{color:#00D4C8}
p{margin:0 0 1rem;color:rgba(255,255,255,.72)}
.btn{display:block;width:100%;border:0;border-radius:14px;padding:.95rem 1rem;margin:.55rem 0 0;font-weight:700;text-decoration:none;color:#061426;background:#00D4C8}
.btn.secondary{background:rgba(255,255,255,.12);color:#fff;border:1px solid rgba(255,255,255,.28)}
</style>
</head>
<body>
<div class="card">
<img class="logo" src="https://ayskampuss.web.app/kampusteyim_icon.png" width="72" height="72" alt="KampüsteyimAPP"/>
<h1>Kampüsteyim<span>APP</span></h1>
<p>Davet uygulamada açılıyor… Giriş yaptıktan sonra kabul veya red verebilirsin.</p>
<a class="btn" href="kampusteyim://open${safePath}">Uygulamayı aç</a>
<a class="btn secondary" href="https://app.kampusteyim.app${safePath}">Tarayıcıda devam et</a>
</div>
</body>
</html>`;
  }

  function adEmailHtml(ad, recipientId) {
    const variants = ad.imageVariants || {};
    const image = String(variants.email || variants.feed || ad.imageUrl || '');
    const owner = escapeHtml(String(ad.ownerName || ad.companyName || 'Sponsor'));
    const ownerPhoto = String(ad.ownerPhotoUrl || '');
    const headline = escapeHtml(
      String(ad.emailHeadline || ad.title || 'Sizin için bir fırsat'),
    );
    const body = escapeHtml(String(ad.emailBody || ad.body || '')).replace(
      /\n/g,
      '<br/>',
    );
    const ctaLabel = escapeHtml(String(ad.ctaLabel || 'Detayları Gör'));
    const directUrl = String(ad.linkUrl || '');
    const hasCta = /^https:\/\//i.test(directUrl);
    const clickUrl = `${EMAIL_CLICK_URL}?ad=${encodeURIComponent(
      ad.id,
    )}&u=${encodeURIComponent(recipientId)}`;
    const openUrl = `${EMAIL_OPEN_URL}?ad=${encodeURIComponent(
      ad.id,
    )}&u=${encodeURIComponent(recipientId)}`;
    const avatarHtml = /^https:\/\//i.test(ownerPhoto)
      ? `<img src="${escapeHtml(ownerPhoto)}" alt="${owner}" width="36" height="36" style="border-radius:50%;vertical-align:middle;margin-right:10px;object-fit:cover;"/>`
      : '';
    const imageHtml = /^https:\/\//i.test(image)
      ? `<img src="${escapeHtml(image)}" alt="${headline}" width="640" style="display:block;width:100%;height:auto;border-radius:16px;"/>`
      : '';
    const cta = hasCta
      ? `<p style="margin:26px 0 8px;text-align:center;">
          <a href="${clickUrl}" style="display:inline-block;background:#0B1F3A;color:#ffffff;text-decoration:none;padding:14px 30px;border-radius:12px;font-weight:800;font-size:15px;">${ctaLabel}</a>
        </p>`
      : '';
    return `<!doctype html>
<html lang="tr">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#F1F5F9;font-family:Segoe UI,Roboto,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:28px 12px;background:#F1F5F9;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:640px;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #E2E8F0;">
        <tr><td style="padding:18px 24px;background:#0B1F3A;">
          <span style="display:inline-block;padding:5px 9px;border-radius:7px;background:#1FA6A0;color:#ffffff;font-size:10px;font-weight:800;letter-spacing:.7px;">SPONSORLU</span>
          <span style="margin-left:10px;color:#D5E4EE;font-size:13px;font-weight:700;">${avatarHtml}${owner}</span>
        </td></tr>
        <tr><td style="padding:20px 20px 0;">${imageHtml}</td></tr>
        <tr><td style="padding:24px 28px 30px;">
          <h1 style="margin:0 0 12px;color:#0B1F3A;font-size:26px;line-height:1.25;">${headline}</h1>
          <div style="color:#334155;font-size:16px;line-height:1.65;">${body}</div>
          ${cta}
          <p style="margin:26px 0 0;color:#94A3B8;font-size:11px;line-height:1.5;text-align:center;">Bu ileti ${owner} hesabı adına yayınlanan sponsorlu bir içeriktir.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
  <img src="${openUrl}" width="1" height="1" alt="" style="display:none!important;"/>
</body>
</html>`;
  }

  async function incrementEmailMetric(adId, field, userId) {
    if (!adId) return;
    const ref = db.collection(ADS).doc(adId);
    const patch = {
      [`metrics.${field}`]: FieldValue.increment(1),
      [`metricsByPlacement.email.${field}`]: FieldValue.increment(1),
      lastMetricAt: nowIso(),
    };
    if (userId) {
      const eventId = crypto
        .createHash('sha256')
        .update(`${adId}:${userId}:${field}`)
        .digest('hex');
      const eventRef = db.collection('ad_email_events').doc(eventId);
      const eventSnap = await eventRef.get();
      if (eventSnap.exists) return;
      await eventRef.set({ adId, field, createdAt: nowIso() });
    }
    await ref.set(expandFieldPaths(patch), { merge: true });
  }

  const trackAdEmailOpen = onRequest(
    { region: 'europe-west1', cors: true },
    async (request, response) => {
      const adId = sanitizePlainText(request.query.ad || '', 100);
      const userId = sanitizePlainText(request.query.u || '', 150);
      try {
        await incrementEmailMetric(adId, 'emailOpened', userId);
      } catch (_) {}
      const pixel = Buffer.from(
        'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
        'base64',
      );
      response.set('Cache-Control', 'no-store, max-age=0');
      response.type('image/gif').status(200).send(pixel);
    },
  );

  const trackAdEmailClick = onRequest(
    { region: 'europe-west1', cors: true },
    async (request, response) => {
      const adId = sanitizePlainText(request.query.ad || '', 100);
      const userId = sanitizePlainText(request.query.u || '', 150);
      try {
        await incrementEmailMetric(adId, 'emailClicks', userId);
        const snap = await db.collection(ADS).doc(adId).get();
        const url = String(snap.data()?.linkUrl || '');
        if (/^https:\/\//i.test(url)) {
          response.redirect(302, url);
          return;
        }
      } catch (_) {}
      response.status(404).send('Bağlantı bulunamadı');
    },
  );

  async function loadUser(uid) {
    const snap = await db.collection('users').doc(uid).get();
    return { exists: snap.exists, id: uid, data: snap.data() || {} };
  }

  function canManageOrg(user, orgId) {
    if (!user) return false;
    if (user.id === orgId) return true;
    if (String(user.panelOrgId || '') === orgId && user.panelAccess === true) {
      return true;
    }
    return false;
  }

  const inviteOrgMember = onCall(
    { region: 'europe-west1', timeoutSeconds: 60 },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const actorUid = request.auth.uid;
      const actor = await loadUser(actorUid);
      const orgId = String(request.data?.orgId || actorUid).trim();
      const orgType = String(request.data?.orgType || '').toLowerCase();
      if (!['company', 'community'].includes(orgType)) {
        throw new HttpsError('invalid-argument', 'orgType gerekli');
      }
      const org = await loadUser(orgId);
      if (!org.exists) throw new HttpsError('not-found', 'Organizasyon yok');
      const role = String(org.data.role || '');
      if (orgType === 'company' && role !== 'company') {
        throw new HttpsError('failed-precondition', 'Firma hesabı değil');
      }
      if (orgType === 'community' && role !== 'community') {
        throw new HttpsError('failed-precondition', 'Topluluk hesabı değil');
      }
      if (!canManageOrg({ id: actorUid, ...actor.data }, orgId) && actorUid !== orgId) {
        throw new HttpsError('permission-denied', 'Bu org için yetkin yok');
      }

      const inviteeUid = String(request.data?.inviteeUid || '').trim();
      if (!inviteeUid) throw new HttpsError('invalid-argument', 'inviteeUid gerekli');
      if (inviteeUid === orgId) {
        throw new HttpsError('invalid-argument', 'Kendini davet edemezsin');
      }
      const invitee = await loadUser(inviteeUid);
      if (!invitee.exists) throw new HttpsError('not-found', 'Kullanıcı yok');
      const grantPanelAccess = request.data?.grantPanelAccess === true;
      const grantBlueBadge = request.data?.grantBlueBadge !== false;

      const ref = db.collection(INVITES).doc();
      const orgName = String(
        org.data.companyName ||
          org.data.displayName ||
          `${org.data.firstName || ''} ${org.data.lastName || ''}`.trim() ||
          org.data.username ||
          orgId,
      );
      const row = {
        id: ref.id,
        orgId,
        orgType,
        orgName,
        inviteeUid,
        inviteeEmail: String(invitee.data.email || '').toLowerCase(),
        inviteeName: String(
          `${invitee.data.firstName || ''} ${invitee.data.lastName || ''}`.trim() ||
            invitee.data.username ||
            '',
        ),
        invitedBy: actorUid,
        grantPanelAccess,
        grantBlueBadge,
        status: 'pending',
        createdAt: nowIso(),
        updatedAt: nowIso(),
      };
      await ref.set(row);

      const link = `${BRAND_HOME}/invites/${ref.id}`;
      const mailTo = row.inviteeEmail;
      if (mailTo.includes('@')) {
        try {
          await sendMail({
            to: mailTo,
            subject: `${orgName} seni KampüsteyimAPP kadrosuna davet etti`,
            html: `<!doctype html><html lang="tr"><body style="margin:0;padding:24px;background:#F1F5F9;font-family:Segoe UI,Roboto,Arial,sans-serif;color:#0B1F3A;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:18px;overflow:hidden;border:1px solid #E2E8F0;">
<tr><td style="padding:18px 24px;background:#0B1F3A;color:#fff;font-weight:800;">KampüsteyimAPP</td></tr>
<tr><td style="padding:28px 24px 32px;">
<p style="margin:0 0 12px;">Merhaba${row.inviteeName ? ` ${escapeHtml(row.inviteeName)}` : ''},</p>
<p style="margin:0 0 16px;line-height:1.55;"><strong>${escapeHtml(orgName)}</strong> seni ${
              grantPanelAccess ? 'yönetim paneline erişim' : 'üyelik / mavi tick'
            } için kadroya davet etti.</p>
<p style="margin:0 0 22px;text-align:center;">
<a href="${link}" style="display:inline-block;background:#0B1F3A;color:#ffffff;text-decoration:none;padding:14px 26px;border-radius:12px;font-weight:800;">Daveti uygulamada aç</a>
</p>
<p style="margin:0;color:#64748B;font-size:13px;line-height:1.5;">Butona basınca Android veya iOS uygulaması açılır; giriş yaptıktan sonra kabul veya red verebilirsin.</p>
</td></tr></table></td></tr></table>
</body></html>`,
          });
        } catch (e) {
          console.error('[inviteOrgMember] mail', e);
        }
      }

      try {
        const tokens = invitee.data.fcmTokens || [];
        await db
          .collection('users')
          .doc(inviteeUid)
          .collection('notifications')
          .add({
            title: 'Organizasyon daveti',
            body: `${orgName} seni davet etti. Mailini ve bildirimleri kontrol et.`,
            emoji: '✉️',
            type: 'org_invite',
            targetId: ref.id,
            link,
            read: false,
            createdAt: nowIso(),
          });
        if (tokens.length && userAllowsPush(invitee.data, 'system')) {
          await sendFcmToUser(
            inviteeUid,
            tokens,
            buildCampusPushPayload({
              title: 'Organizasyon daveti',
              body: `${orgName} seni davet etti`,
              type: 'org_invite',
              data: { targetId: ref.id, link },
            }),
          );
        }
      } catch (e) {
        console.error('[inviteOrgMember] push', e);
      }

      return { ok: true, id: ref.id };
    },
  );

  const respondOrgInvite = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const uid = request.auth.uid;
      const inviteId = String(request.data?.inviteId || '').trim();
      const accept = request.data?.accept !== false;
      if (!inviteId) throw new HttpsError('invalid-argument', 'inviteId gerekli');
      const ref = db.collection(INVITES).doc(inviteId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Davet yok');
      const inv = snap.data() || {};
      if (inv.inviteeUid !== uid) {
        throw new HttpsError('permission-denied', 'Bu davet sana ait değil');
      }
      if (inv.status !== 'pending') {
        throw new HttpsError('failed-precondition', 'Davet yanıtlanmış');
      }
      if (!accept) {
        await ref.set(
          { status: 'declined', updatedAt: nowIso(), respondedAt: nowIso() },
          { merge: true },
        );
        return { ok: true, status: 'declined' };
      }

      const patchUser = {
        updatedAt: nowIso(),
      };
      if (inv.grantBlueBadge) {
        patchUser.hasBlueBadge = true;
      }
      if (inv.orgType === 'community') {
        patchUser.affiliatedCommunityId = inv.orgId;
        patchUser.affiliatedCommunityName = inv.orgName;
      } else {
        patchUser.affiliatedCompanyId = inv.orgId;
        patchUser.affiliatedCompanyName = inv.orgName;
      }
      if (inv.grantPanelAccess) {
        patchUser.panelOrgId = inv.orgId;
        patchUser.panelOrgType = inv.orgType;
        patchUser.panelOrgName = inv.orgName;
        patchUser.panelAccess = true;
        await db.collection('users').doc(inv.orgId).set(
          {
            orgStaff: FieldValue.arrayUnion([
              {
                uid,
                role: 'staff',
                invitedAt: nowIso(),
                inviteId,
              },
            ]),
            updatedAt: nowIso(),
          },
          { merge: true },
        );
      }
      await db.collection('users').doc(uid).set(patchUser, { merge: true });
      await ref.set(
        { status: 'accepted', updatedAt: nowIso(), respondedAt: nowIso() },
        { merge: true },
      );
      return { ok: true, status: 'accepted' };
    },
  );

  const revokeOrgMember = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const actorUid = request.auth.uid;
      const orgId = String(request.data?.orgId || actorUid).trim();
      const memberUid = String(request.data?.memberUid || '').trim();
      const inviteId = String(request.data?.inviteId || '').trim();
      const removeBadge = request.data?.removeBadge !== false;
      if (!memberUid && !inviteId) {
        throw new HttpsError('invalid-argument', 'memberUid veya inviteId');
      }
      if (actorUid !== orgId) {
        const actor = await loadUser(actorUid);
        if (!canManageOrg({ id: actorUid, ...actor.data }, orgId)) {
          throw new HttpsError('permission-denied', 'Yetki yok');
        }
      }

      if (inviteId) {
        await db.collection(INVITES).doc(inviteId).set(
          { status: 'revoked', updatedAt: nowIso() },
          { merge: true },
        );
      }

      if (memberUid) {
        const member = await loadUser(memberUid);
        const patch = { updatedAt: nowIso() };
        if (member.data.panelOrgId === orgId) {
          patch.panelOrgId = FieldValue.delete();
          patch.panelOrgType = FieldValue.delete();
          patch.panelOrgName = FieldValue.delete();
          patch.panelAccess = false;
        }
        if (removeBadge) {
          if (member.data.affiliatedCommunityId === orgId) {
            patch.affiliatedCommunityId = FieldValue.delete();
            patch.affiliatedCommunityName = FieldValue.delete();
          }
          if (member.data.affiliatedCompanyId === orgId) {
            patch.affiliatedCompanyId = FieldValue.delete();
            patch.affiliatedCompanyName = FieldValue.delete();
          }
          patch.hasBlueBadge = false;
        }
        await db.collection('users').doc(memberUid).set(patch, { merge: true });
      }
      return { ok: true };
    },
  );

  const getOrgInvite = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const id = String(request.data?.inviteId || '').trim();
      if (!id) throw new HttpsError('invalid-argument', 'inviteId');
      const snap = await db.collection(INVITES).doc(id).get();
      if (!snap.exists) throw new HttpsError('not-found', 'Davet yok');
      const inv = snap.data() || {};
      if (inv.inviteeUid !== request.auth.uid && inv.orgId !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Yetki yok');
      }
      return { ok: true, invite: { id: snap.id, ...inv } };
    },
  );

  const listOrgInvites = onCall(
    { region: 'europe-west1' },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      const orgId = String(request.data?.orgId || request.auth.uid).trim();
      const actor = await loadUser(request.auth.uid);
      if (!canManageOrg({ id: request.auth.uid, ...actor.data }, orgId)) {
        throw new HttpsError('permission-denied', 'Yetki yok');
      }
      const snap = await db.collection(INVITES).where('orgId', '==', orgId).limit(80).get();
      const invites = snap.docs
        .map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
      const org = await loadUser(orgId);
      const rawStaff = Array.isArray(org.data.orgStaff) ? org.data.orgStaff : [];
      const staff = [];
      for (const row of rawStaff.slice(0, 40)) {
        const uid = String(row?.uid || '').trim();
        if (!uid) continue;
        const member = await loadUser(uid);
        const name = String(
          `${member.data.firstName || ''} ${member.data.lastName || ''}`.trim() ||
            member.data.username ||
            member.data.email ||
            uid,
        );
        staff.push({
          uid,
          name,
          email: String(member.data.email || ''),
          photoUrl: String(member.data.photoUrl || ''),
          invitedAt: row.invitedAt || '',
        });
      }
      return { ok: true, invites, staff };
    },
  );

  const openAppInvite = onRequest(
    { region: 'europe-west1', cors: true },
    async (request, response) => {
      const raw = String(request.path || request.url || '');
      const m = raw.match(/\/invites\/([^/?#]+)/);
      let id = '';
      try {
        id = sanitizePlainText(m ? decodeURIComponent(m[1]) : '', 80);
      } catch (_) {
        id = sanitizePlainText(m ? m[1] : '', 80);
      }
      const path = id ? `/invites/${id}` : '/home';
      response.set('Cache-Control', 'no-store, max-age=0');
      response.status(200).send(openAppLandingHtml(path));
    },
  );

  async function ensureAdLinkedPost(adId, ad, adRef) {
    const savedId = sanitizePlainText(ad.feedPostId || '', 120);
    const postId = savedId || `adpost_${adId}`;
    const postRef = db.collection('posts').doc(postId);
    const imageUrl = String(
      ad.imageVariants?.feed || ad.imageUrl || '',
    ).trim();
    const linkType = String(ad.linkType || '');
    let ctaUrl = String(ad.linkUrl || '').trim();
    if (!ctaUrl && linkType === 'event' && ad.linkEventId) {
      ctaUrl = `https://app.kampusteyim.app/event/${encodeURIComponent(
        String(ad.linkEventId),
      )}`;
    } else if (!ctaUrl && linkType === 'job' && ad.linkJobId) {
      ctaUrl = 'https://app.kampusteyim.app/jobs';
    }
    const title = sanitizePlainText(ad.title || 'Sponsorlu içerik', 120);
    const body = sanitizePlainText(ad.body || '', 800);
    await postRef.set(
      {
        authorId: String(ad.ownerId || ad.companyId || 'company'),
        authorName: sanitizePlainText(
          ad.ownerName || ad.companyName || 'Firma',
          120,
        ),
        authorHandle: sanitizePlainText(
          ad.ownerHandle || ad.ownerUsername || '@firma',
          80,
        ),
        content: body ? `${title}\n\n${body}` : title,
        createdAt: ad.activatedAt || nowIso(),
        likeCount: 0,
        replyCount: 0,
        repostCount: 0,
        isCommunity: ad.ownerType === 'community',
        hashtags: ['sponsorlu', 'reklam'],
        media: imageUrl ? [{ url: imageUrl, type: 'image' }] : [],
        isSponsored: true,
        adCampaignId: adId,
        ctaUrl,
        ctaLabel: sanitizePlainText(ad.ctaLabel || 'Detayları Gör', 50),
        // Bildirim hedefi olarak gerçek bir posttur; akışta reklam kartıyla
        // ikinci kez görünmemesi için standart post listesinden gizlenir.
        hiddenFromFeed: true,
        moderatedByGuard: true,
        guardDecision: 'allow',
        guardSummary: 'Onaylı reklam bağlantı gönderisi',
      },
      { merge: true },
    );
    await adRef.set(
      {
        feedPostId: postId,
        feedPostPath: `/post/${encodeURIComponent(postId)}`,
        updatedAt: nowIso(),
      },
      { merge: true },
    );
    return postId;
  }

  async function dispatchReachInternal(adId, { force = false } = {}) {
    if (!adId) throw new HttpsError('invalid-argument', 'adId gerekli');
    const ref = db.collection(ADS).doc(adId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
    const ad = snap.data() || {};
    if (!['active', 'approved'].includes(String(ad.status || ''))) {
      throw new HttpsError('failed-precondition', 'Reklam aktif değil');
    }
    const now = Date.now();
    const start = Date.parse(ad.scheduleStart || '');
    const end = Date.parse(ad.scheduleEnd || '');
    if (Number.isFinite(start) && now < start) {
      return { ok: true, skipped: true, reason: 'not_started' };
    }
    if (Number.isFinite(end) && now > end) {
      await ref.set(
        {
          status: 'completed',
          completedAt: nowIso(),
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return { ok: true, skipped: true, reason: 'completed' };
    }
    if (ad.reachDispatchedAt && !force) {
      return { ok: true, skipped: true, reason: 'already_dispatched' };
    }
    const placements = Array.isArray(ad.placements) ? ad.placements : [];
    const wantPush = placements.includes('push');
    const wantMail = placements.includes('email');
    if (!wantPush && !wantMail) {
      return { ok: true, skipped: true, reason: 'no_push_email' };
    }

    const cities = (ad.targetCities || []).map((x) => String(x).toLowerCase());
    const unis = (ad.targetUniversities || []).map((x) =>
      String(x).toLowerCase(),
    );
    const nationwide = citiesAreNationwide(cities);
    const usersSnap = await db.collection('users').limit(800).get();
    const targets = [];
    for (const d of usersSnap.docs) {
      const u = d.data() || {};
      const city = String(u.city || '').toLowerCase();
      const uni = String(u.university || '').toLowerCase();
      const cityOk =
        nationwide ||
        cities.length === 0 ||
        cities.some((c) => city.includes(c) || c.includes(city));
      const uniOk =
        unis.length === 0 ||
        unis.some((x) => uni.includes(x) || x.includes(uni));
      if (cities.length && unis.length) {
        if (!(cityOk && uniOk)) continue;
      } else if (cities.length) {
        if (!cityOk) continue;
      } else if (unis.length) {
        if (!uniOk) continue;
      } else {
        continue;
      }
      targets.push({ id: d.id, ...u });
    }

    const title = sanitizePlainText(
      ad.pushTitle || ad.title || 'Sponsorlu içerik',
      80,
    );
    const body = sanitizePlainText(
      ad.pushBody || ad.body || 'Yeni bir fırsat var',
      200,
    );
    const emailSubject = sanitizePlainText(
      ad.emailSubject || ad.title || 'Sponsorlu içerik',
      120,
    );
    const linkedPostId = await ensureAdLinkedPost(adId, ad, ref);
    const linkedPostPath = `/post/${encodeURIComponent(linkedPostId)}`;
    let pushN = 0;
    let mailN = 0;
    for (const u of targets) {
      if (wantPush) {
        try {
          const tokens = u.fcmTokens || [];
          await db
            .collection('users')
            .doc(u.id)
            .collection('notifications')
            .add({
              title,
              body,
              emoji: '📢',
              type: 'promo',
              targetId: linkedPostId,
              linkPath: linkedPostPath,
              adCampaignId: adId,
              read: false,
              createdAt: nowIso(),
            });
          if (tokens.length && userAllowsPush(u, 'promo')) {
            await sendFcmToUser(
              u.id,
              tokens,
              buildCampusPushPayload({
                title,
                body,
                type: 'promo',
                data: {
                  targetId: linkedPostId,
                  link: linkedPostPath,
                  adId,
                },
              }),
            );
            pushN += 1;
          }
        } catch (_) {}
      }
      if (wantMail) {
        const email = String(u.email || '').toLowerCase();
        if (email.includes('@')) {
          try {
            await sendMail({
              to: email,
              subject: emailSubject,
              html: ad.emailHtml || adEmailHtml({ id: adId, ...ad }, u.id),
            });
            mailN += 1;
          } catch (_) {}
        }
      }
    }

    await ref.set(
      expandFieldPaths({
        reachDispatchedAt: nowIso(),
        reachPushCount: pushN,
        reachMailCount: mailN,
        reachTargetCount: targets.length,
        'metrics.pushSent': FieldValue.increment(pushN),
        'metrics.emailSent': FieldValue.increment(mailN),
        'metricsByPlacement.push.sent': FieldValue.increment(pushN),
        'metricsByPlacement.email.sent': FieldValue.increment(mailN),
        updatedAt: nowIso(),
      }),
      { merge: true },
    );
    return { ok: true, targets: targets.length, push: pushN, mail: mailN };
  }

  /** Hedef kullanıcılara push + HTML reklam e-postası */
  const dispatchAdCampaignReach = onCall(
    { region: 'europe-west1', timeoutSeconds: 300 },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      return dispatchReachInternal(String(request.data?.adId || '').trim(), {
        force: request.data?.force === true,
      });
    },
  );

  /** Planlanan kampanyaların push/e-posta teslimatını otomatik başlatır. */
  const dispatchScheduledAdReach = onSchedule(
    {
      region: 'europe-west1',
      schedule: 'every 10 minutes',
      timeoutSeconds: 540,
    },
    async () => {
      const snap = await db
        .collection(ADS)
        .where('status', 'in', ['active', 'approved'])
        .limit(60)
        .get();
      for (const doc of snap.docs) {
        const ad = doc.data() || {};
        if (ad.reachDispatchedAt) continue;
        try {
          await dispatchReachInternal(doc.id);
        } catch (error) {
          console.error('[ad-schedule]', doc.id, error?.message || error);
        }
      }
    },
  );

  return {
    inviteOrgMember,
    respondOrgInvite,
    revokeOrgMember,
    getOrgInvite,
    listOrgInvites,
    openAppInvite,
    dispatchAdCampaignReach,
    dispatchScheduledAdReach,
    trackAdEmailOpen,
    trackAdEmailClick,
  };
}

module.exports = { orgGrowthModule };
