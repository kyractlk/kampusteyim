import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';

import '../../../core/auth/secure_session.dart';
import '../../../models/models.dart';
import '../../notifications/notification_prefs.dart';

/// Firebase Auth + Firestore profil (canlı dizin).
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _authSub = fa.FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
    unawaited(restorePersistedSession());
    unawaited(syncDirectoryFromFirestore());
  }

  StreamSubscription<fa.User?>? _authSub;
  Timer? _refreshTimer;
  bool _restoring = false;
  bool _directorySyncing = false;
  bool _intentionalAuth = false;
  String? _boundAuthUid;
  fa.User? _pendingAuthUser;

  AppUser? _user;
  bool _busy = false;
  String? _error;
  final List<AppUser> _directory = [];
  /// Eski mock id → Firebase uid (paylaşım / feed tutarlılığı).
  final Map<String, String> _idAliases = {};
  /// Instagram tarzı önerilenler — bu oturumda kapatılanlar (sonra tekrar çıkabilir).
  final Set<String> _dismissedSuggestions = {};
  /// Takip mutasyonu sırasında remote sync follow alanlarını ezmesin.
  int _followGraphBusy = 0;

  AppUser? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isBusy => _busy;
  String? get error => _error;
  List<AppUser> get directory => List.unmodifiable(_directory);
  Set<String> get dismissedSuggestions =>
      Set.unmodifiable(_dismissedSuggestions);

  AppUser? findUser(String id) {
    final raw = id.trim();
    final resolved = _idAliases[raw] ?? raw;
    final asHandle = raw.replaceFirst(RegExp(r'^@'), '').toLowerCase();
    for (final u in _directory) {
      if (u.id == raw || u.id == resolved) return u;
      final uname = u.username?.trim().toLowerCase();
      if (uname != null && uname == asHandle) return u;
      if (u.handle.toLowerCase() == '@$asHandle') return u;
    }
    return null;
  }

  /// Profil derin linkleri: username, eski mock id + Firebase uid.
  Set<String> idsFor(String id) {
    final out = <String>{id};
    final mapped = _idAliases[id];
    if (mapped != null) out.add(mapped);
    for (final e in _idAliases.entries) {
      if (e.value == id || e.key == id) {
        out.add(e.key);
        out.add(e.value);
      }
    }
    final user = findUser(id);
    if (user != null) {
      out.add(user.id);
      final uname = user.username?.trim();
      if (uname != null && uname.isNotEmpty) out.add(uname);
    }
    return out;
  }

  Future<AppUser?> ensureUserLoaded(
    String id, {
    bool forceRemote = false,
  }) async {
    final local = findUser(id);
    if (local != null && !forceRemote) return local;
    final key = id.trim().replaceFirst(RegExp(r'^@'), '');
    try {
      // 1) users/{uid}
      var doc =
          await FirebaseFirestore.instance.collection('users').doc(key).get();
      // 2) handles/{username} → authUid / userId
      if (!doc.exists) {
        final handle = await FirebaseFirestore.instance
            .collection('handles')
            .doc(key.toLowerCase())
            .get();
        if (handle.exists && handle.data() != null) {
          final h = handle.data()!;
          final authUid = '${h['authUid'] ?? ''}';
          final userId = '${h['userId'] ?? ''}';
          if (authUid.isNotEmpty) {
            doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(authUid)
                .get();
          }
          if (!doc.exists && userId.isNotEmpty) {
            // stableId ile ara
            final q = await FirebaseFirestore.instance
                .collection('users')
                .where('stableId', isEqualTo: userId)
                .limit(1)
                .get();
            if (q.docs.isNotEmpty) doc = q.docs.first;
          }
          if (!doc.exists) {
            final q2 = await FirebaseFirestore.instance
                .collection('users')
                .where('username', isEqualTo: key.toLowerCase())
                .limit(1)
                .get();
            if (q2.docs.isNotEmpty) doc = q2.docs.first;
          }
        } else {
          final q2 = await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: key.toLowerCase())
              .limit(1)
              .get();
          if (q2.docs.isNotEmpty) doc = q2.docs.first;
        }
      }
      if (!doc.exists || doc.data() == null) return null;
      final m = doc.data()!;
      if (m['deleted'] == true ||
          '${m['usernameStatus'] ?? ''}' == 'deleted' ||
          '${m['email'] ?? ''}'.contains('@invalid.local')) {
        return null;
      }
      final user = _appUserFromFirestore(doc.id, m);
      if (doc.id != user.id) {
        _idAliases[doc.id] = user.id;
        _idAliases[user.id] = doc.id;
      }
      final uname = user.username?.trim().toLowerCase();
      if (uname != null && uname.isNotEmpty) {
        _idAliases[uname] = user.id;
      }
      _upsert(user);
      notifyListeners();
      return user;
    } catch (e) {
      debugPrint('[auth] ensureUser: $e');
      return null;
    }
  }

  /// Plus / admin işlemleri sonrası mevcut kullanıcıyı Firestore’dan yenile.
  Future<void> refreshCurrentUser() async {
    final fb = fa.FirebaseAuth.instance.currentUser;
    if (fb == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(fb.uid).get();
      if (!doc.exists || doc.data() == null) {
        await _forceSignOutDeleted('Profil bulunamadı');
        return;
      }
      final data = doc.data()!;
      if (data['deleted'] == true ||
          '${data['usernameStatus'] ?? ''}' == 'deleted' ||
          '${data['email'] ?? ''}'.contains('@invalid.local')) {
        await _forceSignOutDeleted('Bu hesap silinmiş');
        return;
      }
      final user = _appUserFromFirestore(doc.id, data);
      if (_followGraphBusy > 0 && _user != null) {
        _user = user.copyWith(
          following: _user!.following,
          followers: _user!.followers,
          incomingFollowRequests: _user!.incomingFollowRequests,
          outgoingFollowRequests: _user!.outgoingFollowRequests,
        );
      } else {
        _user = user;
      }
      _boundAuthUid = fb.uid;
      _upsert(_user!);
      if (doc.id != user.id) {
        _idAliases[doc.id] = user.id;
        _idAliases[user.id] = doc.id;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[auth] refreshCurrentUser: $e');
    }
  }

  Future<void> _forceSignOutDeleted(String reason) async {
    debugPrint('[auth] force signOut: $reason');
    try {
      await fa.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await SecureSession.clear();
    _user = null;
    _boundAuthUid = null;
    _pendingAuthUser = null;
    _dismissedSuggestions.clear();
    _intentionalAuth = false;
    _busy = false;
    _error = reason;
    notifyListeners();
  }

  List<AppUser> searchUsers(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return directory;
    final handleQ = q.startsWith('@') ? q : '@$q';
    final bare = q.replaceFirst(RegExp(r'^@'), '');
    final me = _user;
    return _directory.where((u) {
      if (u.hideFromSearch && me?.id != u.id && !me!.canAccessAdmin) {
        return false;
      }
      if (me != null && (me.blocks(u.id) || u.blocks(me.id))) return false;
      final uname = u.username?.trim().toLowerCase() ?? '';
      return u.fullName.toLowerCase().contains(q) ||
          u.handle.toLowerCase().contains(q) ||
          u.handle.toLowerCase().contains(handleQ) ||
          (uname.isNotEmpty &&
              (uname.contains(bare) || uname == bare)) ||
          u.bio.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.studentNo.contains(q) ||
          u.firstName.toLowerCase().contains(q) ||
          u.lastName.toLowerCase().contains(q) ||
          (u.affiliatedCommunityName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Arama ekranı: öğrenci + topluluk (+ isteğe firma) profilleri.
  List<AppUser> searchPeople(String query) {
    final base = searchUsers(query).where((u) {
      return u.role == UserRole.student ||
          u.role == UserRole.community ||
          u.isCommunity ||
          u.role == UserRole.company;
    }).toList();
    base.sort((a, b) {
      int score(AppUser u) {
        var s = 0;
        if (u.isBot) s += 4;
        if (u.isCommunity) s += 3;
        if (u.showGoldBadge) s += 2;
        if (u.showBlueBadge) s += 1;
        return s;
      }
      final c = score(b).compareTo(score(a));
      if (c != 0) return c;
      return a.fullName.compareTo(b.fullName);
    });
    return base;
  }

  /// Rol bazlı giriş sonrası rota.
  static String homeRouteFor(AppUser? user) {
    if (user == null) return '/home';
    if (user.isAccountPending || user.isAccountRejected) {
      return '/pending-approval';
    }
    if (user.isCompany && !user.isBot) return '/firma/dashboard';
    return '/home';
  }

  /// Firebase Auth UID (stableId değil) — push / oturum kilidi için.
  String? get authUid =>
      _boundAuthUid ?? fa.FirebaseAuth.instance.currentUser?.uid;

  Future<bool> signIn({required String email, required String password}) async {
    _busy = true;
    _error = null;
    notifyListeners();

    final mail = email.trim();
    final pass = password.trim();
    if (mail.isEmpty || pass.isEmpty) {
      _error = 'E-posta ve şifre gerekli.';
      _busy = false;
      notifyListeners();
      return false;
    }
    if (pass.length < 6) {
      _error = 'Şifre en az 6 karakter olmalı.';
      _busy = false;
      notifyListeners();
      return false;
    }

    _intentionalAuth = true;
    try {
      // Farklı hesap açıksa önce temizle — karışık oturum olmasın.
      final existing = fa.FirebaseAuth.instance.currentUser;
      if (existing != null &&
          (existing.email ?? '').toLowerCase() != mail.toLowerCase()) {
        await fa.FirebaseAuth.instance.signOut();
        await SecureSession.clear();
        _user = null;
        _boundAuthUid = null;
      }
      final cred = await fa.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: mail,
        password: pass,
      );
      await _finishFirebaseUser(cred.user!, mail);
      return _user != null;
    } on fa.FirebaseAuthException catch (e) {
      debugPrint('[auth] signIn ${e.code}: ${e.message}');
      _error = _friendlyAuthError(e);
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('[auth] signIn error: $e');
      _error = 'Giriş başarısız. Bağlantını kontrol et.';
      _busy = false;
      notifyListeners();
      return false;
    } finally {
      _intentionalAuth = false;
    }
  }

  String _friendlyAuthError(fa.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'invalid-login-credentials':
        return 'E-posta veya şifre hatalı.';
      case 'too-many-requests':
        return 'Çok fazla deneme. Bir süre sonra tekrar dene.';
      case 'user-disabled':
        return 'Bu hesap devre dışı.';
      case 'network-request-failed':
        return 'Ağ hatası. İnternet bağlantını kontrol et.';
      default:
        return e.message ?? 'Giriş başarısız (${e.code}).';
    }
  }

  Future<void> _finishFirebaseUser(fa.User fb, String email) async {
    // Firestore profili kaynak doğruluk — silinmiş / yoksa hesabı YENİDEN YARATMA.
    final remote = await ensureUserLoaded(fb.uid, forceRemote: true);
    if (remote == null) {
      await _forceSignOutDeleted(
        'Bu hesap silinmiş veya profil bulunamadı. Lütfen yeniden kayıt olun.',
      );
      return;
    }
    _user = remote;
    _boundAuthUid = fb.uid;
    _upsert(remote);
    await SecureSession.saveMeta(uid: fb.uid, email: email);
    // Takip / gizlilik alanlarını taze oku; dizin senkronunda _user güncellensin.
    unawaited(refreshCurrentUser());
    unawaited(syncDirectoryFromFirestore());
    _scheduleSilentRefresh();
    _busy = false;
    _error = null;
    notifyListeners();
  }

  /// Sayfa yenileme / uygulama açılışı — Firebase Auth kalıcılığından oturum.
  Future<void> restorePersistedSession() async {
    if (_restoring) return;
    _restoring = true;
    try {
      await SecureSession.ensureAuthPersistence();

      // Web IndexedDB hydrate gecikebilir — currentUser hemen null gelebilir.
      fa.User? fb = fa.FirebaseAuth.instance.currentUser;
      if (fb == null) {
        try {
          fb = await fa.FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          fb = fa.FirebaseAuth.instance.currentUser;
        }
      }

      if (fb == null) {
        // Auth boş; eski meta’yı temizle (yanlış hesaba yapışmasın).
        await SecureSession.clear();
        return;
      }

      final integrity = await SecureSession.checkIntegrity(fb.uid);
      if (integrity == false) {
        debugPrint('[auth] session integrity mismatch — clean logout');
        await fa.FirebaseAuth.instance.signOut();
        await SecureSession.clear();
        _user = null;
        _boundAuthUid = null;
        notifyListeners();
        return;
      }

      await SecureSession.silentRefresh();
      await _finishFirebaseUser(fb, fb.email ?? '');
    } catch (e) {
      debugPrint('[auth] restore: $e');
    } finally {
      _restoring = false;
      final pending = _pendingAuthUser;
      _pendingAuthUser = null;
      if (pending != null) {
        unawaited(_onAuthChanged(pending));
      }
    }
  }

  Future<void> _onAuthChanged(fa.User? u) async {
    if (_restoring) {
      _pendingAuthUser = u;
      return;
    }

    if (u == null) {
      _refreshTimer?.cancel();
      if (_user != null || _boundAuthUid != null) {
        _user = null;
        _boundAuthUid = null;
        await SecureSession.clear();
        notifyListeners();
      }
      return;
    }

    // Aynı Firebase Auth UID zaten bağlı
    if (_boundAuthUid == u.uid && _user != null) {
      return;
    }

    // Bu sekmede başka hesap açıkken dışarıdan (eski LOCAL senkronu vb.)
    // farklı UID gelirse: kasıtlı giriş değilse reddet / temizle.
    if (_boundAuthUid != null &&
        _boundAuthUid != u.uid &&
        !_intentionalAuth) {
      final metaUid = await SecureSession.boundUid();
      if (metaUid != null && metaUid == _boundAuthUid) {
        debugPrint(
          '[auth] foreign auth uid=${u.uid} ignored — keeping $_boundAuthUid',
        );
        // Firebase’i bizim meta ile hizala: yabancı oturumu düşür.
        try {
          await fa.FirebaseAuth.instance.signOut();
        } catch (_) {}
        // signOut null event gelecek; kendi meta’mızı korumak için yeniden giriş yok —
        // kullanıcıyı güvenli şekilde çıkar.
        _user = null;
        _boundAuthUid = null;
        await SecureSession.clear();
        _error = 'Oturum çakışması algılandı. Lütfen tekrar giriş yap.';
        notifyListeners();
        return;
      }
    }

    try {
      await _finishFirebaseUser(u, u.email ?? '');
    } catch (e) {
      debugPrint('[auth] authState restore: $e');
    }
  }

  void _scheduleSilentRefresh() {
    _refreshTimer?.cancel();
    // ~45 dk’da bir yenile (token ~60 dk) — değeri saklamadan
    _refreshTimer = Timer.periodic(const Duration(minutes: 45), (_) {
      unawaited(SecureSession.silentRefresh());
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncProfileToFirestore(
    AppUser user, {
    String? authUid,
    bool privileged = false,
  }) async {
    try {
      final currentUid = fa.FirebaseAuth.instance.currentUser?.uid ?? '';
      final targetDocId = _firestoreDocIdFor(user, authUid: authUid);
      if (privileged &&
          currentUid.isNotEmpty &&
          targetDocId != currentUid &&
          user.id != currentUid &&
          _idAliases[user.id] != currentUid) {
        // Başka kullanıcının ayrıcalıklı alanları yalnızca Cloud Functions ile.
        return;
      }
      final docId = targetDocId;
      // Silinmiş hesabı merge ile canlandırma.
      try {
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .get();
        if (existing.exists) {
          final em = existing.data() ?? {};
          if (em['deleted'] == true ||
              '${em['usernameStatus'] ?? ''}' == 'deleted') {
            debugPrint('[auth] sync skipped — deleted profile $docId');
            return;
          }
        }
      } catch (_) {}
      final data = <String, dynamic>{
        'email': user.email,
        'firstName': user.firstName,
        'lastName': user.lastName,
        'fullName': user.fullName,
        'studentNo': user.studentNo,
        'phone': user.phone,
        'city': user.city,
        'university': user.university,
        'bio': user.bio,
        'photoUrl': user.photoUrl,
        'communityLogoUrl': user.communityLogoUrl,
        'notificationPrefs': user.notificationPrefs.toJson(),
        'stableId': user.id,
        'username': user.username,
        'usernameStatus': user.usernameStatus,
        'allowMentions': user.allowMentions,
        'kvkkAcceptedAt': user.kvkkAcceptedAt?.toIso8601String(),
        'marketingConsent': user.marketingConsent,
        'marketingAcceptedAt': user.marketingAcceptedAt?.toIso8601String(),
        'accountStatus': user.accountStatus,
        'studentIdDocUrl': user.studentIdDocUrl,
        'studentVerificationType': user.studentVerificationType,
        'studentIdFrontUrl': user.studentIdFrontUrl,
        'studentIdBackUrl': user.studentIdBackUrl,
        'hideFromSearch': user.hideFromSearch,
        'isPrivateAccount': user.isPrivateAccount,
        'isSpectatorMode': user.isSpectatorMode,
        'blockedUserIds': user.blockedUserIds,
        'incomingFollowRequests': user.incomingFollowRequests,
        'outgoingFollowRequests': user.outgoingFollowRequests,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (privileged) {
        data.addAll({
          'role': user.role.name,
          'isCommunity': user.isCommunity,
          'isSuperAdmin': user.isSuperAdmin,
          'hasGoldBadge': user.hasGoldBadge,
          'hasBlueBadge': user.hasBlueBadge,
          'badgeTitle': user.badgeTitle,
          'isCampusAmbassador': user.isCampusAmbassador,
          'embassyId': user.embassyId,
          'isEventOrganizer': user.isEventOrganizer,
          'plusActive': user.plusActive,
          'plusSource': user.plusSource,
          'plusStartsAt': user.plusStartsAt?.toIso8601String(),
          'plusExpiresAt': user.plusExpiresAt?.toIso8601String(),
          'plusTrialUsed': user.plusTrialUsed,
          'isBot': user.isBot,
          'staffRoleId': user.staffRoleId,
          'affiliatedCommunityId': user.affiliatedCommunityId,
          'affiliatedCommunityName': user.affiliatedCommunityName,
          'affiliatedCompanyId': user.affiliatedCompanyId,
          'affiliatedCompanyName': user.affiliatedCompanyName,
          'panelOrgId': user.panelOrgId,
          'panelOrgType': user.panelOrgType,
          'panelOrgName': user.panelOrgName,
          'panelAccess': user.panelAccess,
          'affiliatedOrgLogoUrl': user.affiliatedOrgLogoUrl,
          'restrictionType': user.restrictionType,
          'restrictionReason': user.restrictionReason,
          'restrictionUntil': user.restrictionUntil?.toIso8601String(),
        });
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[auth] firestore sync: $e');
    }
  }

  Future<bool> register({
    required String email,
    required String studentNo,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String city,
    required String university,
    required String username,
    required String emailTicket,
    bool kvkkAccepted = false,
    bool marketingConsent = false,
    bool requireVerification = true,
    String? studentIdDocUrl,
    String? studentVerificationType,
    String? studentIdFrontUrl,
    String? studentIdBackUrl,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    if (!kvkkAccepted || !marketingConsent) {
      _error = 'KVKK ve pazarlama onaylarını kabul etmelisin.';
      _busy = false;
      notifyListeners();
      return false;
    }

    final ticket = emailTicket.trim();
    if (ticket.length < 20) {
      _error = 'Önce e-posta adresine gelen kodu doğrula.';
      _busy = false;
      notifyListeners();
      return false;
    }

    var type = studentVerificationType;
    if (requireVerification) {
      if (type == 'card') {
        if (studentIdFrontUrl == null || studentIdFrontUrl.trim().isEmpty) {
          _error = 'Öğrenci kartı ön yüzü zorunlu.';
          _busy = false;
          notifyListeners();
          return false;
        }
      } else if (type == 'document') {
        if (studentIdDocUrl == null || studentIdDocUrl.trim().isEmpty) {
          _error = 'Öğrenci belgesi PDF zorunlu.';
          _busy = false;
          notifyListeners();
          return false;
        }
      } else {
        _error = 'Doğrulama belgesi seçimi zorunlu.';
        _busy = false;
        notifyListeners();
        return false;
      }
    } else {
      type = null;
    }

    final hasDocs = (studentIdFrontUrl ?? '').trim().isNotEmpty ||
        (studentIdDocUrl ?? '').trim().isNotEmpty;

    if ([
      email,
      password,
      firstName,
      lastName,
      city,
      university,
      username,
    ].any((e) => e.trim().isEmpty)) {
      _error = 'E-posta, şifre, ad, soyad, kampüs ve kullanıcı adı zorunlu.';
      _busy = false;
      notifyListeners();
      return false;
    }
    if (password.trim().length < 6) {
      _error = 'Şifre en az 6 karakter olmalı.';
      _busy = false;
      notifyListeners();
      return false;
    }

    final cleanUser = username.trim().replaceAll('@', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(cleanUser)) {
      _error = 'Kullanıcı adı 3–24 karakter; sadece a-z, 0-9, _';
      _busy = false;
      notifyListeners();
      return false;
    }

    _intentionalAuth = true;
    try {
      final pre = await FirebaseFirestore.instance
          .collection('handles')
          .doc(cleanUser)
          .get();
      if (pre.exists) {
        _error = 'Bu kullanıcı adı alınmış. Başka bir tane dene.';
        _busy = false;
        notifyListeners();
        return false;
      }

      final cred = await fa.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName('$firstName $lastName');

      try {
        final consume = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('consumeRegistrationEmailTicket');
        await consume.call({'ticket': ticket});
      } catch (e) {
        debugPrint('[auth] consumeRegistrationEmailTicket: $e');
        try {
          await cred.user?.delete();
        } catch (_) {}
        _error =
            'E-posta doğrulaması geçersiz veya süresi dolmuş. Yeni kod iste.';
        _busy = false;
        notifyListeners();
        return false;
      }

      String finalUsername = cleanUser;
      var status = 'ok';
      String? aiNote;

      try {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('claimUsername');
        final res = await callable.call({
          'username': cleanUser,
          'firstName': firstName.trim(),
          'lastName': lastName.trim(),
        });
        final map = Map<String, dynamic>.from(res.data as Map);
        finalUsername = '${map['username'] ?? cleanUser}';
        status = '${map['status'] ?? 'ok'}';
        aiNote = map['message'] as String?;
      } catch (e) {
        debugPrint('[auth] claimUsername: $e');
        finalUsername =
            'user_${cred.user!.uid.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        status = 'temp';
        aiNote =
            'Kullanıcı adın geçici atandı. Lütfen profilinden kalıcı bir ad seç.';
      }

      _user = AppUser(
        id: cred.user!.uid,
        email: email.trim(),
        studentNo: studentNo.trim(),
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        city: city,
        university: university,
        bio: '$university öğrencisi',
        photoUrl: null,
        username: finalUsername,
        usernameStatus: status,
        kvkkAcceptedAt: DateTime.now(),
        marketingConsent: marketingConsent,
        marketingAcceptedAt: marketingConsent ? DateTime.now() : null,
        accountStatus: requireVerification ? 'pending' : 'approved',
        studentIdDocUrl: studentIdDocUrl?.trim(),
        studentVerificationType: type,
        studentIdFrontUrl: studentIdFrontUrl?.trim(),
        studentIdBackUrl: studentIdBackUrl?.trim(),
      );
      _upsert(_user!);
      await _syncProfileToFirestore(_user!, privileged: true);
      if (requireVerification) {
        try {
          final notify = FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('notifyRegistrationPending');
          await notify.call({
            'uid': cred.user!.uid,
            'email': email.trim(),
            'firstName': firstName.trim(),
            'lastName': lastName.trim(),
            'studentNo': studentNo.trim(),
            'phone': phone.trim(),
            'university': university,
            'studentVerificationType': type,
            'studentIdDocUrl': studentIdDocUrl?.trim(),
            'studentIdFrontUrl': studentIdFrontUrl?.trim(),
            'studentIdBackUrl': studentIdBackUrl?.trim(),
            'hasDocs': hasDocs,
          });
        } catch (e) {
          debugPrint('[auth] notifyRegistrationPending: $e');
        }
      }
      try {
        final welcome = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('sendWelcomeEmail');
        await welcome.call({
          'to': email.trim(),
          'firstName': firstName.trim(),
          'username': finalUsername,
          'variant': requireVerification ? 'pending' : 'welcome',
        });
      } catch (e) {
        debugPrint('[auth] welcome mail: $e');
      }
      _busy = false;
      if (status == 'temp' && aiNote != null) {
        _error = null;
      }
      notifyListeners();
      return true;
    } on fa.FirebaseAuthException catch (e) {
      debugPrint('Firebase register: ${e.code}');
      if (e.code == 'email-already-in-use') {
        _error = 'Bu e-posta zaten kayıtlı. Giriş yap.';
      } else if (e.code == 'weak-password') {
        _error = 'Şifre en az 6 karakter olmalı.';
      } else if (e.code == 'invalid-email') {
        _error = 'Geçersiz e-posta adresi.';
      } else if (e.code == 'network-request-failed') {
        _error = 'Ağ hatası. İnternet bağlantını kontrol et.';
      } else {
        _error = e.message ?? 'Kayıt başarısız (${e.code}).';
      }
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = '$e';
      _busy = false;
      notifyListeners();
      return false;
    } finally {
      _intentionalAuth = false;
    }
  }

  /// Kayıt öncesi e-posta OTP gönder.
  Future<String?> sendRegistrationEmailCode(String email) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('sendRegistrationEmailCode');
      final res = await callable.call({'email': email.trim()});
      final map = Map<String, dynamic>.from(res.data as Map);
      return '${map['emailHint'] ?? 'Kod gönderildi'}';
    } on FirebaseFunctionsException catch (e) {
      _error = e.message ?? e.code;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Kod gönderilemedi.';
      notifyListeners();
      return null;
    }
  }

  /// OTP doğrula → ticket (kayıtta zorunlu).
  Future<String?> verifyRegistrationEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('verifyRegistrationEmailCode');
      final res = await callable.call({
        'email': email.trim(),
        'code': code.trim(),
      });
      final map = Map<String, dynamic>.from(res.data as Map);
      final t = '${map['ticket'] ?? ''}';
      if (t.length < 20) {
        _error = 'Doğrulama başarısız.';
        notifyListeners();
        return null;
      }
      return t;
    } on FirebaseFunctionsException catch (e) {
      _error = e.message ?? e.code;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Kod doğrulanamadı.';
      notifyListeners();
      return null;
    }
  }

  /// Kalıcı kullanıcı adı değiştir (temp sonrası).
  Future<String?> changeUsername(String desired) async {
    final u = _user;
    if (u == null) return 'Giriş gerekli';
    final clean = desired.trim().replaceAll('@', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(clean)) {
      return 'Kullanıcı adı 3–24 karakter; sadece a-z, 0-9, _';
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('claimUsername');
      final res = await callable.call({
        'username': clean,
        'firstName': u.firstName,
        'lastName': u.lastName,
        'replaceTemp': true,
      });
      final map = Map<String, dynamic>.from(res.data as Map);
      if (map['allowed'] == false) {
        return '${map['message'] ?? 'Bu kullanıcı adı uygun değil'}';
      }
      final next = '${map['username'] ?? clean}';
      final status = '${map['status'] ?? 'ok'}';
      _user = u.copyWith(username: next, usernameStatus: status);
      _upsert(_user!);
      await _syncProfileToFirestore(_user!);
      notifyListeners();
      return status == 'temp'
          ? (map['message'] as String? ?? 'Geçici kullanıcı adı atandı')
          : null;
    } catch (e) {
      return 'Kullanıcı adı kaydedilemedi: $e';
    }
  }

  void updateAllowMentions(bool value) {
    if (_user == null) return;
    _user = _user!.copyWith(allowMentions: value);
    _upsert(_user!);
    notifyListeners();
    unawaited(_syncProfileToFirestore(_user!));
  }

  void upsertUser(AppUser user, {bool syncRemote = true}) {
    _upsert(user);
    if (_user?.id == user.id) {
      _user = user;
    }
    if (syncRemote) {
      unawaited(_syncProfileToFirestore(user, privileged: true));
    }
    notifyListeners();
  }

  String _firestoreDocIdFor(AppUser user, {String? authUid}) {
    if (authUid != null && authUid.isNotEmpty) return authUid;
    final aliased = _idAliases[user.id];
    if (aliased != null && aliased.isNotEmpty) return aliased;
    return user.id;
  }

  /// Oturumdaki kullanıcının Firestore doküman kimliği.
  /// `AppUser.id` stableId olabildiği için doğrudan Firestore erişiminde
  /// bunun yerine bu değer kullanılmalı.
  String? get currentDocId {
    final uid = fa.FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;
    final me = _user;
    return me == null ? null : _firestoreDocIdFor(me);
  }

  /// Firestore’daki tüm üyeleri dizine yükle (canlı arama).
  Future<int> syncDirectoryFromFirestore({int maxDocs = 2000}) async {
    if (_directorySyncing) return _directory.length;
    _directorySyncing = true;
    var loaded = 0;
    try {
      DocumentSnapshot? last;
      while (loaded < maxDocs) {
        Query<Map<String, dynamic>> q =
            FirebaseFirestore.instance.collection('users').limit(100);
        if (last != null) q = q.startAfterDocument(last);
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final doc in snap.docs) {
          final m = doc.data();
          if (m['deleted'] == true) continue;
          final email = '${m['email'] ?? ''}'.trim();
          if (email.contains('@invalid.local')) continue;
          final first = '${m['firstName'] ?? ''}'.trim();
          if (email.isEmpty && first.isEmpty) continue;
          final stable = '${m['stableId'] ?? ''}'.trim();
          final id = stable.isNotEmpty ? stable : doc.id;
          final user = _appUserFromFirestore(id, m);
          _upsert(user);
          // Oturumdaki kullanıcıyı da taze profille güncelle (following vb.).
          final me = _user;
          if (me != null &&
              (user.id == me.id ||
                  doc.id == _boundAuthUid ||
                  doc.id == me.id ||
                  (stable.isNotEmpty && stable == me.id))) {
            if (_followGraphBusy > 0) {
              // Optimistic takip grafiği remote boş/stale ile silinmesin.
              _user = user.copyWith(
                following: me.following,
                followers: me.followers,
                incomingFollowRequests: me.incomingFollowRequests,
                outgoingFollowRequests: me.outgoingFollowRequests,
              );
            } else {
              _user = user;
            }
          }
          if (stable.isNotEmpty && stable != doc.id) {
            _idAliases[stable] = doc.id;
            _idAliases[doc.id] = stable;
          }
          final uname = user.username?.trim().toLowerCase();
          if (uname != null && uname.isNotEmpty) {
            _idAliases[uname] = doc.id;
          }
          loaded += 1;
        }
        last = snap.docs.last;
        if (snap.docs.length < 100) break;
      }
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[auth] directory sync: $loaded kullanıcı');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[auth] syncDirectory: $e');
    } finally {
      _directorySyncing = false;
    }
    return loaded;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => '$e'.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  AppUser _appUserFromFirestore(String docId, Map<String, dynamic> m) {
    final roleName = '${m['role'] ?? 'student'}';
    final role = UserRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => UserRole.student,
    );
    final prefsRaw = m['notificationPrefs'];
    final stable = '${m['stableId'] ?? ''}'.trim();
    return AppUser(
      id: stable.isNotEmpty ? stable : docId,
      email: '${m['email'] ?? ''}',
      studentNo: '${m['studentNo'] ?? ''}',
      firstName: '${m['firstName'] ?? ''}',
      lastName: '${m['lastName'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      city: '${m['city'] ?? ''}',
      university: '${m['university'] ?? ''}',
      bio: '${m['bio'] ?? ''}',
      photoUrl: m['photoUrl'] as String?,
      role: role,
      isCommunity: m['isCommunity'] == true,
      isSuperAdmin: m['isSuperAdmin'] == true,
      hasGoldBadge: m['hasGoldBadge'] == true,
      hasBlueBadge: m['hasBlueBadge'] == true,
      badgeTitle: '${m['badgeTitle'] ?? ''}',
      isCampusAmbassador: m['isCampusAmbassador'] == true,
      embassyId: m['embassyId'] as String?,
      isEventOrganizer: m['isEventOrganizer'] == true,
      plusActive: m['plusActive'] == true,
      plusSource: '${m['plusSource'] ?? ''}',
      plusStartsAt: DateTime.tryParse('${m['plusStartsAt'] ?? ''}'),
      plusExpiresAt: DateTime.tryParse('${m['plusExpiresAt'] ?? ''}'),
      plusTrialUsed: m['plusTrialUsed'] == true,
      isBot: m['isBot'] == true,
      staffRoleId: m['staffRoleId'] as String?,
      communityLogoUrl: m['communityLogoUrl'] as String?,
      affiliatedCommunityId: m['affiliatedCommunityId'] as String?,
      affiliatedCommunityName: m['affiliatedCommunityName'] as String?,
      affiliatedOrgLogoUrl: m['affiliatedOrgLogoUrl'] as String?,
      affiliatedCompanyId: m['affiliatedCompanyId'] as String?,
      affiliatedCompanyName: m['affiliatedCompanyName'] as String?,
      panelOrgId: m['panelOrgId'] as String?,
      panelOrgType: m['panelOrgType'] as String?,
      panelOrgName: m['panelOrgName'] as String?,
      panelAccess: m['panelAccess'] == true,
      restrictionType: '${m['restrictionType'] ?? 'none'}',
      restrictionReason: '${m['restrictionReason'] ?? ''}',
      restrictionUntil: DateTime.tryParse('${m['restrictionUntil'] ?? ''}'),
      username: m['username'] as String?,
      usernameStatus: '${m['usernameStatus'] ?? 'ok'}',
      allowMentions: m['allowMentions'] != false,
      kvkkAcceptedAt: DateTime.tryParse('${m['kvkkAcceptedAt'] ?? ''}'),
      marketingConsent: m['marketingConsent'] == true,
      marketingAcceptedAt:
          DateTime.tryParse('${m['marketingAcceptedAt'] ?? ''}'),
      following: _stringList(m['following']),
      followers: _stringList(m['followers']),
      accountStatus: '${m['accountStatus'] ?? 'approved'}',
      studentIdDocUrl: m['studentIdDocUrl'] as String?,
      studentVerificationType: m['studentVerificationType'] as String?,
      studentIdFrontUrl: m['studentIdFrontUrl'] as String?,
      studentIdBackUrl: m['studentIdBackUrl'] as String?,
      registrationRejectReason: '${m['registrationRejectReason'] ?? ''}',
      hideFromSearch: m['hideFromSearch'] == true,
      isPrivateAccount: m['isPrivateAccount'] == true,
      isSpectatorMode: m['isSpectatorMode'] == true,
      blockedUserIds: _stringList(m['blockedUserIds']),
      incomingFollowRequests: _stringList(m['incomingFollowRequests']),
      outgoingFollowRequests: _stringList(m['outgoingFollowRequests']),
      notificationPrefs: prefsRaw is Map
          ? NotificationPrefs.fromJson(Map<String, dynamic>.from(prefsRaw))
          : NotificationPrefs.defaults,
    );
  }

  /// Hedefi (kişi / topluluk / firma) takip ediyor mu?
  bool follows(String targetId) {
    final me = _user;
    if (me == null || targetId.trim().isEmpty) return false;
    final ids = idsFor(targetId);
    return me.following.any(ids.contains);
  }

  /// Karşı taraf beni takip ediyor mu?
  bool isFollowedBy(String otherId) {
    final me = _user;
    if (me == null || otherId.trim().isEmpty) return false;
    final otherIds = idsFor(otherId);
    if (me.followers.any(otherIds.contains)) return true;
    final other = findUser(otherId);
    if (other == null) return false;
    return other.following.any(idsFor(me.id).contains);
  }

  bool hasOutgoingFollowRequest(String targetId) {
    final me = _user;
    if (me == null) return false;
    final ids = idsFor(targetId);
    return me.outgoingFollowRequests.any(ids.contains);
  }

  /// Bana gelen bekleyen takip isteği var mı?
  bool hasIncomingFollowRequest(String fromId) {
    final me = _user;
    if (me == null || fromId.trim().isEmpty) return false;
    final ids = idsFor(fromId);
    return me.incomingFollowRequests.any(ids.contains);
  }

  /// Gizli hesap içeriği (gönderi / takipçi listesi) görülebilir mi?
  bool canViewPrivateContent(AppUser profile) {
    if (!profile.isPrivateAccount) return true;
    final me = _user;
    if (me == null) return false;
    if (me.id == profile.id || idsFor(profile.id).contains(me.id)) return true;
    return follows(profile.id);
  }

  /// Yazarın post / reels / yorum içeriği bu izleyiciye açık mı? (Instagram)
  /// Cache'te yazar yoksa şimdilik true — [ensureUserLoaded] sonrası yeniden hesaplanır.
  bool canViewAuthorContent(String authorId) {
    final id = authorId.trim();
    if (id.isEmpty) return false;
    final me = _user;
    if (me != null && (me.id == id || idsFor(id).contains(me.id))) {
      return true;
    }
    final author = findUser(id);
    if (author == null) return true;
    return canViewPrivateContent(author);
  }

  /// Tek post görünürlüğü — engel + gizli hesap.
  bool canViewPost(Post post) {
    final me = _user;
    if (me != null) {
      if (me.blocks(post.authorId)) return false;
      final author = findUser(post.authorId);
      if (author != null && author.blocks(me.id)) return false;
    }
    return canViewAuthorContent(post.authorId);
  }

  /// Önerilenler kartını kapat — yalnızca bu oturum; sonra tekrar çıkabilir.
  Future<void> dismissSuggestion(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    _dismissedSuggestions.add(id);
    notifyListeners();
  }

  void updateProfile({
    String? bio,
    String? photoUrl,
    List<ProfileLink>? links,
    String? firstName,
    String? lastName,
    String? phone,
    String? communityLogoUrl,
    bool clearPhoto = false,
  }) {
    if (_user == null) return;
    _user = _user!.copyWith(
      bio: bio,
      photoUrl: photoUrl,
      links: links,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      communityLogoUrl: communityLogoUrl,
      clearPhoto: clearPhoto,
    );
    _upsert(_user!);
    _syncProfileToFirestore(_user!);
    notifyListeners();
  }

  /// Reddedilen / bekleyen kullanıcı yeni belge yükler → tekrar pending.
  Future<bool> resubmitStudentVerification({
    required String verificationType,
    String? studentIdFrontUrl,
    String? studentIdBackUrl,
    String? studentIdDocUrl,
  }) async {
    final me = _user;
    final fb = fa.FirebaseAuth.instance.currentUser;
    if (me == null || fb == null) {
      _error = 'Oturum bulunamadı.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final updated = me.copyWith(
        accountStatus: 'pending',
        studentVerificationType: verificationType,
        studentIdFrontUrl: studentIdFrontUrl,
        studentIdBackUrl: studentIdBackUrl,
        studentIdDocUrl: studentIdDocUrl ?? studentIdFrontUrl,
        registrationRejectReason: '',
      );
      await FirebaseFirestore.instance.collection('users').doc(fb.uid).set({
        'accountStatus': 'pending',
        'studentVerificationType': verificationType,
        'studentIdFrontUrl': studentIdFrontUrl,
        'studentIdBackUrl': studentIdBackUrl,
        'studentIdDocUrl': studentIdDocUrl ?? studentIdFrontUrl,
        'registrationRejectReason': null,
        'registrationResubmittedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      _user = updated;
      _upsert(updated);
      _busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Belge güncellenemedi: $e';
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  void updateNotificationPrefs(NotificationPrefs prefs) {
    if (_user == null) return;
    _user = _user!.copyWith(notificationPrefs: prefs);
    _upsert(_user!);
    _syncProfileToFirestore(_user!);
    notifyListeners();
  }

  Future<void> updatePrivacySettings({
    bool? hideFromSearch,
    bool? isPrivateAccount,
    bool? isSpectatorMode,
  }) async {
    if (_user == null) return;
    _user = _user!.copyWith(
      hideFromSearch: hideFromSearch,
      isPrivateAccount: isPrivateAccount,
      isSpectatorMode: isSpectatorMode,
    );
    _upsert(_user!);
    notifyListeners();
    try {
      final uid = fa.FirebaseAuth.instance.currentUser?.uid ?? _user!.id;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'hideFromSearch': ?hideFromSearch,
        'isPrivateAccount': ?isPrivateAccount,
        'isSpectatorMode': ?isSpectatorMode,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[auth] privacy: $e');
    }
  }

  Future<void> blockUser(String targetId) async {
    if (_user == null || targetId.trim().isEmpty) return;
    final target = findUser(targetId) ?? await ensureUserLoaded(targetId);
    final canonical = target?.id ?? targetId;
    if (canonical == _user!.id) return;
    final blocked = List<String>.from(_user!.blockedUserIds);
    if (!blocked.contains(canonical)) blocked.add(canonical);
    // Takibi karşılıklı kaldır.
    final following = List<String>.from(_user!.following)
      ..removeWhere((id) => idsFor(canonical).contains(id));
    final outgoing = List<String>.from(_user!.outgoingFollowRequests)
      ..removeWhere((id) => idsFor(canonical).contains(id));
    _user = _user!.copyWith(
      blockedUserIds: blocked,
      following: following,
      outgoingFollowRequests: outgoing,
    );
    if (target != null) {
      final theirFollowers = List<String>.from(target.followers)
        ..removeWhere((id) => idsFor(_user!.id).contains(id));
      final theirFollowing = List<String>.from(target.following)
        ..removeWhere((id) => idsFor(_user!.id).contains(id));
      final incoming = List<String>.from(target.incomingFollowRequests)
        ..removeWhere((id) => idsFor(_user!.id).contains(id));
      _upsert(
        target.copyWith(
          followers: theirFollowers,
          following: theirFollowing,
          incomingFollowRequests: incoming,
        ),
      );
    }
    _upsert(_user!);
    notifyListeners();
    try {
      final uid = fa.FirebaseAuth.instance.currentUser?.uid ?? _user!.id;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'blockedUserIds': FieldValue.arrayUnion([canonical]),
        'following': FieldValue.arrayRemove([canonical]),
        'outgoingFollowRequests': FieldValue.arrayRemove([canonical]),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      unawaited(
        _mutateFollowRemote(
          action: 'unfollow',
          targetId: canonical,
        ),
      );
    } catch (e) {
      debugPrint('[auth] block: $e');
    }
  }

  Future<void> unblockUser(String targetId) async {
    if (_user == null || targetId.trim().isEmpty) return;
    final ids = idsFor(targetId);
    final blocked = List<String>.from(_user!.blockedUserIds)
      ..removeWhere(ids.contains);
    _user = _user!.copyWith(blockedUserIds: blocked);
    _upsert(_user!);
    notifyListeners();
    try {
      final uid = fa.FirebaseAuth.instance.currentUser?.uid ?? _user!.id;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'blockedUserIds': FieldValue.arrayRemove(ids.toList()),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[auth] unblock: $e');
    }
  }

  /// Gizli hesap: takip isteği gönder.
  Future<void> requestFollow(String targetId) async {
    if (_user == null || _user!.id == targetId) return;
    if (_user!.isSpectatorMode) return;
    final target = findUser(targetId) ?? await ensureUserLoaded(targetId);
    if (target == null) return;
    if (follows(target.id)) return;
    final canonical = target.id;
    final outgoing = List<String>.from(_user!.outgoingFollowRequests);
    if (!outgoing.contains(canonical)) outgoing.add(canonical);
    final incoming = List<String>.from(target.incomingFollowRequests);
    if (!incoming.contains(_user!.id)) incoming.add(_user!.id);
    _user = _user!.copyWith(outgoingFollowRequests: outgoing);
    _upsert(_user!);
    _upsert(target.copyWith(incomingFollowRequests: incoming));
    notifyListeners();
    final ok = await _mutateFollowRemote(
      action: 'request',
      targetId: canonical,
    );
    if (!ok) {
      // Rollback optimistic
      final out2 = List<String>.from(_user!.outgoingFollowRequests)
        ..removeWhere((id) => idsFor(canonical).contains(id));
      _user = _user!.copyWith(outgoingFollowRequests: out2);
      final t = findUser(canonical);
      if (t != null) {
        final inc = List<String>.from(t.incomingFollowRequests)
          ..removeWhere((id) => idsFor(_user!.id).contains(id));
        _upsert(t.copyWith(incomingFollowRequests: inc));
      }
      _upsert(_user!);
      notifyListeners();
    }
  }

  Future<void> cancelFollowRequest(String targetId) async {
    if (_user == null) return;
    final target = findUser(targetId) ?? await ensureUserLoaded(targetId);
    final canonical = target?.id ?? targetId;
    final ids = idsFor(canonical);
    final outgoing = List<String>.from(_user!.outgoingFollowRequests)
      ..removeWhere(ids.contains);
    _user = _user!.copyWith(outgoingFollowRequests: outgoing);
    if (target != null) {
      final incoming = List<String>.from(target.incomingFollowRequests)
        ..removeWhere((id) => idsFor(_user!.id).contains(id));
      _upsert(target.copyWith(incomingFollowRequests: incoming));
    }
    _upsert(_user!);
    notifyListeners();
    await _mutateFollowRemote(action: 'cancel_request', targetId: canonical);
  }

  /// Gelen takip isteğini kabul et → requester beni takip eder.
  Future<bool> acceptFollowRequest(String requesterId) async {
    if (_user == null || requesterId.trim().isEmpty) return false;
    final requester =
        findUser(requesterId) ?? await ensureUserLoaded(requesterId);
    if (requester == null) return false;
    final canonical = requester.id;
    final myIncoming = List<String>.from(_user!.incomingFollowRequests)
      ..removeWhere((id) => idsFor(canonical).contains(id));
    final myFollowers = List<String>.from(_user!.followers);
    if (!myFollowers.any(idsFor(canonical).contains)) {
      myFollowers.add(canonical);
    }
    final theirOutgoing = List<String>.from(requester.outgoingFollowRequests)
      ..removeWhere((id) => idsFor(_user!.id).contains(id));
    final theirFollowing = List<String>.from(requester.following);
    if (!theirFollowing.any(idsFor(_user!.id).contains)) {
      theirFollowing.add(_user!.id);
    }
    _user = _user!.copyWith(
      incomingFollowRequests: myIncoming,
      followers: myFollowers,
    );
    _upsert(_user!);
    _upsert(
      requester.copyWith(
        outgoingFollowRequests: theirOutgoing,
        following: theirFollowing,
      ),
    );
    notifyListeners();
    final ok = await _mutateFollowRemote(
      action: 'accept',
      targetId: canonical,
    );
    if (!ok) {
      await refreshCurrentUser();
      await ensureUserLoaded(canonical, forceRemote: true);
      return false;
    }
    unawaited(ensureUserLoaded(canonical, forceRemote: true));
    return true;
  }

  /// Gelen takip isteğini reddet.
  Future<void> rejectFollowRequest(String requesterId) async {
    if (_user == null || requesterId.trim().isEmpty) return;
    final requester =
        findUser(requesterId) ?? await ensureUserLoaded(requesterId);
    final canonical = requester?.id ?? requesterId;
    final myIncoming = List<String>.from(_user!.incomingFollowRequests)
      ..removeWhere((id) => idsFor(canonical).contains(id));
    _user = _user!.copyWith(incomingFollowRequests: myIncoming);
    if (requester != null) {
      final theirOutgoing = List<String>.from(requester.outgoingFollowRequests)
        ..removeWhere((id) => idsFor(_user!.id).contains(id));
      _upsert(requester.copyWith(outgoingFollowRequests: theirOutgoing));
    }
    _upsert(_user!);
    notifyListeners();
    await _mutateFollowRemote(action: 'reject', targetId: canonical);
  }

  Future<void> toggleFollow(String targetId) async {
    if (_user == null || _user!.id == targetId) return;
    if (_user!.isSpectatorMode) return;
    final target = findUser(targetId) ??
        await ensureUserLoaded(targetId, forceRemote: true);
    if (target == null) return;
    final canonicalTarget = target.id;
    final following = List<String>.from(_user!.following);
    final targetFollowers = List<String>.from(target.followers);
    final already = following.any(idsFor(canonicalTarget).contains) ||
        following.contains(canonicalTarget);
    if (already) {
      following.removeWhere((id) => idsFor(canonicalTarget).contains(id));
      targetFollowers.removeWhere((id) => idsFor(_user!.id).contains(id));
      _user = _user!.copyWith(following: following);
      _upsert(_user!);
      _upsert(target.copyWith(followers: targetFollowers));
      notifyListeners();
      final ok = await _mutateFollowRemote(
        action: 'unfollow',
        targetId: canonicalTarget,
      );
      if (!ok) {
        await refreshCurrentUser();
        await ensureUserLoaded(canonicalTarget, forceRemote: true);
      }
      return;
    }
    // Gizli hesap: anında takip yerine istek.
    if (target.isPrivateAccount) {
      await requestFollow(canonicalTarget);
      return;
    }
    if (!following.contains(canonicalTarget)) {
      following.add(canonicalTarget);
    }
    if (!targetFollowers.contains(_user!.id)) {
      targetFollowers.add(_user!.id);
    }
    // İstek varsa temizle (optimistic)
    final outgoing = List<String>.from(_user!.outgoingFollowRequests)
      ..removeWhere((id) => idsFor(canonicalTarget).contains(id));
    _user = _user!.copyWith(
      following: following,
      outgoingFollowRequests: outgoing,
    );
    _upsert(_user!);
    _upsert(target.copyWith(followers: targetFollowers));
    notifyListeners();
    final ok = await _mutateFollowRemote(
      action: 'follow',
      targetId: canonicalTarget,
    );
    if (!ok) {
      await refreshCurrentUser();
      await ensureUserLoaded(canonicalTarget, forceRemote: true);
    }
  }

  Future<bool> _mutateFollowRemote({
    required String action,
    required String targetId,
  }) async {
    _followGraphBusy++;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('mutateFollow');
      await callable.call({'action': action, 'targetId': targetId});
      return true;
    } catch (e) {
      debugPrint('[auth] mutateFollow($action): $e');
      return false;
    } finally {
      _followGraphBusy = (_followGraphBusy - 1).clamp(0, 999);
    }
  }

  Future<void> signOut() async {
    _refreshTimer?.cancel();
    _intentionalAuth = true;
    try {
      await fa.FirebaseAuth.instance.signOut();
    } catch (_) {}
    await SecureSession.clear();
    _user = null;
    _boundAuthUid = null;
    _pendingAuthUser = null;
    _dismissedSuggestions.clear();
    _intentionalAuth = false;
    notifyListeners();
  }

  void _upsert(AppUser user) {
    final i = _directory.indexWhere(
      (u) => u.id == user.id || u.email == user.email,
    );
    if (i >= 0) {
      final old = _directory[i];
      if (old.id != user.id) {
        _idAliases[old.id] = user.id;
      }
      _directory[i] = user;
    } else {
      _directory.add(user);
    }
  }
}
