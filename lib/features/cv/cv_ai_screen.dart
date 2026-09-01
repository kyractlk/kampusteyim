import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../auth/data/auth_provider.dart';
import 'cv_ai_widgets.dart';
import 'cv_provider.dart';

class CvAiScreen extends StatefulWidget {
  const CvAiScreen({super.key});

  @override
  State<CvAiScreen> createState() => _CvAiScreenState();
}

class _CvAiScreenState extends State<CvAiScreen> {
  late final CvProvider _cv;

  @override
  void initState() {
    super.initState();
    _cv = CvProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) _cv.bootstrap(auth);
    });
  }

  @override
  void dispose() {
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
      child: ListenableBuilder(
        listenable: _cv,
        builder: (context, _) {
          if (!_cv.bootstrapped) {
            return Scaffold(
              appBar: AppBar(title: const Text('CV-AI')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          if (_cv.hasExistingCv) {
            return _CvHubScreen(cv: _cv);
          }
          return _CvWizardScreen(cv: _cv);
        },
      ),
    );
  }
}

/// İlk kurulum — adım adım sihirbaz.
class _CvWizardScreen extends StatefulWidget {
  const _CvWizardScreen({required this.cv});
  final CvProvider cv;

  @override
  State<_CvWizardScreen> createState() => _CvWizardScreenState();
}

class _CvWizardScreenState extends State<_CvWizardScreen> {
  final _page = PageController();
  int _step = 0;

  List<CvSection> get _steps => CvSection.wizardSteps;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;

    if (_steps[_step] == CvSection.photo && widget.cv.cvPhotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CV fotoğrafı yükleyin (bir kez yeterli).')),
      );
      return;
    }

    if (_step < _steps.length - 1) {
      await widget.cv.saveQuiet(user.id);
      setState(() => _step++);
      await _page.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // Son adım: PDF zorunlu değil — kaydet ve hub'a geç
    final ok = await widget.cv.saveQuiet(user.id, markComplete: true);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'CV kaydedildi. PDF’i istediğin zaman aşağıdan oluşturabilirsin.',
          ),
        ),
      );
    } else if (widget.cv.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.cv.error!)),
      );
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.maybePop(context);
      return;
    }
    setState(() => _step--);
    _page.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = _steps[_step];
    final isExport = section == CvSection.export;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adım ${_step + 1}/${_steps.length}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              section.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CvStepDots(current: _step, total: _steps.length),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              section.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PageView.builder(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _steps.length,
              itemBuilder: (_, i) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  children: [
                    CvSectionBody(section: _steps[i], cv: widget.cv),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              if (_step > 0)
                TextButton(onPressed: _back, child: const Text('Geri')),
              const Spacer(),
              FilledButton(
                onPressed: widget.cv.busy ? null : _next,
                child: Text(
                  isExport ? 'Kaydet ve bitir' : 'Devam',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CV oluşturulmuş — hub ekranı.
class _CvHubScreen extends StatelessWidget {
  const _CvHubScreen({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CV-AI', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'Özgeçmişiniz hazır',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _HubHero(cv: cv),
          const SizedBox(height: 20),
          const Text(
            'Ne güncellemek istiyorsunuz?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bir bölüm seçin, düzenleyin ve kaydedin. PDF yalnızca indirirken sorulur.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ...CvSection.hubSections.map(
            (s) => _HubSectionTile(
              section: s,
              cv: cv,
              onTap: () => _openSection(context, s),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => showCvExportSheet(context, cv),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Yeni PDF oluştur & indir'),
          ),
          const SizedBox(height: 6),
          Text(
            auth.user?.email.isNotEmpty == true
                ? 'PDF, ${auth.user!.email} adresine de ek olarak gönderilir.'
                : 'PDF oluşturulunca kayıtlı e-postanıza da gönderilir.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (cv.exports.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Son indirmeler',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            ...cv.exports.take(5).map(
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: auth.user == null
                ? null
                : () async {
                    await cv.refreshFromProfile(auth);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profil bilgileri güncellendi')),
                      );
                    }
                  },
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Profil bilgilerini yenile'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  void _openSection(BuildContext context, CvSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: cv,
          child: _CvSectionEditScreen(section: section),
        ),
      ),
    );
  }
}

class _HubPhoto extends StatelessWidget {
  const _HubPhoto({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    final url = cv.cvPhotoUrl;
    final name = cv.data.personalInfo.name;

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isNotEmpty
                  ? Image.network(url, fit: BoxFit.cover)
                  : const ColoredBox(
                      color: Colors.white12,
                      child: Icon(Icons.person, color: Colors.white70, size: 40),
                    ),
            ),
            Material(
              color: AppColors.lime,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: cv,
                        child: const _CvSectionEditScreen(section: CvSection.photo),
                      ),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.edit, color: AppColors.navy, size: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          name.isEmpty ? 'Öğrenci' : name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}

class _HubHero extends StatelessWidget {
  const _HubHero({required this.cv});
  final CvProvider cv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.navy.withValues(alpha: 0.92),
            AppColors.navy,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _HubPhoto(cv: cv),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.lime.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.lime, size: 16),
                SizedBox(width: 6),
                Text(
                  'CV\'niz hazır',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cv.data.personalInfo.headline.trim().isEmpty
                ? 'Bölümlerden birini seçerek güncelleyin'
                : cv.data.personalInfo.headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubSectionTile extends StatelessWidget {
  const _HubSectionTile({
    required this.section,
    required this.cv,
    required this.onTap,
  });

  final CvSection section;
  final CvProvider cv;
  final VoidCallback onTap;

  String get _badge {
    return switch (section) {
      CvSection.photo => cv.cvPhotoUrl.isNotEmpty ? '✓' : '!',
      CvSection.profile => cv.data.personalInfo.about.trim().length >= 30 ? '✓' : '·',
      CvSection.links => [
            cv.data.personalInfo.linkedin,
            cv.data.personalInfo.github,
            cv.data.personalInfo.website,
          ].any((e) => e.trim().isNotEmpty)
          ? '✓'
          : '·',
      CvSection.education => cv.data.education.isNotEmpty ? '${cv.data.education.length}' : '·',
      CvSection.experience =>
        cv.data.experiences.isNotEmpty ? '${cv.data.experiences.length}' : '·',
      CvSection.projects => cv.data.projects.isNotEmpty ? '${cv.data.projects.length}' : '·',
      CvSection.skills => cv.data.skills.isNotEmpty ? '${cv.data.skills.length}' : '·',
      CvSection.languages =>
        cv.data.languages.isNotEmpty ? '${cv.data.languages.length}' : '·',
      CvSection.motivation =>
        cv.data.personalInfo.motivationLetter.trim().isNotEmpty ? '✓' : '·',
      CvSection.export => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(section.icon, color: AppColors.navy, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        section.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _badge,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tek bölüm düzenleme — kaydet ve geri dön (PDF üretmez).
class _CvSectionEditScreen extends StatefulWidget {
  const _CvSectionEditScreen({required this.section});
  final CvSection section;

  @override
  State<_CvSectionEditScreen> createState() => _CvSectionEditScreenState();
}

class _CvSectionEditScreenState extends State<_CvSectionEditScreen> {
  bool _saving = false;

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final cv = context.read<CvProvider>();
    final user = auth.user;
    if (user == null) return;

    if (widget.section == CvSection.photo && cv.cvPhotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CV fotoğrafı yükleyin.')),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await cv.saveQuiet(user.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi')),
      );
      Navigator.pop(context);
    } else if (cv.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cv.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cv = context.watch<CvProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.section.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          CvSectionBody(section: widget.section, cv: cv),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check),
        label: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
      ),
    );
  }
}
