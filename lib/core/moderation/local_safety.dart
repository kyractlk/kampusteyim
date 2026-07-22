/// Yerel Guard — gömülü küfür/nefret (harf kombinasyonu + obfuscation).
class LocalSafety {
  LocalSafety._();

  static String _norm(String raw) {
    var t = raw.toLowerCase();
    t = t
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('@', 'a')
        .replaceAll(r'$', 's');
    return t;
  }

  static String _compact(String text) {
    final only = text.replaceAll(RegExp(r'[^a-z]'), '');
    return only.replaceAllMapped(
      RegExp(r'(.)\1{2,}'),
      (m) => '${m[1]}${m[1]}',
    );
  }

  static String _maskInnocent(String compact) {
    const safe = [
      'psikolojik',
      'psikoloji',
      'psikolog',
      'sikayetci',
      'sikayetler',
      'sikayet',
      'klasikler',
      'klasik',
      'bisiklet',
      'muzisyen',
      'muzik',
      'fiziksel',
      'fiziki',
      'fizik',
      'muhendislik',
      'muhendis',
      'universite',
      'asik',
    ];
    var t = compact;
    for (final s in safe) {
      t = t.replaceAll(s, 'x' * s.length);
    }
    return t;
  }

  static bool _obfuscationCarrier(String raw, String compact) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || compact.length < 6) return false;
    final tokens =
        trimmed.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    return tokens.length == 1 && compact.length >= 8;
  }

  static const _always = <String>[
    'zenci',
    'nigger',
    'nigga',
    'heilhitler',
    'siktir',
    'sikerim',
    'sikeyim',
    'sikis',
    'amcik',
    'amina',
    'orospu',
    'yarrak',
    'yarrag',
    'gotunu',
    'porno',
    'onlyfans',
    'fuckyou',
    'motherfucker',
  ];

  static const _short = <String>['sik', 'amk', 'pic'];

  static String? blockReason(String content) {
    // @mention'ları tarama dışı bırak (örn. muhendislik → sik false positive)
    final withoutMentions = content.replaceAll(
      RegExp(r'@[\wğüşıöçĞÜŞİÖÇ0-9_]+'),
      ' ',
    );
    final t = _norm(withoutMentions);
    final c = _compact(t);
    final masked = _maskInnocent(c);
    final obfuscated = _obfuscationCarrier(withoutMentions, c);

    for (final stem in _always) {
      if (masked.contains(stem) || c.contains(stem) || t.contains(stem)) {
        return 'Uygunsuz / nefret içeriği engellendi (AYS Tech Guard).';
      }
    }

    for (final stem in _short) {
      final asWord = RegExp('(?:^|[^a-z])$stem(?:[^a-z]|\$)');
      if (asWord.hasMatch(t)) {
        return 'Küfür engellendi (AYS Tech Guard).';
      }
      if (masked.contains(stem) &&
          (obfuscated ||
              (c.length >= 8 &&
                  !withoutMentions.trim().contains(RegExp(r'\s'))))) {
        return 'Küfür engellendi (gömülü harf — AYS Tech Guard).';
      }
      if (RegExp(stem.split('').join(r'[\W_]+'), caseSensitive: false)
          .hasMatch(withoutMentions)) {
        return 'Küfür engellendi (ayrık harf — AYS Tech Guard).';
      }
    }

    if (RegExp(r'(olum|oldurun|katledin).{0,40}(zenci|yahudi|ermeni)').hasMatch(t) ||
        RegExp(r'(zenci|yahudi|ermeni).{0,40}(olum|oldurun|katledin)').hasMatch(t)) {
      return 'Nefret / şiddet engellendi (AYS Tech Guard).';
    }
    return null;
  }
}
