import 'package:flutter_test/flutter_test.dart';

import 'package:mt_mobil/core/utils/hashtag_utils.dart';
import 'package:mt_mobil/main.dart';

void main() {
  test('hashtag aynı etiket bir kez sayılır', () {
    const text = '#kampus #etkinlik #kampus #duyuru';
    expect(HashtagUtils.extractUnique(text), ['kampus', 'etkinlik', 'duyuru']);
    expect(HashtagUtils.uniqueCount(text), 3);
  });

  testWidgets('Misafir doğrudan akışa düşer', (tester) async {
    await tester.pumpWidget(const MtMobilApp());
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('KampüsteyimAPP'), findsWidgets);
    expect(find.text('Giriş'), findsWidgets);
  });
}
