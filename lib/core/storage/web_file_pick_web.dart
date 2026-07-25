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

  final completer = Completer<html.File?>();
  StreamSubscription<html.Event>? changeSub;
  StreamSubscription<html.Event>? focusSub;

  void finish(html.File? file) {
    if (completer.isCompleted) return;
    completer.complete(file);
  }

  changeSub = input.onChange.listen((_) {
    final files = input.files;
    finish(files != null && files.isNotEmpty ? files.first : null);
  });

  // Diyalog kapanınca (iptal veya seçim) pencere focus alır.
  // Seçimde onChange genelde önce gelir; iptalde dosya boş kalır.
  Timer? focusTimer;
  focusSub = html.window.onFocus.listen((_) {
    focusTimer?.cancel();
    focusTimer = Timer(const Duration(milliseconds: 400), () {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        finish(files.first);
      } else {
        finish(null);
      }
    });
  });

  input.click();

  html.File? file;
  try {
    file = await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => null,
    );
  } finally {
    focusTimer?.cancel();
    await changeSub.cancel();
    await focusSub.cancel();
    input.remove();
  }

  if (file == null) return null;

  final reader = html.FileReader();
  final bytesCompleter = Completer<Uint8List>();
  late StreamSubscription<html.ProgressEvent> loadSub;
  late StreamSubscription<html.ProgressEvent> errSub;

  loadSub = reader.onLoad.listen((_) {
    if (bytesCompleter.isCompleted) return;
    final result = reader.result;
    if (result is ByteBuffer) {
      bytesCompleter.complete(Uint8List.view(result));
    } else if (result is Uint8List) {
      bytesCompleter.complete(result);
    } else {
      bytesCompleter.completeError(StateError('Dosya okunamadı'));
    }
  });
  errSub = reader.onError.listen((_) {
    if (!bytesCompleter.isCompleted) {
      bytesCompleter.completeError(StateError('Dosya okunamadı'));
    }
  });

  reader.readAsArrayBuffer(file);
  try {
    final bytes = await bytesCompleter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw StateError('Dosya okuma zaman aşımı'),
    );
    final name = file.name.isNotEmpty ? file.name : fallbackName;
    final mime = file.type.isNotEmpty ? file.type : null;
    return XFile.fromData(bytes, name: name, mimeType: mime);
  } finally {
    await loadSub.cancel();
    await errSub.cancel();
  }
}
