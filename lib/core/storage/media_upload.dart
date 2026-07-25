import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../permissions/app_permissions.dart';
import 'web_file_pick.dart';

/// Ortak medya yükleme: hızlı putFile + progress.
class MediaUpload {
  MediaUpload._();

  static const maxPhotoBytes = 75 * 1024 * 1024; // 75 MB
  static const maxVideoSeconds = 45;

  static final _picker = ImagePicker();

  static String buildFileName({
    required String firstName,
    required String lastName,
    required String studentNo,
    required String extension,
  }) {
    final stamp = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
    final parts = [
      _slug(firstName),
      _slug(lastName),
      _slug(studentNo.isEmpty ? 'user' : studentNo),
      stamp,
    ].where((e) => e.isNotEmpty).join('_');
    final ext = extension.replaceAll('.', '').toLowerCase();
    return '$parts.$ext';
  }

  static String _slug(String v) {
    var s = v.trim().toLowerCase();
    const map = {
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };
    map.forEach((k, rep) => s = s.replaceAll(k, rep));
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  /// Web’de image_picker plugin yoksa HTML file input kullanır.
  static Future<XFile?> pickImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    if (kIsWeb) {
      return pickWebFile(accept: 'image/*', fallbackName: 'photo.jpg');
    }
    if (source == ImageSource.camera) {
      final ok = await AppPermissions.ensureCameraAccess();
      if (!ok) throw StateError('Kamera izni gerekli');
    } else {
      final ok = await AppPermissions.ensureMediaAccess();
      if (!ok) throw StateError('Galeri / dosya izni gerekli');
    }
    try {
      return await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
    } catch (e) {
      debugPrint('[media] pickImage: $e');
      rethrow;
    }
  }

  static Future<XFile?> pickVideo({
    ImageSource source = ImageSource.gallery,
  }) async {
    if (kIsWeb) {
      return pickWebFile(
        accept: 'video/mp4,video/webm,video/quicktime,.mp4,.mov,.webm',
        fallbackName: 'video.mp4',
      );
    }
    if (source == ImageSource.camera) {
      final ok = await AppPermissions.ensureCameraAccess();
      if (!ok) throw StateError('Kamera izni gerekli');
    } else {
      final ok = await AppPermissions.ensureMediaAccess();
      if (!ok) throw StateError('Galeri / dosya izni gerekli');
    }
    try {
      return await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: maxVideoSeconds),
      );
    } catch (e) {
      debugPrint('[media] pickVideo: $e');
      rethrow;
    }
  }

  /// Hızlı yükleme: native putFile + yüzde progress.
  static Future<String> uploadXFile({
    required XFile file,
    required String folder,
    required String firstName,
    required String lastName,
    required String studentNo,
    required bool isVideo,
    void Function(double progress)? onProgress,
  }) async {
    final name = file.name;
    final ext = name.contains('.')
        ? name.split('.').last
        : (isVideo ? 'mp4' : 'jpg');
    final fileName = buildFileName(
      firstName: firstName,
      lastName: lastName,
      studentNo: studentNo,
      extension: ext,
    );
    final contentType = isVideo
        ? (ext.toLowerCase() == 'mov' ? 'video/quicktime' : 'video/mp4')
        : (ext.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg');
    final path = '$folder/$fileName';
    final meta = SettableMetadata(contentType: contentType);
    final ref = FirebaseStorage.instance.ref().child(path);

    UploadTask task;
    if (!kIsWeb && file.path.isNotEmpty) {
      final f = File(file.path);
      final len = await f.length();
      if (len > maxPhotoBytes) {
        throw StateError(
          '${isVideo ? 'Video' : 'Fotoğraf'} 75 MB’dan büyük olamaz '
          '(${(len / (1024 * 1024)).toStringAsFixed(1)} MB).',
        );
      }
      debugPrint('[media] putFile $path ($len bytes)');
      task = ref.putFile(f, meta);
    } else {
      final bytes = await file.readAsBytes();
      if (bytes.length > maxPhotoBytes) {
        throw StateError(
          '${isVideo ? 'Video' : 'Fotoğraf'} 75 MB’dan büyük olamaz '
          '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB).',
        );
      }
      debugPrint('[media] putData $path (${bytes.length} bytes)');
      task = ref.putData(bytes, meta);
    }

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total <= 0) return;
        onProgress((snap.bytesTransferred / total).clamp(0.0, 1.0));
      });
    }
    await task;
    onProgress?.call(1);
    return ref.getDownloadURL();
  }

  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.length > maxPhotoBytes) {
      throw StateError('Dosya 75 MB’dan büyük olamaz.');
    }
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        if (total <= 0) return;
        onProgress((snap.bytesTransferred / total).clamp(0.0, 1.0));
      });
    }
    await task;
    onProgress?.call(1);
    return ref.getDownloadURL();
  }
}
