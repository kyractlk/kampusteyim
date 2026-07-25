import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_mobil/features/cv/cv_pdf.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CV PDF is true A4 and multi-page safe', () async {
    final polished = <String, dynamic>{
      'personal_info': {
        'name': 'Ali Kayra Çatalkaya',
        'headline': 'Software Engineering Student · Flutter & AI',
        'about':
            'Gaziantep Üniversitesi öğrencisi. Kampüs sosyal ürünleri, ATS CV ve '
            'staj süreçleri üzerine çalışıyor. Takım çalışması, ürün odaklı geliştirme '
            've temiz mimariye önem verir.',
        'motivation_letter':
            'Staj programınıza başvurmak istiyorum. Öğrendiklerimi gerçek ürün '
            'ekiplerinde uygulamak ve kampüs-teknoloji kesişiminde değer üretmek '
            'istiyorum. Motivasyon mektubu satırları sayfa taşmasını test eder.',
        'department': 'Bilgisayar Mühendisliği',
        'class': '3. Sınıf',
        'studentNo': '202012345',
        'email': 'kayra@example.com',
        'phone': '+90 555 000 00 00',
        'linkedin': 'linkedin.com/in/example',
        'github': 'github.com/example',
      },
      'experiences': [
        for (var i = 1; i <= 4; i++)
          {
            'position': 'Yazılım Stajyeri $i',
            'company': 'AYS Tech',
            'startDate': '2024-0$i',
            'endDate': '2024-0${i + 1}',
            'description':
                '• Flutter mobil geliştirme\n• Firebase entegrasyonu\n'
                '• Kod inceleme ve dokümantasyon\n• Kullanıcı geri bildirimi analizi',
          },
      ],
      'education': [
        {
          'degree': 'Lisans',
          'field': 'Bilgisayar Mühendisliği',
          'school': 'Gaziantep Üniversitesi',
          'startDate': '2021',
          'endDate': '2026',
          'gpa': '3.40',
          'description': 'Algoritmalar, veri yapıları, yazılım mühendisliği.',
        },
      ],
      'projects': [
        {
          'name': 'KampüsteyimAPP',
          'technologies': 'Flutter, Firebase',
          'description':
              'Kampüs sosyal ağı: akış, hikâye, reels, CV-AI ve staj paneli.',
        },
        {
          'name': 'ATS CV Builder',
          'technologies': 'Dart, PDF',
          'description': 'Çok dilli ATS uyumlu CV üretimi.',
        },
      ],
      'skills': [
        {'name': 'Flutter', 'level': 'Advanced'},
        {'name': 'Dart', 'level': 'Advanced'},
        {'name': 'Firebase', 'level': 'Intermediate'},
        {'name': 'Python', 'level': 'Intermediate'},
      ],
      'languages': [
        {'language': 'Türkçe', 'level': 'Ana dil'},
        {'language': 'English', 'level': 'B2'},
      ],
    };

    final bytes = await CvPdfBuilder.buildBytes(
      polished: polished,
      languageName: 'Türkçe (ATS)',
      languageCode: 'tr',
      accentArgb: 0xFF3DB8A8,
    );

    expect(bytes.length, greaterThan(1000));

    final out = File('build/test_cv_a4.pdf');
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(bytes, flush: true);

    // MediaBox ~ A4 in points: 595.27 x 841.89
    final text = String.fromCharCodes(bytes);
    final media = RegExp(
      r'/MediaBox\s*\[\s*([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s*\]',
    ).firstMatch(text);
    expect(media, isNotNull, reason: 'PDF MediaBox bulunamadı');
    final w = double.parse(media!.group(3)!);
    final h = double.parse(media.group(4)!);
    expect(w, closeTo(PdfPageFormat.a4.width, 1.0));
    expect(h, closeTo(PdfPageFormat.a4.height, 1.0));

    final pageCount = RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
    expect(pageCount, greaterThanOrEqualTo(1));
    // Zengin içerik → en azından tek sayfa dolu; taşma olursa 2+
    expect(pageCount, lessThanOrEqualTo(12));

    // ignore: avoid_print
    print('CV PDF OK: ${out.path}  ${w.toStringAsFixed(1)}x${h.toStringAsFixed(1)} pt  pages≈$pageCount  bytes=${bytes.length}');
  });
}
