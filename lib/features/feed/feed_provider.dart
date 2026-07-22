import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../core/moderation/local_safety.dart';
import '../../core/utils/hashtag_utils.dart';
import '../../core/utils/mention_utils.dart';
import '../../models/models.dart';
import '../notifications/notification_models.dart';
import '../notifications/notification_provider.dart';

class FeedProvider extends ChangeNotifier {
  FeedProvider() {
    _posts = [];
    _announcements = [];
    _events = [];
    _comments = [];
    _bindFirestore();
    _enforceEventDeadlines();
  }

  NotificationProvider? _notifications;

  void attachNotifications(NotificationProvider notifications) {
    _notifications = notifications;
  }

  late List<Post> _posts;
  late List<Announcement> _announcements;
  late List<CampusEvent> _events;
  late List<Comment> _comments;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _postsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _annSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _eventsSub;
  final Set<String> _likedLocal = {};
  final Set<String> _repostedLocal = {};

  List<Post> get posts {
    return _posts
        .where((p) => !p.isDeleted)
        .map(
          (p) => p.copyWith(
            isLiked: _likedLocal.contains(p.id),
            isReposted: _repostedLocal.contains(p.id),
          ),
        )
        .toList(growable: false);
  }

  /// Admin: silinmişler dahil.
  List<Post> get allPostsAdmin {
    return _posts
        .map(
          (p) => p.copyWith(
            isLiked: _likedLocal.contains(p.id),
            isReposted: _repostedLocal.contains(p.id),
          ),
        )
        .toList(growable: false);
  }

  List<Announcement> get announcements => List.unmodifiable(_announcements);
  List<CampusEvent> get events => List.unmodifiable(_events);

