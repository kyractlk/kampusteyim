import 'package:cloud_functions/cloud_functions.dart';

class OrgInviteService {
  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<void> invite({
    required String orgId,
    required String orgType,
    required String inviteeUid,
    required bool grantPanelAccess,
    required bool grantBlueBadge,
  }) async {
    await _fn.httpsCallable('inviteOrgMember').call({
      'orgId': orgId,
      'orgType': orgType,
      'inviteeUid': inviteeUid,
      'grantPanelAccess': grantPanelAccess,
      'grantBlueBadge': grantBlueBadge,
    });
  }

  static Future<Map<String, dynamic>> getInvite(String id) async {
    final res = await _fn.httpsCallable('getOrgInvite').call({'inviteId': id});
    return Map<String, dynamic>.from(
      (res.data as Map?)?['invite'] as Map? ?? {},
    );
  }

  static Future<Map<String, dynamic>> listForOrg(String orgId) async {
    final res = await _fn.httpsCallable('listOrgInvites').call({'orgId': orgId});
    return Map<String, dynamic>.from(res.data as Map? ?? {});
  }

  static Future<void> respond({
    required String inviteId,
    required bool accept,
  }) async {
    await _fn.httpsCallable('respondOrgInvite').call({
      'inviteId': inviteId,
      'accept': accept,
    });
  }

  static Future<void> revoke({
    required String orgId,
    String? memberUid,
    String? inviteId,
    bool removeBadge = true,
  }) async {
    await _fn.httpsCallable('revokeOrgMember').call({
      'orgId': orgId,
      if (memberUid != null) 'memberUid': memberUid,
      if (inviteId != null) 'inviteId': inviteId,
      'removeBadge': removeBadge,
    });
  }
}
