import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'media_upload.dart';

/// Reklam kreatifleri: tek yükleme → mecralara göre otomatik resize.
class AdImageUpload {
  AdImageUpload._();

  /// Feed / e-posta — yatay 16:9
  static const feedSize = (1200, 675);

  /// Reels — dikey 4:5
  static const reelsSize = (1080, 1350);

  /// Hikâye — dikey 9:16
  static const storiesSize = (1080, 1920);

  /// Kaynak üst sınırı (uzun kenar)
  static const masterMaxEdge = 1600;

  static Future<AdCreativeUrls> pickAndUpload({
    void Function(String stage, double progress)? onProgress,
  }) async {
    final picked = await MediaUpload.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      throw StateError('Görsel seçilmedi');
    }
    onProgress?.call('okuma', 0.05);
    final raw = await picked.readAsBytes();
    if (raw.isEmpty) throw StateError('Görsel okunamadı');
    if (raw.length > MediaUpload.maxPhotoBytes) {
      throw StateError('Dosya 75 MB’dan büyük olamaz');
    }

    onProgress?.call('ölçekleme', 0.12);
    final master = await _fitMaxEdge(raw, masterMaxEdge);
    final feed = await _coverExact(raw, feedSize.$1, feedSize.$2);
    final reels = await _coverExact(raw, reelsSize.$1, reelsSize.$2);
    final stories = await _coverExact(raw, storiesSize.$1, storiesSize.$2);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final stamp = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
    final base = 'ads/$uid/$stamp';

    Future<String> put(String name, Uint8List bytes, double from, double span) {
      return MediaUpload.uploadBytes(
        bytes: bytes,
        storagePath: '$base/$name.png',
        contentType: 'image/png',
        onProgress: (p) => onProgress?.call('yükleme', from + p * span),
      );
    }

    onProgress?.call('yükleme', 0.35);
    final masterUrl = await put('master', master, 0.35, 0.12);
    final feedUrl = await put('feed_16x9', feed, 0.48, 0.14);
    final reelsUrl = await put('reels_4x5', reels, 0.63, 0.14);
    final storiesUrl = await put('stories_9x16', stories, 0.78, 0.18);
    onProgress?.call('tamam', 1);
    debugPrint(
      '[ad-image] uploaded feed=${feed.length}B reels=${reels.length}B '
      'stories=${stories.length}B',
    );

    return AdCreativeUrls(
      imageUrl: feedUrl,
      masterUrl: masterUrl,
      variants: {
        'feed': feedUrl,
        'reels': reelsUrl,
        'stories': storiesUrl,
        'email': feedUrl,
        'push': feedUrl,
        'master': masterUrl,
      },
    );
  }

  static Future<Uint8List> _coverExact(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final dst = ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final srcRect = _coverSrc(
        src.width.toDouble(),
        src.height.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );
      canvas.drawImageRect(
        src,
        srcRect,
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(width, height);
      try {
        final data = await out.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Görsel işlenemedi');
        return data.buffer.asUint8List();
      } finally {
        out.dispose();
      }
    } finally {
      src.dispose();
    }
  }

  static Future<Uint8List> _fitMaxEdge(Uint8List bytes, int maxEdge) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    try {
      final sw = src.width;
      final sh = src.height;
      final long = sw > sh ? sw : sh;
      if (long <= maxEdge) {
        final data = await src.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Görsel işlenemedi');
        return data.buffer.asUint8List();
      }
      final scale = maxEdge / long;
      final tw = (sw * scale).round().clamp(1, maxEdge);
      final th = (sh * scale).round().clamp(1, maxEdge);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        src,
        ui.Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
        ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(tw, th);
      try {
        final data = await out.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Görsel işlenemedi');
        return data.buffer.asUint8List();
      } finally {
        out.dispose();
      }
    } finally {
      src.dispose();
    }
  }

  static ui.Rect _coverSrc(double sw, double sh, double dw, double dh) {
    final srcAspect = sw / sh;
    final dstAspect = dw / dh;
    if (srcAspect > dstAspect) {
      final w = sh * dstAspect;
      final left = (sw - w) / 2;
      return ui.Rect.fromLTWH(left, 0, w, sh);
    }
    final h = sw / dstAspect;
    final top = (sh - h) / 2;
    return ui.Rect.fromLTWH(0, top, sw, h);
  }
}

class AdCreativeUrls {
  const AdCreativeUrls({
    required this.imageUrl,
    required this.masterUrl,
    required this.variants,
  });

  final String imageUrl;
  final String masterUrl;
  final Map<String, String> variants;
}
