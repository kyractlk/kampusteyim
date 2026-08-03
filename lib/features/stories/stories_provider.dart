import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/media_disk_cache.dart';
import '../../core/storage/media_upload.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'story_models.dart';

class StoriesProvider extends ChangeNotifier {
  StoriesProvider();

  final List<StoryItem> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _viewerId;
  Set<String> _followingIds = {};
  AuthProvider? _auth;
  bool _loading = false;
  String? _error;

  bool get isLoading => _loading;
  String? get error => _error;
  List<StoryItem> get allItems => List.unmodifiable(_items);

  void attachAuth(AuthProvider auth) {
    _auth = auth;
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;
    final me = auth.user;
    final nextId = me?.id;
    final nextFollowing = <String>{
      if (me != null) ...me.following,
      if (me != null) me.id,
    };
    // Aynı kullanıcı: takip listesi değişince stream’i koparma — anında filtrele.
    if (nextId != null && nextId == _viewerId && _sub != null) {
      if (!setEquals(nextFollowing, _followingIds)) {
        _followingIds = nextFollowing;
        notifyListeners();
        unawaited(_prefetchVisibleMedia());
      }
      return;
    }
    _viewerId = nextId;
    _followingIds = nextFollowing;
    _bind();
  }

  int _liveEpoch = 0;
  bool _hasLiveSnapshot = false;

  void _bind() {
    _sub?.cancel();
    _sub = null;
    _hasLiveSnapshot = false;
    if (_viewerId == null) {
      _items.clear();
      notifyListeners();
      return;
    }
    // İlk açılışta loading; yeniden bağlanırken halkayı boşaltma.
    if (_items.isEmpty) {
      _loading = true;
      notifyListeners();
    }
    unawaited(_hydrateFromCallable());
    _sub = FirebaseFirestore.instance
        .collection('stories')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen(
      (snap) {
        _liveEpoch++;
        _hasLiveSnapshot = true;
        final next = snap.docs
            .map((d) => StoryItem.fromFirestore(d.id, d.data()))
            .toList();
        _applyLiveItems(next);
        _loading = false;
        _error = null;
        notifyListeners();
        unawaited(_prefetchVisibleMedia());
      },
      onError: (e) {
        debugPrint('[stories] bind: $e');
        _loading = false;
        _error = 'Hikâyeler yüklenemedi';
        notifyListeners();
      },
    );
  }

  /// Snapshot / callable birleşimi — id bazlı upsert, silinenler düşer.
  void _applyLiveItems(List<StoryItem> next) {
    _items
      ..clear()
      ..addAll(next);
  }

