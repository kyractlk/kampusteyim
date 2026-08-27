import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Kayıt doğrulama stratejisi (admin seçer).
enum RegVerificationMode {
  /// Belge / e-Devlet adımı yok — hesap doğrudan onay.
  off,

  /// Yalnız e-Devlet barkod; kart/PDF yok.
  edevletOnly,

  /// e-Devlet tercih + kart/PDF yedek (admin onayı).
  edevletPlusDoc,

  /// Yalnız kart / PDF yükleme; e-Devlet kapalı.
  documentOnly,

  /// Adım gösterilir ama “şimdilik geç” ile kayıt; belge sonra istenir.
  defer,
}

extension RegVerificationModeX on RegVerificationMode {
  String get id => name;

  String get title => switch (this) {
        RegVerificationMode.off => 'Kapalı',
        RegVerificationMode.edevletOnly => 'Yalnız e-Devlet',
        RegVerificationMode.edevletPlusDoc => 'e-Devlet + belge',
        RegVerificationMode.documentOnly => 'Yalnız belge',
        RegVerificationMode.defer => 'Belgeyi sonra iste',
      };

  String get subtitle => switch (this) {
        RegVerificationMode.off =>
          'Doğrulama adımı yok; kayıtlar otomatik onaylanır',
        RegVerificationMode.edevletOnly =>
          'Barkod + TC zorunlu; kart/PDF kapalı',
        RegVerificationMode.edevletPlusDoc =>
          'e-Devlet önce; olmazsa kart veya PDF → admin',
        RegVerificationMode.documentOnly =>
          'Kart / PDF yükleme; e-Devlet kapalı',
        RegVerificationMode.defer =>
          'İsteğe bağlı adım; geçebilir, belge sonra istenir',
      };

  bool get showVerificationStep => this != RegVerificationMode.off;

  /// Şimdi belge/doğrulama zorunlu mu? (defer’da hayır)
  bool get requireDocsNow =>
      this == RegVerificationMode.edevletOnly ||
      this == RegVerificationMode.edevletPlusDoc ||
      this == RegVerificationMode.documentOnly;

  bool get allowEdevlet =>
      this == RegVerificationMode.edevletOnly ||
      this == RegVerificationMode.edevletPlusDoc ||
      this == RegVerificationMode.defer;

  bool get allowEdevletPdfFallback =>
      this == RegVerificationMode.edevletPlusDoc ||
      this == RegVerificationMode.defer;

  bool get allowSkip => this == RegVerificationMode.defer;

  static RegVerificationMode parse(String? raw) {
    final s = (raw ?? '').trim();
    return RegVerificationMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => RegVerificationMode.off,
    );
  }
}

/// Kayıt güvenlik / form alan ayarları — yalnız admin. Kullanıcıya gerekçe gösterilmez.
class RegistrationSecurityConfig {
  const RegistrationSecurityConfig({
    this.verificationMode = RegVerificationMode.off,
    this.requireStudentNo = true,
    this.requirePhone = true,
    this.allowStudentCard = true,
    this.allowStudentDocumentPdf = true,
    this.requireCardBothSides = true,
    this.malwareScanEnabled = true,
    this.maxImageBytes = 8 * 1024 * 1024,
    this.maxPdfBytes = 12 * 1024 * 1024,
  });

  final RegVerificationMode verificationMode;

  /// Geriye uyum: belge adımı zorunlu mu?
  bool get requireStudentVerification => verificationMode.requireDocsNow;

  bool get showVerificationStep => verificationMode.showVerificationStep;
  bool get allowEdevlet => verificationMode.allowEdevlet;
  bool get allowEdevletPdfFallback =>
      verificationMode.allowEdevletPdfFallback;
  bool get allowSkipVerification => verificationMode.allowSkip;
  bool get requireDocsNow => verificationMode.requireDocsNow;

  /// Açıkken öğrenci no zorunlu; kapalıyken alan gizlenir.
  final bool requireStudentNo;

  /// Açıkken telefon zorunlu; kapalıyken alan gizlenir.
  final bool requirePhone;

  final bool allowStudentCard;
  final bool allowStudentDocumentPdf;
  final bool requireCardBothSides;
  final bool malwareScanEnabled;
  final int maxImageBytes;
  final int maxPdfBytes;

  static const defaults = RegistrationSecurityConfig();

  static const docPath = 'app_config/registration_security';

  /// Eski bayraklardan mod türet.
  static RegVerificationMode _legacyMode(Map<String, dynamic> m) {
    final require = m['requireStudentVerification'] == true;
    if (!require) {
      if (m['allowDeferVerification'] == true) {
        return RegVerificationMode.defer;
      }
      return RegVerificationMode.off;
    }
    final edevlet = m['allowEdevlet'] != false;
    final card = m['allowStudentCard'] != false;
    final pdf = m['allowStudentDocumentPdf'] != false;
    if (edevlet && !card && !pdf) return RegVerificationMode.edevletOnly;
    if (!edevlet && (card || pdf)) return RegVerificationMode.documentOnly;
    if (edevlet) return RegVerificationMode.edevletPlusDoc;
    return RegVerificationMode.documentOnly;
  }

  factory RegistrationSecurityConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;
    final modeRaw = '${m['verificationMode'] ?? ''}'.trim();
    final mode = modeRaw.isNotEmpty
        ? RegVerificationModeX.parse(modeRaw)
        : _legacyMode(m);

