import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_info.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../moderation/moderation_models.dart';
import '../notifications/notification_provider.dart';
import 'admin_permissions.dart';

/// Ana platform admin işlemleri + RBAC.
class AdminProvider extends ChangeNotifier {
  AdminProvider() {
    _roles = StaffRole.defaults();
    unawaited(loadRolesFromFirestore());
  }

  final List<ContentReport> reports = [];
  late List<StaffRole> _roles;
  bool busy = false;
  bool rolesLoading = false;
  String? status;

  List<StaffRole> get roles => List.unmodifiable(_roles);

  StaffRole? roleById(String? id) {
    if (id == null) return null;
    try {
      return _roles.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcının yetkisi var mı? Süper admin her zaman true.
  bool can(AppUser? user, AdminPermission permission) {
    if (user == null) return false;
    if (user.isSuperAdmin) return true;
    final role = roleById(user.staffRoleId);
    if (role == null) {
      return user.role == UserRole.admin;
    }
    return role.has(permission);
  }

  bool canAny(AppUser? user, Iterable<AdminPermission> perms) =>
      perms.any((p) => can(user, p));

  /// Bakım bypass: süper admin, manageMaintenance veya accessDuringMaintenance.
  bool canAccessDuringMaintenance(AppUser? user) {
    if (user == null) return false;
    if (user.isSuperAdmin) return true;
    return can(user, AdminPermission.accessDuringMaintenance) ||
        can(user, AdminPermission.manageMaintenance);
  }

  Set<AdminPermission> permissionsOf(AppUser? user) {
    if (user == null) return {};
    if (user.isSuperAdmin) return {...AdminPermission.values};
    final role = roleById(user.staffRoleId);
    if (role == null) {
      return user.role == UserRole.admin ? {...AdminPermission.values} : {};
    }
    if (role.isSuper) return {...AdminPermission.values};
    return Set.of(role.permissions);
  }

  Future<void> loadRolesFromFirestore() async {
    rolesLoading = true;
    notifyListeners();
    try {
      final snap =
          await FirebaseFirestore.instance.collection('staff_roles').get();
      if (snap.docs.isNotEmpty) {
        final loaded = <StaffRole>[];
        for (final d in snap.docs) {
          try {
            final data = d.data();
            data['id'] = data['id'] ?? d.id;
            loaded.add(StaffRole.fromJson(data));
          } catch (_) {}
        }
        if (loaded.isNotEmpty) {
          _roles = StaffRole.mergeWithDefaults(loaded);
        }
      } else {
        _roles = StaffRole.defaults();
        await _persistAllRoles();
      }
      // Süper her zaman tam katalog
      final i = _roles.indexWhere((r) => r.isSuper);
      if (i >= 0) {
        _roles[i] =
            _roles[i].copyWith(permissions: {...AdminPermission.values});
      }
    } catch (e) {
      debugPrint('[admin] loadRoles: $e');
      _roles = StaffRole.defaults();
    }
    rolesLoading = false;
    notifyListeners();
  }

  Future<void> _persistRole(StaffRole role) async {
    try {
      await FirebaseFirestore.instance
          .collection('staff_roles')
          .doc(role.id)
          .set(role.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[admin] persistRole: $e');
    }
  }

  Future<void> _persistAllRoles() async {
    for (final r in _roles) {
      await _persistRole(r);
    }
  }

  Future<void> _deleteRoleDoc(String roleId) async {
    try {
      await FirebaseFirestore.instance
          .collection('staff_roles')
          .doc(roleId)
          .delete();
    } catch (e) {
      debugPrint('[admin] deleteRoleDoc: $e');
    }
  }

  Future<void> loadReportsFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reports')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      if (snap.docs.isEmpty) return;
      final loaded = <ContentReport>[];
      for (final d in snap.docs) {
        try {
          loaded.add(ContentReport.fromJson(d.id, d.data()));
        } catch (_) {}
      }
      if (loaded.isEmpty) return;
      reports
        ..clear()
        ..addAll(loaded);
      notifyListeners();
    } catch (e) {
      debugPrint('[admin] loadReports: $e');
    }
  }

  Future<void> seedDemoReports() async {
    await loadReportsFromFirestore();
  }

  StaffRole createRole({
    required String name,
    required String description,
    required Set<AdminPermission> permissions,
  }) {
    final role = StaffRole(
      id: 'role_${const Uuid().v4().substring(0, 8)}',
      name: name.trim(),
      description: description.trim(),
      permissions: Set.of(permissions),
    );
    _roles.add(role);
    unawaited(_persistRole(role));
    status = 'Rol oluşturuldu: ${role.name}';
    notifyListeners();
    return role;
  }

  void updateRole({
    required String roleId,
    String? name,
    String? description,
    Set<AdminPermission>? permissions,
  }) {
    final i = _roles.indexWhere((r) => r.id == roleId);
    if (i < 0) return;
    final current = _roles[i];
    if (current.isSuper) {
      status = 'Süper Admin rolü değiştirilemez';
      notifyListeners();
      return;
    }
    _roles[i] = current.copyWith(
      name: name,
      description: description,
      permissions: permissions,
    );
    unawaited(_persistRole(_roles[i]));
    status = 'Rol güncellendi';
    notifyListeners();
  }

  void deleteRole(String roleId, AuthProvider auth) {
    final role = roleById(roleId);
    if (role == null) return;
    if (role.isSystem || role.isSuper) {
      status = 'Sistem rolleri silinemez';
      notifyListeners();
      return;
    }
    for (final u in auth.directory) {
      if (u.staffRoleId == roleId) {
        auth.upsertUser(
          u.copyWith(
            clearStaffRole: true,
            role: UserRole.student,
            isSuperAdmin: false,
          ),
        );
      }
    }
    _roles.removeWhere((r) => r.id == roleId);
    unawaited(_deleteRoleDoc(roleId));
    status = 'Rol silindi';
    notifyListeners();
  }

  /// Sistem rollerini güncel AdminPermission kataloğuna göre yeniden kurar.
  void resyncSystemRoles() {
    _roles = StaffRole.mergeWithDefaults(_roles);
    final i = _roles.indexWhere((r) => r.isSuper);
    if (i >= 0) {
      _roles[i] = _roles[i].copyWith(
        permissions: {...AdminPermission.values},
      );
    }
    unawaited(_persistAllRoles());
    status =
        'Sistem rolleri güncellendi · ${AdminPermission.values.length} izin';
    notifyListeners();
  }

  String _tempPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Firma / topluluk hesabı — Auth + Firestore + geçici şifre.
  Future<({AppUser user, String password})> createManagedAccount({
    required AuthProvider auth,
    required String displayName,
    required String email,
    required String kind, // company | community
    String? logoUrl,
    String? password,
  }) async {
    busy = true;
    status = 'Hesap oluşturuluyor…';
    notifyListeners();
    final pass =
        (password != null && password.trim().length >= 6)
            ? password.trim()
            : _tempPassword();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminCreateManagedAccount');
      final res = await callable.call({
        'email': email.trim(),
        'password': pass,
        'displayName': displayName.trim(),
        'kind': kind,
        'logoUrl': ?logoUrl,
      });
      final map = Map<String, dynamic>.from(res.data as Map);
      final uid = '${map['uid'] ?? ''}';
      final stableId = '${map['stableId'] ?? uid}';
      final isCompany = kind == 'company';
      final user = AppUser(
        id: stableId.isNotEmpty ? stableId : uid,
        email: email.trim(),
        studentNo: isCompany
            ? 'C${DateTime.now().millisecondsSinceEpoch % 100000}'
            : 'T${DateTime.now().millisecondsSinceEpoch % 100000}',
        firstName: displayName.trim(),
        lastName: isCompany ? '' : 'Topluluğu',
        phone: '',
        city: 'Gaziantep',
        university: isCompany ? '—' : 'Gaziantep Üniversitesi',
        bio: isCompany
            ? 'Firma hesabı · admin tarafından açıldı'
            : '${displayName.trim()} resmi topluluk hesabı',
        role: isCompany ? UserRole.company : UserRole.community,
        isCommunity: !isCompany,
        hasGoldBadge: !isCompany,
        communityLogoUrl: isCompany
            ? null
            : (logoUrl ?? 'assets/logos/ays_circle.png'),
        username: map['username'] as String?,
      );
      auth.upsertUser(user);
      status = isCompany
          ? 'Firma hesabı hazır · şifreyi kaydet'
          : 'Topluluk hesabı hazır · şifreyi kaydet';
      busy = false;
      notifyListeners();
      return (user: user, password: pass);
    } catch (e) {
      debugPrint('[admin] createManagedAccount: $e');
      if (kind == 'company') {
        final u = await createCompanyAccount(
          auth: auth,
          companyName: displayName,
          email: email,
        );
        busy = false;
        notifyListeners();
        return (user: u, password: pass);
      }
      final u = await createCommunityAccount(
        auth: auth,
        name: displayName,
        email: email,
        logoUrl: logoUrl,
      );
      busy = false;
      notifyListeners();
      return (user: u, password: pass);
    }
  }

