import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/brand_svgs.dart';
import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import 'cv_models.dart';
import 'cv_provider.dart';

class CvAiScreen extends StatefulWidget {
  const CvAiScreen({super.key});

  @override
  State<CvAiScreen> createState() => _CvAiScreenState();
}

class _CvAiScreenState extends State<CvAiScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final CvProvider _cv;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _cv = CvProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) {
        _cv.bootstrap(auth);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _cv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('CV-AI')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => AuthGate.requireAuth(
              context,
              message: 'CV-AI için giriş yapmalısın.',
            ),
            child: const Text('Giriş Yap'),
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _cv,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CV-AI', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(
                'ATS özgeçmiş · motivasyon · foto yükle',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Profil'),
              Tab(text: 'Deneyim'),
              Tab(text: 'Üret / İndir'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Kaydet',
              onPressed: () async {
                await _cv.saveRemote(auth.user!.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_cv.status ?? 'Kaydedildi')),
                );
              },
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _PersonalTab(cv: _cv),
            _CareerTab(cv: _cv),
            _GenerateTab(cv: _cv),
          ],
        ),
      ),
    );
  }
}

class _PersonalTab extends StatelessWidget {
  const _PersonalTab({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final p = cv.data.personalInfo;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
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
                'Kişisel bilgiler platform profilinden otomatik dolar.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ad, e-posta, telefon, öğrenci no ve şehir CV’ye tekrar yazılmaz.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: auth.user == null
                    ? null
                    : () => cv.refreshFromProfile(auth),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Profilden yenile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.surface,
                    backgroundImage: p.photoUrl.trim().isNotEmpty
                        ? NetworkImage(p.photoUrl.trim())
                        : null,
                    child: p.photoUrl.trim().isEmpty
                        ? const Icon(Icons.person, size: 44)
                        : null,
                  ),
                  Material(
                    color: AppColors.navy,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        final user = auth.user;
                        if (user == null) return;
                        try {
                          final file = await MediaUpload.pickImage();
                          if (file == null) return;
                          final authUid = fa.FirebaseAuth.instance.currentUser?.uid ??
                              user.id;
                          final url = await MediaUpload.uploadXFile(
                            file: file,
                            folder: 'cv/$authUid',
                            firstName: user.firstName,
                            lastName: user.lastName,
                            studentNo: user.studentNo,
                            isVideo: false,
                          );
                          p.photoUrl = url;
                          cv.touch();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
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
              Text(
                [p.email, p.phone, p.studentNo, p.address]
                    .where((e) => e.trim().isNotEmpty)
                    .join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'CV fotoğrafı ayrı yüklenir (max 75 MB). Profil fotosundan bağımsızdır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _field('Ünvan / Headline', p.headline, (v) => p.headline = v, cv),
        _field('Bölüm', p.department, (v) => p.department = v, cv),
        _field('Sınıf', p.classYear, (v) => p.classYear = v, cv),
        _field('LinkedIn', p.linkedin, (v) => p.linkedin = v, cv,
            brandSvg: BrandSvgs.linkedin, linkKind: 'linkedin'),
        _field('GitHub', p.github, (v) => p.github = v, cv,
            brandSvg: BrandSvgs.github, linkKind: 'github'),
        _field('Website', p.website, (v) => p.website = v, cv,
            brandSvg: BrandSvgs.website, linkKind: 'website'),
        _field('Hakkımda / Özet', p.about, (v) => p.about = v, cv, maxLines: 5),
        _field(
          'Motivasyon mektubu',
          p.motivationLetter,
          (v) => p.motivationLetter = v,
          cv,
          maxLines: 7,
        ),
        const Text(
          'Motivasyon mektubu firmalara başvurunda görünür; ATS PDF’te özetin altında yer alır.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _CareerTab extends StatelessWidget {
  const _CareerTab({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cv,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hızlı yol: Üret sekmesindeki serbest nota yapıştır.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'AI yapılandırır ve seçilen dile çevirir. Aşağıdaki kartlar isteğe bağlı detay içindir.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _SectionHeader(
              title: 'Eğitim',
              onAdd: () {
                cv.data.education.add(CvEducation(id: const Uuid().v4()));
                cv.touch();
              },
            ),
            ...cv.data.education.map(
              (e) => _ExpandCard(
                title: e.school.isEmpty ? 'Okul' : e.school,
                subtitle: [
                  e.degree,
                  e.field,
                ].where((s) => s.trim().isNotEmpty).join(' · '),
                onDelete: () {
                  cv.data.education.remove(e);
                  cv.touch();
                },
                children: [
                  _field('Okul', e.school, (v) => e.school = v, cv),
                  _field('Derece', e.degree, (v) => e.degree = v, cv),
                  _field('Alan', e.field, (v) => e.field = v, cv),
                  _field('Başlangıç', e.startDate, (v) => e.startDate = v, cv),
                  _field('Bitiş', e.endDate, (v) => e.endDate = v, cv),
                  _field('GPA', e.gpa, (v) => e.gpa = v, cv),
                  _field('Açıklama', e.description, (v) => e.description = v, cv,
                      maxLines: 3),
                ],
              ),
            ),
            _SectionHeader(
              title: 'İş Deneyimi',
              onAdd: () {
                cv.data.experiences.add(CvExperience(id: const Uuid().v4()));
                cv.touch();
              },
            ),
            ...cv.data.experiences.map(
              (e) => _ExpandCard(
                title: e.company.isEmpty ? 'Şirket' : e.company,
                subtitle: e.position,
                onDelete: () {
                  cv.data.experiences.remove(e);
                  cv.touch();
                },
                children: [
                  _field('Şirket', e.company, (v) => e.company = v, cv),
                  _field('Pozisyon', e.position, (v) => e.position = v, cv),
                  _field('Başlangıç', e.startDate, (v) => e.startDate = v, cv),
                  _field('Bitiş', e.endDate, (v) => e.endDate = v, cv),
                  _field('Açıklama', e.description, (v) => e.description = v, cv,
                      maxLines: 4),
                ],
              ),
            ),
            _SectionHeader(
              title: 'Projeler',
              onAdd: () {
                cv.data.projects.add(CvProject(id: const Uuid().v4()));
                cv.touch();
              },
            ),
            ...cv.data.projects.map(
              (e) => _ExpandCard(
                title: e.name.isEmpty ? 'Proje' : e.name,
                subtitle: e.technologies,
                onDelete: () {
                  cv.data.projects.remove(e);
                  cv.touch();
                },
                children: [
                  _field('Ad', e.name, (v) => e.name = v, cv),
                  _field(
                      'Teknolojiler', e.technologies, (v) => e.technologies = v, cv),
                  _field('Link', e.link, (v) => e.link = v, cv),
                  _field('Açıklama', e.description, (v) => e.description = v, cv,
                      maxLines: 3),
                ],
              ),
            ),
            _SectionHeader(
              title: 'Beceriler',
              onAdd: () {
                cv.data.skills.add(CvSkill(id: const Uuid().v4()));
                cv.touch();
              },
            ),
            ...cv.data.skills.map(
              (e) => _ExpandCard(
                title: e.name.isEmpty ? 'Beceri' : e.name,
                subtitle: e.level,
                initiallyExpanded: false,
                onDelete: () {
                  cv.data.skills.remove(e);
                  cv.touch();
                },
                children: [
                  _field('Beceri', e.name, (v) => e.name = v, cv),
                  _field('Seviye', e.level, (v) => e.level = v, cv),
                ],
              ),
            ),
            _SectionHeader(
              title: 'Diller',
              onAdd: () {
                cv.data.languages.add(CvLanguage(id: const Uuid().v4()));
                cv.touch();
              },
            ),
            ...cv.data.languages.map(
              (e) => _ExpandCard(
                title: e.language.isEmpty ? 'Dil' : e.language,
                subtitle: e.level,
                initiallyExpanded: false,
                onDelete: () {
                  cv.data.languages.remove(e);
                  cv.touch();
                },
                children: [
                  _field('Dil', e.language, (v) => e.language = v, cv),
                  _field('Seviye (CEFR)', e.level, (v) => e.level = v, cv),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

class _GenerateTab extends StatelessWidget {
  const _GenerateTab({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return ListenableBuilder(
      listenable: cv,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Serbest not yaz veya yapıştır → dil seç → canlı AI yapılandırır, '
              'seçilen dilin imla kurallarıyla tam çeviri yapar → PDF indir.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: cv.data.rawNotes,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Hızlı not / yapıştır',
                alignLabelWithHint: true,
                hintText:
                    'Örn: Gaziantep Üni Bilgisayar Müh 3. sınıf. Flutter stajı AYS Tech’te… '
                    'Projeler: … Beceriler: … İngilizce B2…',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 120),
                  child: Icon(Icons.notes_outlined),
                ),
              ),
              onChanged: cv.setRawNotes,
            ),
            const SizedBox(height: 8),
            const Text(
              'Kaynak dil önemli değil — çıktı her zaman seçilen ATS dilinde olur '
              '(sadece başlıklar değil, tüm metinler).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CvLanguageOption>(
              // ignore: deprecated_member_use
              value: cv.selectedLanguage,
              decoration: const InputDecoration(
                labelText: 'ATS çıktı dili (resmi çeviri)',
                prefixIcon: Icon(Icons.translate),
              ),
              items: kCvWorldLanguages
                  .map(
                    (l) => DropdownMenuItem(
                      value: l,
                      child: Text('${l.name} (${l.code})'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) cv.setLanguage(v);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: cv.busy
                  ? null
                  : () async {
                      final ok = await cv.generateAts(auth: auth);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? (cv.status ?? 'Tamam')
                                : (cv.error ?? 'Hata'),
                          ),
                        ),
                      );
                    },
              icon: cv.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                cv.busy
                    ? 'Canlı AI çalışıyor…'
                    : 'Canlı AI · ATS CV Oluştur & İndir',
              ),
            ),
            if (cv.status != null) ...[
              const SizedBox(height: 8),
              Text(cv.status!, style: const TextStyle(color: AppColors.cyan)),
            ],
            if (cv.error != null) ...[
              const SizedBox(height: 4),
              Text(cv.error!, style: const TextStyle(color: AppColors.crimson)),
            ],
            const SizedBox(height: 24),
            Text(
              'Önceki CV\'lerim',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (cv.exports.isEmpty)
              const Text('Henüz dışa aktarım yok.')
            else
              ...cv.exports.map(
                (e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(e.languageName),
                    subtitle: Text(e.createdAt),
                    trailing: IconButton(
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () => cv.redownload(e),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Ekle'),
          ),
        ],
      ),
    );
  }
}

class _ExpandCard extends StatelessWidget {
  const _ExpandCard({
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

Widget _field(
  String label,
  String value,
  ValueChanged<String> onChanged,
  CvProvider cv, {
  int maxLines = 1,
  String? brandSvg,
  String? linkKind,
}) {
  final href = linkKind == null
      ? null
      : BrandLinkUtils.href(kind: linkKind, raw: value);

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: value,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: brandSvg == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(10),
                child: BrandSvgIcon(brandSvg, size: 22),
              ),
        prefixIconConstraints: brandSvg == null
            ? null
            : const BoxConstraints(minWidth: 44, minHeight: 44),
        suffixIcon: href == null || value.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Aç',
                onPressed: () async {
                  final uri = Uri.tryParse(href);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 18),
              ),
      ),
      onChanged: (v) {
        onChanged(v);
        cv.touch();
      },
    ),
  );
}
