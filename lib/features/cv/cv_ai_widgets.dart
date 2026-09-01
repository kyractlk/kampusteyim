import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/brand_svgs.dart';
import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import '../plus/plus_gate.dart';
import '../plus/plus_provider.dart';
import 'cv_form_fields.dart';
import 'cv_models.dart';
import 'cv_provider.dart';

/// CV-AI bölüm tanımları (sihirbaz + hub).
enum CvSection {
  photo('Fotoğraf', Icons.photo_camera_outlined, 'CV fotoğrafınız'),
  profile('Özet & Ünvan', Icons.person_outline, 'Headline, bölüm, hakkımda'),
  links('Bağlantılar', Icons.link, 'LinkedIn, GitHub, web'),
  education('Eğitim', Icons.school_outlined, 'Okul ve derece'),
  experience('İş Deneyimi', Icons.work_outline, 'Staj ve işler'),
  projects('Projeler', Icons.code, 'Projeler ve teknolojiler'),
  skills('Beceriler', Icons.psychology_outlined, 'Teknik / soft beceriler'),
  languages('Diller', Icons.translate, 'Yabancı dil seviyeleri'),
  motivation('Motivasyon', Icons.mail_outline, 'Motivasyon mektubu'),
  export('PDF Oluştur', Icons.picture_as_pdf_outlined, 'Dil seç, indir');

  const CvSection(this.title, this.icon, this.subtitle);
  final String title;
  final IconData icon;
  final String subtitle;

  static List<CvSection> get wizardSteps => CvSection.values;
  static List<CvSection> get hubSections =>
      CvSection.values.where((s) => s != CvSection.export).toList();
}

