import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Ön kamera önizlemesi genelde aynalıdır; kayıt ham sensör yönündedir.
/// Kaydı yatay çevirerek “ekranda gördüğün = çekilen” yapar.
Future<XFile> mirrorImageFileHorizontal(XFile input) async {
  if (kIsWeb) return input;
  try {
    final bytes = await input.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width;
    final h = src.height;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(w.toDouble(), 0);
    canvas.scale(-1.0, 1.0);
    canvas.drawImage(src, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    if (png == null) return input;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/cam_mirror_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    return XFile(path, mimeType: 'image/png', name: 'mirrored.png');
  } catch (e) {
    debugPrint('[camera] mirror: $e');
    return input;
  }
}
