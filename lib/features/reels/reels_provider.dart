import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/media_upload.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'reel_models.dart';

/// Kampüs Reels — izlenenler sona, yeniler üste.
class ReelsProvider extends ChangeNotifier {
  ReelsProvider();

  final List<CampusReel> _items = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  AuthProvider? _auth;
  bool _loading = false;
  String? _error;

  bool get isLoading => _loading;
  String? get error => _error;

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
      },
      onError: (e) {
        debugPrint('[reels] bind: $e');
        _loading = false;
        _error = 'Reels yüklenemedi';
        notifyListeners();
      },
    );
  }

  /// İzlenmemişler önce (yeni → eski), izlenenler sonda.
  List<CampusReel> feedFor(String? viewerId) {
    final list = List<CampusReel>.from(_items);
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
      );
      final doc = FirebaseFirestore.instance.collection('reels').doc();
      final reel = CampusReel.fromAuthor(
        id: doc.id,
        author: author,
        mediaUrl: url,
        isVideo: isVideo,
        caption: caption.trim(),
      );
      await doc.set(reel.toFirestore());
      return null;
    } catch (e) {
      debugPrint('[reels] create: $e');
      return 'Reels paylaşılamadı: $e';
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

  @override
  void dispose() {
    _sub?.cancel();
    _auth?.removeListener(_onAuth);
    super.dispose();
  }
}