  Future<void> assignStaffRole({
    required AuthProvider auth,
    required String userId,
    required String roleId,
  }) async {
    final u = auth.findUser(userId);
    final role = roleById(roleId);
    if (u == null || role == null) return;
    if (u.isSuperAdmin && !role.isSuper) {
      status = 'Süper admin rolü düşürülemez';
      notifyListeners();
      return;
    }
    auth.upsertUser(
      u.copyWith(
        role: UserRole.admin,
        staffRoleId: roleId,
        isSuperAdmin: role.isSuper,
      ),
    );
    status = '${u.fullName} → ${role.name}';
    notifyListeners();
  }

  Future<void> revokeStaffAccess({
    required AuthProvider auth,
    required String userId,
  }) async {
    final u = auth.findUser(userId);
    if (u == null) return;
    if (u.isSuperAdmin) {
      status = 'Süper admin kaldırılamaz';
      notifyListeners();
      return;
    }
    auth.upsertUser(
      u.copyWith(
        role: UserRole.student,
        clearStaffRole: true,
        isSuperAdmin: false,
      ),
    );
    status = 'Admin erişimi kaldırıldı';
    notifyListeners();
  }

  Future<AppUser> createAdminAccount({
    required AuthProvider auth,
    required String firstName,
    required String lastName,
    required String email,
    required String roleId,
  }) async {
    final role = roleById(roleId);
    if (role == null) {
      throw StateError('Rol bulunamadı');
    }
    final user = AppUser(
      id: 'admin_${const Uuid().v4().substring(0, 8)}',
      email: email.trim(),
      studentNo: 'A${DateTime.now().millisecondsSinceEpoch % 100000}',
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      phone: '',
      city: 'Gaziantep',
      university: 'Gaziantep Üniversitesi',
      bio: 'Platform personeli · ${role.name}',
      role: UserRole.admin,
      staffRoleId: roleId,
      isSuperAdmin: role.isSuper,
    );
    auth.upsertUser(user);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyMail');
      await callable.call({
        'to': email.trim(),
        'subject': 'KampüsteyimAPP · Admin hesabın hazır',
        'html':
            '<p>Merhaba $firstName,</p><p>Sana <b>${role.name}</b> rolü ile admin paneli açıldı.</p><p>Yetkiler: ${AdminPermission.keysOf(role.permissions).join(', ')}</p><p>AYS Tech · Kayra Çatalkaya</p>',
      });
    } catch (_) {}
    status = 'Admin oluşturuldu: $email (${role.name})';
    notifyListeners();
    return user;
  }

  Future<void> fileReport(ContentReport report) async {
    reports.insert(0, report);
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(report.id)
          .set(report.toJson());
    } catch (e) {
      debugPrint('[report] firestore: $e');
    }

    // AI ön denetim
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('preReviewReport');
      final res = await callable.call({'reportId': report.id});
      final map = Map<String, dynamic>.from(res.data as Map);
      final i = reports.indexWhere((r) => r.id == report.id);
      if (i >= 0) {
        final st = '${map['status'] ?? report.status.name}';
        reports[i].status = ReportStatus.values.firstWhere(
          (e) => e.name == st,
          orElse: () => report.status,
        );
        reports[i].aiDecision = '${map['aiDecision'] ?? ''}';
        reports[i].aiSummary = '${map['aiSummary'] ?? ''}';
        reports[i].aiConfidence =
            (map['aiConfidence'] as num?)?.toDouble() ?? 0;
        reports[i].aiActed = map['aiActed'] == true;
        reports[i].aiAdminNote = '${map['aiAdminNote'] ?? ''}';
        reports[i].aiLabels =
            ((map['aiLabels'] as List?) ?? []).map((e) => '$e').toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[report] AI preReview: $e');
    }

    if (report.reporterEmail.trim().isNotEmpty) {
      try {
        final callable =
            FirebaseFunctions.instanceFor(region: 'europe-west1')
                .httpsCallable('notifyReportReceived');
        await callable.call({
          'to': report.reporterEmail.trim(),
          'reporterName': report.reporterName,
          'reason': report.reason,
          'targetType': report.targetType.name,
          'snapshotUrl': report.snapshotUrl,
        });
      } catch (e) {
        debugPrint('[report] mail: $e');
      }
    }
  }

  Future<void> resolveReport(String id, ReportStatus next) async {
    final i = reports.indexWhere((r) => r.id == id);
    if (i < 0) return;
    reports[i].status = next;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('reports').doc(id).set({
        'status': next.name,
        'resolvedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[admin] resolveReport: $e');
    }
  }

  Future<void> setCommunityBadge({
    required AuthProvider auth,
    required String userId,
    required bool enabled,
    String? logoUrl,
  }) async {
    final u = auth.findUser(userId);
    if (u == null) return;
    auth.upsertUser(
      u.copyWith(
        isCommunity: enabled,
        role: enabled ? UserRole.community : UserRole.student,
        hasGoldBadge: enabled,
        communityLogoUrl: logoUrl ??
            u.communityLogoUrl ??
            (enabled ? 'assets/logos/ays_circle.png' : null),
        clearAffiliation: enabled,
        hasBlueBadge: enabled ? false : u.hasBlueBadge,
        clearStaffRole: enabled,
        isSuperAdmin: false,
      ),
    );
    status = enabled ? 'Topluluk badge verildi' : 'Topluluk badge kaldırıldı';
    notifyListeners();
  }

  Future<void> linkToCommunity({
    required AuthProvider auth,
    required String userId,
    required String communityId,
  }) async {
    await linkToOrganization(auth: auth, userId: userId, orgId: communityId);
  }

  /// Topluluk veya firma hesabına Twitter tarzı ilişki + isteğe bağlı mavi tick.
  Future<void> linkToOrganization({
    required AuthProvider auth,
    required String userId,
    required String orgId,
    bool grantBlueBadge = false,
    bool grantGoldBadge = false,
  }) async {
    final u = auth.findUser(userId);
    final org = auth.findUser(orgId);
    if (u == null || org == null) return;
    final isOrg = org.isCommunity || org.isCompany || org.hasGoldBadge;
    if (!isOrg) return;
    final logo = org.communityLogoUrl ?? org.photoUrl;
    auth.upsertUser(
      u.copyWith(
        hasBlueBadge: grantBlueBadge ? true : u.hasBlueBadge,
        hasGoldBadge: grantGoldBadge ? true : u.hasGoldBadge,
        affiliatedCommunityId: orgId,
        affiliatedCommunityName: org.fullName.trim().isEmpty
            ? org.firstName
            : org.fullName.trim(),
        affiliatedOrgLogoUrl: logo,
      ),
    );
    status = grantGoldBadge
        ? 'Gold tick + kurum ilişkisi bağlandı'
        : 'Kurum ilişkisi bağlandı';
    notifyListeners();
  }

  Future<void> unlinkCommunity({
    required AuthProvider auth,
    required String userId,
  }) async {
    final u = auth.findUser(userId);
    if (u == null) return;
    auth.upsertUser(
      u.copyWith(
        hasBlueBadge: false,
        clearAffiliation: true,
      ),
    );
    status = 'Kurum ilişkisi kaldırıldı';
    notifyListeners();
  }

  Future<void> applyRestriction({
    required AuthProvider auth,
    required NotificationProvider notifications,
    required String userId,
    required String type,
    required String reason,
    Duration? duration,
  }) async {
    final u = auth.findUser(userId);
    if (u == null) return;
    final until = duration == null ? null : DateTime.now().add(duration);
    auth.upsertUser(
      u.copyWith(
        restrictionType: type,
        restrictionReason: reason,
        restrictionUntil: until,
        clearRestrictionUntil: type == 'none',
      ),
    );

    final title = type == 'none'
        ? 'Kısıtlama kaldırıldı'
        : type == 'fullBan'
            ? 'Hesap askıya alındı'
            : type == 'mute'
                ? 'Hesap susturuldu'
                : type == 'warn'
                    ? 'Uyarı aldın'
                    : 'Paylaşım yasağı';
    final body = type == 'none'
        ? 'Hesap kısıtlamaların kaldırıldı.'
        : '$reason${until != null ? ' · Bitiş: ${until.toLocal()}' : ''}';

    await notifications.pushSocial(
      toUserId: userId,
      title: title,
      body: body,
      emoji: type == 'none'
          ? 'OK'
          : type == 'warn'
              ? '⚠️'
              : 'BAN',
      type: 'moderation',
      actorId: 'ays_guard',
    );

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyMail');
      await callable.call({
        'to': u.email,
        'subject': 'KampüsteyimAPP · $title',
        'title': title,
        'greeting': 'Merhaba ${u.firstName},',
        'bodyHtml':
            '<p>$body</p><p>Bu işlem <b>AYS Tech Guard</b> / platform moderasyonu tarafından kaydedildi.</p>',
        'ctaLabel': 'KampüsteyimAPP’e git',
        'ctaUrl': AppInfo.webBaseUrl,
      });
    } catch (_) {}

    try {
      await FirebaseFirestore.instance.collection('moderation_actions').add({
        'userId': userId,
        'userEmail': u.email,
        'userName': u.fullName,
        'type': type,
        'reason': reason,
        'until': until?.toIso8601String(),
        'actorId': 'ays_guard',
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    status = 'Kısıtlama güncellendi';
    notifyListeners();
  }

  Future<void> sendPasswordReset({required String email}) async {
    busy = true;
    status = 'Şifre sıfırlama gönderiliyor…';
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('sendPasswordReset');
      await callable.call({'email': email});
      status = 'Sıfırlama bağlantısı mail ile gönderildi';
    } catch (e) {
      status = 'Mail kuyruğa alındı (mock): $email';
      debugPrint('$e');
    }
    busy = false;
    notifyListeners();
  }

  Future<AppUser> createCompanyAccount({
    required AuthProvider auth,
    required String companyName,
    required String email,
  }) async {
    final user = AppUser(
      id: 'company_${const Uuid().v4().substring(0, 8)}',
      email: email.trim(),
      studentNo: 'C${DateTime.now().millisecondsSinceEpoch % 100000}',
      firstName: companyName.trim(),
      lastName: '',
      phone: '',
      city: 'Gaziantep',
      university: '—',
      bio: 'Firma hesabı · admin tarafından açıldı',
      role: UserRole.company,
      isCommunity: false,
    );
    auth.upsertUser(user);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyMail');
      await callable.call({
        'to': email.trim(),
        'subject': 'KampüsteyimAPP Firma hesabın hazır',
        'html':
            '<p>Merhaba $companyName,</p><p>Firma panelin açıldı. Giriş: /firma</p><p>Geçici şifre admin tarafından iletilecek.</p><p>AYS Tech · Kayra Çatalkaya</p>',
      });
    } catch (_) {}
    status = 'Firma hesabı oluşturuldu: $email';
    notifyListeners();
    return user;
  }

  Future<AppUser> createCommunityAccount({
    required AuthProvider auth,
    required String name,
    required String email,
    String? logoUrl,
  }) async {
    final user = AppUser(
      id: 'comm_${const Uuid().v4().substring(0, 8)}',
      email: email.trim(),
      studentNo: 'T${DateTime.now().millisecondsSinceEpoch % 100000}',
      firstName: name.trim(),
      lastName: 'Topluluğu',
      phone: '',
      city: 'Gaziantep',
      university: 'Gaziantep Üniversitesi',
      bio: '$name resmi topluluk hesabı',
      role: UserRole.community,
      isCommunity: true,
      hasGoldBadge: true,
      communityLogoUrl: logoUrl ?? 'assets/logos/ays_circle.png',
    );
    auth.upsertUser(user);
    status = 'Topluluk hesabı oluşturuldu';
    notifyListeners();
    return user;
  }

  List<AppUser> communities(AuthProvider auth) =>
      auth.directory.where((u) => u.isCommunity).toList();

  List<AppUser> organizations(AuthProvider auth) => auth.directory
      .where((u) => u.isCommunity || u.isCompany || u.hasGoldBadge)
      .toList();

  List<AppUser> staffMembers(AuthProvider auth) =>
      auth.directory.where((u) => u.canAccessAdmin).toList();

  List<ContentReport> get openReports => reports
      .where((r) =>
          r.status == ReportStatus.open || r.status == ReportStatus.reviewing)
      .toList();

  /// Seçili veya tüm kullanıcılara push + inbox + (opsiyonel) mail.
  Future<({int targeted, int delivered})> broadcastPush({
    required AuthProvider auth,
    required NotificationProvider notifications,
    required String title,
    required String body,
    required bool toAll,
    required Set<String> selectedUserIds,
    bool alsoMail = false,
  }) async {
    busy = true;
    status = 'Push gönderiliyor…';
    notifyListeners();

    final targets = toAll
        ? auth.directory.map((u) => u.id).toList()
        : selectedUserIds.toList();

    var delivered = 0;
    var targeted = targets.length;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('broadcastPush');
      final result = await callable.call({
        'title': title.trim(),
        'body': body.trim(),
        'emoji': '📢',
        'type': 'admin_broadcast',
        'all': toAll,
        'userIds': toAll ? <String>[] : targets,
        'alsoMail': alsoMail,
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      delivered = (data['delivered'] as num?)?.toInt() ?? 0;
      targeted = (data['targeted'] as num?)?.toInt() ?? targeted;
      final noToken = (data['noToken'] as num?)?.toInt() ?? 0;
      if (delivered == 0 && targeted > 0) {
        status =
            'Push: $targeted hedef · 0 cihaz. Token yok ($noToken). Kullanıcı uygulamayı açıp giriş yapsın, bildirim iznini açsın.';
      } else {
        status =
            'Push tamam · $targeted hedef · $delivered cihaz FCM';
      }
    } catch (e) {
      debugPrint('broadcastPush CF: $e');
      for (final id in targets) {
        await notifications.pushSocial(
          toUserId: id,
          title: title.trim(),
          body: body.trim(),
          emoji: '📢',
          type: 'admin_broadcast',
          actorId: auth.user?.id,
        );
        delivered++;
      }
      status = 'Push CF hata · yerel inbox $delivered (FCM yok olabilir)';
    }

    busy = false;
    notifyListeners();
    return (targeted: targeted, delivered: delivered);
  }

  Future<void> setMaintenance({
    required String title,
    required String message,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required bool active,
    bool autoActivate = true,
    bool notifyOnStart = true,
  }) async {
    busy = true;
    status = 'Bakım kaydediliyor…';
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('setMaintenance');
      final result = await callable.call({
        'title': title,
        'message': message,
        'plannedStart': plannedStart.toUtc().toIso8601String(),
        'plannedEnd': plannedEnd.toUtc().toIso8601String(),
        'active': active,
        'autoActivate': autoActivate,
        'notifyOnStart': notifyOnStart,
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      status = data['message']?.toString() ??
          (active ? 'Bakım aktif' : 'Bakım planı kaydedildi');
    } catch (e) {
      debugPrint('setMaintenance: $e');
      status = 'Bakım kaydı başarısız';
      busy = false;
      notifyListeners();
      rethrow;
    }
    busy = false;
    notifyListeners();
  }

  Future<void> endMaintenance() async {
    busy = true;
    status = 'Bakım bitiriliyor…';
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('endMaintenance');
      final result = await callable.call({});
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final mail = (data['mailed'] as num?)?.toInt() ?? 0;
      final push = (data['pushed'] as num?)?.toInt() ?? 0;
      status = 'Bakım bitti · $push push · $mail e-posta';
    } catch (e) {
      debugPrint('endMaintenance: $e');
      status = 'Bakım bitirme başarısız';
      busy = false;
      notifyListeners();
      rethrow;
    }
    busy = false;
    notifyListeners();
  }
}
