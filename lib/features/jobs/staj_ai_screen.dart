import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../auth/data/auth_provider.dart';
import '../cv/cv_provider.dart';
import '../notifications/notification_provider.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

class StajAiScreen extends StatefulWidget {
  const StajAiScreen({super.key});

  @override
  State<StajAiScreen> createState() => _StajAiScreenState();
}

class _StajAiScreenState extends State<StajAiScreen> {
  bool _checkedCv = false;
  bool _hasCv = false;
  _CvGateProgress _progress = const _CvGateProgress.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recheckCv());
  }

  Future<void> _recheckCv() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      if (mounted) setState(() => _checkedCv = true);
      return;
    }
    setState(() => _checkedCv = false);
    final jobs = context.read<JobsProvider>();
    await jobs.bindJobsFromFirestore();
    final cv = CvProvider();
    await cv.bootstrap(auth);
    final progress = _CvGateProgress.fromCv(cv);
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _hasCv = progress.isReady;
      _checkedCv = true;
    });
  }

  Future<void> _openCvAi() async {
    await context.push('/cv-ai');
    if (mounted) await _recheckCv();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Staj-AI')),
        body: _AuthGate(onLogin: () => AuthGate.requireAuth(context)),
      );
    }

    final jobs = context.watch<JobsProvider>();
    final offers = jobs.offersFor(auth.user!.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Staj-AI'),
        actions: [
          TextButton(
            onPressed: _openCvAi,
            child: const Text('CV-AI'),
          ),
        ],
      ),
      body: !_checkedCv
          ? const _CheckingState()
          : !_hasCv
              ? _CvRequiredGate(
                  progress: _progress,
                  onCreateCv: _openCvAi,
                  onRefresh: _recheckCv,
                )
              : RefreshIndicator(
                  onRefresh: _recheckCv,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _ReadyBanner(onEditCv: _openCvAi),
                      const SizedBox(height: 18),
                      if (offers.isNotEmpty) ...[
                        Text(
                          'Firma teklifleri',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        ...offers.map(
                          (o) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: AppColors.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.handshake_outlined,
                                    color: AppColors.navy,
                                  ),
                                ),
                                title: Text(
                                  o.companyName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(o.message),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        'Açık ilanlar',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${jobs.openJobs.length} aktif fırsat',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (jobs.openJobs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Şu an açık ilan yok. Daha sonra tekrar bak.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        ...jobs.openJobs.map((job) {
                          final applied =
                              job.applicantIds.contains(auth.user!.id);
                          return _JobTile(
                            job: job,
                            applied: applied,
                            onApply: () => _apply(job),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Future<void> _apply(JobListing job) async {
    final auth = context.read<AuthProvider>();
    final jobs = context.read<JobsProvider>();
    final gate = CvProvider();
    await gate.bootstrap(auth);
    if (!mounted) return;
    if (!gate.isReadyForJobs) {
      setState(() {
        _progress = _CvGateProgress.fromCv(gate);
        _hasCv = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Başvuru için önce CV’ni tamamla.'),
        ),
      );
      return;
    }
    final notif = context.read<NotificationProvider>();
    final ok = await jobs.apply(
      jobId: job.id,
      studentId: auth.user!.id,
      hasCv: true,
      notifications: notif,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Başvuru gönderildi' : 'Başvuru başarısız'),
      ),
    );
  }
}

class _CvGateProgress {
  const _CvGateProgress({
    required this.hasIdentity,
    required this.hasAbout,
    required this.hasEducation,
    required this.hasExperience,
    required this.hasSkills,
  });

  const _CvGateProgress.empty()
      : hasIdentity = false,
        hasAbout = false,
        hasEducation = false,
        hasExperience = false,
        hasSkills = false;

  factory _CvGateProgress.fromCv(CvProvider cv) {
    final d = cv.data;
    final p = d.personalInfo;
    return _CvGateProgress(
      hasIdentity:
          p.name.trim().isNotEmpty && p.email.trim().isNotEmpty,
      hasAbout: p.about.trim().length >= 30,
      hasEducation: d.education.isNotEmpty,
      hasExperience: d.experiences.isNotEmpty,
      hasSkills: d.skills.length >= 2,
    );
  }

  final bool hasIdentity;
  final bool hasAbout;
  final bool hasEducation;
  final bool hasExperience;
  final bool hasSkills;

  int get completed {
    var n = 0;
    if (hasIdentity) n++;
    if (hasAbout) n++;
    if (hasEducation) n++;
    if (hasExperience) n++;
    if (hasSkills) n++;
    return n;
  }

  int get total => 5;

  double get ratio => completed / total;

  bool get isReady =>
      hasIdentity && (hasAbout || hasEducation || hasExperience || hasSkills);
}

class _CheckingState extends StatelessWidget {
  const _CheckingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.navy,
              backgroundColor: AppColors.navy.withValues(alpha: 0.12),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'CV durumun kontrol ediliyor…',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Staj-AI için hazırlık adımları yükleniyor',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 280.ms);
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AppCircleLogo(logo: AppLogo.ays, size: 72),
          const SizedBox(height: 20),
          Text(
            'Staj-AI’ye hoş geldin',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'İlanları görmek ve başvurmak için önce giriş yap.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onLogin,
              child: const Text('Giriş yap'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CvRequiredGate extends StatelessWidget {
  const _CvRequiredGate({
    required this.progress,
    required this.onCreateCv,
    required this.onRefresh,
  });

  final _CvGateProgress progress;
  final VoidCallback onCreateCv;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final steps = <(bool, String, String)>[
      (progress.hasIdentity, 'Kimlik', 'Ad & e-posta profilinden gelir'),
      (progress.hasAbout, 'Özet', 'Hakkımda / motivasyon metni'),
      (progress.hasEducation, 'Eğitim', 'Okul ve bölüm bilgisi'),
      (progress.hasExperience, 'Deneyim', 'Staj veya proje deneyimi'),
      (progress.hasSkills, 'Yetkinlik', 'En az 2 beceri'),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.navy, AppColors.navySoft],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.work_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress.ratio * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Staj-AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Başvurmadan önce CV-AI ile özgeçmişini tamamla. '
                  'İlanlar ve firma eşleşmesi ancak hazır CV ile açılır.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.45,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress.ratio.clamp(0.05, 1),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    color: AppColors.cyan,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${progress.completed} / ${progress.total} adım tamam',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.06, curve: Curves.easeOutCubic),
          const SizedBox(height: 22),
          Text(
            'Hazırlık yolu',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Sırayla tamamla — kişisel bilgiler profilinden otomatik dolar.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (i) {
            final s = steps[i];
            final done = s.$1;
            final isLast = i == steps.length - 1;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: done
                                ? AppColors.lime
                                : AppColors.surfaceMuted,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: done ? AppColors.lime : AppColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            done ? Icons.check_rounded : Icons.circle,
                            size: done ? 16 : 8,
                            color: done ? Colors.white : AppColors.border,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: done
                                  ? AppColors.lime.withValues(alpha: 0.55)
                                  : AppColors.border,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.$2,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: done
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.$3,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: (60 * i).ms, duration: 320.ms)
                .slideX(begin: 0.04, curve: Curves.easeOutCubic);
          }),
          const SizedBox(height: 28),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: onCreateCv,
            child: Text(
              progress.completed == 0 ? 'CV-AI ile başla' : 'CV’yi tamamla',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          )
              .animate()
              .fadeIn(delay: 280.ms)
              .slideY(begin: 0.08, curve: Curves.easeOutCubic),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: onRefresh,
            child: const Text('Durumu yenile'),
          ),
        ],
      ),
    );
  }
}

class _ReadyBanner extends StatelessWidget {
  const _ReadyBanner({required this.onEditCv});
  final VoidCallback onEditCv;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lime.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.lime.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: AppColors.lime),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'CV’n hazır · ilanlara başvurabilirsin',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onEditCv, child: const Text('Düzenle')),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.applied,
    required this.onApply,
  });

  final JobListing job;
  final bool applied;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _typeLabel(job.type),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    job.companyName,
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                job.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                job.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                job.location,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: applied ? null : onApply,
                  child: Text(applied ? 'Başvuruldu' : 'Başvur'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(JobType t) => switch (t) {
        JobType.internship => 'Staj',
        JobType.fulltime => 'Tam zamanlı',
        JobType.parttime => 'Part-time',
      };
}
