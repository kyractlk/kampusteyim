import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/icons/brand_svgs.dart';
import 'cv_models.dart';

/// KampüsteyimAPP CV-AI — hafif ATS şablonu, bölüm bütünlüğü + profil fotoğrafı.
class CvPdfBuilder {
  CvPdfBuilder._();

  static const _ink = PdfColor.fromInt(0xFF243B53);
  static const _navy = PdfColor.fromInt(0xFF3A5A78);
  static const _accent = PdfColor.fromInt(0xFF3DB8A8);
  static const _accentSoft = PdfColor.fromInt(0xFFD8F3EF);
  static const _text = PdfColor.fromInt(0xFF2A3540);
  static const _muted = PdfColor.fromInt(0xFF6B7C8A);
  static const _line = PdfColor.fromInt(0xFFDCE4EC);
  static const _panel = PdfColor.fromInt(0xFFF5F8FA);
  static const _headerBg = PdfColor.fromInt(0xFF2F4B66);
  static const _white = PdfColors.white;

  static pw.Font? _cachedRegular;
  static pw.Font? _cachedBold;

  static Future<void> previewAndShare({
    required Map<String, dynamic> polished,
    required String languageName,
    required String fileHint,
    String languageCode = 'en',
  }) async {
    final bytes = await buildBytes(
      polished: polished,
      languageName: languageName,
      languageCode: languageCode,
    );
    await Printing.layoutPdf(
      name: fileHint,
      onLayout: (_) async => bytes,
    );
  }

  static Future<({pw.Font? base, pw.Font? bold})> _loadFonts() async {
    if (_cachedRegular != null && _cachedBold != null) {
      return (base: _cachedRegular, bold: _cachedBold);
    }
    try {
      final reg = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final bld = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      _cachedRegular = pw.Font.ttf(reg);
      _cachedBold = pw.Font.ttf(bld);
      return (base: _cachedRegular, bold: _cachedBold);
    } catch (_) {
      try {
        return (
          base: await PdfGoogleFonts.nunitoRegular(),
          bold: await PdfGoogleFonts.nunitoBold(),
        );
      } catch (_) {
        return (base: null, bold: null);
      }
    }
  }

