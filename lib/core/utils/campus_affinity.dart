import '../../models/models.dart';
import '../../features/auth/data/auth_provider.dart';

/// Kampüs affinity — aynı üni / şehir / rozet / arkadaşın arkadaşı / takip.
class CampusAffinity {
  CampusAffinity._();

  static String _norm(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool sameUniversity(AppUser? a, AppUser? b) {
    if (a == null || b == null) return false;
    final ua = _norm(a.university);
    final ub = _norm(b.university);
    if (ua.isEmpty || ub.isEmpty) return false;
    return ua == ub;
  }

  static bool sameCity(AppUser? a, AppUser? b) {
    if (a == null || b == null) return false;
    final ca = _norm(a.city);
    final cb = _norm(b.city);
    if (ca.isEmpty || cb.isEmpty) return false;
    return ca == cb;
  }

  /// Aynı topluluk / firma rozeti veya bağlı kurum.
  static bool sameOrgBadge(AppUser? a, AppUser? b) {
    if (a == null || b == null) return false;
    final aComm = (a.affiliatedCommunityId ?? '').trim();
    final bComm = (b.affiliatedCommunityId ?? '').trim();
    if (aComm.isNotEmpty && aComm == bComm) return true;
    final aCo = (a.affiliatedCompanyId ?? '').trim();
    final bCo = (b.affiliatedCompanyId ?? '').trim();
    if (aCo.isNotEmpty && aCo == bCo) return true;
    final aEmb = (a.embassyId ?? '').trim();
    final bEmb = (b.embassyId ?? '').trim();
    if (aEmb.isNotEmpty && aEmb == bEmb) return true;
    return false;
  }

  /// Arkadaşın arkadaşı: takip ettiğin biri adayı takip ediyor (veya aday onu).
  static bool isFriendOfFriend({
    required AppUser viewer,
    required AppUser candidate,
    required AuthProvider auth,
  }) {
    final candIds = auth.idsFor(candidate.id).toSet();
    for (final fid in viewer.following) {
      if (auth.idsFor(fid).any(candIds.contains)) continue; // zaten takip
      final friend = auth.findUser(fid);
      if (friend == null) continue;
      if (friend.following.any(candIds.contains)) return true;
      if (candidate.followers.any(auth.idsFor(fid).contains)) return true;
    }
    return false;
  }

  static String? suggestionReason({
    required AppUser viewer,
    required AppUser candidate,
    required AuthProvider auth,
  }) {
    if (sameUniversity(viewer, candidate)) return 'Aynı üniversite';
    if (isFriendOfFriend(viewer: viewer, candidate: candidate, auth: auth)) {
      return 'Arkadaşının arkadaşı';
    }
    if (sameOrgBadge(viewer, candidate)) return 'Ortak rozet';
    if (sameCity(viewer, candidate)) return 'Aynı şehir';
    if (candidate.showGoldBadge || candidate.showBlueBadge) {
      return 'Rozetli hesap';
    }
    return null;
  }

  /// Oneri adayi skoru (yuksek = once).
  static double scoreCandidate({
    required AppUser viewer,
    required AppUser candidate,
    required AuthProvider auth,
  }) {
    var s = 0.0;
    if (sameUniversity(viewer, candidate)) s += 3.2;
    if (isFriendOfFriend(viewer: viewer, candidate: candidate, auth: auth)) {
      s += 2.6;
    }
    if (sameOrgBadge(viewer, candidate)) s += 1.8;
    if (sameCity(viewer, candidate)) s += 1.1;
    if (candidate.showGoldBadge) s += 0.7;
    if (candidate.showBlueBadge) s += 0.5;
    if (candidate.isCommunity) s += 0.4;
    if (candidate.isCampusAmbassador) s += 0.35;
    // Populerlik hafif
    s += (candidate.followers.length.clamp(0, 80)) / 80.0 * 0.6;
    return s;
  }

  /// Feed post skoru (yüksek = üstte).
  static double scorePost({
    required AppUser? viewer,
    required AppUser? author,
    required DateTime createdAt,
    required int likeCount,
    required int replyCount,
    required int repostCount,
    required bool followingAuthor,
    bool friendOfFriend = false,
  }) {
    final ageHours =
        DateTime.now().difference(createdAt).inMinutes.clamp(0, 72 * 60) / 60.0;
    final recency = 1.0 / (1.0 + ageHours / 8.0);
    final engagement =
        (likeCount * 1.0 + replyCount * 2.2 + repostCount * 3.0).clamp(0, 400);
    final engNorm = engagement / (40 + engagement);

    var campus = 0.0;
    if (sameUniversity(viewer, author)) campus += 0.50;
    if (followingAuthor) {
      campus += 0.30;
    } else if (friendOfFriend) {
      campus += 0.18;
    }
    if (sameOrgBadge(viewer, author)) campus += 0.10;
    if (sameCity(viewer, author)) campus += 0.06;
    if (author?.showGoldBadge == true || author?.showBlueBadge == true) {
      campus += 0.10;
    }
    if (author?.isCommunity == true || author?.isCompany == true) {
      campus += 0.06;
    }

    return recency * 0.40 + engNorm * 0.20 + campus * 0.40;
  }

  /// Reels skoru.
  static double scoreReel({
    required AppUser? viewer,
    required AppUser? author,
    required DateTime createdAt,
    required bool followingAuthor,
    required bool unseen,
    bool friendOfFriend = false,
  }) {
    final ageHours =
        DateTime.now().difference(createdAt).inMinutes.clamp(0, 72 * 60) / 60.0;
    final recency = 1.0 / (1.0 + ageHours / 10.0);
    var campus = 0.0;
    if (sameUniversity(viewer, author)) campus += 0.52;
    if (followingAuthor) {
      campus += 0.28;
    } else if (friendOfFriend) {
      campus += 0.16;
    }
    if (sameOrgBadge(viewer, author)) campus += 0.10;
    if (sameCity(viewer, author)) campus += 0.06;
    if (unseen) campus += 0.18;
    return recency * 0.32 + campus * 0.68;
  }
}

class SuggestedPerson {
  const SuggestedPerson({
    required this.user,
    required this.score,
    this.reason,
  });

