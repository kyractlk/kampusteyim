import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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
    if (nextId == _viewerId &&
        setEquals(nextFollowing, _followingIds) &&
        _sub != null) {
      return;
    }
    _viewerId = nextId;
    _followingIds = nextFollowing;
    _bind();
  }

  void _bind() {
    _sub?.cancel();
    _sub = null;
    if (_viewerId == null) {
      _items.clear();
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    _sub = FirebaseFirestore.instance
        .collection('stories')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen(
      (snap) {
        _items
          ..clear()
          ..addAll(
            snap.docs.map((d) => StoryItem.fromFirestore(d.id, d.data())),
          );
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[stories] bind: $e');
        _loading = false;
        _error = 'Hikâyeler yüklenemedi';
        notifyListeners();
      },
    );
  }

  bool _canSeeAuthor(String authorId) {
    final me = _viewerId;
    if (me == null) return false;
    if (authorId == me) return true;
    final auth = _auth;
    if (auth != null) {
      return auth.follows(authorId) || _followingIds.contains(authorId);
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

  /// Halka çubuğu: yazar bazında gruplanmış aktif hikâyeler.
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
    rings.sort((a, b) {
      final me = _viewerId;
      if (me != null) {
        if (a.authorId == me && b.authorId != me) return -1;
        if (b.authorId == me && a.authorId != me) return 1;
      }
      return b.latestAt.compareTo(a.latestAt);
    });
    return rings;
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