class CvStepDots extends StatelessWidget {
  const CvStepDots({
    super.key,
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active || done ? AppColors.navy : AppColors.border,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

class CvProfileSummaryCard extends StatelessWidget {
  const CvProfileSummaryCard({super.key, required this.cv});

  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final p = cv.data.personalInfo;
    final lines = [
      p.email,
      p.phone,
      p.studentNo,
      p.address,
    ].where((e) => e.trim().isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Platform profilinden',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            p.name.isEmpty ? 'Ad Soyad' : p.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          if (lines.isNotEmpty)
            Text(
              lines,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Bu alanlar profilden gelir; CV ekranında tekrar yazılmaz.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class CvPhotoPicker extends StatelessWidget {
  const CvPhotoPicker({
    super.key,
    required this.cv,
    this.size = 112,
    this.showHint = true,
  });

  final CvProvider cv;
  final double size;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final url = cv.cvPhotoUrl;
    final p = cv.data.personalInfo;

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceMuted,
                border: Border.all(color: AppColors.navy.withValues(alpha: 0.25), width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isNotEmpty
                  ? Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person,
                        size: size * 0.45,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: size * 0.45,
                      color: AppColors.textSecondary,
                    ),
            ),
            Material(
              color: AppColors.navy,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _pick(context, auth),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(Icons.photo_camera, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          p.name.isEmpty ? 'Ad Soyad' : p.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        if (showHint) ...[
          const SizedBox(height: 6),
          const Text(
            'CV fotoğrafı bir kez yüklenir; tüm PDF’lerde aynı kalır.\n'
            'Değiştirmek için tekrar dokunun.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, AuthProvider auth) async {
    final user = auth.user;
    if (user == null) return;
    try {
      final file = await MediaUpload.pickImage();
      if (file == null) return;
      final authUid = fa.FirebaseAuth.instance.currentUser?.uid ?? user.id;
      final url = await MediaUpload.uploadXFile(
        file: file,
        folder: 'cv/$authUid',
        firstName: user.firstName,
        lastName: user.lastName,
        studentNo: user.studentNo,
        isVideo: false,
      );
      await cv.setCvPhoto(url, user.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CV fotoğrafı kaydedildi')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class CvSectionHeader extends StatelessWidget {
  const CvSectionHeader({super.key, required this.title, required this.onAdd});

  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ekle'),
          ),
        ],
      ),
    );
  }
}

class CvExpandCard extends StatelessWidget {
  const CvExpandCard({
    super.key,
    required this.title,
    required this.children,
    required this.onDelete,
    this.subtitle = '',
    this.initiallyExpanded = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback onDelete;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: subtitle.trim().isEmpty
              ? null
              : Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: AppColors.crimson),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
          children: children,
        ),
      ),
    );
  }
}

Widget cvBoundField(
  String label,
  String value,
  ValueChanged<String> onChanged,
  CvProvider cv, {
  int maxLines = 1,
  String? brandSvg,
  String? linkKind,
}) {
  if (brandSvg != null || linkKind != null) {
    final href = linkKind == null
        ? null
        : BrandLinkUtils.href(kind: linkKind, raw: value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CvLinkField(
        label: label,
        value: value,
        brandSvg: brandSvg,
        href: href,
        onChanged: (v) {
          onChanged(v);
          cv.touch();
        },
      ),
    );
  }
  return CvBoundField(
    label: label,
    value: value,
    maxLines: maxLines,
    onChanged: (v) {
      onChanged(v);
      cv.touch();
    },
  );
}

class _CvLinkField extends StatefulWidget {
  const _CvLinkField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.brandSvg,
    this.href,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? brandSvg;
  final String? href;

  @override
  State<_CvLinkField> createState() => _CvLinkFieldState();
}

class _CvLinkFieldState extends State<_CvLinkField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CvLinkField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: widget.brandSvg == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(10),
                child: BrandSvgIcon(widget.brandSvg!, size: 22),
              ),
        prefixIconConstraints: widget.brandSvg == null
            ? null
            : const BoxConstraints(minWidth: 44, minHeight: 44),
        suffixIcon: widget.href == null || widget.value.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Aç',
                onPressed: () async {
                  final uri = Uri.tryParse(widget.href!);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

// Geriye uyumluluk
Widget cvField(
  String label,
  String value,
  ValueChanged<String> onChanged,
  CvProvider cv, {
  int maxLines = 1,
  String? brandSvg,
  String? linkKind,
}) =>
    cvBoundField(
      label,
      value,
      onChanged,
      cv,
      maxLines: maxLines,
      brandSvg: brandSvg,
      linkKind: linkKind,
    );

// Eski cvField implementasyonu kaldırıldı — CvBoundField kullanılıyor.

/// Tek bölüm içeriği — sihirbaz ve düzenleme ekranında paylaşılır.
class CvSectionBody extends StatelessWidget {
  const CvSectionBody({super.key, required this.section, required this.cv});

  final CvSection section;
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = cv.data.personalInfo;

    return switch (section) {
      CvSection.photo => Column(
          children: [
            const SizedBox(height: 8),
            CvPhotoPicker(cv: cv),
            const SizedBox(height: 20),
            CvProfileSummaryCard(cv: cv),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: auth.user == null
                  ? null
                  : () => cv.refreshFromProfile(auth),
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Profil bilgilerini yenile'),
            ),
          ],
        ),
      CvSection.profile => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CvProfileSummaryCard(cv: cv),
            const SizedBox(height: 14),
            cvBoundField('Ünvan / Headline', p.headline, (v) => p.headline = v, cv),
            cvBoundField('Bölüm', p.department, (v) => p.department = v, cv),
            cvBoundField('Sınıf', p.classYear, (v) => p.classYear = v, cv),
            cvBoundField('Hakkımda / Özet', p.about, (v) => p.about = v, cv,
                maxLines: 6),
          ],
        ),
      CvSection.links => Column(
          children: [
            cvBoundField('LinkedIn', p.linkedin, (v) => p.linkedin = v, cv,
                brandSvg: BrandSvgs.linkedin, linkKind: 'linkedin'),
            cvBoundField('GitHub', p.github, (v) => p.github = v, cv,
                brandSvg: BrandSvgs.github, linkKind: 'github'),
            cvBoundField('Website', p.website, (v) => p.website = v, cv,
                brandSvg: BrandSvgs.website, linkKind: 'website'),
          ],
        ),
      CvSection.education => _listSection(
          cv,
          CvSection.education,
        ),
      CvSection.experience => _listSection(cv, CvSection.experience),
      CvSection.projects => _listSection(cv, CvSection.projects),
      CvSection.skills => _listSection(cv, CvSection.skills),
      CvSection.languages => _listSection(cv, CvSection.languages),
      CvSection.motivation => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cvBoundField(
              'Motivasyon mektubu',
              p.motivationLetter,
              (v) => p.motivationLetter = v,
              cv,
              maxLines: 10,
            ),
            const Text(
              'İsteğe bağlı · firmalara başvuruda görünür.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      CvSection.export => CvExportPanel(cv: cv),
    };
  }

