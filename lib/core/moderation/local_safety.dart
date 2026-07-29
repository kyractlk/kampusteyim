/// Yerel Guard — yalnızca bariz küfür / nefret / cinsiyetçilik.
/// Cümle içine gömülü harf kombinasyonları engellenmez (yönetim FP şikayeti).
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

  /// Masum kelimeleri boşlukla ayır ki kısa kök yanlış pozitif üretmesin.
  static String _maskInnocentWords(String text) {
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
    var t = text;
    for (final s in safe) {
      t = t.replaceAll(s, ' ');
    }
    return t;
  }

  /// Net / uzun kökler — yanlış pozitif riski düşük.
  static const _clear = <String>[
    // nefret / ırkçılık
    'zenci',
    'nigger',
    'nigga',
    'heilhitler',
    'faggot',
    // küfür / cinsiyetçilik (bariz)
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
    'kahpe',
    'porno',
    'onlyfans',
    'fuckyou',
    'motherfucker',
  ];

  /// Kısa kökler — yalnızca kelime sınırı (cümle içi / gömülü YOK).
  static const _shortWords = <String>['sik', 'amk', 'pic'];

  static bool _asWholeWord(String text, String stem) {
    return RegExp('(?:^|[^a-z])${RegExp.escape(stem)}(?:[^a-z]|\$)')
        .hasMatch(text);
  }

  static String? blockReason(String content) {
    final withoutMentions = content.replaceAll(
      RegExp(r'@[\wğüşıöçĞÜŞİÖÇ0-9_]+'),
      ' ',
    );
    final t = _maskInnocentWords(_norm(withoutMentions));

    for (final stem in _clear) {
      if (_asWholeWord(t, stem) || t.contains(stem)) {
        final hate = RegExp(r'zenci|nigger|nigga|heil|faggot').hasMatch(stem);
        return hate
            ? 'Nefret / ayrımcı içerik engellendi (AYS Tech Guard).'
            : 'Küfür / uygunsuz içerik engellendi (AYS Tech Guard).';
      }
    }

    for (final stem in _shortWords) {
      if (_asWholeWord(t, stem)) {
        return 'Küfür engellendi (AYS Tech Guard).';
      }
    }

    // Bariz nefret + şiddet (ırk hedefi)
    if (RegExp(r'(olum|oldurun|katledin).{0,40}(zenci|yahudi|ermeni)')
            .hasMatch(t) ||
        RegExp(r'(zenci|yahudi|ermeni).{0,40}(olum|oldurun|katledin)')
            .hasMatch(t)) {
      return 'Nefret / şiddet engellendi (AYS Tech Guard).';
    }
    return null;
  }
}
