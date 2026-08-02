import 'dart:math' as math;

import '../../models/models.dart';
import '../../features/auth/data/auth_provider.dart';
import '../../features/reels/reel_models.dart';

/// Beğeni / hashtag etkileşiminden türetilen sinyal.
class EngagementSignals {
  const EngagementSignals({
    this.likedAuthorIds = const {},
    this.tagWeights = const {},
  });

  final Set<String> likedAuthorIds;
  final Map<String, double> tagWeights;

  static const empty = EngagementSignals();

  factory EngagementSignals.fromContent({
    required AuthProvider auth,
    required String viewerId,
    required List<Post> posts,
    required List<CampusReel> reels,
  }) {
    final likedAuthors = <String>{};
    final tags = <String, double>{};

    void bumpTag(String raw, double w) {
      final t = raw.trim().toLowerCase();
      if (t.isEmpty) return;
      tags[t] = (tags[t] ?? 0) + w;
    }

    for (final p in posts) {
      if (!p.isLiked) continue;
      likedAuthors.addAll(auth.idsFor(p.authorId));
      for (final t in p.hashtags) {
        bumpTag(t, 1.4);
      }
    }
    for (final r in reels) {
      if (!r.likedByUser(viewerId)) continue;
      likedAuthors.addAll(auth.idsFor(r.authorId));
      for (final t in r.hashtags) {
        bumpTag(t, 2.0);
      }
      // #reels / #reel özel boost
      final cap = r.caption.toLowerCase();
      if (cap.contains('#reel')) bumpTag('reels', 1.2);
    }

    // Global popüler etiketler (hafif)
    for (final p in posts) {
      final eng = p.likeCount + p.replyCount * 2 + p.repostCount * 3;
      if (eng < 3) continue;
      for (final t in p.hashtags) {
        bumpTag(t, 0.08 * (eng / (8 + eng)));
      }
    }
    for (final r in reels) {
      final eng = r.likedBy.length + r.commentCount * 2;
      if (eng < 2) continue;
      for (final t in r.hashtags) {
        bumpTag(t, 0.12 * (eng / (6 + eng)));
      }
      if (r.hashtags.any((t) => t.toLowerCase() == 'reels' || t.toLowerCase() == 'reel')) {
        bumpTag('reels', 0.25);
      }
    }

    return EngagementSignals(likedAuthorIds: likedAuthors, tagWeights: tags);
  }

  double authorBoost(AppUser candidate, AuthProvider auth) {
    final ids = auth.idsFor(candidate.id);
    if (ids.any(likedAuthorIds.contains)) return 2.15;
    return 0;
  }

