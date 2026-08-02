import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../storage/media_disk_cache.dart';
import 'web_safe_image.dart';

/// Ağ görseli — native: disk cache; web: HTML &lt;img&gt; (CDN stream, CORS-XHR yok).
class SafeNetworkImage extends StatefulWidget {
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.placeholder,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Bellekte küçük decode (avatar vb.) — cihaz px cinsinden.
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Widget? placeholder;

  @override
  State<SafeNetworkImage> createState() => _SafeNetworkImageState();
}

class _SafeNetworkImageState extends State<SafeNetworkImage> {
  File? _file;
  bool _ready = false;
  Object? _loadToken;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant SafeNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = null;
      _ready = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url.trim();
    final token = Object();
    _loadToken = token;
    if (url.isEmpty || !url.startsWith('http')) {
      if (mounted && identical(_loadToken, token)) {
        setState(() => _ready = true);
      }
      return;
    }

    // Web: disk yok — hemen network/HTML img.
    if (kIsWeb) {
      if (mounted && identical(_loadToken, token)) {
        setState(() => _ready = true);
      }
      return;
    }

    try {
      final existing = await MediaDiskCache.instance.fileFor(url);
      if (!mounted || !identical(_loadToken, token)) return;
      if (existing != null) {
        setState(() {
          _file = existing;
          _ready = true;
        });
        return;
      }
    } catch (_) {}

    if (mounted && identical(_loadToken, token)) {
      setState(() => _ready = true);
    }

    try {
      final f = await MediaDiskCache.instance.ensure(
        url,
        timeout: const Duration(seconds: 25),
        highPriority: true,
      );
      if (!mounted || !identical(_loadToken, token) || f == null) return;
      setState(() => _file = f);
    } catch (_) {}
  }

  Widget _placeholder() {
    return widget.placeholder ??
        ColoredBox(
          color: Colors.black12,
          child: SizedBox(width: widget.width, height: widget.height),
        );
  }

  Widget _error() {
    return (widget.errorBuilder != null)
        ? widget.errorBuilder!(context, Exception('image'), null)
        : ColoredBox(
            color: Colors.black12,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: (widget.width != null && widget.width! < 64) ? 18 : 36,
                color: Colors.black45,
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;

    if (!kIsWeb && _file != null) {
      return Image.file(
        _file!,
        fit: widget.fit,
        width: w,
        height: h,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (c, e, s) => _error(),
      );
    }

    if (!_ready) return _placeholder();

    final url = widget.url.trim();
    if (url.isEmpty || !url.startsWith('http')) return _error();

    return webSafeNetworkImage(
      url,
      fit: widget.fit,
      width: w,
      height: h,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      errorBuilder: widget.errorBuilder ?? (c, e, s) => _error(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder();
      },
    );
  }
}
