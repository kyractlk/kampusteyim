import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/media_disk_cache.dart';
import 'reel_models.dart';

/// Reels video — Instagram tarzı pencere: prev / current / next(+1) hazır.
class ReelsVideoCache {
  ReelsVideoCache._();
  static final instance = ReelsVideoCache._();

  final Map<String, VideoPlayerController> _controllers = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  final Map<String, int> _failCount = {};
  bool _bgRunning = false;
  List<CampusReel> _queue = const [];

  VideoPlayerController? peek(String reelId) => _controllers[reelId];

  bool isReady(String reelId) {
    final c = _controllers[reelId];
    return c != null && c.value.isInitialized;
  }

  /// Hazır controller döner; yoksa disk/network’ten başlatır.
  Future<VideoPlayerController?> obtain({
    required String reelId,
    required String url,
  }) async {
    if (url.isEmpty) return null;
    if (_failed.contains(reelId) && (_failCount[reelId] ?? 0) >= 3) {
      return null;
    }
    final existing = _controllers[reelId];
    if (existing != null && existing.value.isInitialized) return existing;

    if (_loading.contains(reelId)) {
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final c = _controllers[reelId];
        if (c != null && c.value.isInitialized) return c;
        if (_failed.contains(reelId) && (_failCount[reelId] ?? 0) >= 3) {
          return null;
        }
      }
      return _controllers[reelId];
    }

    _loading.add(reelId);
    try {
      File? file;
      if (!kIsWeb) {
        file = await MediaDiskCache.instance.ensure(
          url,
          highPriority: true,
          timeout: const Duration(seconds: 20),
        );
      }
      final VideoPlayerController c = (file != null)
          ? VideoPlayerController.file(file)
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: VideoPlayerOptions(
                mixWithOthers: true,
                allowBackgroundPlayback: false,
              ),
            );
      _controllers[reelId] = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      // İlk kareyi hazırla — kaydırınca anında oynasın.
      try {
        await c.seekTo(Duration.zero);
        await c.pause();
      } catch (_) {}
      _failed.remove(reelId);
      _failCount.remove(reelId);
      return c;
    } catch (e) {
      debugPrint('[reels-cache] $reelId: $e');
      final n = (_failCount[reelId] ?? 0) + 1;
      _failCount[reelId] = n;
      if (n >= 3) _failed.add(reelId);
      final dead = _controllers.remove(reelId);
      try {
        await dead?.dispose();
      } catch (_) {}
      return null;
    } finally {
      _loading.remove(reelId);
    }
  }

  /// Kaydırma penceresi — Instagram: aktif ± komşular.
  Future<void> warmWindow(
    List<CampusReel> feed,
    int index, {
    int behind = 1,
    int ahead = 2,
  }) async {
    if (feed.isEmpty) return;
    final videos = <CampusReel>[];
    final start = (index - behind).clamp(0, feed.length - 1);
    final end = (index + ahead).clamp(0, feed.length - 1);
    for (var i = start; i <= end; i++) {
      final r = feed[i];
      if (r.mediaType == ReelMediaType.video && r.mediaUrl.isNotEmpty) {
        videos.add(r);
      }
    }
    // Aktif önce, sonra sonraki, sonra önceki.
    videos.sort((a, b) {
      final ai = feed.indexWhere((e) => e.id == a.id);
      final bi = feed.indexWhere((e) => e.id == b.id);
      final ad = (ai - index).abs();
      final bd = (bi - index).abs();
      if (ad != bd) return ad.compareTo(bd);
      return ai.compareTo(bi);
    });

    if (!kIsWeb) {
      MediaDiskCache.instance.prefetchAll(
        videos.map((r) => r.mediaUrl),
        concurrency: 4,
        front: true,
      );
    }

    // Paralel ama web’de 2’şer.
    final chunk = kIsWeb ? 2 : 3;
    for (var i = 0; i < videos.length; i += chunk) {
      final batch = videos.skip(i).take(chunk);
      await Future.wait(
        batch.map((r) => obtain(reelId: r.id, url: r.mediaUrl)),
      );
    }

    final keep = videos.map((r) => r.id).toSet();
    // Biraz daha geniş tut (kaydırma hissi).
    for (var i = (index - 2).clamp(0, feed.length); i <= (index + 3).clamp(0, feed.length - 1); i++) {
      keep.add(feed[i].id);
    }
    await trim(keep);
  }

  /// Öncelikli dilim + arka plan kuyruğu.
  Future<void> prefetch(
    List<CampusReel> feed, {
    int count = 14,
    bool keepWarm = true,
  }) async {
    final videos = feed
        .where(
          (r) => r.mediaType == ReelMediaType.video && r.mediaUrl.isNotEmpty,
        )
        .toList();
    _queue = videos;

    if (!kIsWeb) {
      MediaDiskCache.instance.prefetchAll(
        videos.take(40).map((r) => r.mediaUrl),
        concurrency: 5,
        front: true,
      );
      MediaDiskCache.instance.prefetchAll(
        videos.skip(40).map((r) => r.mediaUrl),
        concurrency: 3,
      );
    }

    final take = kIsWeb ? count.clamp(3, 8) : count.clamp(8, 28);
    await warmWindow(videos, 0, behind: 0, ahead: take - 1);

    if (keepWarm) {
      unawaited(kIsWeb ? _runBackgroundWarmWeb() : _runBackgroundWarm());
    }
  }

  Future<void> _runBackgroundWarmWeb() async {
    if (_bgRunning) return;
    _bgRunning = true;
    try {
      for (final r in List<CampusReel>.from(_queue.take(12))) {
        if (_controllers.containsKey(r.id) || _loading.contains(r.id)) continue;
        if (_controllers.length >= 8) break;
        await obtain(reelId: r.id, url: r.mediaUrl);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    } finally {
      _bgRunning = false;
    }
  }

  Future<void> _runBackgroundWarm() async {
    if (_bgRunning) return;
    _bgRunning = true;
    try {
      for (final r in List<CampusReel>.from(_queue)) {
        if (_controllers.containsKey(r.id) ||
            _loading.contains(r.id) ||
            _failed.contains(r.id)) {
          continue;
        }
        await MediaDiskCache.instance.ensure(r.mediaUrl, highPriority: false);
        if (_controllers.length < 42) {
          await obtain(reelId: r.id, url: r.mediaUrl);
        }
        await Future<void>.delayed(const Duration(milliseconds: 18));
        if (_controllers.length > 48) {
          final keep = _queue.take(36).map((e) => e.id).toSet();
          await trim(keep);
        }
      }
    } finally {
      _bgRunning = false;
    }
  }

  Future<void> trim(Set<String> keepIds) async {
    final drop =
        _controllers.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in drop) {
      final c = _controllers.remove(id);
      try {
        await c?.pause();
        await c?.dispose();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final all = Map<String, VideoPlayerController>.from(_controllers);
    _controllers.clear();
    _loading.clear();
    _failed.clear();
    _failCount.clear();
    _queue = const [];
    for (final c in all.values) {
      try {
        await c.pause();
        await c.dispose();
      } catch (_) {}
    }
  }
}
