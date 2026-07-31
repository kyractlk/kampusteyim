import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../features/reels/reels_provider.dart';
import '../../features/stories/stories_provider.dart';
import 'media_disk_cache.dart';

/// Hikâye + Reels medya ısıtıcısı — hayat kurtarıcı arka plan helper'ı.
///
/// Uygulama açıkken ve arka planda (process canlıyken) sürekli tarar:
/// var olan medyayı indirir, yeni yüklemeleri anında kuyruğa alır,
/// resume'da tam tarama yapar, pause'da disk kuyruğunu boşaltmaya devam eder.
class MediaWarmHelper with WidgetsBindingObserver {
  MediaWarmHelper._();
  static final instance = MediaWarmHelper._();

  StoriesProvider? _stories;
  ReelsProvider? _reels;
  Timer? _scanTimer;
  bool _started = false;
  bool _scanning = false;
  String _lastFingerprint = '';
  DateTime _lastFullScan = DateTime.fromMillisecondsSinceEpoch(0);

  static const _scanInterval = Duration(seconds: 8);
  static const _fullScanMinGap = Duration(seconds: 3);

  void start({
    required StoriesProvider stories,
    required ReelsProvider reels,
  }) {
    if (kIsWeb) return;
    _stories = stories;
    _reels = reels;
    if (_started) {
      unawaited(scan(force: true, reason: 'rebind'));
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    stories.addListener(_onProvidersChanged);
    reels.addListener(_onProvidersChanged);
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(_scanInterval, (_) {
      unawaited(scan(reason: 'periodic'));
    });
    unawaited(scan(force: true, reason: 'boot'));
    debugPrint('[media-warm] started');
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _stories?.removeListener(_onProvidersChanged);
    _reels?.removeListener(_onProvidersChanged);
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(scan(force: true, reason: 'resumed'));
        unawaited(_reels?.warmAllMedia(forceControllers: true));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(scan(reason: 'background'));
        MediaDiskCache.instance.unawaitedDrain(concurrency: 3);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onProvidersChanged() {
    unawaited(scan(reason: 'provider'));
  }

  Future<void> kick({String reason = 'kick'}) =>
      scan(force: true, reason: reason);

  Future<void> scan({bool force = false, String reason = ''}) async {
    if (kIsWeb || !_started) return;
    if (_scanning) return;
    final stories = _stories;
    final reels = _reels;
    if (stories == null || reels == null) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastFullScan) < _fullScanMinGap) {
      return;
    }

    _scanning = true;
    try {
      final storyUrls = stories.warmMediaUrls();
      final reelUrls = reels.warmMediaUrls();
      final fingerprint =
          '${storyUrls.length}:${reelUrls.length}:'
          '${storyUrls.isEmpty ? 0 : storyUrls.first.hashCode}:'
          '${reelUrls.isEmpty ? 0 : reelUrls.first.hashCode}:'
          '${storyUrls.isEmpty ? 0 : storyUrls.last.hashCode}:'
          '${reelUrls.isEmpty ? 0 : reelUrls.last.hashCode}';

      final changed = fingerprint != _lastFingerprint;
      if (!force && !changed) {
        MediaDiskCache.instance.prefetchAll(
          [...storyUrls.take(16), ...reelUrls.take(16)],
          concurrency: 2,
        );
        return;
      }

      _lastFingerprint = fingerprint;
      _lastFullScan = now;

      MediaDiskCache.instance.prefetchAll(
        storyUrls,
        concurrency: 5,
        front: true,
      );
      MediaDiskCache.instance.prefetchAll(
        reelUrls.take(60),
        concurrency: 4,
        front: true,
      );
      if (reelUrls.length > 60) {
        MediaDiskCache.instance.prefetchAll(
          reelUrls.skip(60),
          concurrency: 2,
        );
      }

      unawaited(reels.warmAllMedia(forceControllers: force || changed));

      debugPrint(
        '[media-warm] scan($reason) stories=${storyUrls.length} '
        'reels=${reelUrls.length} changed=$changed',
      );
    } catch (e) {
      debugPrint('[media-warm] scan: $e');
    } finally {
      _scanning = false;
    }
  }
}
