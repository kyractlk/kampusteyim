import 'dart:typed_data';

import 'promo_card_download_stub.dart'
    if (dart.library.html) 'promo_card_download_web.dart' as impl;

Future<void> savePngBytes(Uint8List bytes, String filename) {
  return impl.savePngBytes(bytes, filename);
}