  /// Etkileşim skoruna göre en popüler hashtag’ler (beğeni+yorum+repost).
  List<({String tag, int score, int posts})> popularHashtags({int limit = 5}) {
    final scores = <String, int>{};
    final counts = <String, int>{};
    for (final p in posts) {
      final score = p.likeCount + p.replyCount * 2 + p.repostCount * 3;
      for (final raw in p.hashtags) {
        final tag = raw.replaceFirst('#', '').toLowerCase().trim();
        if (tag.isEmpty) continue;
        scores[tag] = (scores[tag] ?? 0) + score + 1;
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final keys = scores.keys.toList()
      ..sort((a, b) {
        final cmp = scores[b]!.compareTo(scores[a]!);
        if (cmp != 0) return cmp;
        return counts[b]!.compareTo(counts[a]!);
      });
    return keys
        .take(limit)
        .map(
          (t) => (
            tag: t,
            score: scores[t]!,
            posts: counts[t]!,
          ),
        )
        .toList();
  }

  Post? postById(String id) {
    try {
      final p = _posts.firstWhere((p) => p.id == id && !p.isDeleted);
      return p.copyWith(
        isLiked: _likedLocal.contains(p.id),
        isReposted: _repostedLocal.contains(p.id),
      );
    } catch (_) {
      return null;
    }
  }

  List<Post> postsByAuthor(String authorId) =>
      postsByAuthors({authorId});

  List<Post> postsByAuthors(Set<String> authorIds) {
    if (authorIds.isEmpty) return const [];
    return posts.where((p) => authorIds.contains(p.authorId)).toList();
  }

  Announcement? announcementById(String id) {
    try {
      return _announcements.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  CampusEvent? eventById(String id) {
    try {
      return _events.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Comment> commentsFor(String postId) {
    final list = _comments
        .where((c) => c.postId == postId && !c.isDeleted)
        .map(
          (c) => c.copyWith(
            replies: c.replies.where((r) => !r.isDeleted).toList(),
          ),
        )
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  Future<Post?> ensurePostLoaded(String id) async {
    final local = postByIdIncludingDeleted(id);
    if (local != null) return local;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('posts').doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      final post = Post.fromMap(doc.id, doc.data()!);
      final i = _posts.indexWhere((p) => p.id == id);
      if (i >= 0) {
        _posts[i] = post;
      } else {
        _posts.insert(0, post);
      }
      notifyListeners();
      return post;
    } catch (e) {
      debugPrint('[feed] ensurePost: $e');
      return null;
    }
  }

  Post? postByIdIncludingDeleted(String id) {
    try {
      final p = _posts.firstWhere((p) => p.id == id);
      return p.copyWith(
        isLiked: _likedLocal.contains(p.id),
        isReposted: _repostedLocal.contains(p.id),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> softDeletePost(String postId, {required String byUserId}) async {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final updated = _posts[i].copyWith(
      deletedAt: DateTime.now(),
      deletedBy: byUserId,
    );
    _posts[i] = updated;
    notifyListeners();
    await _writePost(updated);
  }

  Future<void> softDeleteComment(
    String commentId, {
    required String byUserId,
    String? parentId,
  }) async {
    if (parentId == null) {
      final i = _comments.indexWhere((c) => c.id == commentId);
      if (i < 0) return;
      final updated = _comments[i].copyWith(
        deletedAt: DateTime.now(),
        deletedBy: byUserId,
        content: 'Bu yorum silindi',
      );
      _comments[i] = updated;
      notifyListeners();
      await _writeComment(updated);
      return;
    }
    final i = _comments.indexWhere((c) => c.id == parentId);
    if (i < 0) return;
    final parent = _comments[i];
    final replies = parent.replies.map((r) {
      if (r.id != commentId) return r;
      return r.copyWith(
        deletedAt: DateTime.now(),
        deletedBy: byUserId,
        content: 'Bu yorum silindi',
      );
    }).toList();
    final updated = parent.copyWith(replies: replies);
    _comments[i] = updated;
    notifyListeners();
    await _writeComment(updated);
  }

  Future<void> restorePost(String postId) async {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final updated = _posts[i].copyWith(clearDeleted: true);
    _posts[i] = updated;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).set({
        ...updated.toMap(),
        'deletedAt': FieldValue.delete(),
        'deletedBy': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] restore: $e');
    }
  }

  Future<void> hardDeletePost(String postId) async {
    _posts.removeWhere((p) => p.id == postId);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
    } catch (e) {
      debugPrint('[feed] hardDelete: $e');
    }
  }

  void _bindFirestore() {
    final db = FirebaseFirestore.instance;
    _postsSub = db.collection('posts').snapshots().listen((snap) async {
      final remote = snap.docs
          .map((d) => Post.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (remote.isEmpty) {
        _posts = [];
        notifyListeners();
        return;
      }
      _posts = remote;
      notifyListeners();
    }, onError: (e) => debugPrint('[feed] posts stream: $e'));

    _commentsSub = db.collection('comments').snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      _comments = snap.docs
          .map((d) => Comment.fromMap(d.id, d.data()))
          .toList();
      notifyListeners();
    }, onError: (e) => debugPrint('[feed] comments stream: $e'));

    _annSub = db.collection('announcements').snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      final remote = snap.docs
          .map((d) => Announcement.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _announcements = remote;
      notifyListeners();
    }, onError: (e) => debugPrint('[feed] announcements stream: $e'));

    _eventsSub = db.collection('events').snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      final remote = snap.docs
          .map((d) => CampusEvent.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      _events = remote;
      notifyListeners();
      _enforceEventDeadlines();
    }, onError: (e) => debugPrint('[feed] events stream: $e'));
  }

  Future<void> _writeEvent(CampusEvent event) async {
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .set(event.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] writeEvent: $e');
    }
  }

  Future<void> _notify({
    required String toUserId,
    required (String, String, String) copy,
    required String type,
    String? actorId,
    String? targetId,
  }) async {
    final n = _notifications;
    if (n == null || toUserId.isEmpty) return;
    await n.pushSocial(
      toUserId: toUserId,
      title: copy.$1,
      body: copy.$2,
      emoji: copy.$3,
      type: type,
      actorId: actorId,
      targetId: targetId,
    );
  }

  /// Son başvuru saati geçen etkinliklerde bekleyen başvuruları iptal eder.
  Future<void> _enforceEventDeadlines() async {
    var changed = false;
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      if (!e.isDeadlinePassed || !e.applicationsOpen) continue;
      final hadPending =
          e.applications.any((a) => a.status == EventApplicationStatus.pending);
      if (!hadPending && !e.applicationsOpen) continue;

      final apps = e.applications.map((a) {
        if (a.status != EventApplicationStatus.pending) return a;
        return a.copyWith(status: EventApplicationStatus.cancelled);
      }).toList();
      final updated = e.copyWith(
        applications: apps,
        applicationsOpen: false,
        applicantCount: apps.where((a) => a.holdsSlot).length,
        isApplied: false,
      );
      // isApplied kullanıcıya özel — stream'de korunmaz; local flag için ayrı
      _events[i] = updated.copyWith(isApplied: e.isApplied);
      changed = true;
      await _writeEvent(updated);

      final communityId = e.communityId;
      if (communityId != null && hadPending) {
        await _notify(
          toUserId: communityId,
          copy: NotificationCopy.eventDeadlinePassed(e.title),
          type: 'community',
          targetId: e.id,
        );
        for (final a in e.applications) {
          if (a.status != EventApplicationStatus.pending) continue;
          await _notify(
            toUserId: a.userId,
            copy: NotificationCopy.eventApplicationCancelled(
              eventTitle: e.title,
            ),
            type: 'community',
            targetId: e.id,
          );
        }
      }
    }
    if (changed) notifyListeners();
  }

  /// Eski mock seed kaldırıldı — feed yalnızca Firestore.
  Future<void> trySeedMockIfEmpty() async {}

  Future<void> _writePost(Post post) async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post.id)
          .set(post.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] writePost: $e');
    }
  }

  Future<void> _writeComment(Comment comment) async {
    try {
      await FirebaseFirestore.instance
          .collection('comments')
          .doc(comment.id)
          .set(comment.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] writeComment: $e');
    }
  }

  void toggleLike(String postId) {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final post = _posts[i];
    final liked = !_likedLocal.contains(postId);
    if (liked) {
      _likedLocal.add(postId);
    } else {
      _likedLocal.remove(postId);
    }
    final updated = post.copyWith(
      isLiked: liked,
      likeCount: post.likeCount + (liked ? 1 : -1),
    );
    _posts[i] = updated;
    notifyListeners();
    _writePost(updated.copyWith(isLiked: false));
  }

  void toggleRepost({
    required String postId,
    required AppUser user,
  }) {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final post = _posts[i];
    final reposted = !_repostedLocal.contains(postId);
    if (reposted) {
      _repostedLocal.add(postId);
    } else {
      _repostedLocal.remove(postId);
    }
    final updated = post.copyWith(
      isReposted: reposted,
      repostCount: post.repostCount + (reposted ? 1 : -1),
    );
    _posts[i] = updated;

    if (reposted) {
      final rp = Post(
        id: 'rp_${DateTime.now().millisecondsSinceEpoch}',
        authorId: user.id,
        authorName: user.fullName,
        authorHandle: user.handle,
        content: post.content,
        createdAt: DateTime.now(),
        media: post.media,
        hashtags: post.hashtags,
        isCommunity: user.isCommunity,
        repostedFromId: post.id,
        repostedFromName: post.authorName,
      );
      _posts.insert(0, rp);
      _writePost(rp);
    }
    notifyListeners();
    _writePost(updated.copyWith(isReposted: false));
  }

  String? lastPostedId;

  Future<String?> addPost({
    required String authorId,
    required String authorName,
    required String authorHandle,
    required String content,
    List<MediaItem> media = const [],
    bool isCommunity = false,
    List<AppUser> directory = const [],
  }) async {
    final text = content.trim();
    if (text.isEmpty && media.isEmpty) return 'Boş gönderi';

    // Yerel Guard — OpenAI kotası olmasa da nefret/şiddet engeli
    final localBlock = LocalSafety.blockReason(text);
    if (localBlock != null) return localBlock;

    final tags = HashtagUtils.extractUnique(text);
    final post = Post(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      authorId: authorId,
      authorName: authorName,
      authorHandle: authorHandle,
      content: text,
      createdAt: DateTime.now(),
      media: media,
      hashtags: tags,
      isCommunity: isCommunity,
    );

    // AYS Tech Guard: içerik + link denetimi
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('moderatePostContent');
      final res = await callable.call({
        'postId': post.id,
        'authorId': authorId,
        'content': text,
        'mediaUrls': media.map((m) => m.url).toList(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (data['blocked'] == true) {
        return '${data['message'] ?? 'İçerik Guard tarafından engellendi.'}';
      }
      if (data['warning'] != null && '${data['warning']}'.isNotEmpty) {
        _posts.insert(0, post);
        lastPostedId = post.id;
        notifyListeners();
        await _writePost(post);
        unawaited(_notifyMentions(
          content: text,
          postId: post.id,
          actorId: authorId,
          actorName: authorName,
          directory: directory,
        ));
        return 'WARN:${data['warning']}';
      }
    } catch (e) {
      debugPrint('[feed] moderatePost: $e');
    }

    _posts.insert(0, post);
    lastPostedId = post.id;
    notifyListeners();
    await _writePost(post);
    unawaited(_notifyMentions(
      content: text,
      postId: post.id,
      actorId: authorId,
      actorName: authorName,
      directory: directory,
    ));
    return null;
  }

  Future<void> _notifyMentions({
    required String content,
    required String postId,
    required String actorId,
    required String actorName,
    required List<AppUser> directory,
  }) async {
    final handles = MentionUtils.extractHandles(content);
    if (handles.isEmpty) return;
    final notified = <String>{};
    for (final h in handles) {
      AppUser? target;
      for (final u in directory) {
        final uh = u.handle.replaceFirst('@', '').toLowerCase();
        final un = (u.username ?? '').toLowerCase();
        if (uh == h || un == h) {
          target = u;
          break;
        }
      }
      if (target == null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: h)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final m = snap.docs.first.data();
            if (m['allowMentions'] == false) continue;
            final uid = snap.docs.first.id;
            if (uid == actorId || notified.contains(uid)) continue;
            notified.add(uid);
            await _notify(
              toUserId: uid,
              copy: NotificationCopy.mention(actorName),
              type: 'mention',
              actorId: actorId,
              targetId: postId,
            );
          }
        } catch (e) {
          debugPrint('[feed] mention lookup: $e');
        }
        continue;
      }
      if (!target.allowMentions) continue;
      if (target.id == actorId || notified.contains(target.id)) continue;
      notified.add(target.id);
      await _notify(
        toUserId: target.id,
        copy: NotificationCopy.mention(actorName),
        type: 'mention',
        actorId: actorId,
        targetId: postId,
      );
    }
  }

  void addComment({
    required String postId,
    required AppUser author,
    required String content,
    String? parentId,
  }) {
    final text = content.trim();
    if (text.isEmpty) return;

    final comment = Comment(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      postId: postId,
      parentId: parentId,
      authorId: author.id,
      authorName: author.fullName,
      authorHandle: author.handle,
      content: text,
      createdAt: DateTime.now(),
    );

    if (parentId == null) {
      _comments.insert(0, comment);
      _writeComment(comment);
    } else {
      final i = _comments.indexWhere((c) => c.id == parentId);
      if (i < 0) return;
      final parent = _comments[i];
      final updated = parent.copyWith(
        replies: [comment, ...parent.replies],
      );
      _comments[i] = updated;
      _writeComment(updated);
    }

    final pi = _posts.indexWhere((p) => p.id == postId);
    if (pi >= 0) {
      final post = _posts[pi];
      final updated = post.copyWith(replyCount: post.replyCount + 1);
      _posts[pi] = updated;
      _writePost(updated);
    }
    notifyListeners();
  }

  void toggleCommentLike(String commentId, {String? parentId}) {
    if (parentId == null) {
      final i = _comments.indexWhere((c) => c.id == commentId);
      if (i < 0) return;
      final c = _comments[i];
      final liked = !c.isLiked;
      final updated = c.copyWith(
        isLiked: liked,
        likeCount: c.likeCount + (liked ? 1 : -1),
      );
      _comments[i] = updated;
      _writeComment(updated);
    } else {
      final i = _comments.indexWhere((c) => c.id == parentId);
      if (i < 0) return;
      final parent = _comments[i];
      final replies = [...parent.replies];
      final ri = replies.indexWhere((r) => r.id == commentId);
      if (ri < 0) return;
      final r = replies[ri];
      final liked = !r.isLiked;
      replies[ri] = r.copyWith(
        isLiked: liked,
        likeCount: r.likeCount + (liked ? 1 : -1),
      );
      final updated = parent.copyWith(replies: replies);
      _comments[i] = updated;
      _writeComment(updated);
    }
    notifyListeners();
  }

  void pinComment(String postId, String commentId) {
    for (var i = 0; i < _comments.length; i++) {
      final c = _comments[i];
      if (c.postId != postId) continue;
      final updated =
          c.copyWith(isPinned: c.id == commentId ? !c.isPinned : false);
      _comments[i] = updated;
      _writeComment(updated);
    }
    notifyListeners();
  }

  Future<String?> applyToEvent(
    String eventId, {
    AppUser? applicant,
    bool Function(String communityId)? follows,
  }) async {
    await _enforceEventDeadlines();
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) return 'Etkinlik bulunamadı';
    final event = _events[i];
    if (applicant == null) return 'Giriş gerekli';

    final already = event.applications.any(
      (a) =>
          a.userId == applicant.id &&
          (a.status == EventApplicationStatus.pending ||
              a.status == EventApplicationStatus.approved),
    );
    if (already || event.isApplied) return 'Zaten başvurdun';

    final blocked = event.applyBlockedReason(
      user: applicant,
      follows: follows,
    );
    if (blocked.isNotEmpty) return blocked;

    final apps = [
      ...event.applications,
      EventApplication(
        id: 'ea_${DateTime.now().millisecondsSinceEpoch}',
        userId: applicant.id,
        userName: applicant.fullName,
        createdAt: DateTime.now(),
      ),
    ];
    final updated = event.copyWith(
      isApplied: true,
      applicantCount: apps.where((a) => a.holdsSlot).length,
      applications: apps,
    );
    _events[i] = updated;
    notifyListeners();
    await _writeEvent(updated);

    final communityId = event.communityId;
    if (communityId != null) {
      await _notify(
        toUserId: communityId,
        copy: NotificationCopy.eventApplication(
          who: applicant.fullName,
          eventTitle: event.title,
        ),
        type: 'community',
        actorId: applicant.id,
        targetId: event.id,
      );
    }
    return null;
  }

  Future<void> addEvent(
    CampusEvent event, {
    bool notifyAudience = false,
  }) async {
    _events.insert(0, event);
    notifyListeners();
    await _writeEvent(event);
    if (notifyAudience) {
      unawaited(_notifyAudienceBroadcast(
        kind: 'event',
        actorId: event.communityId ?? '',
        actorName: event.communityName ?? 'Topluluk',
        audience: event.audience,
        title: 'Yeni etkinlik',
        body: event.title,
        emoji: '📅',
        targetId: event.id,
        sendEmail: event.audience == 'followers',
      ));
    }
  }

  Future<void> updateEvent(CampusEvent event) async {
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i < 0) return;
    _events[i] = event;
    notifyListeners();
    await _writeEvent(event);
  }

  /// Son başvuru saatini uzatır / yeniden açar; topluluk adminine bildirir.
  Future<void> extendEventDeadline({
    required String eventId,
    required DateTime newDeadline,
    required String communityAdminId,
  }) async {
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) return;
    final event = _events[i];
    final updated = event.copyWith(
      applicationDeadline: newDeadline,
      applicationsOpen: true,
    );
    _events[i] = updated;
    notifyListeners();
    await _writeEvent(updated);

    final label =
        '${newDeadline.day}.${newDeadline.month}.${newDeadline.year} '
        '${newDeadline.hour.toString().padLeft(2, '0')}:'
        '${newDeadline.minute.toString().padLeft(2, '0')}';
    await _notify(
      toUserId: communityAdminId,
      copy: NotificationCopy.eventDeadlineExtended(
        eventTitle: event.title,
        untilLabel: label,
      ),
      type: 'community',
      targetId: event.id,
    );
  }

  void addAnnouncement(Announcement announcement) {
    _announcements.insert(0, announcement);
    notifyListeners();
  }

  Future<void> publishAnnouncement(Announcement announcement) async {
    addAnnouncement(announcement);
    try {
      await FirebaseFirestore.instance
          .collection('announcements')
          .doc(announcement.id)
          .set(announcement.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] writeAnnouncement: $e');
    }
    // Duyuru aynı zamanda feed postu olarak da görünsün
    final post = Post(
      id: 'ann_${announcement.id}',
      authorId: announcement.communityId ?? 'community',
      authorName: announcement.communityName ?? 'Topluluk',
      authorHandle:
          '@${(announcement.communityName ?? 'topluluk').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}',
      content:
          '📢 ${announcement.title}\n\n${announcement.body}\n\n#duyuru #mt',
      createdAt: announcement.createdAt,
      isCommunity: true,
      hashtags: const ['duyuru', 'mt'],
    );
    _posts.insert(0, post);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('posts').doc(post.id).set({
        ...post.toMap(),
        'moderatedByGuard': true,
        'guardDecision': 'allow',
        'fromAnnouncement': true,
        'announcementId': announcement.id,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[feed] writeAnnouncementPost: $e');
    }
    unawaited(_notifyAudienceBroadcast(
      kind: 'announcement',
      actorId: announcement.communityId ?? '',
      actorName: announcement.communityName ?? 'Topluluk',
      audience: announcement.audience,
      title: 'Topluluk duyurusu',
      body: announcement.title,
      emoji: '📢',
      targetId: announcement.id,
      sendEmail: true,
    ));
  }

  Future<void> _notifyAudienceBroadcast({
    required String kind,
    required String actorId,
    required String actorName,
    required String audience,
    required String title,
    required String body,
    required String emoji,
    String? targetId,
    bool sendEmail = false,
  }) async {
    if (actorId.isEmpty) return;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('notifyAudience');
      await callable.call({
        'kind': kind,
        'actorId': actorId,
        'actorName': actorName,
        'audience': audience,
        'title': title,
        'body': body,
        'emoji': emoji,
        'targetId': targetId,
        'sendEmail': sendEmail,
      });
    } catch (e) {
      debugPrint('[feed] notifyAudience: $e');
    }
  }

  Future<void> reviewEventApplication({
    required String eventId,
    required String applicationId,
    required bool approve,
  }) async {
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) return;
    final event = _events[i];
    EventApplication? target;
    final apps = event.applications.map((a) {
      if (a.id != applicationId) return a;
      target = a;
      return a.copyWith(
        status: approve
            ? EventApplicationStatus.approved
            : EventApplicationStatus.rejected,
      );
    }).toList();

    var updated = event.copyWith(
      applications: apps,
      applicantCount: apps.where((a) => a.holdsSlot).length,
    );

    // Red sonrası slot açılır; kadro doluysa ve red ise başvurular yeniden açılabilir
    if (!approve && updated.isRosterFull == false) {
      updated = updated.copyWith(
        applicationsOpen: !updated.isDeadlinePassed,
      );
    }

    _events[i] = updated;
    notifyListeners();
    await _writeEvent(updated);

    if (target != null) {
      await _notify(
        toUserId: target!.userId,
        copy: approve
            ? NotificationCopy.eventApplicationApproved(eventTitle: event.title)
            : NotificationCopy.eventApplicationRejected(eventTitle: event.title),
        type: 'community',
        targetId: event.id,
      );
    }

    if (approve && updated.isRosterFull && event.communityId != null) {
      await _notify(
        toUserId: event.communityId!,
        copy: NotificationCopy.eventRosterFull(event.title),
        type: 'community',
        targetId: event.id,
      );
    }
  }

  /// Topluluk başvuruyu siler → kontenjan açılır, admin bilgilendirilir.
  Future<void> deleteEventApplication({
    required String eventId,
    required String applicationId,
    required String communityAdminId,
  }) async {
    final i = _events.indexWhere((e) => e.id == eventId);
    if (i < 0) return;
    final event = _events[i];
    EventApplication? removed;
    final apps = <EventApplication>[];
    for (final a in event.applications) {
      if (a.id == applicationId) {
        removed = a;
        continue;
      }
      apps.add(a);
    }
    if (removed == null) return;

    final updated = event.copyWith(
      applications: apps,
      applicantCount: apps.where((a) => a.holdsSlot).length,
      applicationsOpen: !event.isDeadlinePassed,
    );
    _events[i] = updated;
    notifyListeners();
    await _writeEvent(updated);

    await _notify(
      toUserId: communityAdminId,
      copy: NotificationCopy.eventApplicationRemoved(
        who: removed.userName,
        eventTitle: event.title,
      ),
      type: 'community',
      targetId: event.id,
    );
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _commentsSub?.cancel();
    _annSub?.cancel();
    _eventsSub?.cancel();
    super.dispose();
  }
}