  static Future<pw.ImageProvider?> _loadPhoto(String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    try {
      return await networkImage(u);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> buildBytes({
    required Map<String, dynamic> polished,
    required String languageName,
    String languageCode = 'en',
  }) async {
    final fonts = await _loadFonts();
    final pi =
        (polished['personal_info'] as Map?)?.cast<String, dynamic>() ?? {};
    final photo = await _loadPhoto('${pi['photoUrl'] ?? ''}');
    final doc = build(
      polished: polished,
      languageName: languageName,
      languageCode: languageCode,
      base: fonts.base,
      bold: fonts.bold,
      photo: photo,
    );
    return doc.save();
  }

  /// Resmi ATS bölüm başlıkları — dil seçimine göre tam HR terminolojisi.
  static Map<String, String> atsLabels(String code) {
    const en = {
      'profile': 'PROFESSIONAL SUMMARY',
      'experience': 'PROFESSIONAL EXPERIENCE',
      'education': 'EDUCATION',
      'projects': 'PROJECTS',
      'skills': 'CORE COMPETENCIES',
      'languages': 'LANGUAGE PROFICIENCY',
    };
    switch (code.toLowerCase()) {
      case 'tr':
        return {
          'profile': 'PROFESYONEL ÖZET',
          'experience': 'İŞ DENEYİMİ',
          'education': 'EĞİTİM',
          'projects': 'PROJELER',
          'skills': 'TEMEL YETKİNLİKLER',
          'languages': 'DİL YETERLİLİKLERİ',
        };
      case 'de':
        return {
          'profile': 'BERUFLICHES PROFIL',
          'experience': 'BERUFSERFAHRUNG',
          'education': 'AUSBILDUNG',
          'projects': 'PROJEKTE',
          'skills': 'FACHKOMPETENZEN',
          'languages': 'SPRACHKENNTNISSE',
        };
      case 'fr':
        return {
          'profile': 'PROFIL PROFESSIONNEL',
          'experience': 'EXPÉRIENCE PROFESSIONNELLE',
          'education': 'FORMATION',
          'projects': 'PROJETS',
          'skills': 'COMPÉTENCES CLÉS',
          'languages': 'COMPÉTENCES LINGUISTIQUES',
        };
      case 'es':
        return {
          'profile': 'PERFIL PROFESIONAL',
          'experience': 'EXPERIENCIA PROFESIONAL',
          'education': 'FORMACIÓN ACADÉMICA',
          'projects': 'PROYECTOS',
          'skills': 'COMPETENCIAS CLAVE',
          'languages': 'COMPETENCIA LINGÜÍSTICA',
        };
      case 'it':
        return {
          'profile': 'PROFILO PROFESSIONALE',
          'experience': 'ESPERIENZA PROFESSIONALE',
          'education': 'ISTRUZIONE',
          'projects': 'PROGETTI',
          'skills': 'COMPETENZE CHIAVE',
          'languages': 'COMPETENZE LINGUISTICHE',
        };
      case 'pt':
        return {
          'profile': 'RESUMO PROFISSIONAL',
          'experience': 'EXPERIÊNCIA PROFISSIONAL',
          'education': 'FORMAÇÃO ACADÊMICA',
          'projects': 'PROJETOS',
          'skills': 'COMPETÊNCIAS ESSENCIAIS',
          'languages': 'PROFICIÊNCIA LINGUÍSTICA',
        };
      case 'ar':
        return {
          'profile': 'الملخص المهني',
          'experience': 'الخبرة المهنية',
          'education': 'التعليم',
          'projects': 'المشاريع',
          'skills': 'الكفاءات الأساسية',
          'languages': 'إتقان اللغات',
        };
      case 'ru':
        return {
          'profile': 'ПРОФЕССИОНАЛЬНОЕ РЕЗЮМЕ',
          'experience': 'ОПЫТ РАБОТЫ',
          'education': 'ОБРАЗОВАНИЕ',
          'projects': 'ПРОЕКТЫ',
          'skills': 'КЛЮЧЕВЫЕ КОМПЕТЕНЦИИ',
          'languages': 'ВЛАДЕНИЕ ЯЗЫКАМИ',
        };
      case 'nl':
        return {
          'profile': 'PROFESSIONEEL PROFIEL',
          'experience': 'WERKERVARING',
          'education': 'OPLEIDING',
          'projects': 'PROJECTEN',
          'skills': 'KERNCOMPETENTIES',
          'languages': 'TAALVAARDIGHEDEN',
        };
      case 'pl':
        return {
          'profile': 'PODSUMOWANIE ZAWODOWE',
          'experience': 'DOŚWIADCZENIE ZAWODOWE',
          'education': 'WYKSZTAŁCENIE',
          'projects': 'PROJEKTY',
          'skills': 'KLUCZOWE KOMPETENCJE',
          'languages': 'ZNANE JĘZYKI',
        };
      case 'sv':
        return {
          'profile': 'PROFESSIONELL SAMMANFATTNING',
          'experience': 'YRKESEERFARENHET',
          'education': 'UTBILDNING',
          'projects': 'PROJEKT',
          'skills': 'KÄRNKOMPETENSER',
          'languages': 'SPRÅKKUNSKAPER',
        };
      case 'no':
        return {
          'profile': 'PROFESJONELL OPPSUMMERING',
          'experience': 'ARBEIDSERFARING',
          'education': 'UTDANNING',
          'projects': 'PROSJEKTER',
          'skills': 'KJERNEKOMPETANSER',
          'languages': 'SPRÅKFERDIGHETER',
        };
      case 'da':
        return {
          'profile': 'PROFESSIONELT RESUMÉ',
          'experience': 'ERHVERVSERFARING',
          'education': 'UDDANNELSE',
          'projects': 'PROJEKTER',
          'skills': 'KERNEKOMPETENCER',
          'languages': 'SPROGFÆRDIGHEDER',
        };
      case 'fi':
        return {
          'profile': 'AMMATTILLINEN YHTEENVETO',
          'experience': 'TYÖKOKEMUS',
          'education': 'KOULUTUS',
          'projects': 'PROJEKTIT',
          'skills': 'YDINOSAAMINEN',
          'languages': 'KIELITAITO',
        };
      case 'el':
        return {
          'profile': 'ΕΠΑΓΓΕΛΜΑΤΙΚΗ ΠΕΡΙΛΗΨΗ',
          'experience': 'ΕΠΑΓΓΕΛΜΑΤΙΚΗ ΕΜΠΕΙΡΙΑ',
          'education': 'ΕΚΠΑΙΔΕΥΣΗ',
          'projects': 'ΕΡΓΑ',
          'skills': 'ΒΑΣΙΚΕΣ ΙΚΑΝΟΤΗΤΕΣ',
          'languages': 'ΓΛΩΣΣΙΚΗ ΕΠΑΡΚΕΙΑ',
        };
      case 'he':
        return {
          'profile': 'תקציר מקצועי',
          'experience': 'ניסיון מקצועי',
          'education': 'השכלה',
          'projects': 'פרויקטים',
          'skills': 'כישורים מרכזיים',
          'languages': 'שליטה בשפות',
        };
      case 'hi':
        return {
          'profile': 'व्यावसायिक सारांश',
          'experience': 'व्यावसायिक अनुभव',
          'education': 'शिक्षा',
          'projects': 'परियोजनाएँ',
          'skills': 'मुख्य दक्षताएँ',
          'languages': 'भाषा प्रवीणता',
        };
      case 'zh':
        return {
          'profile': '职业摘要',
          'experience': '工作经历',
          'education': '教育背景',
          'projects': '项目经历',
          'skills': '核心能力',
          'languages': '语言能力',
        };
      case 'ja':
        return {
          'profile': '職務要約',
          'experience': '職歴',
          'education': '学歴',
          'projects': 'プロジェクト',
          'skills': 'コア・コンピテンシー',
          'languages': '語学力',
        };
      case 'ko':
        return {
          'profile': '경력 요약',
          'experience': '경력 사항',
          'education': '학력',
          'projects': '프로젝트',
          'skills': '핵심 역량',
          'languages': '어학 능력',
        };
      case 'id':
        return {
          'profile': 'RINGKASAN PROFESIONAL',
          'experience': 'PENGALAMAN KERJA',
          'education': 'PENDIDIKAN',
          'projects': 'PROYEK',
          'skills': 'KOMPETENSI INTI',
          'languages': 'KEMAMPUAN BAHASA',
        };
      case 'ms':
        return {
          'profile': 'RINGKASAN PROFESIONAL',
          'experience': 'PENGALAMAN KERJA',
          'education': 'PENDIDIKAN',
          'projects': 'PROJEK',
          'skills': 'KOMPETENSI TERAS',
          'languages': 'KEMAHIRAN BAHASA',
        };
      case 'th':
        return {
          'profile': 'สรุปประวัติวิชาชีพ',
          'experience': 'ประสบการณ์การทำงาน',
          'education': 'การศึกษา',
          'projects': 'โครงการ',
          'skills': 'สมรรถนะหลัก',
          'languages': 'ความสามารถทางภาษา',
        };
      case 'vi':
        return {
          'profile': 'TÓM TẮT CHUYÊN MÔN',
          'experience': 'KINH NGHIỆM LÀM VIỆC',
          'education': 'HỌC VẤN',
          'projects': 'DỰ ÁN',
          'skills': 'NĂNG LỰC CỐT LÕI',
          'languages': 'TRÌNH ĐỘ NGOẠI NGỮ',
        };
      case 'uk':
        return {
          'profile': 'ПРОФЕСІЙНЕ РЕЗЮМЕ',
          'experience': 'ДОСВІД РОБОТИ',
          'education': 'ОСВІТА',
          'projects': 'ПРОЄКТИ',
          'skills': 'КЛЮЧОВІ КОМПЕТЕНЦІЇ',
          'languages': 'МОВНІ НАВИЧКИ',
        };
      case 'cs':
        return {
          'profile': 'PROFESNÍ SHRNUTÍ',
          'experience': 'PRACOVNÍ ZKUŠENOSTI',
          'education': 'VZDĚLÁNÍ',
          'projects': 'PROJEKTY',
          'skills': 'KLÍČOVÉ KOMPETENCE',
          'languages': 'JAZYKOVÉ ZNALOSTI',
        };
      case 'ro':
        return {
          'profile': 'REZUMAT PROFESIONAL',
          'experience': 'EXPERIENȚĂ PROFESIONALĂ',
          'education': 'EDUCAȚIE',
          'projects': 'PROIECTE',
          'skills': 'COMPETENȚE CHEIE',
          'languages': 'COMPETENȚE LINGVISTICE',
        };
      case 'hu':
        return {
          'profile': 'SZAKMAI ÖSSZEFOGLALÓ',
          'experience': 'SZAKMAI TAPASZTALAT',
          'education': 'TANULMÁNYOK',
          'projects': 'PROJEKTEK',
          'skills': 'KULCSKOMPETENCIÁK',
          'languages': 'NYELVTUDÁS',
        };
      case 'bg':
        return {
          'profile': 'ПРОФЕСИОНАЛНО РЕЗЮМЕ',
          'experience': 'ТРУДОВ ОПИТ',
          'education': 'ОБРАЗОВАНИЕ',
          'projects': 'ПРОЕКТИ',
          'skills': 'КЛЮЧОВИ КОМПЕТЕНТНОСТИ',
          'languages': 'ЕЗИКОВИ УМЕНИЯ',
        };
      default:
        return Map<String, String>.from(en);
    }
  }



  static pw.Document build({
    required Map<String, dynamic> polished,
    required String languageName,
    String languageCode = 'en',
    pw.Font? base,
    pw.Font? bold,
    pw.ImageProvider? photo,
  }) {
    final theme = pw.ThemeData.withFont(base: base, bold: bold);
    final labels = atsLabels(languageCode);
    final aiLabels =
        (polished['section_labels'] as Map?)?.cast<String, dynamic>();
    String L(String key) =>
        '${aiLabels?[key] ?? labels[key] ?? labels['profile']}'.trim();

    final pi =
        (polished['personal_info'] as Map?)?.cast<String, dynamic>() ?? {};
    final education = (polished['education'] as List?) ?? [];
    final experiences = (polished['experiences'] as List?) ?? [];
    final projects = (polished['projects'] as List?) ?? [];
    final skills = (polished['skills'] as List?) ?? [];
    final languages = (polished['languages'] as List?) ?? [];

    final name = '${pi['name'] ?? ''}';
    final headline = '${pi['headline'] ?? pi['title'] ?? ''}'.trim();
    final about = '${pi['about'] ?? ''}'.trim();
    final motivation =
        '${pi['motivation_letter'] ?? pi['motivationLetter'] ?? ''}'.trim();

    final campus = [
      if ('${pi['department'] ?? ''}'.isNotEmpty) '${pi['department']}',
      if ('${pi['class'] ?? ''}'.isNotEmpty) '${pi['class']}',
      if ('${pi['studentNo'] ?? ''}'.isNotEmpty) 'No: ${pi['studentNo']}',
    ].join('  ·  ');

    final initials = _initials(name);

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        maxPages: 12,
        footer: (ctx) => pw.Container(
          color: _white,
          padding: const pw.EdgeInsets.fromLTRB(28, 4, 28, 12),
          child: pw.Column(
            children: [
              pw.Container(height: 1, color: _line),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'KampüsteyimAPP CV-AI  ·  GAÜN  ·  AYS Tech  ·  $languageName',
                    style: const pw.TextStyle(fontSize: 7.2, color: _muted),
                  ),
                  pw.Text(
                    '${ctx.pageNumber} / ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 7.2, color: _muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        build: (context) {
          final out = <pw.Widget>[
            pw.Inseparable(
              child: _header(
                name: name,
                headline: headline,
                campus: campus,
                pi: pi,
                photo: photo,
                initials: initials,
              ),
            ),
          ];

          if (about.isNotEmpty) {
            out.add(_keepSection(
              children: [
                _sectionTitle(L('profile')),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: const pw.BoxDecoration(
                    color: _panel,
                    border: pw.Border(
                      left: pw.BorderSide(color: _accent, width: 3.5),
                    ),
                  ),
                  child: pw.Text(
                    about,
                    style: const pw.TextStyle(
                      fontSize: 9.7,
                      lineSpacing: 2.8,
                      color: _text,
                    ),
                    textAlign: pw.TextAlign.justify,
                  ),
                ),
              ],
            ));
          }

          if (motivation.isNotEmpty) {
            final motLabel = switch (languageCode.toLowerCase()) {
              'en' => 'Motivation Letter',
              'de' => 'Motivationsschreiben',
              'fr' => 'Lettre de motivation',
              _ => 'Motivasyon Mektubu',
            };
            out.add(_keepSection(
              children: [
                _sectionTitle(motLabel),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: const pw.BoxDecoration(
                    color: _panel,
                    border: pw.Border(
                      left: pw.BorderSide(color: _accent, width: 3.5),
                    ),
                  ),
                  child: pw.Text(
                    motivation,
                    style: const pw.TextStyle(
                      fontSize: 9.7,
                      lineSpacing: 2.8,
                      color: _text,
                    ),
                    textAlign: pw.TextAlign.justify,
                  ),
                ),
              ],
            ));
          }

          if (experiences.isNotEmpty) {
            final items = experiences.map((raw) {
              final e = (raw as Map).cast<String, dynamic>();
              return _entry(
                title: '${e['position'] ?? ''}',
                place: '${e['company'] ?? ''}',
                when: _dates(e['startDate'], e['endDate']),
                body: '${e['description'] ?? ''}',
              );
            }).toList();
            out.addAll(_sectionFlow(L('experience'), items));
          }

          if (education.isNotEmpty) {
            final items = education.map((raw) {
              final e = (raw as Map).cast<String, dynamic>();
              final title = [
                if ('${e['degree'] ?? ''}'.isNotEmpty) '${e['degree']}',
                if ('${e['field'] ?? ''}'.isNotEmpty) '${e['field']}',
              ].join(' · ');
              final when = [
                _dates(e['startDate'], e['endDate']),
                if ('${e['gpa'] ?? ''}'.isNotEmpty) 'GPA ${e['gpa']}',
              ].where((x) => x.isNotEmpty).join(' · ');
              return _entry(
                title: title,
                place: '${e['school'] ?? ''}',
                when: when,
                body: '${e['description'] ?? ''}',
              );
            }).toList();
            out.addAll(_sectionFlow(L('education'), items));
          }

          if (projects.isNotEmpty) {
            final items = projects.map((raw) {
              final e = (raw as Map).cast<String, dynamic>();
              return _entry(
                title: '${e['name'] ?? ''}',
                place: '${e['technologies'] ?? ''}',
                when: '',
                body: '${e['description'] ?? ''}',
              );
            }).toList();
            out.addAll(_sectionFlow(L('projects'), items));
          }

          if (skills.isNotEmpty) {
            out.add(_keepSection(
              children: [
                _sectionTitle(L('skills')),
                pw.SizedBox(height: 8),
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skills.map((raw) {
                    final e = (raw as Map).cast<String, dynamic>();
                    final n = '${e['name'] ?? ''}';
                    final l = '${e['level'] ?? ''}';
                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: _accentSoft,
                        border: pw.Border.all(color: _accent, width: 0.7),
                      ),
                      child: pw.Text(
                        l.isEmpty ? n : '$n  ·  $l',
                        style: const pw.TextStyle(
                          fontSize: 8.2,
                          color: _ink,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ));
          }

          if (languages.isNotEmpty) {
            out.add(_keepSection(
              children: [
                _sectionTitle(L('languages')),
                pw.SizedBox(height: 8),
                ...languages.map((raw) {
                  final e = (raw as Map).cast<String, dynamic>();
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 5),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: _panel,
                      border: pw.Border(
                        left: pw.BorderSide(color: _navy, width: 3),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '${e['language'] ?? ''}',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: _ink,
                            ),
                          ),
                        ),
                        pw.Text(
                          '${e['level'] ?? ''}',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ));
          }

          return out;
        },
      ),
    );
    return doc;
  }

  /// Kısa bölümler tek parça; uzunlarda başlık+ilk madde birlikte, diğerleri ayrı iner.
  static List<pw.Widget> _sectionFlow(String title, List<pw.Widget> items) {
    if (items.isEmpty) return [];
    if (items.length <= 2) {
      return [
        _keepSection(
          children: [
            _sectionTitle(title),
            pw.SizedBox(height: 8),
            ...items,
          ],
        ),
      ];
    }
    return [
      _keepSection(
        children: [
          _sectionTitle(title),
          pw.SizedBox(height: 8),
          items.first,
        ],
      ),
      ...items.skip(1).map(
            (e) => pw.Inseparable(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(28, 2, 28, 2),
                child: e,
              ),
            ),
          ),
    ];
  }

  static pw.Widget _keepSection({required List<pw.Widget> children}) {
    return pw.Inseparable(
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(28, 14, 28, 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  static pw.Widget _header({
    required String name,
    required String headline,
    required String campus,
    required Map<String, dynamic> pi,
    required pw.ImageProvider? photo,
    required String initials,
  }) {
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(color: _headerBg),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(height: 3.5, color: _accent),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(28, 18, 28, 14),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        name.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 21,
                          fontWeight: pw.FontWeight.bold,
                          color: _white,
                          letterSpacing: 0.9,
                        ),
                      ),
                      if (headline.isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          headline,
                          style: const pw.TextStyle(
                            fontSize: 10.5,
                            color: _accent,
                          ),
                        ),
                      ],
                      if (campus.isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          campus,
                          style: const pw.TextStyle(
                            fontSize: 8.3,
                            color: PdfColor.fromInt(0xFFB7C7D6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Container(
                  width: 78,
                  height: 78,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: _navy,
                    border: pw.Border.all(color: _accent, width: 2.2),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.ClipOval(
                    child: pw.Container(
                      width: 74,
                      height: 74,
                      color: const PdfColor.fromInt(0xFF3D5F7A),
                      child: photo != null
                          ? pw.Image(photo, fit: pw.BoxFit.cover)
                          : pw.Center(
                              child: pw.Text(
                                initials,
                                style: pw.TextStyle(
                                  fontSize: 22,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _white,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            color: const PdfColor.fromInt(0xFF27445C),
            padding: const pw.EdgeInsets.fromLTRB(28, 9, 28, 10),
            child: pw.Wrap(
              spacing: 14,
              runSpacing: 7,
              children: [
                if ('${pi['email'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.email,
                    label: BrandLinkUtils.display('${pi['email']}'),
                    href: BrandLinkUtils.href(
                      kind: 'email',
                      raw: '${pi['email']}',
                    ),
                  ),
                if ('${pi['phone'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.phone,
                    label: BrandLinkUtils.display('${pi['phone']}'),
                    href: BrandLinkUtils.href(
                      kind: 'phone',
                      raw: '${pi['phone']}',
                    ),
                  ),
                if ('${pi['address'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.location,
                    label: BrandLinkUtils.display('${pi['address']}'),
                    href: null,
                  ),
                if ('${pi['linkedin'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.linkedin,
                    label: BrandLinkUtils.display('${pi['linkedin']}'),
                    href: BrandLinkUtils.href(
                      kind: 'linkedin',
                      raw: '${pi['linkedin']}',
                    ),
                  ),
                if ('${pi['github'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.github,
                    label: BrandLinkUtils.display('${pi['github']}'),
                    href: BrandLinkUtils.href(
                      kind: 'github',
                      raw: '${pi['github']}',
                    ),
                  ),
                if ('${pi['website'] ?? ''}'.isNotEmpty)
                  _contactLink(
                    svg: BrandSvgs.website,
                    label: BrandLinkUtils.display('${pi['website']}'),
                    href: BrandLinkUtils.href(
                      kind: 'website',
                      raw: '${pi['website']}',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dates(dynamic a, dynamic b) {
    final s = '${a ?? ''}'.trim();
    final e = '${b ?? ''}'.trim();
    if (s.isEmpty && e.isEmpty) return '';
    if (s.isEmpty) return e;
    if (e.isEmpty) return s;
    return '$s – $e';
  }

  static pw.Widget _contactLink({
    required String svg,
    required String label,
    required String? href,
  }) {
    final row = pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(
          width: 10,
          height: 10,
          child: pw.SvgImage(svg: svg, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 4),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: const PdfColor.fromInt(0xFFE6EEF5),
            decoration: href != null ? pw.TextDecoration.underline : null,
          ),
        ),
      ],
    );
    if (href == null || href.isEmpty) return row;
    return pw.UrlLink(destination: href, child: row);
  }

  static pw.Widget _sectionTitle(String title) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 3.5, height: 12, color: _accent),
              pw.SizedBox(width: 8),
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                  letterSpacing: 1.05,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(height: 1, color: _line),
        ],
      );

  static pw.Widget _entry({
    required String title,
    required String place,
    required String when,
    required String body,
  }) {
    final bullets = _splitBullets(body);
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 9),
      padding: const pw.EdgeInsets.fromLTRB(2, 2, 2, 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _line, width: 0.8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
              if (when.isNotEmpty)
                pw.Text(
                  when,
                  style: const pw.TextStyle(fontSize: 8, color: _muted),
                ),
            ],
          ),
          if (place.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2, bottom: 4),
              child: pw.Text(
                place,
                style: const pw.TextStyle(fontSize: 9.1, color: _accent),
              ),
            ),
          ...bullets.map(
            (b) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2.5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 4,
                    height: 4,
                    margin: const pw.EdgeInsets.only(top: 3.5, right: 7),
                    decoration: const pw.BoxDecoration(
                      color: _accent,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      b,
                      style: const pw.TextStyle(
                        fontSize: 9.2,
                        lineSpacing: 2.2,
                        color: _text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _splitBullets(String body) {
    final t = body.trim();
    if (t.isEmpty) return [];
    final parts = t
        .split(RegExp(r'\n+|•|\u2022|(?:^|\s)[-–—]\s+'))
        .map((e) => e.replaceAll(RegExp(r'^[\-\*\u2022•]+\s*'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 1) return [t];
    return parts;
  }

  static CvData mapToCvData(Map<String, dynamic> polished) =>
      CvData.fromJson(polished);
}
