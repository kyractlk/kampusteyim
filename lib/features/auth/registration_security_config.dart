import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Kayıt doğrulama güvenlik ayarları — admin anlık aç/kapa.
class RegistrationSecurityConfig {
  const RegistrationSecurityConfig({
    this.requireStudentVerification = true,
    this.allowStudentCard = true,
    this.allowStudentDocumentPdf = true,
    this.requireCardBothSides = true,
    this.malwareScanEnabled = true,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.maxPdfBytes = 12 * 1024 * 1024,
  });

  final bool requireStudentVerification;
  final bool allowStudentCard;
  final bool allowStudentDocumentPdf;
  final bool requireCardBothSides;
  final bool malwareScanEnabled;
  final int maxImageBytes;
  final int maxPdfBytes;

  static const defaults = RegistrationSecurityConfig();

  static const docPath = 'app_config/registration_security';

  factory RegistrationSecurityConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;
    return RegistrationSecurityConfig(
      requireStudentVerification: m['requireStudentVerification'] != false,
      allowStudentCard: m['allowStudentCard'] != false,
      allowStudentDocumentPdf: m['allowStudentDocumentPdf'] != false,
      requireCardBothSides: m['requireCardBothSides'] != false,
      malwareScanEnabled: m['malwareScanEnabled'] != false,
      maxImageBytes: (m['maxImageBytes'] as num?)?.toInt() ?? defaults.maxImageBytes,
      maxPdfBytes: (m['maxPdfBytes'] as num?)?.toInt() ?? defaults.maxPdfBytes,
    );
  }

  Map<String, dynamic> toMap() => {
        'requireStudentVerification': requireStudentVerification,
        'allowStudentCard': allowStudentCard,
        'allowStudentDocumentPdf': allowStudentDocumentPdf,
        'requireCardBothSides': requireCardBothSides,
        'malwareScanEnabled': malwareScanEnabled,
        'maxImageBytes': maxImageBytes,
        'maxPdfBytes': maxPdfBytes,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  static Future<RegistrationSecurityConfig> load() async {
    try {
      final doc = await FirebaseFirestore.instance.doc(docPath).get();
      if (!doc.exists) return defaults;
      return RegistrationSecurityConfig.fromMap(doc.data());
    } catch (e) {
      debugPrint('[reg-security] load: $e');
      return defaults;
    }
  }

  Future<void> save() async {
    await FirebaseFirestore.instance.doc(docPath).set(toMap(), SetOptions(merge: true));
  }

  RegistrationSecurityConfig copyWith({
    bool? requireStudentVerification,
    bool? allowStudentCard,
    bool? allowStudentDocumentPdf,
    bool? requireCardBothSides,
    bool? malwareScanEnabled,
  }) {
    return RegistrationSecurityConfig(
      requireStudentVerification:
          requireStudentVerification ?? this.requireStudentVerification,
      allowStudentCard: allowStudentCard ?? this.allowStudentCard,
      allowStudentDocumentPdf:
          allowStudentDocumentPdf ?? this.allowStudentDocumentPdf,
      requireCardBothSides: requireCardBothSides ?? this.requireCardBothSides,
      malwareScanEnabled: malwareScanEnabled ?? this.malwareScanEnabled,
      maxImageBytes: maxImageBytes,
      maxPdfBytes: maxPdfBytes,
    );
  }
}

enum StudentDocKind { jpeg, png, pdf }

/// Magic-byte + zararlı imza taraması (istemci koruması).
class StudentDocGuard {
  StudentDocGuard._();

  static StudentDocKind? detectKind(Uint8List bytes) {
    if (bytes.length < 8) return null;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return StudentDocKind.jpeg;
    }
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return StudentDocKind.png;
    }
    // PDF
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return StudentDocKind.pdf;
    }
    return null;
  }

  static String? malwareHint(Uint8List bytes) {
    if (bytes.length < 4) return 'Dosya çok küçük veya bozuk.';
    // PE / EXE
    if (bytes[0] == 0x4D && bytes[1] == 0x5A) {
      return 'Çalıştırılabilir dosya engellendi.';
    }
    // ELF
    if (bytes[0] == 0x7F &&
        bytes[1] == 0x45 &&
        bytes[2] == 0x4C &&
        bytes[3] == 0x46) {
      return 'Çalıştırılabilir dosya engellendi.';
    }
    // ZIP (apk/jar/docx disguised) — PDF dışı arşiv
    if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) {
      return 'Arşiv / sıkıştırılmış zararlı olası dosya engellendi.';
    }
    // HTML script drop
    final head = String.fromCharCodes(
      bytes.take(64).where((b) => b >= 32 && b < 127),
    ).toLowerCase();
    if (head.contains('<script') || head.contains('<!doctype html')) {
      return 'HTML / script içeriği engellendi.';
    }
    return null;
  }

  static void assertSafe({
    required Uint8List bytes,
    required bool allowPdf,
    required bool allowImage,
    required int maxBytes,
    required bool malwareScan,
  }) {
    if (bytes.length > maxBytes) {
      throw StateError(
        'Dosya çok büyük (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB).',
      );
    }
    if (malwareScan) {
      final bad = malwareHint(bytes);
      if (bad != null) throw StateError(bad);
    }
    final kind = detectKind(bytes);
    if (kind == null) {
      throw StateError(
        'Geçersiz dosya. Yalnızca JPEG, PNG veya PDF kabul edilir.',
      );
    }
    if (kind == StudentDocKind.pdf && !allowPdf) {
      throw StateError('PDF şu an kapalı.');
    }
    if ((kind == StudentDocKind.jpeg || kind == StudentDocKind.png) &&
        !allowImage) {
      throw StateError('Görsel yükleme şu an kapalı.');
    }
  }

  static String contentType(StudentDocKind kind) => switch (kind) {
        StudentDocKind.jpeg => 'image/jpeg',
        StudentDocKind.png => 'image/png',
        StudentDocKind.pdf => 'application/pdf',
      };

  static String extension(StudentDocKind kind) => switch (kind) {
        StudentDocKind.jpeg => 'jpg',
        StudentDocKind.png => 'png',
        StudentDocKind.pdf => 'pdf',
      };
}
