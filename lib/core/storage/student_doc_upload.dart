import 'package:file_selector/file_selector.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/auth/registration_security_config.dart';
import '../permissions/app_permissions.dart';
import 'media_upload.dart';
import 'web_file_pick.dart';

/// Öğrenci kartı / belge — hızlı putData + magic-byte güvenlik.
class StudentDocUpload {
  StudentDocUpload._();

  static final _picker = ImagePicker();

  static Future<XFile?> pickCardImage() async {
    if (kIsWeb) {
      return pickWebFile(
        accept: 'image/jpeg,image/png,image/*',
        fallbackName: 'card.jpg',
      );
    }
    final ok = await AppPermissions.ensureMediaAccess();
    if (!ok) throw StateError('Medya izni gerekli');
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 68,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
  }

  static Future<XFile?> captureCardImage() async {
    if (kIsWeb) {
      return pickWebFile(accept: 'image/*', fallbackName: 'card.jpg');
    }
    final ok = await AppPermissions.ensureCameraAccess();
    if (!ok) throw StateError('Kamera izni gerekli');
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 68,
      maxWidth: 1600,
      maxHeight: 1600,
      requestFullMetadata: false,
    );
  }

  static Future<XFile?> pickPdf() async {
    if (kIsWeb) {
      return pickWebFile(
        accept: 'application/pdf,.pdf',
        fallbackName: 'ogrenci_belgesi.pdf',
      );
    }
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: <String>['pdf'],
      mimeTypes: <String>['application/pdf'],
      uniformTypeIdentifiers: <String>['com.adobe.pdf'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return XFile.fromData(
      bytes,
      name: file.name,
      mimeType: 'application/pdf',
    );
  }

  static Future<String> uploadSecure({
    required XFile file,
    required String side,
    required String firstName,
    required String lastName,
    required String studentNo,
    required RegistrationSecurityConfig security,
    required bool expectPdf,
  }) async {
    final bytes = await file.readAsBytes();
    StudentDocGuard.assertSafe(
      bytes: bytes,
      allowPdf: expectPdf && security.allowStudentDocumentPdf,
      allowImage: !expectPdf && security.allowStudentCard,
      maxBytes: expectPdf ? security.maxPdfBytes : security.maxImageBytes,
      malwareScan: security.malwareScanEnabled,
    );
    final kind = StudentDocGuard.detectKind(bytes)!;
    if (expectPdf && kind != StudentDocKind.pdf) {
      throw StateError('PDF seçmelisin.');
    }
    if (!expectPdf && kind == StudentDocKind.pdf) {
      throw StateError('Kart için fotoğraf seçmelisin.');
    }

    final fileName = MediaUpload.buildFileName(
      firstName: firstName.isEmpty ? 'aday' : firstName,
      lastName: lastName.isEmpty ? 'ogrenci' : lastName,
      studentNo: studentNo.isEmpty ? 'pending' : studentNo,
      extension: '${side}_${StudentDocGuard.extension(kind)}',
    );
    final path = 'student_ids/$fileName';
    final ref = FirebaseStorage.instance.ref().child(path);
    final meta = SettableMetadata(
      contentType: StudentDocGuard.contentType(kind),
      customMetadata: {
        'side': side,
        'kind': kind.name,
        'scanned': security.malwareScanEnabled ? 'client_magic' : 'off',
      },
      cacheControl: 'private, max-age=0',
    );
    debugPrint('[student-doc] putData $path (${bytes.length}b)');
    await ref.putData(bytes, meta);
    return ref.getDownloadURL();
  }
}
