import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// dart:io yalnızca native — web stub File kullanmaz; kIsWeb guard zorunlu.
import 'dart:io';

/// Hikâye / Reels medyasını diske indirir — LRU + TTL + paralel kuyruk.
/// Web’de no-op (tarayıcı CDN stream kullanır).
class MediaDiskCache {
  MediaDiskCache._();
  static final instance = MediaDiskCache._();

  static const maxEntries = 220;
  static const maxBytes = 450 * 1024 * 1024; // ~450 MB
  static const ttl = Duration(hours: 36);

  final Set<String> _inflight = {};
  final List<String> _queue = [];
  bool _drainRunning = false;
  Directory? _dir;

  Future<Directory> _base() async {
    if (kIsWeb) {
      throw UnsupportedError('MediaDiskCache is native-only');
    }
    if (_dir != null) return _dir!;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/kampus_media_cache_v2');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  String _key(String url) => 'm_${url.hashCode.abs().toRadixString(16)}';

  String _ext(String url) {
    final u = url.toLowerCase();
    if (u.contains('.mp4') || u.contains('video')) return '.mp4';
    if (u.contains('.webm')) return '.webm';
    if (u.contains('.png')) return '.png';
    if (u.contains('.webp')) return '.webp';
    if (u.contains('.gif')) return '.gif';
    return '.jpg';
  }

  Future<File?> fileFor(String url) async {
    if (kIsWeb || !url.startsWith('http')) return null;
    try {
      final dir = await _base();
      final f = File('${dir.path}/${_key(url)}${_ext(url)}');
      if (!await f.exists()) return null;
      final len = await f.length();
      if (len < 1024) {
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }
      final age = DateTime.now().difference(await f.lastModified());
      if (age > ttl) {
        try {
          await f.delete();
        } catch (_) {}
        return null;
      }
      // LRU dokunuşu
      try {
        await f.setLastModified(DateTime.now());
      } catch (_) {}
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Varsa dosya yolu; yoksa indirip döner (başarısızsa null).
  Future<File?> ensure(
    String url, {
    Duration timeout = const Duration(seconds: 45),
    bool highPriority = false,
  }) async {
    if (kIsWeb || !url.startsWith('http')) return null;
    final existing = await fileFor(url);
    if (existing != null) return existing;
    if (_inflight.contains(url)) {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final f = await fileFor(url);
        if (f != null) return f;
        if (!_inflight.contains(url)) break;
      }
      return fileFor(url);
    }
    _inflight.add(url);
    try {
      final dir = await _base();
      final f = File('${dir.path}/${_key(url)}${_ext(url)}');
      final res = await http.get(Uri.parse(url)).timeout(timeout);
      if (res.statusCode == 200 && res.bodyBytes.length > 1024) {
        await f.writeAsBytes(res.bodyBytes, flush: true);
        await _enforceBudget();
        return f;
      }
    } catch (e) {
      debugPrint('[media-cache] $e');
    } finally {
      _inflight.remove(url);
    }
    return null;
  }

  /// Arka plan kuyruğu — yakın olanlar önce, daha agresif concurrency.
  void prefetchAll(
    Iterable<String> urls, {
    int concurrency = 5,
    bool front = false,
  }) {
    if (kIsWeb) return;
    final list = urls
        .where((u) => u.startsWith('http'))
        .toSet()
        .toList(growable: false);
    if (front) {
      _queue.insertAll(0, list);
    } else {
      _queue.addAll(list);
    }
    // Tekilleştir
    final seen = <String>{};
    _queue.retainWhere((u) => seen.add(u));
    unawaitedDrain(concurrency: concurrency);
  }

  void unawaitedDrain({int concurrency = 5}) {
    if (kIsWeb) return;
    if (_drainRunning) return;
    _drainRunning = true;
    () async {
      try {
        while (_queue.isNotEmpty) {
          final batch = <String>[];
          while (batch.length < concurrency && _queue.isNotEmpty) {
            batch.add(_queue.removeAt(0));
          }
          await Future.wait(
            batch.map((u) => ensure(u)),
            eagerError: false,
          );
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
        await _enforceBudget();
      } finally {
        _drainRunning = false;
        if (_queue.isNotEmpty) unawaitedDrain(concurrency: concurrency);
      }
    }();
  }

  Future<void> _enforceBudget() async {
    if (kIsWeb) return;
    try {
      final dir = await _base();
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      final meta = <({File file, DateTime mtime, int size})>[];
      var total = 0;
      for (final f in files) {
        try {
          final s = await f.length();
          final m = await f.lastModified();
          if (DateTime.now().difference(m) > ttl) {
            await f.delete();
            continue;
          }
          total += s;
          meta.add((file: f, mtime: m, size: s));
        } catch (_) {}
      }
      meta.sort((a, b) => a.mtime.compareTo(b.mtime)); // eski önce
      while (meta.length > maxEntries || total > maxBytes) {
        if (meta.isEmpty) break;
        final victim = meta.removeAt(0);
        total -= victim.size;
        try {
          await victim.file.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[media-cache] budget: $e');
    }
  }
}
