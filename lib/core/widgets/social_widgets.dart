import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import 'media_viewer.dart';
import 'safe_network_image.dart';

final _urlPattern = RegExp(
  r'(https?:\/\/[^\s<>\]]+|www\.[^\s<>\]]+)',
  caseSensitive: false,
);
final _hashtagPattern = RegExp(r'(#[\wğüşıöçĞÜŞİÖÇ]+)');
final _mentionPattern = RegExp(r'(@[\wğüşıöçĞÜŞİÖÇ0-9_]+)');

/// Hashtag + @mention + URL (tıklanabilir).
class HashtagText extends StatelessWidget {
  const HashtagText({
    super.key,
    required this.text,
    this.style,
  });

  final String text;
  final TextStyle? style;

  static bool _isAppHost(String host) {
    return host.contains('gaunengineering.com.tr') ||
        host.contains('ayskampuss.web.app') ||
        host.contains('ayskampuss.firebaseapp.com');
  }

  static String linkLabel(String raw) {
    var u = raw.trim();
    if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
    try {
      final uri = Uri.parse(u);
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      if (_isAppHost(host)) {
        final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isEmpty) return 'KampüsteyimAPP';
        switch (segs.first) {
          case 'post':
            // Gönderi linki metinde gösterilmez — karta basılır (Twitter mantığı).
            return '';
          case 'user':
            return segs.length > 1 ? '@${segs[1]}' : 'Profil';
          case 'event':
            return 'Etkinlik';
          case 'announcement':
            return 'Duyuru';
          case 'r':
            return 'Şifre sıfırlama';
          default:
            return 'KampüsteyimAPP';
        }
      }
      if (host.isEmpty) return 'Bağlantı';
      return host;
    } catch (_) {
      return 'Bağlantı';
    }
  }

  /// Feed kartına basınca açılır; gövdede /post/ URL’si yazılmaz.
  static bool isInternalPostUrl(String raw) {
    var u = raw.trim();
    if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
    try {
      final uri = Uri.parse(u);
      final host = uri.host;
      if (!_isAppHost(host)) {
        return false;
      }
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return segs.isNotEmpty && segs.first == 'post';
    } catch (_) {
      return false;
    }
  }

  static Future<void> openUrl(BuildContext context, String raw) async {
    var u = raw.trim();
    if (u.toLowerCase().startsWith('www.')) u = 'https://$u';
    Uri? uri;
    try {
      uri = Uri.parse(u);
    } catch (_) {
      return;
    }
    final host = uri.host;
    if (_isAppHost(host)) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length >= 2) {
        final path = '/${segs[0]}/${Uri.encodeComponent(segs[1])}';
        if (context.mounted) context.push(path);
        return;
      }
      if (context.mounted) context.go('/home');
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    final accent = base?.copyWith(
      color: AppColors.cyan,
      fontWeight: FontWeight.w700,
    );
    final linkStyle = base?.copyWith(
      color: AppColors.cyan,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.cyan.withValues(alpha: 0.5),
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    final urlMatches = _urlPattern.allMatches(text).toList();

    void addPlainWithTags(String chunk) {
      if (chunk.isEmpty) return;
      // Mentions + hashtags birlikte
      final tokens = <({int start, int end, String kind, String value})>[];
      for (final m in _mentionPattern.allMatches(chunk)) {
        tokens.add((start: m.start, end: m.end, kind: 'mention', value: m.group(0)!));
      }
      for (final m in _hashtagPattern.allMatches(chunk)) {
        tokens.add((start: m.start, end: m.end, kind: 'tag', value: m.group(0)!));
      }
      tokens.sort((a, b) => a.start.compareTo(b.start));

      var start = 0;
      for (final t in tokens) {
        if (t.start < start) continue; // overlap
        if (t.start > start) {
          spans.add(TextSpan(text: chunk.substring(start, t.start), style: base));
        }
        if (t.kind == 'mention') {
          final handle = t.value.substring(1);
          spans.add(
            TextSpan(
              text: t.value,
              style: accent,
              recognizer: TapGestureRecognizer()
                ..onTap = () => context.push('/user/${Uri.encodeComponent(handle)}'),
            ),
          );
        } else {
          spans.add(
            TextSpan(
              text: t.value,
              style: accent,
              recognizer: TapGestureRecognizer()
                ..onTap = () =>
                    context.push('/search?q=${Uri.encodeComponent(t.value)}'),
            ),
          );
        }
        start = t.end;
      }
      if (start < chunk.length) {
        spans.add(TextSpan(text: chunk.substring(start), style: base));
      }
    }

    for (final m in urlMatches) {
      if (m.start > cursor) {
        addPlainWithTags(text.substring(cursor, m.start));
      }
      final raw = m.group(0)!;
      // /post/... linklerini metinden çıkar — detaya kart tıklanınca gidilir.
      if (isInternalPostUrl(raw)) {
        cursor = m.end;
        continue;
      }
      final label = linkLabel(raw);
      if (label.isEmpty) {
        cursor = m.end;
        continue;
      }
      spans.add(
        TextSpan(
          text: label,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => openUrl(context, raw),
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      addPlainWithTags(text.substring(cursor));
    }
    if (spans.isEmpty) {
      return Text(text, style: base);
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 22,
    this.isCommunity = false,
    this.onTap,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final bool isCommunity;
  final VoidCallback? onTap;

  bool get _isBrokenCdn {
    final u = photoUrl ?? '';
    return u.contains('pravatar.cc');
  }

  Widget _initials() {
    return Text(
      isCommunity
          ? (name.isNotEmpty ? name[0].toUpperCase() : 'K')
          : (name.isNotEmpty ? name[0].toUpperCase() : '?'),
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: radius * 0.7,
        color: isCommunity ? Colors.white : AppColors.navy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = photoUrl;
    final useNetwork = url != null &&
        url.isNotEmpty &&
        !url.startsWith('assets/') &&
        !_isBrokenCdn;
    final useAsset = url != null && url.startsWith('assets/');

    Widget avatar;
    if (useAsset) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor:
            isCommunity ? AppColors.navy : AppColors.cyan.withValues(alpha: 0.22),
        backgroundImage: AssetImage(url),
      );
    } else if (useNetwork) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor:
            isCommunity ? AppColors.navy : AppColors.cyan.withValues(alpha: 0.22),
        child: ClipOval(
          child: SafeNetworkImage(
            url: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => SizedBox(
              width: size,
              height: size,
              child: ColoredBox(
                color: isCommunity
                    ? AppColors.navy
                    : AppColors.cyan.withValues(alpha: 0.22),
                child: Center(child: _initials()),
              ),
            ),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor:
            isCommunity ? AppColors.navy : AppColors.cyan.withValues(alpha: 0.22),
        child: _initials(),
      );
    }

    if (onTap == null) return avatar;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }
}

class MediaCarousel extends StatelessWidget {
  const MediaCarousel({super.key, required this.urls, required this.types});

  final List<String> urls;
  final List<bool> types; // true = video

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 220,
      child: PageView.builder(
        itemCount: urls.length,
        controller:
            PageController(viewportFraction: urls.length == 1 ? 1 : 0.92),
        itemBuilder: (context, i) {
          return Padding(
            padding: EdgeInsets.only(right: urls.length == 1 ? 0 : 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: AppColors.surfaceMuted,
                child: InkWell(
                  onTap: () => openMediaViewer(
                    context,
                    urls: urls,
                    isVideo: types,
                    initialIndex: i,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SafeNetworkImage(
                        url: urls[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 36),
                            SizedBox(height: 6),
                            Text(
                              'Medyayı açmak için dokun',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (types[i])
                        Container(
                          color: Colors.black38,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Tam ekran',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
