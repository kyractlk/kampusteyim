import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Hikâye / Reels medyasını diske indirir — tıklanınca anlık açılır.
class MediaDiskCache {
  MediaDiskCache._();
  static final instance = MediaDiskCache._();

  final Set<String> _inflight = {};
  Directory? _dir;

  Future<Directory> _base() async {
    if (_dir != null) return _dir!;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/kampus_media_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  String _key(String url) =>
      'm_${url.hashCode.abs().toRadixString(16)}';

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
      if (await f.exists() && await f.length() > 1024) return f;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Varsa dosya yolu; yoksa indirip döner (başarısızsa null).
  Future<File?> ensure(String url, {Duration timeout = const Duration(seconds: 60)}) async {
    if (kIsWeb || !url.startsWith('http')) return null;
    final existing = await fileFor(url);
    if (existing != null) return existing;
    if (_inflight.contains(url)) {
      for (var i = 0; i < 80; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
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
        return f;
      }
    } catch (e) {
      debugPrint('[media-cache] $e');
    } finally {
      _inflight.remove(url);
    }
    return null;
  }

  /// Arka plan kuyruğu — UI’yi bloklamaz.
  void prefetchAll(Iterable<String> urls, {int concurrency = 3}) {
    if (kIsWeb) return;
    final list = urls.where((u) => u.startsWith('http')).toList();
    Future<void>(() async {
      for (var i = 0; i < list.length; i += concurrency) {
        final chunk = list.skip(i).take(concurrency);
        await Future.wait(chunk.map((u) => ensure(u)));
      }
    });
  }
}