    // Modun önerdiği kart/PDF varsayılanları; admin ince ayarı override edebilir
    var allowCard = m['allowStudentCard'] != false;
    var allowPdf = m['allowStudentDocumentPdf'] != false;
    if (mode == RegVerificationMode.edevletOnly) {
      allowCard = false;
      allowPdf = false;
    } else if (mode == RegVerificationMode.documentOnly) {
      // en az biri açık kalsın
      if (!allowCard && !allowPdf) {
        allowCard = true;
        allowPdf = true;
      }
    } else if (mode == RegVerificationMode.edevletPlusDoc ||
        mode == RegVerificationMode.defer) {
      if (m['allowStudentCard'] == null) allowCard = true;
      if (m['allowStudentDocumentPdf'] == null) allowPdf = true;
    }

    return RegistrationSecurityConfig(
      verificationMode: mode,
      requireStudentNo: m['requireStudentNo'] != false,
      requirePhone: m['requirePhone'] != false,
      allowStudentCard: allowCard,
      allowStudentDocumentPdf: allowPdf,
      requireCardBothSides: m['requireCardBothSides'] != false,
      malwareScanEnabled: m['malwareScanEnabled'] != false,
      maxImageBytes:
          (m['maxImageBytes'] as num?)?.toInt() ?? defaults.maxImageBytes,
      maxPdfBytes: (m['maxPdfBytes'] as num?)?.toInt() ?? defaults.maxPdfBytes,
    );
  }

  Map<String, dynamic> toMap() => {
        'verificationMode': verificationMode.id,
        // Eski istemciler için
        'requireStudentVerification': requireStudentVerification,
        'allowEdevlet': allowEdevlet,
        'allowEdevletPdfFallback': allowEdevletPdfFallback,
        'allowDeferVerification': allowSkipVerification,
        'requireStudentNo': requireStudentNo,
        'requirePhone': requirePhone,
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
    await FirebaseFirestore.instance
        .doc(docPath)
        .set(toMap(), SetOptions(merge: true));
  }

  RegistrationSecurityConfig copyWith({
    RegVerificationMode? verificationMode,
    bool? requireStudentVerification,
    bool? requireStudentNo,
    bool? requirePhone,
    bool? allowStudentCard,
    bool? allowStudentDocumentPdf,
    bool? requireCardBothSides,
    bool? malwareScanEnabled,
  }) {
    var mode = verificationMode ?? this.verificationMode;
    // Eski API: requireStudentVerification false → off
    if (requireStudentVerification != null && verificationMode == null) {
      if (!requireStudentVerification) {
        mode = RegVerificationMode.off;
      } else if (mode == RegVerificationMode.off) {
        mode = RegVerificationMode.edevletPlusDoc;
      }
    }
    return RegistrationSecurityConfig(
      verificationMode: mode,
      requireStudentNo: requireStudentNo ?? this.requireStudentNo,
      requirePhone: requirePhone ?? this.requirePhone,
      allowStudentCard: allowStudentCard ?? this.allowStudentCard,
      allowStudentDocumentPdf:
          allowStudentDocumentPdf ?? this.allowStudentDocumentPdf,
      requireCardBothSides: requireCardBothSides ?? this.requireCardBothSides,
      malwareScanEnabled: malwareScanEnabled ?? this.malwareScanEnabled,
      maxImageBytes: maxImageBytes,
      maxPdfBytes: maxPdfBytes,
    );
  }

  /// Mod seçince kart/PDF bayraklarını makul varsayılana çek.
  RegistrationSecurityConfig withMode(RegVerificationMode mode) {
    switch (mode) {
      case RegVerificationMode.off:
        return copyWith(verificationMode: mode);
      case RegVerificationMode.edevletOnly:
        return copyWith(
          verificationMode: mode,
          allowStudentCard: false,
          allowStudentDocumentPdf: false,
        );
      case RegVerificationMode.edevletPlusDoc:
        return copyWith(
          verificationMode: mode,
          allowStudentCard: true,
          allowStudentDocumentPdf: true,
        );
      case RegVerificationMode.documentOnly:
        return copyWith(
          verificationMode: mode,
          allowStudentCard: true,
          allowStudentDocumentPdf: true,
        );
      case RegVerificationMode.defer:
        return copyWith(
          verificationMode: mode,
          allowStudentCard: true,
          allowStudentDocumentPdf: true,
        );
    }
  }
}

enum StudentDocKind { jpeg, png, pdf }

/// Magic-byte + zararlı imza taraması (istemci koruması).
class StudentDocGuard {
  StudentDocGuard._();

  static StudentDocKind? detectKind(Uint8List bytes) {
    if (bytes.length < 8) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return StudentDocKind.jpeg;
    }
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return StudentDocKind.png;
    }
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
    if (bytes[0] == 0x4D && bytes[1] == 0x5A) {
      return 'Çalıştırılabilir dosya engellendi.';
    }
    if (bytes[0] == 0x7F &&
        bytes[1] == 0x45 &&
        bytes[2] == 0x4C &&
        bytes[3] == 0x46) {
      return 'Çalıştırılabilir dosya engellendi.';
    }
    if (bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return 'Arşiv / sıkıştırılmış zararlı olası dosya engellendi.';
    }
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
