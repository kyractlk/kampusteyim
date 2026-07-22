import '../../models/models.dart';

/// @mention yardımcıları (Instagram / X tarzı).
class MentionUtils {
  MentionUtils._();

  static final pattern = RegExp(r'@([\wğüşıöçĞÜŞİÖÇ0-9_]+)');

  /// Metindeki benzersiz handle’lar (@ olmadan, küçük harf).
  static List<String> extractHandles(String text) {
    final out = <String>{};
    for (final m in pattern.allMatches(text)) {
      final h = (m.group(1) ?? '').trim().toLowerCase();
      if (h.isNotEmpty) out.add(h);
    }
    return out.toList();
  }

  /// Guard taraması öncesi @mention’ları çıkar (muhendislik → sik false positive).
  static String stripForModeration(String text) {
    return text.replaceAll(pattern, ' ');
  }

  /// İmleçten geriye doğru aktif @ sorgusu. Yoksa null.
  static String? activeQuery(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    final m = RegExp(r'@([\wğüşıöçĞÜŞİÖÇ0-9_]*)$').firstMatch(before);
    if (m == null) return null;
    return (m.group(1) ?? '').toLowerCase();
  }

  /// Öneri listesi: allowMentions != false olanlar.
  static List<AppUser> suggestions({
    required List<AppUser> directory,
    required String query,
    String? excludeUserId,
    int limit = 8,
  }) {
    final q = query.toLowerCase();
    final list = directory.where((u) {
      if (excludeUserId != null && u.id == excludeUserId) return false;
      if (!u.allowMentions) return false;
      final handle = u.handle.replaceFirst('@', '').toLowerCase();
      final name = u.fullName.toLowerCase();
      if (q.isEmpty) return true;
      return handle.startsWith(q) ||
          handle.contains(q) ||
          name.contains(q);
    }).toList();
    list.sort((a, b) {
      final ah = a.handle.replaceFirst('@', '').toLowerCase();
      final bh = b.handle.replaceFirst('@', '').toLowerCase();
      final aExact = ah == q ? 0 : (ah.startsWith(q) ? 1 : 2);
      final bExact = bh == q ? 0 : (bh.startsWith(q) ? 1 : 2);
      if (aExact != bExact) return aExact.compareTo(bExact);
      return ah.compareTo(bh);
    });
    return list.take(limit).toList();
  }

  /// Aktif @ sorgusunu seçilen kullanıcıyla değiştir.
  static ({String text, int cursor}) applyMention({
    required String text,
    required int cursor,
    required AppUser user,
  }) {
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);
    final m = RegExp(r'@([\wğüşıöçĞÜŞİÖÇ0-9_]*)$').firstMatch(before);
    if (m == null) {
      final insert = '${user.handle} ';
      return (text: '$before$insert$after', cursor: before.length + insert.length);
    }
    final start = m.start;
    final handle = user.handle.startsWith('@') ? user.handle : '@${user.handle}';
    final next = '${before.substring(0, start)}$handle $after';
    final newCursor = start + handle.length + 1;
    return (text: next, cursor: newCursor);
  }
}
