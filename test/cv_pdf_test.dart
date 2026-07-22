import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_mobil/features/cv/cv_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CV-AI PDF üretimi geçerli %PDF üretir', () async {
    final polished = <String, dynamic>{
      'personal_info': {
        'name': 'Ali Kayra Çatalkaya',
        'headline': 'Bilgisayar Mühendisliği · Flutter Developer',
        'email': 'kayra@aystech.com',
        'phone': '+90 555 000 00 00',
        'address': 'Gaziantep',
        'linkedin': 'linkedin.com/in/kayra',
        'github': 'github.com/aystech',
        'website': 'aystech.com',
        'about':
            'Kampüs ürünleri ve mobil deneyim odaklı yazılım geliştirici. Flutter, Firebase ve Cloud Functions ile uçtan uca özellikler üretir.',
        'department': 'Bilgisayar Mühendisliği',
        'class': '3. Sınıf',
        'studentNo': '202012345',
      },
      'experiences': [
        {
          'position': 'Flutter Developer',
          'company': 'AYS Tech',
          'startDate': '2025-06',
          'endDate': '2025-09',
          'description':
              'KampüsteyimAPP sosyal akış ve bildirim modüllerini geliştirdi.\nCV-AI ATS PDF üretim akışını tasarladı.\nFirebase Auth/Firestore entegrasyonlarını tamamladı.',
        },
      ],
      'education': [
        {
          'degree': 'Lisans',
          'field': 'Bilgisayar Mühendisliği',
          'school': 'Gaziantep Üniversitesi',
          'startDate': '2020',
          'endDate': '2026',
          'gpa': '3.40',
        },
      ],
      'projects': [
        {
          'name': 'KampüsteyimAPP',
          'technologies': 'Flutter, Firebase, Cloud Functions',
          'description':
              'GAÜN Mühendislik Topluluğu için misafir-first kampüs uygulaması.\nAdmin RBAC, push yayın ve CV-AI modüllerini içerir.',
        },
      ],
      'skills': [
        {'name': 'Dart', 'level': 'Advanced'},
        {'name': 'Flutter', 'level': 'Advanced'},
        {'name': 'Firebase', 'level': 'Intermediate'},
      ],
      'languages': [
        {'language': 'Türkçe', 'level': 'Ana dil'},
        {'language': 'English', 'level': 'B2'},
      ],
    };

    final bytes = await CvPdfBuilder.buildBytes(
      polished: polished,
      languageName: 'Turkish',
      languageCode: 'tr',
    );

    expect(bytes.length, greaterThan(800));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');

    final out = Directory('build/cv_samples')..createSync(recursive: true);
    final file = File('${out.path}/sample_ats_cv_tr.pdf');
    await file.writeAsBytes(bytes, flush: true);
    // ignore: avoid_print
    print('PDF yazıldı: ${file.absolute.path} (${bytes.length} bytes)');
  });
}
