// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

Future<XFile?> pickWebFile({
  required String accept,
  required String fallbackName,
}) async {
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = false;
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final file = files.first;
  final reader = html.FileReader();
  final completer = Completer<Uint8List>();
  reader.onLoad.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is Uint8List) {
      completer.complete(result);
    } else {
      completer.completeError(StateError('Dosya okunamadı'));
    }
  });
  reader.onError.listen((_) => completer.completeError(StateError('Dosya okunamadı')));
  reader.readAsArrayBuffer(file);
  final bytes = await completer.future;
  final name = file.name.isNotEmpty ? file.name : fallbackName;
  final mime = file.type.isNotEmpty ? file.type : null;
  return XFile.fromData(bytes, name: name, mimeType: mime);
}
