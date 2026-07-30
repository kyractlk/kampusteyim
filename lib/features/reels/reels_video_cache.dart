import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/media_disk_cache.dart';
import 'reel_models.dart';

/// Reels video önbelleği — önce diske indir, sonra controller ısıt (takılmasız).
class ReelsVideoCache {
  ReelsVideoCache._();
  static final instance = ReelsVideoCache._();

  final Map<String, VideoPlayerController> _controllers = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
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
    if (url.isEmpty || _failed.contains(reelId)) return null;
    final existing = _controllers[reelId];
    if (existing != null && existing.value.isInitialized) return existing;

    if (_loading.contains(reelId)) {
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final c = _controllers[reelId];
        if (c != null && c.value.isInitialized) return c;
        if (_failed.contains(reelId)) return null;
      }
      return _controllers[reelId];
    }

    _loading.add(reelId);
    try {
      // Önce diske indir — streaming jank’ini azaltır.
      File? file;
      if (!kIsWeb) {
        file = await MediaDiskCache.instance.ensure(url);
      }
      final VideoPlayerController c = (file != null)
          ? VideoPlayerController.file(file)
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
      _controllers[reelId] = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      return c;
    } catch (e) {
      debugPrint('[reels-cache] $reelId: $e');
      _failed.add(reelId);
      final dead = _controllers.remove(reelId);
      try {
        await dead?.dispose();
      } catch (_) {}
      return null;
    } finally {
      _loading.remove(reelId);
    }
  }

  /// Öncelikli dilim + arka plan kuyruğu (sekme kapalıyken de sürer).
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

    // Disk’e agresif kuyruk — yakınlar önde.
    MediaDiskCache.instance.prefetchAll(
      videos.take(40).map((r) => r.mediaUrl),
      concurrency: 5,
      front: true,
    );
    MediaDiskCache.instance.prefetchAll(
      videos.skip(40).map((r) => r.mediaUrl),
      concurrency: 3,
    );

    final priority = videos.take(count.clamp(8, 36)).toList();
    for (var i = 0; i < priority.length; i += 3) {
      final chunk = priority.skip(i).take(3);
      await Future.wait(
        chunk.map((r) => obtain(reelId: r.id, url: r.mediaUrl)),
      );
    }

    if (keepWarm) {
      final keep = {
        ...priority.map((r) => r.id),
        ...videos.take(36).map((r) => r.id),
      };
      await trim(keep);
      unawaited(_runBackgroundWarm());
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
    _queue = const [];
    for (final c in all.values) {
      try {
        await c.pause();
        await c.dispose();
      } catch (_) {}
    }
  }
}
