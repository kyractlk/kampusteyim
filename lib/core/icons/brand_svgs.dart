import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Marka SVG ikonları — UI (flutter_svg) + PDF (pw.SvgImage) ortak kaynak.
class BrandSvgs {
  BrandSvgs._();

  static const linkedin = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect width="24" height="24" rx="4" fill="#0A66C2"/>
  <path fill="#FFFFFF" d="M7.1 9.2H4.7v9.1h2.4V9.2zm-.1-2.7a1.4 1.4 0 1 1 0-2.8 1.4 1.4 0 0 1 0 2.8zM19.3 13.6c0-2.7-1.4-4-3.4-4-1.6 0-2.3.9-2.7 1.5V9.2h-2.4c0 .8 0 9.1 0 9.1h2.4v-5.1c0-.3 0-.5.1-.7.2-.5.7-1.1 1.5-1.1 1.1 0 1.5.8 1.5 2v4.9h2.4v-5.6z"/>
</svg>''';

  static const github = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="12" fill="#181717"/>
  <path fill="#FFFFFF" d="M12 4.2c-4.3 0-7.8 3.5-7.8 7.8 0 3.4 2.2 6.4 5.3 7.4.4.1.5-.2.5-.4v-1.4c-2.2.5-2.6-1-2.6-1-.4-.9-.9-1.1-.9-1.1-.7-.5.1-.5.1-.5.8.1 1.2.8 1.2.8.7 1.2 1.9.9 2.3.7.1-.5.3-.9.5-1.1-1.7-.2-3.5-.9-3.5-3.9 0-.9.3-1.6.8-2.1-.1-.2-.4-1 .1-2.1 0 0 .7-.2 2.2.8.6-.2 1.3-.3 2-.3s1.4.1 2 .3c1.5-1 2.2-.8 2.2-.8.5 1.1.2 1.9.1 2.1.5.6.8 1.3.8 2.1 0 3-1.8 3.7-3.5 3.9.3.2.5.7.5 1.4v2.1c0 .2.2.5.5.4 3.1-1 5.3-4 5.3-7.4 0-4.3-3.5-7.8-7.8-7.8z"/>
</svg>''';

  static const website = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="12" fill="#1FA8A0"/>
  <path fill="none" stroke="#FFFFFF" stroke-width="1.6" d="M12 4.5a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15z"/>
  <path fill="none" stroke="#FFFFFF" stroke-width="1.5" d="M4.8 12h14.4M12 4.5c2 2.4 3 4.8 3 7.5s-1 5.1-3 7.5c-2-2.4-3-4.8-3-7.5s1-5.1 3-7.5z"/>
</svg>''';

  static const email = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect width="24" height="24" rx="4" fill="#C8102E"/>
  <path fill="none" stroke="#FFFFFF" stroke-width="1.7" d="M5 8.2h14v8.2H5z"/>
  <path fill="none" stroke="#FFFFFF" stroke-width="1.7" d="M5.4 8.5 12 13.2l6.6-4.7"/>
</svg>''';

  static const phone = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect width="24" height="24" rx="4" fill="#0B1F3A"/>
  <path fill="#FFFFFF" d="M8.2 5.8c.3-.6.9-.9 1.5-.8l1.5.3c.6.1 1 .6 1.1 1.2l.3 1.6c.1.5-.1 1-.5 1.3l-.9.7c.8 1.5 2 2.7 3.5 3.5l.7-.9c.3-.4.8-.6 1.3-.5l1.6.3c.6.1 1 .5 1.2 1.1l.3 1.5c.1.6-.2 1.2-.8 1.5-.9.5-2.1.7-3.5.2-2.6-.9-4.9-3.1-5.9-5.8-.6-1.4-.4-2.6.1-3.5z"/>
</svg>''';

  static const location = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <rect width="24" height="24" rx="4" fill="#5A6A7A"/>
  <path fill="#FFFFFF" d="M12 5.2c-2.5 0-4.5 2-4.5 4.5 0 3.1 4.5 8.1 4.5 8.1s4.5-5 4.5-8.1c0-2.5-2-4.5-4.5-4.5zm0 6.1a1.6 1.6 0 1 1 0-3.2 1.6 1.6 0 0 1 0 3.2z"/>
</svg>''';

  static String forLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('linkedin')) return linkedin;
    if (l.contains('github') || l.contains('git')) return github;
    if (l.contains('mail') || l.contains('e-posta') || l.contains('email')) {
      return email;
    }
    if (l.contains('tel') || l.contains('phone') || l.contains('gsm')) {
      return phone;
    }
    if (l.contains('web') || l.contains('site') || l.contains('http')) {
      return website;
    }
    if (l.contains('adres') || l.contains('location') || l.contains('map')) {
      return location;
    }
    return website;
  }
}

class BrandSvgIcon extends StatelessWidget {
  const BrandSvgIcon(
    this.raw, {
    super.key,
    this.size = 20,
  });

  final String raw;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(raw, width: size, height: size);
  }
}

/// Ham metinden tıklanabilir URL üretir.
class BrandLinkUtils {
  BrandLinkUtils._();

  static String display(String raw) {
    var t = raw.trim();
    t = t.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
    if (t.length > 36) return '${t.substring(0, 34)}…';
    return t;
  }

  static String? href({
    required String kind,
    required String raw,
  }) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    switch (kind) {
      case 'email':
        return t.startsWith('mailto:') ? t : 'mailto:$t';
      case 'phone':
        final digits = t.replaceAll(RegExp(r'[^\d+]'), '');
        return digits.isEmpty ? null : 'tel:$digits';
      case 'linkedin':
        if (t.startsWith('http')) return t;
        if (t.contains('linkedin.com')) {
          return 'https://${t.replaceFirst(RegExp(r'^/+'), '')}';
        }
        return 'https://www.linkedin.com/in/${t.replaceAll(RegExp(r'^@'), '')}';
      case 'github':
        if (t.startsWith('http')) return t;
        if (t.contains('github.com')) {
          return 'https://${t.replaceFirst(RegExp(r'^/+'), '')}';
        }
        return 'https://github.com/${t.replaceAll(RegExp(r'^@'), '')}';
      case 'website':
        if (t.startsWith('http')) return t;
        return 'https://$t';
      default:
        if (t.startsWith('http')) return t;
        return null;
    }
  }
}
