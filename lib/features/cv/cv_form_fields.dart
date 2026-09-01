import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../data/campus_catalog.dart';
import 'cv_models.dart';
import 'cv_provider.dart';

const kCvDegrees = [
  'Lisans',
  'Ön Lisans',
  'Yüksek Lisans',
  'Doktora',
  'Lise',
  'Sertifika',
];

const kCvSkillLevels = [
  'Başlangıç',
  'Orta',
  'İleri',
  'Uzman',
];

const kCvLanguageNames = [
  'Türkçe',
  'English',
  'Deutsch',
  'Français',
  'Español',
  'Italiano',
  'العربية',
  'Русский',
  '中文',
  '日本語',
  '한국어',
];

const kCvCefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'Ana dil'];

/// Controller tabanlı alan — ExpansionTile içinde label kayması olmaz.
class CvBoundField extends StatefulWidget {
  const CvBoundField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.hint,
    this.keyboardType,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  State<CvBoundField> createState() => _CvBoundFieldState();
}

class _CvBoundFieldState extends State<CvBoundField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(CvBoundField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _controller,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          filled: true,
          fillColor: AppColors.surface,
          alignLabelWithHint: widget.maxLines > 1,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class CvDateField extends StatefulWidget {
  const CvDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<CvDateField> createState() => _CvDateFieldState();
}

class _CvDateFieldState extends State<CvDateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(CvDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DateTime? _parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'[./-]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d);
      }
    }
    return DateTime.tryParse(s);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Future<void> _pick() async {
    final initial = _parse(_controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      locale: const Locale('tr'),
    );
    if (picked == null) return;
    final text = _fmt(picked);
    _controller.text = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _controller,
        keyboardType: TextInputType.datetime,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9./-]')),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'gg.aa.yyyy',
          filled: true,
          fillColor: AppColors.surface,
          suffixIcon: IconButton(
            tooltip: 'Takvimden seç',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pick,
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class CvDropdownField extends StatelessWidget {
  const CvDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.allowCustom = false,
    this.customHint = 'Diğer (yaz)',
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final bool allowCustom;
  final String customHint;

  @override
  Widget build(BuildContext context) {
    final trimmed = value.trim();
    final inList = items.contains(trimmed);
    final effective = inList ? trimmed : (trimmed.isEmpty ? null : trimmed);
    final dropdownItems = <String>[...items];
    if (allowCustom && trimmed.isNotEmpty && !inList) {
      dropdownItems.insert(0, trimmed);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: effective?.isEmpty == true ? null : effective,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surface,
        ),
        items: [
          ...dropdownItems.map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (allowCustom)
            const DropdownMenuItem(
              value: '__custom__',
              child: Text('Diğer…'),
            ),
        ],
        onChanged: (v) async {
          if (v == null) return;
          if (v == '__custom__') {
            final custom = await _askCustom(context, customHint, trimmed);
            if (custom != null && custom.trim().isNotEmpty) {
              onChanged(custom.trim());
            }
            return;
          }
          onChanged(v);
        },
      ),
    );
  }

  Future<String?> _askCustom(
    BuildContext context,
    String hint,
    String initial,
  ) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hint),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Yazın'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

class CvEducationEditor extends StatefulWidget {
  const CvEducationEditor({
    super.key,
    required this.education,
    required this.cv,
  });

  final CvEducation education;
  final CvProvider cv;

  @override
  State<CvEducationEditor> createState() => _CvEducationEditorState();
}

