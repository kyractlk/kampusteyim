/**
 * Org davetleri + reklam reach (push/mail).
 * commerce.js reklam koleksiyonunu kullanır.
 */
const crypto = require('crypto');

function orgGrowthModule({
  db,
  onCall,
  HttpsError,
  assertPlatformAdmin,
  sanitizePlainText,
  FieldValue,
  sendMail,
  sendFcmToUser,
  buildCampusPushPayload,
  userAllowsPush,
}) {
  const INVITES = 'org_invites';
  const ADS = 'ad_campaigns';
  const BRAND_HOME = 'https://app.kampusteyim.app';

  function nowIso() {
    return new Date().toISOString();
  }

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
            subject: `${orgName} seni KampüsteyimAPP’e davet etti`,
            html: `<p>Merhaba,</p>
<p><strong>${orgName}</strong> seni ${
              grantPanelAccess ? 'panele erişim' : 'üyelik / rozet'
            } için davet etti.</p>
<p>Mailini kontrol et ve uygulamada daveti yanıtla:</p>
<p><a href="${link}">${link}</a></p>
<p>KampüsteyimAPP</p>`,
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
            type: 'system',
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
              type: 'system',
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

  /** Hedef kullanıcılara push + mail reklam */
  const dispatchAdCampaignReach = onCall(
    { region: 'europe-west1', timeoutSeconds: 300 },
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş gerekli');
      await assertPlatformAdmin(request.auth.uid);
      const adId = String(request.data?.adId || '').trim();
      const force = request.data?.force === true;
      if (!adId) throw new HttpsError('invalid-argument', 'adId gerekli');
      const ref = db.collection(ADS).doc(adId);
      const snap = await ref.get();
      if (!snap.exists) throw new HttpsError('not-found', 'Reklam yok');
      const ad = snap.data() || {};
      if (ad.status !== 'approved') {
        throw new HttpsError('failed-precondition', 'Reklam onaylı değil');
      }
      if (ad.reachDispatchedAt && !force) {
        throw new HttpsError(
          'failed-precondition',
          'Reach zaten gönderilmiş (force:true ile tekrar)',
        );
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
      // Geniş çekim — filtre client-side
      let query = db.collection('users').limit(800);
      const usersSnap = await query.get();
      const targets = [];
      for (const d of usersSnap.docs) {
        const u = d.data() || {};
        const city = String(u.city || '').toLowerCase();
        const uni = String(u.university || '').toLowerCase();
        const cityOk = cities.length === 0 || cities.some((c) => city.includes(c) || c.includes(city));
        const uniOk = unis.length === 0 || unis.some((x) => uni.includes(x) || x.includes(uni));
        // Plan: en az bir hedef seçilmiş olmalı; ikisi de varsa AND
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

      const title =
        sanitizePlainText(ad.pushTitle || ad.title || 'Kampüsteyim', 80);
      const body = sanitizePlainText(
        ad.pushBody || ad.body || 'Yeni kampüs duyurusu',
        200,
      );
      const emailSubject = sanitizePlainText(
        ad.emailSubject || ad.title || 'Kampüsteyim reklam',
        120,
      );
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
                targetId: adId,
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
                  data: { targetId: adId },
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
                html:
                  ad.emailHtml ||
                  `<p>${body}</p><p><a href="${BRAND_HOME}">KampüsteyimAPP</a></p>`,
              });
              mailN += 1;
            } catch (_) {}
          }
        }
      }

      await ref.set(
        {
          reachDispatchedAt: nowIso(),
          reachPushCount: pushN,
          reachMailCount: mailN,
          reachTargetCount: targets.length,
          updatedAt: nowIso(),
        },
        { merge: true },
      );
      return {
        ok: true,
        targets: targets.length,
        push: pushN,
        mail: mailN,
      };
    },
  );

  return {
    inviteOrgMember,
    respondOrgInvite,
    revokeOrgMember,
    getOrgInvite,
    dispatchAdCampaignReach,
  };
}

module.exports = { orgGrowthModule };
