import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Ders notu / PDF vb. (Plus). Document picker foto izni istemez (SAF / UIDocumentPicker).
  static Future<XFile?> pickDocument() async {
    const accept =
        '.pdf,.doc,.docx,.ppt,.pptx,.txt,.xls,.xlsx,application/pdf';
    if (kIsWeb) {
      return pickWebFile(accept: accept, fallbackName: 'not.pdf');
    }
    try {
      const group = XTypeGroup(
        label: 'documents',
        extensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt', 'xls', 'xlsx'],
      );
      // Tip kısıtı bazen cihazda picker’ı boş açıyor — önce kısıtlı, olmazsa açık dene.
      var f = await openFile(acceptedTypeGroups: [group]);
      f ??= await openFile();
      if (f == null) return null;
      return XFile(f.path, name: f.name, mimeType: f.mimeType);
    } catch (e) {
      debugPrint('[media] pickDocument: $e');
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
    bool isFile = false,
    void Function(double progress)? onProgress,
  }) async {
    final name = file.name;
    final ext = name.contains('.')
        ? name.split('.').last
        : (isVideo ? 'mp4' : (isFile ? 'pdf' : 'jpg'));
    final fileName = buildFileName(
      firstName: firstName,
      lastName: lastName,
      studentNo: studentNo,
      extension: ext,
    );
    final lower = ext.toLowerCase();
    final contentType = isVideo
        ? (lower == 'mov' ? 'video/quicktime' : 'video/mp4')
        : isFile
            ? _docMime(lower)
            : (lower == 'png' ? 'image/png' : 'image/jpeg');
    final path = '$folder/$fileName';
    final meta = SettableMetadata(contentType: contentType);
    final ref = FirebaseStorage.instance.ref().child(path);

    UploadTask task;
    if (!kIsWeb && file.path.isNotEmpty) {
      final f = File(file.path);
      final len = await f.length();
      if (len > maxPhotoBytes) {
        throw StateError(
          'Dosya 75 MB’dan büyük olamaz '
          '(${(len / (1024 * 1024)).toStringAsFixed(1)} MB).',
        );
      }
      debugPrint('[media] putFile $path ($len bytes)');
      task = ref.putFile(f, meta);
    } else {
      final bytes = await file.readAsBytes();
      if (bytes.length > maxPhotoBytes) {
        throw StateError(
          'Dosya 75 MB’dan büyük olamaz '
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

  static String _docMime(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// Paylaşılan dosyayı indir / paylaş (foto-video değil).
  static Future<void> downloadOrShareFile({
    required String url,
    String? fileName,
  }) async {
    final name = (fileName == null || fileName.trim().isEmpty)
        ? 'kampusteyim_dosya'
        : fileName.trim();
    if (kIsWeb) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('İndirme başarısız (${res.statusCode})');
    }
    final ext = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : 'bin';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            res.bodyBytes,
            mimeType: _docMime(ext),
            name: name.contains('.') ? name : '$name.$ext',
          ),
        ],
        text: 'KampüsteyimAPP dosya',
      ),
    );
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