  final AppUser user;
  final double score;
  final String? reason;
}

/// Instagram tarzı "Onerilenler" listesi.
class PeopleSuggestions {
  PeopleSuggestions._();

  static List<SuggestedPerson> build({
    required AuthProvider auth,
    int limit = 24,
    Set<String> dismissed = const {},
  }) {
    final me = auth.user;
    if (me == null) return const [];

    final myIds = auth.idsFor(me.id).toSet();
    final following = me.following
        .expand((id) => auth.idsFor(id))
        .toSet()
      ..addAll(myIds);
    final outgoing = me.outgoingFollowRequests
        .expand((id) => auth.idsFor(id))
        .toSet();
    final blocked = me.blockedUserIds
        .expand((id) => auth.idsFor(id))
        .toSet();
    final dismissedIds = dismissed
        .expand((id) => auth.idsFor(id))
        .toSet();

    final scored = <SuggestedPerson>[];
    for (final u in auth.directory) {
      final ids = auth.idsFor(u.id);
      if (ids.any(myIds.contains)) continue;
      if (ids.any(following.contains)) continue;
      if (ids.any(outgoing.contains)) continue;
      if (ids.any(blocked.contains)) continue;
      if (ids.any(dismissedIds.contains)) continue;
      if (u.hideFromSearch && !me.canAccessAdmin) continue;
      if (u.blocks(me.id) || me.blocks(u.id)) continue;
      // Hesap durumu: onayli ogrenci / topluluk / firma
      if (u.role == UserRole.student &&
          u.accountStatus != 'approved' &&
          u.accountStatus.isNotEmpty) {
        continue;
      }
      // Botlari atla (MT resmi botlar oneride olmasin)
      if (u.isBot) continue;

      final score = CampusAffinity.scoreCandidate(
        viewer: me,
        candidate: u,
        auth: auth,
      );
      if (score < 0.8) continue; // zayif bag yoksa gosterme
      scored.add(
        SuggestedPerson(
          user: u,
          score: score,
          reason: CampusAffinity.suggestionReason(
            viewer: me,
            candidate: u,
            auth: auth,
          ),
        ),
      );
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.user.fullName.compareTo(b.user.fullName);
    });
    return scored.take(limit).toList();
  }
}
