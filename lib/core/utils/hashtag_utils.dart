/// Aynı hashtag metinde 50 kez yazılsa bile 1 sayılır.
class HashtagUtils {
  HashtagUtils._();

  static final _pattern = RegExp(r'#([\wğüşıöçĞÜŞİÖÇ]+)');

  static List<String> extractUnique(String text) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final match in _pattern.allMatches(text)) {
      final tag = match.group(1)!.toLowerCase();
      if (seen.add(tag)) ordered.add(tag);
    }
    return ordered;
  }

  static int uniqueCount(String text) => extractUnique(text).length;
}
