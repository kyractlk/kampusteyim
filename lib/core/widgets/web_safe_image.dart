import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Web’de Storage görselleri için HTML &lt;img&gt; tercih et (CORS/XHR/304 sorununu aşar).
/// Native’de varsayılan Image.network davranışı.
Image webSafeNetworkImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  int? cacheWidth,
  int? cacheHeight,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  FilterQuality filterQuality = FilterQuality.low,
}) {
  return Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    gaplessPlayback: true,
    filterQuality: filterQuality,
    // Header YOK — header XHR tetikler ve CORS ister.
    webHtmlElementStrategy:
        kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never,
    errorBuilder: errorBuilder,
    loadingBuilder: loadingBuilder,
  );
}

/// Precache: web’de HTML img ile uyumlu provider.
ImageProvider webSafeImageProvider(String url) {
  // NetworkImage web’de XHR kullanır → CORS gerekir (bucket CORS sonrası OK).
  // Yine de cache busting ile bozuk 304’leri azalt.
  if (kIsWeb) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.contains('firebasestorage')) {
      final q = Map<String, String>.from(uri.queryParameters);
      // Tarayıcıdaki CORS’suz 304 cache’ini kır (bir kez).
      q.putIfAbsent('v', () => '2');
      return NetworkImage(uri.replace(queryParameters: q).toString());
    }
  }
  return NetworkImage(url);
}
