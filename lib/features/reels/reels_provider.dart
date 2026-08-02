import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/media_disk_cache.dart';
import '../../core/storage/media_upload.dart';
import '../../core/utils/hashtag_utils.dart';
import '../../core/utils/mention_utils.dart';
import '../../core/utils/campus_affinity.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
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
  FeedProvider? _feed;
  bool _loading = false;
  String? _error;
  bool _tabActive = false;
  String? _focusReelId;

  /// Alt bar Reels sekmesi görünür mü — ses/oynatma kapısı.
  bool get tabActive => _tabActive;
  bool get isLoading => _loading;
  String? get error => _error;
  List<CampusReel> get items => List.unmodifiable(_items);

  /// Profil grid’den Reels sekmesine odaklanılacak id.
  String? get focusReelId => _focusReelId;

  void requestFocusReel(String reelId) {
    final id = reelId.trim();
    if (id.isEmpty) return;
    _focusReelId = id;
    notifyListeners();
  }

  String? takeFocusReelId() {
    final id = _focusReelId;
    _focusReelId = null;
    return id;
  }

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
    final viaApi = await _hydrateFromCallable();
    if (viaApi) {
      _loading = false;
      notifyListeners();
      await _prefetchFeed();
      return;
    }
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
    await ReelsVideoCache.instance.prefetch(feed, count: 24, keepWarm: true);
  }

  /// MediaWarmHelper için görünür reels medya URL'leri.
  List<String> warmMediaUrls() {
    return feedFor(_auth?.user?.id)
        .map((r) => r.mediaUrl)
        .where((u) => u.startsWith('http'))
        .toList(growable: false);
  }

  /// Disk + controller ısıtma (sekme kapalıyken de).
  Future<void> warmAllMedia({bool forceControllers = false}) async {
    final feed = feedFor(_auth?.user?.id);
    if (feed.isEmpty) return;
    MediaDiskCache.instance.prefetchAll(
      feed.map((r) => r.mediaUrl),
      concurrency: 4,
      front: true,
    );
    await ReelsVideoCache.instance.prefetch(
      feed,
      count: forceControllers ? 28 : 20,
      keepWarm: true,
    );
  }

  Future<void> prefetchAround(List<CampusReel> feed, int index) async {
    if (feed.isEmpty) return;
    await ReelsVideoCache.instance.warmWindow(
      feed,
      index,
      behind: 1,
      ahead: kIsWeb ? 2 : 3,
    );
    // Uzak medyayı da disk kuyruğuna al (native).
    if (!kIsWeb) {
      final start = (index - 3).clamp(0, feed.length);
      final end = (index + 10).clamp(0, feed.length);
      MediaDiskCache.instance.prefetchAll(
        feed.sublist(start, end).map((r) => r.mediaUrl),
        concurrency: 4,
        front: true,
      );
    }
  }

  void attachAuth(AuthProvider auth) {
    _auth = auth;
    auth.addListener(_onAuth);
    _onAuth();
  }

  void attachFeed(FeedProvider feed) {
    _feed = feed;
  }

  /// Profil / gönderi sayacı — yazarın silinmemiş reels’leri.
  /// [onlyVisibleToViewer] true ise gizli hesap filtresi uygulanır.
  List<CampusReel> reelsByAuthors(
    Iterable<String> authorIds, {
    bool onlyVisibleToViewer = false,
  }) {
    final ids = authorIds.toSet();
    if (ids.isEmpty) return const [];
    final viewerId = _auth?.user?.id;
    final list = _items
        .where((r) {
          if (r.isDeleted || !ids.contains(r.authorId)) return false;
          if (onlyVisibleToViewer && !_canSeeReel(r, viewerId)) return false;
          return true;
        })
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
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
    unawaited(_hydrateFromCallable());
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

  Future<bool> _hydrateFromCallable() async {
    final me = _auth?.user;
    if (me == null) return false;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getReelsFeed');
      final res = await callable.call({
        'followingIds': me.following,
        'limit': 120,
      });
      final map = Map<String, dynamic>.from(res.data as Map? ?? {});
      final raw = (map['items'] as List?) ?? [];
      if (raw.isEmpty) return false;
      _items
        ..clear()
        ..addAll(
          raw.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = '${m.remove('id') ?? ''}';
            return CampusReel.fromFirestore(id, m);
          }).where((r) => !r.isDeleted),
        );
      _error = null;
      notifyListeners();
      unawaited(_prefetchFeed());
      return true;
    } catch (e) {
      debugPrint('[reels] getReelsFeed: $e');
      return false;
    }
  }

  bool _canSeeReel(CampusReel r, String? viewerId) {
    final auth = _auth;
    if (viewerId != null &&
        (auth?.idsFor(r.authorId).contains(viewerId) ?? false)) {
      return true;
    }
    if (auth == null) return true;
    return auth.canViewAuthorContent(r.authorId);
  }

  /// İzlenmemişler + aynı üniversite affinity; gizli hesap reels’leri takipçilere özel.
  List<CampusReel> feedFor(String? viewerId) {
    final list = _items.where((r) => _canSeeReel(r, viewerId)).toList();
    if (viewerId == null || viewerId.isEmpty) return list;
    final viewer = _auth?.user;
    list.sort((a, b) {
      final authorA = _auth?.findUser(a.authorId);
      final authorB = _auth?.findUser(b.authorId);
      final sa = CampusAffinity.scoreReel(
        viewer: viewer,
        author: authorA,
        createdAt: a.createdAt,
        followingAuthor: _auth?.follows(a.authorId) == true,
        unseen: !a.viewedByUser(viewerId),
        friendOfFriend: viewer != null &&
            authorA != null &&
            CampusAffinity.isFriendOfFriend(
              viewer: viewer,
              candidate: authorA,
              auth: _auth!,
            ),
      );
      final sb = CampusAffinity.scoreReel(
        viewer: viewer,
        author: authorB,
        createdAt: b.createdAt,
        followingAuthor: _auth?.follows(b.authorId) == true,
        unseen: !b.viewedByUser(viewerId),
        friendOfFriend: viewer != null &&
            authorB != null &&
            CampusAffinity.isFriendOfFriend(
              viewer: viewer,
              candidate: authorB,
              auth: _auth!,
            ),
      );
      final cmp = sb.compareTo(sa);
      if (cmp != 0) return cmp;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
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

      // Saf Reels paylaşımı → profil/akışta da gönderi olarak görünsün.
      var linkedPostId = sourcePostId;
      if (linkedPostId == null || linkedPostId.isEmpty) {
        final feed = _feed;
        if (feed != null) {
          final postErr = await feed.addPost(
            authorId: author.id,
            authorName: author.fullName,
            authorHandle: author.handle,
            content: text,
            media: [
              MediaItem(
                url: mediaUrl,
                type: isVideo ? MediaType.video : MediaType.image,
              ),
            ],
            isCommunity: author.isCommunity,
            directory: _auth?.directory ?? const [],
            skipReelMirror: true,
          );
          if (postErr != null && !postErr.startsWith('WARN:')) {
            return postErr;
          }
          linkedPostId = feed.lastPostedId;
        }
      }

      final doc = FirebaseFirestore.instance.collection('reels').doc();
      final reel = CampusReel.fromAuthor(
        id: doc.id,
        author: author,
        mediaUrl: mediaUrl,
        isVideo: isVideo,
        caption: text,
        hashtags: tags,
        mentionedUserIds: mentionedIds,
        sourcePostId: linkedPostId,
      );
      await doc.set(reel.toFirestore());
      _items.insert(0, reel);
      notifyListeners();
      // Atıldığı an cihaza indir / ısıt.
      MediaDiskCache.instance.prefetchAll([mediaUrl], concurrency: 1);
      unawaited(ReelsVideoCache.instance.prefetch([reel], count: 1, keepWarm: true));
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

  Future<String?> updateCaption({
    required String reelId,
    required String caption,
    required String actorId,
  }) async {
    final i = _items.indexWhere((r) => r.id == reelId);
    if (i < 0) return 'Reels bulunamadı';
    final reel = _items[i];
    if (reel.authorId != actorId) return 'Bu Reels’i düzenleyemezsin';
    final text = caption.trim();
    final tags = HashtagUtils.extractUnique(text);
    final mentionedIds = _resolveMentionIds(
      text: text,
      actorId: actorId,
      directory: _auth?.directory ?? const [],
    );
    final updated = reel.copyWith(
      caption: text,
      hashtags: tags,
      mentionedUserIds: mentionedIds,
    );
    _items[i] = updated;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('reels').doc(reelId).set({
        'caption': text,
        'hashtags': tags,
        'mentionedUserIds': mentionedIds,
      }, SetOptions(merge: true));
      final postId = reel.sourcePostId;
      if (postId != null && postId.isNotEmpty) {
        await _feed?.updatePostContent(postId, text);
      }
      return null;
    } catch (e) {
      debugPrint('[reels] updateCaption: $e');
      return 'Açıklama güncellenemedi';
    }
  }

  Future<String?> deleteReel({
    required String reelId,
    required String byUserId,
  }) async {
    final i = _items.indexWhere((r) => r.id == reelId);
    if (i < 0) return 'Reels bulunamadı';
    final reel = _items[i];
    if (reel.authorId != byUserId) return 'Bu Reels’i silemezsin';
    final now = DateTime.now();
    _items[i] = reel.copyWith(deletedAt: now);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('reels').doc(reelId).set(
        {'deletedAt': now.toIso8601String()},
        SetOptions(merge: true),
      );
      final postId = reel.sourcePostId;
      if (postId != null && postId.isNotEmpty) {
        await _feed?.softDeletePost(
          postId,
          byUserId: byUserId,
          cascadeReels: false,
        );
      }
      _items.removeWhere((r) => r.id == reelId);
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('[reels] delete: $e');
      return 'Reels silinemedi';
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
