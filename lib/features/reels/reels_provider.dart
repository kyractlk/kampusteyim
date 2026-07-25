import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/media_upload.dart';
import '../../core/utils/hashtag_utils.dart';
import '../../core/utils/mention_utils.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_models.dart';
import '../notifications/push_service.dart';
import 'reel_models.dart';
import 'reels_video_cache.dart';

/// Kampüs Reels — izlenenler sona, yeniler üste; gizli hesap filtresi.
class ReelsProvider extends ChangeNotifier {
  ReelsProvider();

  final List<CampusReel> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  AuthProvider? _auth;
  bool _loading = false;
  String? _error;
  bool _tabActive = false;

  /// Alt bar Reels sekmesi görünür mü — ses/oynatma kapısı.
  bool get tabActive => _tabActive;
  bool get isLoading => _loading;
  String? get error => _error;

  void setTabActive(bool active) {
    if (_tabActive == active) return;
    _tabActive = active;
    notifyListeners();
    // Aktif olmasa da prefetch sürer — kaydırma için hazır.
    unawaited(_prefetchFeed());
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reels')
          .orderBy('createdAt', descending: true)
          .limit(120)
          .get();
      _items
        ..clear()
        ..addAll(
          snap.docs
              .map((d) => CampusReel.fromFirestore(d.id, d.data()))
              .where((r) => !r.isDeleted),
        );
      _error = null;
    } catch (e) {
      debugPrint('[reels] refresh: $e');
      _error = 'Yenilenemedi';
    }
    _loading = false;
    notifyListeners();
    await _prefetchFeed();
  }

  Future<void> _prefetchFeed() async {
    final feed = feedFor(_auth?.user?.id);
    // Kullanıcı Reels’te olmasa da arka planda ısıtmaya devam.
    await ReelsVideoCache.instance.prefetch(feed, count: 10, keepWarm: true);
  }

  Future<void> prefetchAround(List<CampusReel> feed, int index) async {
    if (feed.isEmpty) return;
    final start = (index - 3).clamp(0, feed.length);
    final end = (index + 8).clamp(0, feed.length);
    final slice = feed.sublist(start, end);
    await ReelsVideoCache.instance.prefetch(slice, count: slice.length);
    // Tüm feed’i de kuyruğa koy — kaydırırken hazır olsun.
    unawaited(
      ReelsVideoCache.instance.prefetch(feed, count: 12, keepWarm: true),
    );
  }

  void attachAuth(AuthProvider auth) {
    _auth = auth;
    auth.addListener(_onAuth);
    _onAuth();
  }

  void _onAuth() {
    final id = _auth?.user?.id;
    if (id == null) {
      _sub?.cancel();
      _sub = null;
      _items.clear();
      notifyListeners();
      return;
    }
    if (_sub != null) return;
    _bind();
  }

  void _bind() {
    _sub?.cancel();
    _loading = true;
    notifyListeners();
    _sub = FirebaseFirestore.instance
        .collection('reels')
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots()
        .listen(
      (snap) {
        _items
          ..clear()
          ..addAll(
            snap.docs
                .map((d) => CampusReel.fromFirestore(d.id, d.data()))
                .where((r) => !r.isDeleted),
          );
        _loading = false;
        _error = null;
        notifyListeners();
        // Uygulama açılır açılmaz ilk reels’leri ısıt.
        unawaited(_prefetchFeed());
      },
      onError: (e) {
        debugPrint('[reels] bind: $e');
        _loading = false;
        _error = 'Reels yüklenemedi';
        notifyListeners();
      },
    );
  }

  bool _canSeeReel(CampusReel r, String? viewerId) {
    if (viewerId != null &&
        (_auth?.idsFor(r.authorId).contains(viewerId) ?? false)) {
      return true;
    }
    final author = _auth?.findUser(r.authorId);
    if (author == null) return true;
    if (!author.isPrivateAccount) return true;
    if (viewerId == null || viewerId.isEmpty) return false;
    return _auth?.follows(r.authorId) == true;
  }

  /// İzlenmemişler önce; gizli hesap reels’leri takipçilere özel.
  List<CampusReel> feedFor(String? viewerId) {
    final list = _items.where((r) => _canSeeReel(r, viewerId)).toList();
    if (viewerId == null || viewerId.isEmpty) return list;
    final unseen = <CampusReel>[];
    final seen = <CampusReel>[];
    for (final r in list) {
      if (r.viewedByUser(viewerId)) {
        seen.add(r);
      } else {
        unseen.add(r);
      }
    }
    unseen.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    seen.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [...unseen, ...seen];
  }

  Future<String?> createReel({
    required AppUser author,
    required XFile file,
    required bool isVideo,
    String caption = '',
    void Function(double progress)? onProgress,
  }) async {
    if (author.isSpectatorMode) {
      return 'İzleyici modunda Reels paylaşamazsın.';
    }
    if (!author.canUseStories) {
      return 'Reels paylaşımı şu an kullanılamıyor.';
    }
    try {
      final url = await MediaUpload.uploadXFile(
        file: file,
        folder: 'reels/${author.id}',
        firstName: author.firstName,
        lastName: author.lastName,
        studentNo: author.studentNo,
        isVideo: isVideo,
        onProgress: onProgress,
      );
      return createReelFromUrl(
        author: author,
        mediaUrl: url,
        isVideo: isVideo,
        caption: caption,
      );
    } catch (e) {
      debugPrint('[reels] create: $e');
      return 'Reels paylaşılamadı: $e';
    }
  }

  Future<String?> createReelFromUrl({
    required AppUser author,
    required String mediaUrl,
    required bool isVideo,
    String caption = '',
    String? sourcePostId,
  }) async {
    try {
      if (sourcePostId != null && sourcePostId.isNotEmpty) {
        final existing = await FirebaseFirestore.instance
            .collection('reels')
            .where('sourcePostId', isEqualTo: sourcePostId)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) return null;
      }
      final text = caption.trim();
      final tags = HashtagUtils.extractUnique(text);
      final mentionedIds = _resolveMentionIds(
        text: text,
        actorId: author.id,
        directory: _auth?.directory ?? const [],
      );
      final doc = FirebaseFirestore.instance.collection('reels').doc();
      final reel = CampusReel.fromAuthor(
        id: doc.id,
        author: author,
        mediaUrl: mediaUrl,
        isVideo: isVideo,
        caption: text,
        hashtags: tags,
        mentionedUserIds: mentionedIds,
        sourcePostId: sourcePostId,
      );
      await doc.set(reel.toFirestore());
      unawaited(_notifyReelMentions(
        content: text,
        reelId: doc.id,
        actorId: author.id,
        actorName: author.fullName,
        mentionedIds: mentionedIds,
      ));
      return null;
    } catch (e) {
      debugPrint('[reels] createUrl: $e');
      return 'Reels paylaşılamadı: $e';
    }
  }

  List<String> _resolveMentionIds({
    required String text,
    required String actorId,
    required List<AppUser> directory,
  }) {
    final handles = MentionUtils.extractHandles(text);
    if (handles.isEmpty) return const [];
    final ids = <String>{};
    for (final h in handles) {
      for (final u in directory) {
        final uh = u.handle.replaceFirst('@', '').toLowerCase();
        final un = (u.username ?? '').toLowerCase();
        if ((uh == h || un == h) && u.id != actorId && u.allowMentions) {
          ids.add(u.id);
          break;
        }
      }
    }
    return ids.toList();
  }

  Future<void> _notifyReelMentions({
    required String content,
    required String reelId,
    required String actorId,
    required String actorName,
    required List<String> mentionedIds,
  }) async {
    if (mentionedIds.isEmpty && content.isEmpty) return;
    final copy = NotificationCopy.mention(actorName);
    for (final uid in mentionedIds) {
      try {
        await PushService.instance.dispatch(
          toUserId: uid,
          title: copy.$1,
          body: '${copy.$2} (Kampüs Reels)',
          emoji: copy.$3,
          type: 'mention',
          actorId: actorId,
          targetId: reelId,
        );
      } catch (e) {
        debugPrint('[reels] mention notify: $e');
      }
    }
  }

  Future<void> markViewed(String reelId, String userId) async {
    if (userId.isEmpty) return;
    final i = _items.indexWhere((r) => r.id == reelId);
    if (i < 0) return;
    if (_items[i].viewedByUser(userId)) return;
    final viewed = List<String>.from(_items[i].viewedBy)..add(userId);
    _items[i] = _items[i].copyWith(viewedBy: viewed);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('reels').doc(reelId).set(
        {
          'viewedBy': FieldValue.arrayUnion([userId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[reels] view: $e');
    }
  }

  Future<void> toggleLike(String reelId, String userId) async {
    final i = _items.indexWhere((r) => r.id == reelId);
    if (i < 0) return;
    final liked = List<String>.from(_items[i].likedBy);
    final was = liked.contains(userId);
    if (was) {
      liked.remove(userId);
    } else {
      liked.add(userId);
    }
    _items[i] = _items[i].copyWith(likedBy: liked);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('reels').doc(reelId).set(
        {
          'likedBy': was
              ? FieldValue.arrayRemove([userId])
              : FieldValue.arrayUnion([userId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[reels] like: $e');
    }
  }

  Stream<List<ReelComment>> commentsStream(String reelId) {
    return FirebaseFirestore.instance
        .collection('reels')
        .doc(reelId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(80)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => ReelComment.fromFirestore(d.id, d.data()))
              .toList(),
        );
  }

  Future<String?> addComment({
    required String reelId,
    required AppUser author,
    required String content,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return 'Boş yorum';
    try {
      final col = FirebaseFirestore.instance
          .collection('reels')
          .doc(reelId)
          .collection('comments');
      final doc = col.doc();
      final comment = ReelComment(
        id: doc.id,
        reelId: reelId,
        authorId: author.id,
        authorName: author.fullName,
        authorHandle: author.handle,
        authorPhotoUrl: author.photoUrl,
        authorVerified: author.showBlueBadge || author.showGoldBadge,
        content: text,
        createdAt: DateTime.now(),
      );
      await doc.set(comment.toFirestore());
      await FirebaseFirestore.instance.collection('reels').doc(reelId).set(
        {'commentCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      final i = _items.indexWhere((r) => r.id == reelId);
      if (i >= 0) {
        _items[i] =
            _items[i].copyWith(commentCount: _items[i].commentCount + 1);
        notifyListeners();
      }
      final mentioned = _resolveMentionIds(
        text: text,
        actorId: author.id,
        directory: _auth?.directory ?? const [],
      );
      unawaited(_notifyReelMentions(
        content: text,
        reelId: reelId,
        actorId: author.id,
        actorName: author.fullName,
        mentionedIds: mentioned,
      ));
      return null;
    } catch (e) {
      debugPrint('[reels] comment: $e');
      return 'Yorum gönderilemedi';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _auth?.removeListener(_onAuth);
    unawaited(ReelsVideoCache.instance.clear());
    super.dispose();
  }
}
