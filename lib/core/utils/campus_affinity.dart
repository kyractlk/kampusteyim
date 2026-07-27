import '../../models/models.dart';

/// Kampüs affinity skoru — aynı üniversite / takip / etkileşim.
/// Basit online öğrenme: ağırlıklar sabit; skor anlık hesaplanır.
class CampusAffinity {
  CampusAffinity._();

  static String _normUni(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool sameUniversity(AppUser? a, AppUser? b) {
    if (a == null || b == null) return false;
    final ua = _normUni(a.university);
    final ub = _normUni(b.university);
    if (ua.isEmpty || ub.isEmpty) return false;
    return ua == ub;
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
  }) {
    final ageHours =
        DateTime.now().difference(createdAt).inMinutes.clamp(0, 72 * 60) / 60.0;
    // Zaman çürümesi
    final recency = 1.0 / (1.0 + ageHours / 8.0);
    final engagement =
        (likeCount * 1.0 + replyCount * 2.2 + repostCount * 3.0).clamp(0, 400);
    final engNorm = engagement / (40 + engagement);

    var campus = 0.0;
    if (sameUniversity(viewer, author)) campus += 0.55;
    if (followingAuthor) campus += 0.28;
    if (author?.showGoldBadge == true || author?.showBlueBadge == true) {
      campus += 0.12;
    }
    if (author?.isCommunity == true || author?.isCompany == true) {
      campus += 0.08;
    }

    // Ağırlıklı skor
    return recency * 0.42 + engNorm * 0.22 + campus * 0.36;
  }

  /// Reels skoru.
  static double scoreReel({
    required AppUser? viewer,
    required AppUser? author,
    required DateTime createdAt,
    required bool followingAuthor,
    required bool unseen,
  }) {
    final ageHours =
        DateTime.now().difference(createdAt).inMinutes.clamp(0, 72 * 60) / 60.0;
    final recency = 1.0 / (1.0 + ageHours / 10.0);
    var campus = 0.0;
    if (sameUniversity(viewer, author)) campus += 0.6;
    if (followingAuthor) campus += 0.25;
    if (unseen) campus += 0.2;
    return recency * 0.35 + campus * 0.65;
  }
}
