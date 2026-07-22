import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../auth/data/auth_provider.dart' show AuthProvider;
import 'cv_models.dart';
import 'cv_pdf.dart';

class CvProvider extends ChangeNotifier {
  CvProvider();

  CvData data = CvData();
  List<CvExportMeta> exports = [];
  bool busy = false;
  String? status;
  String? error;
  CvLanguageOption selectedLanguage = kCvWorldLanguages.first;

  bool get isReadyForJobs => data.isReadyForJobs;

  String get _authUid =>
      fa.FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Platform profilinden kişisel alanları doldur (mevcut değerleri ezer).
  void applyProfileFromUser(AppUser user) {
    final p = data.personalInfo;
    p.name = user.fullName;
    p.email = user.email;
    p.studentNo = user.studentNo;
    p.phone = user.phone;
    if (user.city.trim().isNotEmpty) {
      p.address = user.city;
    }
    for (final link in user.links) {
      final label = link.label.toLowerCase();
      final url = link.url.trim();
      if (url.isEmpty) continue;
      if (label.contains('linkedin') && p.linkedin.isEmpty) p.linkedin = url;
      if (label.contains('github') && p.github.isEmpty) p.github = url;
      if ((label.contains('web') || label.contains('site')) &&
          p.website.isEmpty) {
        p.website = url;
      }
    }
    if (p.about.trim().isEmpty && user.bio.trim().isNotEmpty) {
      p.about = user.bio.trim();
    }
    if (data.education.isEmpty && user.university.trim().isNotEmpty) {
      data.education.add(
        CvEducation(
          id: 'edu_auto',
          school: user.university,
          degree: 'Lisans',
          field: p.department,
        ),
      );
    }
  }

  Future<void> bootstrap(AuthProvider auth) async {
    final user = auth.user;
    if (user == null) return;
    await loadLocal();
    await loadRemote(user.id);
    applyProfileFromUser(user);
    await loadExports(user.id);
    notifyListeners();
  }

  Future<void> refreshFromProfile(AuthProvider auth) async {
    final user = auth.user;
    if (user == null) return;
    applyProfileFromUser(user);
    await saveLocal();
    notifyListeners();
  }

  Future<void> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cv_draft_json');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        data = CvData.fromJson(map.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cv_draft_json', jsonEncode(data.toJson()));
  }

  Future<void> saveRemote(String userId) async {
    busy = true;
    error = null;
    status = 'CV kaydediliyor…';
    notifyListeners();
    try {
      final docId = _authUid.isNotEmpty ? _authUid : userId;
      await FirebaseFirestore.instance.collection('cvs').doc(docId).set({
        'user_id': userId,
        'stableId': userId,
        'cv_data': data.toJson(),
        'has_cv': data.isReadyForJobs,
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      await saveLocal();
      status = 'CV kaydedildi';
    } catch (e) {
      error = 'Kayıt başarısız: $e';
      status = null;
      debugPrint('[cv] saveRemote: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> loadRemote(String userId) async {
    try {
      DocumentSnapshot<Map<String, dynamic>>? doc;
      if (_authUid.isNotEmpty) {
        doc = await FirebaseFirestore.instance.collection('cvs').doc(_authUid).get();
      }
      if (doc == null || !doc.exists) {
        doc = await FirebaseFirestore.instance.collection('cvs').doc(userId).get();
      }
      if (!doc.exists) return;
      final cvData = doc.data()?['cv_data'];
      if (cvData is Map) {
        data = CvData.fromJson(cvData.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> loadExports(String userId) async {
    try {
      final uid = _authUid.isNotEmpty ? _authUid : userId;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('cv_exports')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      exports = snap.docs.map((d) {
        final m = d.data();
        return CvExportMeta(
          id: d.id,
          languageCode: '${m['languageCode'] ?? ''}',
          languageName: '${m['languageName'] ?? ''}',
          createdAt: '${m['createdAt'] ?? ''}',
          polished: ((m['polished'] as Map?) ?? {}).cast<String, dynamic>(),
        );
      }).toList();
    } catch (_) {}
  }

  Future<bool> generateAts({
    required AuthProvider auth,
  }) async {
    final user = auth.user;
    if (user == null) {
      error = 'Giriş gerekli';
      notifyListeners();
      return false;
    }
    if (!data.isReadyForJobs) {
      error =
          'En az bir özet, hızlı not veya deneyim/eğitim/beceri ekle.';
      notifyListeners();
      return false;
    }

    busy = true;
    error = null;
    status =
        'Canlı AI · ${selectedLanguage.name} — tam çeviri + ATS düzenleme…';
    notifyListeners();

    try {
      await saveRemote(user.id);

      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
        'generateAtsCv',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final result = await callable.call(<String, dynamic>{
        'cvData': data.toJson(),
        'languageCode': selectedLanguage.code,
        'languageName': selectedLanguage.name,
        'userEmail': user.email,
        'userName': user.fullName,
        'studentNo': user.studentNo,
      });

      final map = Map<String, dynamic>.from(result.data as Map);
      final polished =
          Map<String, dynamic>.from(map['polished'] as Map? ?? {});
      _preservePhoto(polished);
      final exportId = '${map['exportId']}';

      exports.insert(
        0,
        CvExportMeta(
          id: exportId,
          languageCode: selectedLanguage.code,
          languageName: selectedLanguage.name,
          createdAt: DateTime.now().toIso8601String(),
          polished: polished,
        ),
      );

      final fileHint =
          '${user.studentNo}_${user.fullName.replaceAll(' ', '_')}_CV_${selectedLanguage.code.toUpperCase()}.pdf';
      await CvPdfBuilder.previewAndShare(
        polished: polished,
        languageName: selectedLanguage.name,
        languageCode: selectedLanguage.code,
        fileHint: fileHint,
      );

      status = 'ATS CV hazır · ${selectedLanguage.name} (canlı AI)';
      busy = false;
      notifyListeners();
      return true;
    } on FirebaseFunctionsException catch (e) {
      error =
          'Canlı AI başarısız (${e.code}): ${e.message ?? 'bilinmeyen hata'}';
      status = null;
      busy = false;
      notifyListeners();
      debugPrint('[cv] generateAts CF: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      error = 'Üretim hatası: $e';
      status = null;
      busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> redownload(CvExportMeta export) async {
    await CvPdfBuilder.previewAndShare(
      polished: export.polished,
      languageName: export.languageName,
      languageCode: export.languageCode,
      fileHint: 'CV_${export.languageCode.toUpperCase()}_${export.id}.pdf',
    );
  }

  void setLanguage(CvLanguageOption lang) {
    selectedLanguage = lang;
    notifyListeners();
  }

  void setRawNotes(String value) {
    data.rawNotes = value;
    notifyListeners();
  }

  /// AI çıktısı photoUrl düşürürse profil / taslak fotoğrafını koru.
  void _preservePhoto(Map<String, dynamic> polished) {
    final src = data.personalInfo.photoUrl.trim();
    if (src.isEmpty) return;
    final pi = (polished['personal_info'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if ('${pi['photoUrl'] ?? ''}'.trim().isEmpty) {
      pi['photoUrl'] = src;
      polished['personal_info'] = pi;
    }
  }

  void touch() => notifyListeners();
}