  Future<void> _hydrateFromCallable() async {
    final me = _auth?.user;
    if (me == null || _viewerId == null) return;
    final epochAtStart = _liveEpoch;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getStoriesFeed');
      final res = await callable.call({
        'followingIds': me.following,
        'limit': 200,
      });
      // Canlı snapshot geldiyse callable eski veriyle ezmesin (WS hissi).
      if (_hasLiveSnapshot || _liveEpoch != epochAtStart) return;
      final map = Map<String, dynamic>.from(res.data as Map? ?? {});
      final raw = (map['items'] as List?) ?? [];
      if (raw.isEmpty) return;
      if (_hasLiveSnapshot || _liveEpoch != epochAtStart) return;
      _applyLiveItems(
        raw.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          final id = '${m.remove('id') ?? ''}';
          return StoryItem.fromFirestore(id, m);
        }).toList(),
      );
      _loading = false;
      _error = null;
      notifyListeners();
      unawaited(_prefetchVisibleMedia());
    } catch (e) {
      debugPrint('[stories] getStoriesFeed: $e');
    }
  }

  bool _canSeeAuthor(String authorId) {
    final me = _viewerId;
    if (me == null) return false;
    if (authorId == me) return true;
    final auth = _auth;
    // Instagram: hikâye yalnız takip edenlere (gizli/açık hesap fark etmez).
    // Gizli hesapta zaten takip isteği olmadan following olmaz.
    if (auth != null) {
      if (auth.follows(authorId) || _followingIds.contains(authorId)) {
        return true;
      }
      return false;
    }
    return _followingIds.contains(authorId);
  }

  List<StoryItem> visibleItemsForViewer() {
    final me = _viewerId;
    if (me == null) return const [];
    final spectator = _auth?.user?.isSpectatorMode == true;
    if (spectator) return const [];
    return _items.where((s) {
      if (!_canSeeAuthor(s.authorId)) return false;
      return s.isVisibleTo(me, isFollowerOrSelf: true);
    }).toList(growable: false);
  }

  Future<void> _prefetchVisibleMedia() async {
    final urls = warmMediaUrls();
    // Disk ısıtma arka planda — UI’yı bloklamaz (stream-first ile uyumlu).
    MediaDiskCache.instance.prefetchAll(
      urls.take(30),
      concurrency: 3,
      front: true,
    );
    for (final url in urls.take(16)) {
      unawaited(_prefetchUrl(url, isVideo: false));
    }
  }

  /// MediaWarmHelper için görünür hikâye medya URL'leri.
  List<String> warmMediaUrls() {
    return visibleItemsForViewer()
        .map((s) => s.mediaUrl)
        .where((u) => u.startsWith('http'))
        .toList(growable: false);
  }

  Future<void> _prefetchUrl(String url, {required bool isVideo}) async {
    if (!url.startsWith('http')) return;
    try {
      // Tam indirmeyi bekleme — görseller için ImageCache, video disk arka plan.
      if (!isVideo) {
        if (kIsWeb) return;
        final existing = await MediaDiskCache.instance.fileFor(url);
        if (existing != null) return;
        final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
        final completer = Completer<void>();
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, sync) {
            if (!completer.isCompleted) completer.complete();
            stream.removeListener(listener);
          },
          onError: (e, st) {
            if (!completer.isCompleted) completer.complete();
            stream.removeListener(listener);
          },
        );
        stream.addListener(listener);
        await completer.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () {},
        );
        unawaited(MediaDiskCache.instance.ensure(url, highPriority: false));
      } else if (!kIsWeb) {
        unawaited(MediaDiskCache.instance.ensure(url, highPriority: false));
      }
    } catch (_) {}
  }

  /// Halka çubuğu: kendi → görülmemiş (renkli) → görülmüş (gri, sonda).
  List<Story> storyRings() {
    final visible = visibleItemsForViewer();
    final byAuthor = <String, List<StoryItem>>{};
    for (final item in visible) {
      byAuthor.putIfAbsent(item.authorId, () => []).add(item);
    }
    final rings = <Story>[];
    for (final entry in byAuthor.entries) {
      final items = List<StoryItem>.from(entry.value)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final first = items.first;
      final author = _auth?.findUser(entry.key);
      rings.add(
        Story(
          authorId: entry.key,
          authorName: author?.fullName ?? first.authorName,
          authorHandle: author?.handle ?? first.authorHandle,
          authorPhotoUrl: author?.photoUrl,
          items: items,
        ),
      );
    }
    final me = _viewerId;
    final myIds = me == null
        ? <String>{}
        : (_auth?.idsFor(me) ?? <String>{me});

    rings.sort((a, b) {
      if (me != null) {
        if (a.authorId == me && b.authorId != me) return -1;
        if (b.authorId == me && a.authorId != me) return 1;
      }
      final aSeen = me != null &&
          a.authorId != me &&
          a.isFullySeenBy(myIds);
      final bSeen = me != null &&
          b.authorId != me &&
          b.isFullySeenBy(myIds);
      // Görülmemişler önde, görülmüşler sonda.
      if (aSeen != bSeen) return aSeen ? 1 : -1;
      return b.latestAt.compareTo(a.latestAt);
    });
    return rings;
  }

  /// Halka rengi için: bu yazarın hikâyesi tamamen görüldü mü?
  bool isRingSeen(Story ring) {
    final me = _viewerId;
    if (me == null) return false;
    if (ring.authorId == me) return false;
    final ids = _auth?.idsFor(me) ?? <String>{me};
    return ring.isFullySeenBy(ids);
  }

  Story? storyForUser(String userId) {
    try {
      return storyRings().firstWhere((s) => s.authorId == userId);
    } catch (_) {
      return null;
    }
  }

  Future<String?> createStory({
    required AppUser author,
    required XFile file,
    bool isVideo = false,
    void Function(double progress)? onProgress,
  }) async {
    if (author.isSpectatorMode) {
      return 'İzleyici modunda hikâye paylaşamazsın.';
    }
    if (!author.canUseStories) {
      return 'Hikâye paylaşımı şu an kullanılamıyor.';
    }
    try {
      final authUid = author.id;
      final url = await MediaUpload.uploadXFile(
        file: file,
        folder: 'stories/$authUid',
        firstName: author.firstName,
        lastName: author.lastName,
        studentNo: author.studentNo,
        isVideo: isVideo,
        onProgress: onProgress,
      );
      final now = DateTime.now();
      final doc = FirebaseFirestore.instance.collection('stories').doc();
      final item = StoryItem(
        id: doc.id,
        authorId: author.id,
        authorName: author.fullName,
        authorHandle: author.handle,
        mediaUrl: url,
        mediaType: isVideo ? MediaType.video : MediaType.image,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
      );
      await doc.set(item.toFirestore());
      // Optimistic — snapshot gelmeden halkada saniyelik görünsün.
      final existing = _items.indexWhere((s) => s.id == item.id);
      if (existing >= 0) {
        _items[existing] = item;
      } else {
        _items.insert(0, item);
      }
      notifyListeners();
      // Yeni hikâyeyi arka planda ısıt (stream-first — bloklama yok).
      MediaDiskCache.instance.prefetchAll([url], concurrency: 1, front: true);
      return null;
    } catch (e) {
      debugPrint('[stories] create: $e');
      return 'Hikâye paylaşılamadı: $e';
    }
  }

  Future<void> likeStory(String storyId, String userId) async {
    if (_auth?.user?.isSpectatorMode == true) return;
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    final item = _items[i];
    final liked = List<String>.from(item.likedBy);
    final wasLiked = liked.contains(userId);
    if (wasLiked) {
      liked.remove(userId);
    } else {
      liked.add(userId);
    }
    _items[i] = item.copyWith(likedBy: liked);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {
          'likedBy': wasLiked
              ? FieldValue.arrayRemove([userId])
              : FieldValue.arrayUnion([userId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] like: $e');
    }
  }

  /// İzleyici kaydı — sahip kendi hikâyesine bakınca yazılmaz.
  Future<void> recordView(String storyId, String viewerId) async {
    if (viewerId.isEmpty) return;
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    final item = _items[i];
    final myIds = _auth?.idsFor(viewerId) ?? <String>{viewerId};
    if (myIds.contains(item.authorId) || item.authorId == viewerId) return;
    if (item.viewedBy.any(myIds.contains)) return;
    // Canonical olarak viewerId yaz; UI eşlemesi idsFor ile yapılır.
    final viewed = List<String>.from(item.viewedBy)..add(viewerId);
    _items[i] = item.copyWith(viewedBy: viewed);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {
          'viewedBy': FieldValue.arrayUnion([viewerId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] view: $e');
    }
  }

  Future<void> deleteStory(String storyId) async {
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    final now = DateTime.now();
    _items[i] = _items[i].copyWith(deletedAt: now);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {'deletedAt': now.toIso8601String()},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] delete: $e');
    }
  }

  Future<void> archiveStory(String storyId) async {
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(archived: true);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {'archived': true},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] archive: $e');
    }
  }

  Future<void> hideFromUsers(String storyId, List<String> userIds) async {
    if (userIds.isEmpty) return;
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    final hidden = {..._items[i].hiddenFrom, ...userIds}.toList();
    _items[i] = _items[i].copyWith(hiddenFrom: hidden);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {'hiddenFrom': FieldValue.arrayUnion(userIds)},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] hide: $e');
    }
  }

  Future<void> reportStory(String storyId) async {
    final i = _items.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    final next = _items[i].reportCount + 1;
    _items[i] = _items[i].copyWith(reportCount: next);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).set(
        {'reportCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[stories] report: $e');
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _sub?.cancel();
    super.dispose();
  }
}
