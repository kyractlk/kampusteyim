import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'reel_models.dart';

/// Reels video önbelleği — uygulama açılınca / sekme açılınca anlık oynatma.
class ReelsVideoCache {
  ReelsVideoCache._();
  static final instance = ReelsVideoCache._();

  final Map<String, VideoPlayerController> _controllers = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  VideoPlayerController? peek(String reelId) => _controllers[reelId];

  bool isReady(String reelId) {
    final c = _controllers[reelId];
    return c != null && c.value.isInitialized;
  }

  /// Hazır controller döner; yoksa başlatır (paylaşımlı).
  Future<VideoPlayerController?> obtain({
    required String reelId,
    required String url,
  }) async {
    if (url.isEmpty || _failed.contains(reelId)) return null;
    final existing = _controllers[reelId];
    if (existing != null) {
      if (existing.value.isInitialized) return existing;
      // Hâlâ init bekleniyor olabilir.
    }
    if (_loading.contains(reelId)) {
      // Kısa poll — aynı anda birden fazla sayfa aynı id isterse.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final c = _controllers[reelId];
        if (c != null && c.value.isInitialized) return c;
        if (_failed.contains(reelId)) return null;
      }
      return _controllers[reelId];
    }
    _loading.add(reelId);
    try {
      final c = VideoPlayerController.networkUrl(
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

  /// Feed’deki ilk N videoyu arka planda ısıt.
  Future<void> prefetch(List<CampusReel> feed, {int count = 5}) async {
    final videos = feed
        .where((r) => r.mediaType == ReelMediaType.video && r.mediaUrl.isNotEmpty)
        .take(count)
        .toList();
    // Sırayla: ilk reel en öncelikli.
    for (final r in videos) {
      if (_controllers.containsKey(r.id) || _loading.contains(r.id)) continue;
      await obtain(reelId: r.id, url: r.mediaUrl);
    }
    // Eski / kaymış controller’ları budar (bellek).
    final keep = feed.take(12).map((r) => r.id).toSet();
    await trim(keep);
  }

  Future<void> trim(Set<String> keepIds) async {
    final drop = _controllers.keys.where((id) => !keepIds.contains(id)).toList();
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
    for (final c in all.values) {
      try {
        await c.pause();
        await c.dispose();
      } catch (_) {}
    }
  }
}
