/// Düz metin sanitizasyonu — XSS / enjeksiyon için (Flutter Text güvenli ama
/// e-posta / paylaşım / Firestore alanları için yine de temizleriz).
class SafeText {
  SafeText._();

  static final _tagRe = RegExp(r'<[^>]*>');
  static final _ctrlRe = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

  /// HTML etiketleri ve kontrol karakterlerini temizler.
  static String plain(String? raw, {int maxLen = 800}) {
    var s = (raw ?? '').trim();
    s = s.replaceAll(_tagRe, '');
    s = s.replaceAll(_ctrlRe, '');
    s = s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    // Tekrar strip (decode sonrası kalan etiket)
    s = s.replaceAll(_tagRe, '');
    if (s.length > maxLen) s = s.substring(0, maxLen);
    return s.trim();
  }

  static bool isValidEmail(String email) {
    final e = email.trim().toLowerCase();
    if (e.length < 5 || e.length > 120) return false;
    if (e.contains('<') || e.contains('>') || e.contains('"')) return false;
    return RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$').hasMatch(e);
  }
}
