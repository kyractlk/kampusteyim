import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Platforma özel çizilmiş SVG ikonlar (Material emoji yerine).
class MtIcons {
  MtIcons._();

  static const like = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 20.5S3.5 15.2 3.5 9.8A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 8.5 2.6c0 5.4-8.5 10.7-8.5 10.7Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <path d="M8.2 9.4c.6-1.2 1.8-1.8 3.1-1.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
</svg>''';

  static const likeFilled = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 20.5S3.5 15.2 3.5 9.8A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 8.5 2.6c0 5.4-8.5 10.7-8.5 10.7Z" fill="currentColor"/>
</svg>''';

  static const comment = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M5 6.5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H10l-4.5 3v-3H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <circle cx="9" cy="12" r="1" fill="currentColor"/>
  <circle cx="12" cy="12" r="1" fill="currentColor"/>
  <circle cx="15" cy="12" r="1" fill="currentColor"/>
</svg>''';

  static const repost = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7 7h8.5a3.5 3.5 0 0 1 0 7H11" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
  <path d="M9.5 4.5 7 7l2.5 2.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M17 17H8.5a3.5 3.5 0 0 1 0-7H13" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
  <path d="M14.5 19.5 17 17l-2.5-2.5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const follow = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="10" cy="9" r="3.2" stroke="currentColor" stroke-width="1.7"/>
  <path d="M4.5 19c.6-3 2.8-4.8 5.5-4.8s4.9 1.8 5.5 4.8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
  <path d="M17.5 8v5M15 10.5h5" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
</svg>''';

  static const bell = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M6.5 16.5h11l-.8-1.2a6.2 6.2 0 0 1-1-3.4V10a4.7 4.7 0 1 0-9.4 0v1.9c0 1.2-.3 2.4-1 3.4L6.5 16.5Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <path d="M10 18.8a2.1 2.1 0 0 0 4 0" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
</svg>''';

  static const report = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 3.5v17" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
  <path d="M6 4.5h9.5l-1.8 3.2 1.8 3.3H6" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
</svg>''';

  static const ban = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="8.2" stroke="currentColor" stroke-width="1.7"/>
  <path d="M6.4 6.4 17.6 17.6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>
</svg>''';

  static const badgeGold = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="9" fill="#D9B31E"/>
  <path d="M8.2 12.2 10.6 14.6 15.8 9.4" stroke="#0B1F3A" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</svg>''';

  static const badgeBlue = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="9" fill="#1D9BF0"/>
  <path d="M8.2 12.2 10.6 14.6 15.8 9.4" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</svg>''';

  static const admin = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M12 3.5 19 7v5.2c0 4.4-3 7.6-7 8.8-4-1.2-7-4.4-7-8.8V7l7-3.5Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <path d="M9.5 12.2 11.4 14l3.6-3.8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const community = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="8" cy="9" r="2.6" stroke="currentColor" stroke-width="1.6"/>
  <circle cx="16" cy="9" r="2.6" stroke="currentColor" stroke-width="1.6"/>
  <circle cx="12" cy="14.5" r="2.6" stroke="currentColor" stroke-width="1.6"/>
  <path d="M4.2 18.5c.5-2 2-3.2 3.8-3.2M19.8 18.5c-.5-2-2-3.2-3.8-3.2M9.2 19c.6-1.5 1.7-2.3 2.8-2.3s2.2.8 2.8 2.3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
</svg>''';

  static const job = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="3.5" y="8" width="17" height="11.5" rx="2" stroke="currentColor" stroke-width="1.7"/>
  <path d="M9 8V6.8A1.8 1.8 0 0 1 10.8 5h2.4A1.8 1.8 0 0 1 15 6.8V8" stroke="currentColor" stroke-width="1.7"/>
  <path d="M3.5 12.5h17" stroke="currentColor" stroke-width="1.7"/>
</svg>''';

  static const cv = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7 3.5h7.5L19 8v12.5H7V3.5Z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <path d="M14.5 3.5V8H19" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>
  <path d="M9.5 12h5M9.5 15h5M9.5 18h3.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
</svg>''';
}

class MtIcon extends StatelessWidget {
  const MtIcon(
    this.raw, {
    super.key,
    this.size = 20,
    this.color,
  });

  final String raw;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return SvgPicture.string(
      raw.replaceAll('currentColor', _toHex(c)),
      width: size,
      height: size,
    );
  }

  static String _toHex(Color c) {
    final v = c.toARGB32();
    return '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    required this.gold,
    this.size = 16,
  });

  final bool gold;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MtIcon(
      gold ? MtIcons.badgeGold : MtIcons.badgeBlue,
      size: size,
    );
  }
}

/// Onaylı bot hesabı rozeti.
class BotBadge extends StatelessWidget {
  const BotBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Resmi bot',
      child: Icon(
        Icons.smart_toy_rounded,
        size: size,
        color: AppColors.cyan,
      ),
    );
  }
}

/// Twitter tarzı “X ile ilişkili” satırı — minik logo + kurum adı (+ opsiyonel tick).
/// Basılınca kurum / topluluk profiline gider.
class AffiliationBadge extends StatelessWidget {
  const AffiliationBadge({
    super.key,
    required this.orgName,
    this.logoUrl,
    this.orgId,
    this.light = false,
    this.compact = false,
    this.verifiedGold = false,
    this.verifiedBlue = false,
  });

  final String orgName;
  final String? logoUrl;
  final String? orgId;
  final bool light;
  final bool compact;
  final bool verifiedGold;
  final bool verifiedBlue;

  @override
  Widget build(BuildContext context) {
    if (orgName.trim().isEmpty) return const SizedBox.shrink();
    final textColor = light
        ? Colors.white.withValues(alpha: 0.88)
        : AppColors.textSecondary;
    final size = compact ? 14.0 : 16.0;
    final tickSize = compact ? 13.0 : 15.0;

    Widget logo;
    final url = logoUrl;
    if (url != null && url.startsWith('assets/')) {
      logo = ClipOval(
        child: Image.asset(url, width: size, height: size, fit: BoxFit.cover),
      );
    } else if (url != null && url.isNotEmpty) {
      logo = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(
            Icons.apartment_rounded,
            size: size,
            color: textColor,
          ),
        ),
      );
    } else {
      logo = Icon(Icons.apartment_rounded, size: size, color: textColor);
    }

    return InkWell(
      onTap: orgId == null || orgId!.isEmpty
          ? null
          : () => context.push('/user/${Uri.encodeComponent(orgId!)}'),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                orgName,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (verifiedGold) ...[
              const SizedBox(width: 4),
              VerifiedBadge(gold: true, size: tickSize),
            ] else if (verifiedBlue) ...[
              const SizedBox(width: 4),
              VerifiedBadge(gold: false, size: tickSize),
            ],
          ],
        ),
      ),
    );
  }
}