class _CvEducationEditorState extends State<CvEducationEditor> {
  CampusCatalog? _catalog;
  List<String> _universities = const [];
  List<String> _departments = const [];
  /// true = üniversite listesinden seç; false = serbest yazım (lise, meslek vb.)
  bool _universityMode = true;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final c = await CampusCatalog.load();
    final unis = c.byName.keys.toList()..sort((a, b) => a.compareTo(b));
    if (!mounted) return;
    final school = widget.education.school.trim();
    final inCatalog = school.isNotEmpty && unis.contains(school);
    setState(() {
      _catalog = c;
      _universities = unis;
      _universityMode = school.isEmpty || inCatalog;
      _departments = inCatalog
          ? c.departmentsFor(universityName: school)
          : const [];
    });
  }

  void _onUniversity(String uni) {
    widget.education.school = uni;
    final deps = _catalog?.departmentsFor(universityName: uni) ?? const [];
    setState(() => _departments = deps);
    if (deps.isNotEmpty &&
        !deps.contains(widget.education.field.trim())) {
      widget.education.field = deps.first;
    }
    widget.cv.touch();
  }

  void _setUniversityMode(bool university) {
    if (_universityMode == university) return;
    setState(() {
      _universityMode = university;
      if (!university) {
        _departments = const [];
      } else {
        final school = widget.education.school.trim();
        if (school.isNotEmpty && _universities.contains(school)) {
          _departments =
              _catalog?.departmentsFor(universityName: school) ?? const [];
        } else {
          widget.education.school = '';
          widget.education.field = '';
          _departments = const [];
        }
      }
    });
    widget.cv.touch();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.education;
    if (_catalog == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Üniversite'),
                icon: Icon(Icons.school_outlined, size: 18),
              ),
              ButtonSegment(
                value: false,
                label: Text('Diğer okul'),
                icon: Icon(Icons.edit_outlined, size: 18),
              ),
            ],
            selected: {_universityMode},
            onSelectionChanged: (s) => _setUniversityMode(s.first),
          ),
        ),
        if (_universityMode)
          CvDropdownField(
            label: 'Üniversite',
            value: e.school,
            items: _universities,
            allowCustom: true,
            customHint: 'Üniversite adı',
            onChanged: _onUniversity,
          )
        else
          CvBoundField(
            label: 'Okul adı',
            value: e.school,
            hint: 'Lise, meslek okulu, kurum adı…',
            onChanged: (v) {
              e.school = v;
              widget.cv.touch();
            },
          ),
        CvDropdownField(
          label: 'Derece',
          value: e.degree,
          items: kCvDegrees,
          allowCustom: true,
          customHint: 'Derece',
          onChanged: (v) {
            e.degree = v;
            widget.cv.touch();
          },
        ),
        if (_universityMode && _departments.isNotEmpty)
          CvDropdownField(
            label: 'Bölüm',
            value: e.field,
            items: _departments,
            allowCustom: true,
            customHint: 'Bölüm adı',
            onChanged: (v) {
              e.field = v;
              widget.cv.touch();
            },
          )
        else
          CvBoundField(
            label: 'Bölüm / Alan',
            value: e.field,
            onChanged: (v) {
              e.field = v;
              widget.cv.touch();
            },
          ),
        CvDateField(
          label: 'Başlangıç',
          value: e.startDate,
          onChanged: (v) {
            e.startDate = v;
            widget.cv.touch();
          },
        ),
        CvDateField(
          label: 'Bitiş',
          value: e.endDate,
          onChanged: (v) {
            e.endDate = v;
            widget.cv.touch();
          },
        ),
        CvBoundField(
          label: 'GPA',
          value: e.gpa,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            e.gpa = v;
            widget.cv.touch();
          },
        ),
        CvBoundField(
          label: 'Açıklama',
          value: e.description,
          maxLines: 3,
          onChanged: (v) {
            e.description = v;
            widget.cv.touch();
          },
        ),
      ],
    );
  }
}

class CvExperienceEditor extends StatelessWidget {
  const CvExperienceEditor({
    super.key,
    required this.experience,
    required this.cv,
  });

  final CvExperience experience;
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final e = experience;
    return Column(
      children: [
        CvBoundField(
          label: 'Şirket',
          value: e.company,
          onChanged: (v) {
            e.company = v;
            cv.touch();
          },
        ),
        CvBoundField(
          label: 'Pozisyon',
          value: e.position,
          onChanged: (v) {
            e.position = v;
            cv.touch();
          },
        ),
        CvDateField(
          label: 'Başlangıç',
          value: e.startDate,
          onChanged: (v) {
            e.startDate = v;
            cv.touch();
          },
        ),
        CvDateField(
          label: 'Bitiş',
          value: e.endDate,
          onChanged: (v) {
            e.endDate = v;
            cv.touch();
          },
        ),
        CvBoundField(
          label: 'Açıklama',
          value: e.description,
          maxLines: 4,
          onChanged: (v) {
            e.description = v;
            cv.touch();
          },
        ),
      ],
    );
  }
}

class CvSkillEditor extends StatefulWidget {
  const CvSkillEditor({
    super.key,
    required this.skill,
    required this.cv,
  });

  final CvSkill skill;
  final CvProvider cv;

  @override
  State<CvSkillEditor> createState() => _CvSkillEditorState();
}

class _CvSkillEditorState extends State<CvSkillEditor> {
  @override
  void initState() {
    super.initState();
    if (!kCvSkillLevels.contains(widget.skill.level)) {
      widget.skill.level = _mapLegacy(widget.skill.level);
    }
  }

  String _mapLegacy(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('begin') || s.contains('başlang')) return 'Başlangıç';
    if (s.contains('inter') || s.contains('orta')) return 'Orta';
    if (s.contains('adv') || s.contains('ileri')) return 'İleri';
    if (s.contains('expert') || s.contains('uzman')) return 'Uzman';
    return 'Orta';
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    final cv = widget.cv;
    return Column(
      children: [
        CvBoundField(
          label: 'Beceri',
          value: skill.name,
          onChanged: (v) {
            skill.name = v;
            cv.touch();
          },
        ),
        CvDropdownField(
          label: 'Seviye',
          value: skill.level,
          items: kCvSkillLevels,
          onChanged: (v) {
            skill.level = v;
            cv.touch();
          },
        ),
      ],
    );
  }
}

class CvLanguageEditor extends StatelessWidget {
  const CvLanguageEditor({
    super.key,
    required this.language,
    required this.cv,
  });

  final CvLanguage language;
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final lang = kCvLanguageNames.contains(language.language)
        ? language.language
        : (language.language.trim().isEmpty ? kCvLanguageNames[1] : language.language);
    final level = kCvCefrLevels.contains(language.level)
        ? language.level
        : kCvCefrLevels[2];
    return Column(
      children: [
        CvDropdownField(
          label: 'Dil',
          value: lang,
          items: kCvLanguageNames,
          allowCustom: true,
          customHint: 'Dil adı',
          onChanged: (v) {
            language.language = v;
            cv.touch();
          },
        ),
        CvDropdownField(
          label: 'Seviye (CEFR)',
          value: level,
          items: kCvCefrLevels,
          onChanged: (v) {
            language.level = v;
            cv.touch();
          },
        ),
      ],
    );
  }
}