  Widget _listSection(CvProvider cv, CvSection section) {
    return ListenableBuilder(
      listenable: cv,
      builder: (context, _) {
        return switch (section) {
          CvSection.education => Column(
              children: [
                CvSectionHeader(
                  title: 'Eğitim',
                  onAdd: () {
                    cv.data.education.add(CvEducation(id: const Uuid().v4()));
                    cv.touch();
                  },
                ),
                ...cv.data.education.map(
                  (e) => CvExpandCard(
                    key: ValueKey(e.id),
                    title: e.school.isEmpty ? 'Okul' : e.school,
                    subtitle: [e.degree, e.field]
                        .where((s) => s.trim().isNotEmpty)
                        .join(' · '),
                    onDelete: () {
                      cv.data.education.remove(e);
                      cv.touch();
                    },
                    children: [
                      CvEducationEditor(education: e, cv: cv),
                    ],
                  ),
                ),
              ],
            ),
          CvSection.experience => Column(
              children: [
                CvSectionHeader(
                  title: 'İş Deneyimi',
                  onAdd: () {
                    cv.data.experiences.add(CvExperience(id: const Uuid().v4()));
                    cv.touch();
                  },
                ),
                ...cv.data.experiences.map(
                  (e) => CvExpandCard(
                    key: ValueKey(e.id),
                    title: e.company.isEmpty ? 'Şirket' : e.company,
                    subtitle: e.position,
                    onDelete: () {
                      cv.data.experiences.remove(e);
                      cv.touch();
                    },
                    children: [
                      CvExperienceEditor(experience: e, cv: cv),
                    ],
                  ),
                ),
              ],
            ),
          CvSection.projects => Column(
              children: [
                CvSectionHeader(
                  title: 'Projeler',
                  onAdd: () {
                    cv.data.projects.add(CvProject(id: const Uuid().v4()));
                    cv.touch();
                  },
                ),
                ...cv.data.projects.map(
                  (e) => CvExpandCard(
                    key: ValueKey(e.id),
                    title: e.name.isEmpty ? 'Proje' : e.name,
                    subtitle: e.technologies,
                    onDelete: () {
                      cv.data.projects.remove(e);
                      cv.touch();
                    },
                    children: [
                      cvBoundField('Ad', e.name, (v) => e.name = v, cv),
                      cvBoundField('Teknolojiler', e.technologies, (v) => e.technologies = v, cv),
                      cvBoundField('Link', e.link, (v) => e.link = v, cv),
                      cvBoundField('Açıklama', e.description, (v) => e.description = v, cv,
                          maxLines: 3),
                    ],
                  ),
                ),
              ],
            ),
          CvSection.skills => Column(
              children: [
                CvSectionHeader(
                  title: 'Beceriler',
                  onAdd: () {
                    cv.data.skills.add(CvSkill(id: const Uuid().v4()));
                    cv.touch();
                  },
                ),
                ...cv.data.skills.map(
                  (e) => CvExpandCard(
                    key: ValueKey(e.id),
                    title: e.name.isEmpty ? 'Beceri' : e.name,
                    subtitle: e.level,
                    initiallyExpanded: false,
                    onDelete: () {
                      cv.data.skills.remove(e);
                      cv.touch();
                    },
                    children: [
                      CvSkillEditor(skill: e, cv: cv),
                    ],
                  ),
                ),
              ],
            ),
          CvSection.languages => Column(
              children: [
                CvSectionHeader(
                  title: 'Diller',
                  onAdd: () {
                    cv.data.languages.add(CvLanguage(id: const Uuid().v4()));
                    cv.touch();
                  },
                ),
                ...cv.data.languages.map(
                  (e) => CvExpandCard(
                    key: ValueKey(e.id),
                    title: e.language.isEmpty ? 'Dil' : e.language,
                    subtitle: e.level,
                    initiallyExpanded: false,
                    onDelete: () {
                      cv.data.languages.remove(e);
                      cv.touch();
                    },
                    children: [
                      CvLanguageEditor(language: e, cv: cv),
                    ],
                  ),
                ),
              ],
            ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

class CvExportPanel extends StatelessWidget {
  const CvExportPanel({super.key, required this.cv});

  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return ListenableBuilder(
      listenable: cv,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.navy.withValues(alpha: 0.06),
                    AppColors.cyan.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ATS PDF çıktısı',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'PDF indirmek zorunlu değil — önce kaydedebilir, sonra dil seçip oluşturabilirsin.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _languagePicker(context, auth),
            const SizedBox(height: 14),
            _themePicker(context, auth),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: cv.busy
                  ? null
                  : () async {
                      final ok = await cv.generateAts(auth: auth);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? (cv.status ?? 'PDF hazır') : (cv.error ?? 'Hata'),
                          ),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    },
              icon: cv.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(cv.busy ? 'AI çalışıyor…' : 'PDF Oluştur & İndir'),
            ),
            if (cv.error != null) ...[
              const SizedBox(height: 8),
              Text(cv.error!, style: const TextStyle(color: AppColors.crimson)),
            ],
            if (cv.exports.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'Önceki CV\'lerim',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              ...cv.exports.map(
                (e) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(e.languageName),
                    subtitle: Text(_fmtDate(e.createdAt)),
                    trailing: IconButton(
                      tooltip: 'Tekrar indir',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: () => cv.redownload(e),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _languagePicker(BuildContext context, AuthProvider auth) {
    final plus = context.watch<PlusProvider>();
    final user = auth.user;
    final allLangs =
        user != null && user.isPlusActive && plus.config.features.cvAllLanguages;
    final list = allLangs
        ? kCvWorldLanguages
        : kCvWorldLanguages.where((l) => l.code == 'tr' || l.code == 'en').toList();
    final items = !list.any((l) => l.code == cv.selectedLanguage.code)
        ? [...list, cv.selectedLanguage]
        : list;

    return DropdownButtonFormField<CvLanguageOption>(
      // ignore: deprecated_member_use
      value: cv.selectedLanguage,
      decoration: InputDecoration(
        labelText: 'ATS çıktı dili',
        prefixIcon: const Icon(Icons.translate),
        helperText: allLangs
            ? 'Plus: tüm diller'
            : 'Ücretsiz: Türkçe / English',
      ),
      items: items
          .map(
            (l) => DropdownMenuItem(
              value: l,
              child: Text('${l.name} (${l.code})'),
            ),
          )
          .toList(),
      onChanged: (v) async {
        if (v == null) return;
        if (!allLangs && v.code != 'tr' && v.code != 'en') {
          await requirePlus(context, featureLabel: 'Tüm CV dilleri');
          return;
        }
        cv.setLanguage(v);
      },
    );
  }

  Widget _themePicker(BuildContext context, AuthProvider auth) {
    final plus = context.watch<PlusProvider>();
    final user = auth.user;
    final themeOk =
        user != null && user.isPlusActive && plus.config.features.cvTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Tema rengi',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (!themeOk) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => requirePlus(context, featureLabel: 'CV tema rengi'),
                child: const Text('Plus'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kCvThemePalette.map((swatch) {
            final c = swatch.argb;
            final selected = cv.accentArgb == c;
            return InkWell(
              onTap: () async {
                if (!themeOk) {
                  await requirePlus(context, featureLabel: 'CV tema rengi');
                  return;
                }
                await cv.setAccentArgb(c);
              },
              borderRadius: BorderRadius.circular(20),
              child: Opacity(
                opacity: themeOk ? 1 : 0.45,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.navy : Colors.black26,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

Future<void> showCvExportSheet(BuildContext context, CvProvider cv) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.paddingOf(ctx).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Yeni PDF oluştur',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            CvExportPanel(cv: cv),
          ],
        ),
      ),
    ),
  );
}
