import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/storage/media_disk_cache.dart';
import 'reel_models.dart';

/// Reels video motoru — uluslararası kısa-video protokolü:
///
/// 1. **Poster / anında UI** (ekran katmanı) — siyah bekleme yok.
/// 2. **Stream-first**: aktif reel ağdan progressive oynar; tam dosya indirmeyi
///    beklemez (TikTok / IG / YouTube Shorts).
/// 3. **Pencere**: yalnızca N−1 / N / N+1(+1) decoder açık.
/// 4. **Disk ısıtma ayrı**: native’de sonraki URL’ler arka planda cache’lenir;
///    aktif oynatmayı bloklamaz.
/// 5. **Ref-count**: ekranda kullanılan controller trim ile dispose edilmez.
class ReelsVideoCache {
  ReelsVideoCache._();
  static final instance = ReelsVideoCache._();

  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, Completer<VideoPlayerController?>> _inflight = {};
  final Map<String, int> _refs = {};
  final Set<String> _failed = {};
  final Map<String, int> _failCount = {};
  bool _bgRunning = false;
  List<CampusReel> _queue = const [];

  /// Web’de decoder kotası düşük (MediaSource / MSE sınırı).
  int get maxControllers => kIsWeb ? 4 : 6;

  VideoPlayerController? peek(String reelId) => _controllers[reelId];

  bool isReady(String reelId) {
    final c = _controllers[reelId];
    return c != null && c.value.isInitialized;
  }

  void retain(String reelId) {
    _refs[reelId] = (_refs[reelId] ?? 0) + 1;
  }

  void release(String reelId) {
    final n = (_refs[reelId] ?? 0) - 1;
    if (n <= 0) {
      _refs.remove(reelId);
    } else {
      _refs[reelId] = n;
    }
  }