  double tagsBoost(Iterable<String> tags) {
    var s = 0.0;
    for (final raw in tags) {
      final t = raw.trim().toLowerCase();
      if (t.isEmpty) continue;
      s += (tagWeights[t] ?? 0) * 0.22;
      if (t == 'reels' || t == 'reel') s += 0.35;
    }
    return s.clamp(0, 3.5);
  }
}

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
    EngagementSignals signals = EngagementSignals.empty,
  }) {
    if (isFriendOfFriend(viewer: viewer, candidate: candidate, auth: auth)) {
      return 'Takip ettiklerinin takip ettiği';
    }
    if (signals.authorBoost(candidate, auth) > 0) {
      return 'Beğendiğin içeriklerden';
    }
    if (sameUniversity(viewer, candidate)) return 'Aynı üniversite';
    if (sameCity(viewer, candidate)) return 'Aynı şehir';
    if (sameOrgBadge(viewer, candidate)) return 'Ortak rozet';
    if (candidate.followers.length >= 25) return 'Popüler hesap';
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
    EngagementSignals signals = EngagementSignals.empty,
    Iterable<String> candidateTags = const [],
  }) {
    var s = 0.0;
    if (isFriendOfFriend(viewer: viewer, candidate: candidate, auth: auth)) {
      s += 3.4;
    }
    if (sameUniversity(viewer, candidate)) s += 3.0;
    if (sameCity(viewer, candidate)) s += 1.4;
    if (sameOrgBadge(viewer, candidate)) s += 1.7;
    s += signals.authorBoost(candidate, auth);
    s += signals.tagsBoost(candidateTags);
    if (candidate.showGoldBadge) s += 0.7;
    if (candidate.showBlueBadge) s += 0.5;
    if (candidate.isCommunity) s += 0.45;
    if (candidate.isCampusAmbassador) s += 0.4;
    // Takipçi popülerliği
    final fol = candidate.followers.length.clamp(0, 200);
    s += (fol / 200.0) * 1.5;
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
    List<String> hashtags = const [],
    EngagementSignals signals = EngagementSignals.empty,
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
    final tagBoost = signals.tagsBoost(hashtags) / 8.0;

    return recency * 0.36 + engNorm * 0.24 + campus * 0.34 + tagBoost * 0.06;
  }

  /// Reels skoru.
  static double scoreReel({
    required AppUser? viewer,
    required AppUser? author,
    required DateTime createdAt,
    required bool followingAuthor,
    required bool unseen,
    bool friendOfFriend = false,
    int likeCount = 0,
    int commentCount = 0,
    List<String> hashtags = const [],
    EngagementSignals signals = EngagementSignals.empty,
  }) {
    final ageHours =
        DateTime.now().difference(createdAt).inMinutes.clamp(0, 72 * 60) / 60.0;
    final recency = 1.0 / (1.0 + ageHours / 10.0);
    final engagement = (likeCount * 1.2 + commentCount * 2.4).clamp(0, 500);
    final engNorm = engagement / (30 + engagement);

    var campus = 0.0;
    if (sameUniversity(viewer, author)) campus += 0.48;
    if (followingAuthor) {
      campus += 0.26;
    } else if (friendOfFriend) {
      campus += 0.16;
    }
    if (sameOrgBadge(viewer, author)) campus += 0.10;
    if (sameCity(viewer, author)) campus += 0.06;
    if (unseen) campus += 0.16;

    final tags = [...hashtags];
    final lower = tags.map((e) => e.toLowerCase()).toSet();
    if (lower.contains('reels') || lower.contains('reel')) {
      campus += 0.12;
    }
    final tagBoost = signals.tagsBoost(tags) / 7.0;

    return recency * 0.28 + engNorm * 0.22 + campus * 0.42 + tagBoost * 0.08;
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

/// Instagram tarzı "Onerilenler" listesi — skor + ağırlıklı karıştırma.
class PeopleSuggestions {
  PeopleSuggestions._();

  static List<SuggestedPerson> build({
    required AuthProvider auth,
    int limit = 24,
    Set<String> dismissed = const {},
    EngagementSignals signals = EngagementSignals.empty,
    Map<String, List<String>> authorTags = const {},
    int? shuffleSeed,
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
      if (u.role == UserRole.student &&
          u.accountStatus != 'approved' &&
          u.accountStatus.isNotEmpty) {
        continue;
      }
      if (u.isBot) continue;

      final tags = <String>{
        ...?authorTags[u.id],
        for (final id in ids) ...?authorTags[id],
      };

      final score = CampusAffinity.scoreCandidate(
        viewer: me,
        candidate: u,
        auth: auth,
        signals: signals,
        candidateTags: tags,
      );
      if (score < 0.45) continue;
      scored.add(
        SuggestedPerson(
          user: u,
          score: score,
          reason: CampusAffinity.suggestionReason(
            viewer: me,
            candidate: u,
            auth: auth,
            signals: signals,
          ),
        ),
      );
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.user.fullName.compareTo(b.user.fullName);
    });

    // Üst havuzdan ağırlıklı karıştır — her açılışta taze sıra.
    final pool = scored.take(math.max(limit * 2, 28)).toList();
    return weightedShuffle(pool, limit: limit, seed: shuffleSeed);
  }

  /// Skora göre ağırlıklı rastgele sıra (yüksek skor daha sık önde).
  static List<SuggestedPerson> weightedShuffle(
    List<SuggestedPerson> ranked, {
    required int limit,
    int? seed,
  }) {
    if (ranked.isEmpty) return const [];
    final rng = math.Random(
      seed ?? DateTime.now().millisecondsSinceEpoch,
    );
    final pool = List<SuggestedPerson>.of(ranked);
    final out = <SuggestedPerson>[];
    while (pool.isNotEmpty && out.length < limit) {
      var total = 0.0;
      final weights = List<double>.generate(pool.length, (i) {
        final w = math.pow(pool[i].score + 0.35, 1.55).toDouble();
        total += w;
        return w;
      });
      var r = rng.nextDouble() * total;
      var pick = pool.length - 1;
      for (var i = 0; i < weights.length; i++) {
        r -= weights[i];
        if (r <= 0) {
          pick = i;
          break;
        }
      }
      out.add(pool.removeAt(pick));
    }
    return out;
  }
}