  /// Hazır controller; yoksa stream ile başlatır (tam indirme beklemez).
  Future<VideoPlayerController?> obtain({
    required String reelId,
    required String url,
    bool preferCachedFile = true,
  }) async {
    if (url.isEmpty) return null;
    if (_failed.contains(reelId) && (_failCount[reelId] ?? 0) >= 3) {
      return null;
    }

    final existing = _controllers[reelId];
    if (existing != null && existing.value.isInitialized) return existing;

    final pending = _inflight[reelId];
    if (pending != null) return pending.future;

    final completer = Completer<VideoPlayerController?>();
    _inflight[reelId] = completer;

    try {
      // 1) Diskte hazırsa file — anında. Yoksa ASLA ensure ile bekleme.
      File? file;
      if (!kIsWeb && preferCachedFile) {
        file = await MediaDiskCache.instance.fileFor(url);
      }

      final VideoPlayerController c = (file != null)
          ? VideoPlayerController.file(file)
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: VideoPlayerOptions(
                mixWithOthers: true,
                allowBackgroundPlayback: false,
              ),
              httpHeaders: const {
                // Progressive range — CDN’ler için ipucu.
                'Accept': '*/*',
              },
            );

      _controllers[reelId] = c;
      await c.initialize().timeout(
        kIsWeb ? const Duration(seconds: 25) : const Duration(seconds: 18),
      );
      await c.setLooping(true);
      await c.setVolume(0);
      try {
        await c.seekTo(Duration.zero);
        await c.pause();
      } catch (_) {}

      _failed.remove(reelId);
      _failCount.remove(reelId);
      completer.complete(c);

      // Native: arka planda dosyayı ısıt (sonraki açılış için), oynatmayı bloklama.
      if (!kIsWeb && file == null) {
        unawaited(
          MediaDiskCache.instance.ensure(
            url,
            highPriority: false,
            timeout: const Duration(seconds: 90),
          ),
        );
      }
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
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      _inflight.remove(reelId);
    }
  }

  /// Başarısız işaretini temizle — kullanıcı “Tekrar dene” için.
  void clearFailure(String reelId) {
    _failed.remove(reelId);
    _failCount.remove(reelId);
  }

  /// Kaydırma penceresi — IG/TikTok: aktif ± komşular (decoder).
  Future<void> warmWindow(
    List<CampusReel> feed,
    int index, {
    int behind = 1,
    int ahead = 1,
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

    // Disk prefetch ayrı — yalnızca URL bytes, decoder değil.
    if (!kIsWeb) {
      final diskStart = (index - 1).clamp(0, feed.length);
      final diskEnd = (index + 6).clamp(0, feed.length);
      MediaDiskCache.instance.prefetchAll(
        feed.sublist(diskStart, diskEnd).map((r) => r.mediaUrl),
        concurrency: 2,
        front: true,
      );
    }

    // Aktifi önce serileştir, komşuları düşük paralellikte.
    if (videos.isNotEmpty) {
      await obtain(reelId: videos.first.id, url: videos.first.mediaUrl);
    }
    final rest = videos.skip(1).toList();
    final chunk = kIsWeb ? 1 : 2;
    for (var i = 0; i < rest.length; i += chunk) {
      final batch = rest.skip(i).take(chunk);
      await Future.wait(
        batch.map((r) => obtain(reelId: r.id, url: r.mediaUrl)),
      );
    }

    final keep = <String>{
      for (var i = start; i <= end; i++) feed[i].id,
    };
    // Ref’li olanlar her zaman korunur.
    keep.addAll(_refs.keys);
    await trim(keep);
  }

  /// Arka plan: disk ısıtma + çok sınırlı decoder (feed’in başı).
  Future<void> prefetch(
    List<CampusReel> feed, {
    int count = 6,
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
        videos.take(12).map((r) => r.mediaUrl),
        concurrency: 2,
        front: true,
      );
    }

    // Decoder: yalnızca ilk birkaç — kotayı doldurma.
    final take = kIsWeb ? count.clamp(2, 4) : count.clamp(3, 6);
    if (videos.isNotEmpty) {
      await warmWindow(videos, 0, behind: 0, ahead: take - 1);
    }

    if (keepWarm) {
      unawaited(_runBackgroundWarm());
    }
  }

  Future<void> _runBackgroundWarm() async {
    if (_bgRunning) return;
    _bgRunning = true;
    try {
      for (final r in List<CampusReel>.from(_queue.take(kIsWeb ? 8 : 20))) {
        if (_controllers.containsKey(r.id) || _inflight.containsKey(r.id)) {
          continue;
        }
        if (!kIsWeb) {
          // Önce bytes — decoder açma.
          await MediaDiskCache.instance.ensure(
            r.mediaUrl,
            highPriority: false,
            timeout: const Duration(seconds: 60),
          );
        }
        // Decoder kotası doluysa sadece disk ısıt.
        if (_controllers.length >= maxControllers) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          continue;
        }
        await obtain(reelId: r.id, url: r.mediaUrl);
        await Future<void>.delayed(
          Duration(milliseconds: kIsWeb ? 120 : 40),
        );
      }
    } finally {
      _bgRunning = false;
    }
  }

  Future<void> trim(Set<String> keepIds) async {
    final drop = _controllers.keys.where((id) {
      if (keepIds.contains(id)) return false;
      if ((_refs[id] ?? 0) > 0) return false;
      return true;
    }).toList();
    for (final id in drop) {
      final c = _controllers.remove(id);
      try {
        await c?.pause();
        await c?.dispose();
      } catch (_) {}
    }
    // Kotayı aştıysa en eski ref’sizleri düş.
    while (_controllers.length > maxControllers) {
      final victim = _controllers.keys.firstWhere(
        (id) => (_refs[id] ?? 0) == 0 && !keepIds.contains(id),
        orElse: () => '',
      );
      if (victim.isEmpty) break;
      final c = _controllers.remove(victim);
      try {
        await c?.pause();
        await c?.dispose();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final all = Map<String, VideoPlayerController>.from(_controllers);
    _controllers.clear();
    _inflight.clear();
    _refs.clear();
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
