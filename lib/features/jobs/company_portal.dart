import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/breakpoints.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import 'company_applicant_widgets.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

/// Firma Online — temiz kurumsal işveren paneli (kullanım odaklı).
class CompanyPortalShell extends StatelessWidget {
  const CompanyPortalShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.navy,
          textColor: AppColors.textPrimary,
        ),
        dividerColor: AppColors.border,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      child: child,
    );
  }
}

class CompanyLoginScreen extends StatefulWidget {
  const CompanyLoginScreen({super.key});

  @override
  State<CompanyLoginScreen> createState() => _CompanyLoginScreenState();
}

class _CompanyLoginScreenState extends State<CompanyLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyPortalShell(
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCircleLogo(logo: AppLogo.ays, size: 64),
                    const SizedBox(height: 12),
                    Text(
                      'Firma Online',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'İlan yönetimi · öğrenci CV tarama · teklif',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'İş e-postası'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Şifre'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Firma hesapları yalnızca ana admin tarafından açılır. Kayıt kapalıdır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final auth = context.read<AuthProvider>();
                          final match = auth.directory.where(
                            (u) =>
                                u.role == UserRole.company &&
                                u.email.toLowerCase() ==
                                    _email.text.trim().toLowerCase(),
                          );
                          if (match.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Bu e-posta ile firma hesabı yok. Admin hesabı açmalı.',
                                ),
                              ),
                            );
                            return;
                          }
                          final companyUser = match.first;
                          final ok = await auth.signIn(
                            email: _email.text,
                            password: _password.text,
                          );
                          if (!context.mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(auth.error ?? 'Giriş başarısız'),
                              ),
                            );
                            return;
                          }
                          await context.read<JobsProvider>().companyLogin(
                                email: companyUser.email,
                                password: _password.text,
                                companyName: companyUser.fullName,
                                userId: auth.user?.id ?? companyUser.id,
                              );
                          if (context.mounted) context.go('/firma/dashboard');
                        },
                        child: const Text('Panele gir'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Öğrenci uygulamasına dön'),
                    ),
                    Text(
                      '${AppInfo.developer} · ${AppInfo.author}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CompanyDashboardScreen extends StatelessWidget {
  const CompanyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final jobs = context.watch<JobsProvider>();
    if (jobs.company == null) {
      return const CompanyLoginScreen();
    }

    return CompanyPortalShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppBreakpoints.wide;
          final openCount =
              jobs.companyJobs.where((j) => j.status == JobStatus.open).length;
          final applicants = jobs.companyJobs
              .fold<int>(0, (n, j) => n + j.applicantIds.length);

          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const AppCircleLogo(logo: AppLogo.ays, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jobs.company!.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Text(
                          'Firma Online · işveren paneli',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (jobs.status != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: Text(
                        jobs.status!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Kampüs akışı',
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.home_outlined),
                ),
                IconButton(
                  tooltip: 'Çıkış',
                  onPressed: () async {
                    jobs.companyLogout();
                    await context.read<AuthProvider>().signOut();
                    if (context.mounted) context.go('/home');
                  },
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => context.push('/firma/job/new'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni ilan'),
            ),
            body: Column(
              children: [
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FirmaStat(
                            label: 'Açık ilan',
                            value: '$openCount',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FirmaStat(
                            label: 'Başvuru',
                            value: '$applicants',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FirmaStat(
                            label: 'Toplam ilan',
                            value: '${jobs.companyJobs.length}',
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            SizedBox(
                              width: 280,
                              child: _SideNav(jobs: jobs),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: _JobsPane(jobs: jobs)),
                          ],
                        )
                      : _JobsPane(jobs: jobs),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FirmaStat extends StatelessWidget {
  const _FirmaStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.jobs});
  final JobsProvider jobs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const Icon(Icons.work_outline),
          title: const Text('İlanlarım'),
          selected: true,
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('Öğrenci tara'),
          onTap: () => context.push('/firma/students'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Firma AI'),
          subtitle: Text(jobs.status ?? 'Başvuranları sırala'),
          onTap: () {
            final open = jobs.companyJobs.where((j) => j.status == JobStatus.open);
            if (open.isEmpty) return;
            jobs.rankApplicantsWithAi(open.first);
            context.push('/firma/ai');
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            'Firma Online',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '  ${AppInfo.developer}\n  ${AppInfo.author}',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _JobsPane extends StatelessWidget {
  const _JobsPane({required this.jobs});
  final JobsProvider jobs;

  @override
  Widget build(BuildContext context) {
    final list = jobs.companyJobs;
    if (list.isEmpty) {
      return const Center(child: Text('Henüz ilan yok. Yeni ilan oluştur.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final job = list[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ExpansionTile(
            collapsedIconColor: AppColors.textSecondary,
            iconColor: AppColors.navy,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Text(job.title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              '${job.status.name} · ${job.applicantIds.length} başvuru · ${_type(job.type)}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            children: [
              Text(job.description),
              const SizedBox(height: 8),
              Text(
                'Gereksinimler: ${job.requirements}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push('/firma/job/${job.id}'),
                    child: const Text('Düzenle'),
                  ),
                  OutlinedButton(
                    onPressed: job.status == JobStatus.closed
                        ? null
                        : () => jobs.closeJob(job.id),
                    child: const Text('Kapat'),
                  ),
                  OutlinedButton(
                    onPressed: () => jobs.deleteJob(job.id),
                    child: const Text('Sil'),
                  ),
                  FilledButton.tonal(
                    onPressed: job.applicantIds.isEmpty
                        ? null
                        : () {
                            jobs.rankApplicantsWithAi(job);
                            context.push('/firma/ai');
                          },
                    child: const Text('AI sırala'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              JobApplicantsBlock(job: job),
            ],
          ),
        ),
        );
      },
    );
  }

  String _type(JobType t) => switch (t) {
        JobType.internship => 'Staj',
        JobType.fulltime => 'İş',
        JobType.parttime => 'Part-time',
      };
}

class CompanyJobEditorScreen extends StatefulWidget {
  const CompanyJobEditorScreen({super.key, this.jobId});
  final String? jobId;

  @override
  State<CompanyJobEditorScreen> createState() => _CompanyJobEditorScreenState();
}

class _CompanyJobEditorScreenState extends State<CompanyJobEditorScreen> {
  late JobListing job;
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late final TextEditingController _req;
  late final TextEditingController _loc;

  @override
  void initState() {
    super.initState();
    final jobs = context.read<JobsProvider>();
    if (widget.jobId == null || widget.jobId == 'new') {
      job = jobs.newDraft();
    } else {
      job = jobs.companyJobs.firstWhere(
        (j) => j.id == widget.jobId,
        orElse: jobs.newDraft,
      );
    }
    _title = TextEditingController(text: job.title);
    _desc = TextEditingController(text: job.description);
    _req = TextEditingController(text: job.requirements);
    _loc = TextEditingController(text: job.location);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _req.dispose();
    _loc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyPortalShell(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.jobId == 'new' ? 'Yeni ilan' : 'İlanı düzenle')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Başlık'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<JobType>(
                  // ignore: deprecated_member_use
                  value: job.type,
                  items: JobType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => job.type = v ?? job.type),
                  decoration: const InputDecoration(labelText: 'Tür'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _loc,
                  decoration: const InputDecoration(labelText: 'Konum'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _desc,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _req,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Gereksinimler'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    job.title = _title.text.trim();
                    job.description = _desc.text.trim();
                    job.requirements = _req.text.trim();
                    job.location = _loc.text.trim();
                    if (job.title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('İlan başlığı gerekli')),
                      );
                      return;
                    }
                    final jobsProv = context.read<JobsProvider>();
                    final notif = context.read<NotificationProvider>();
                    final auth = context.read<AuthProvider>();
                    await jobsProv.saveJob(
                      job,
                      notifications: notif,
                      students: auth.directory,
                      notifyStudents: true,
                    );
                    if (!context.mounted) return;
                    final msg = jobsProv.status ?? 'İlan kaydedildi';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                    context.go('/firma/dashboard');
                  },
                  child: const Text('Yayınla & bildir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CompanyStudentsScreen extends StatefulWidget {
  const CompanyStudentsScreen({super.key});

  @override
  State<CompanyStudentsScreen> createState() => _CompanyStudentsScreenState();
}

class _CompanyStudentsScreenState extends State<CompanyStudentsScreen> {
  final _q = TextEditingController();
  final _mail = TextEditingController();
  final _offer = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    _mail.dispose();
    _offer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final jobs = context.watch<JobsProvider>();
    final students = auth.searchUsers(_q.text).where((u) => !u.isCommunity).toList();

    return CompanyPortalShell(
      child: Scaffold(
        appBar: AppBar(title: const Text('Öğrenci tarama')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'İsim / handle ara',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, i) {
                  final s = students[i];
                  return ListTile(
                    title: Text(s.fullName),
                    subtitle: Text('${s.handle} · ${s.bio}'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'CV-AI profili',
                          onPressed: () => context.push('/user/${s.id}'),
                          icon: const Icon(Icons.description_outlined),
                        ),
                        IconButton(
                          tooltip: 'Mail gönder',
                          onPressed: () async {
                            _mail.text =
                                'Merhaba ${s.firstName}, firmamız sizi değerlendirmek istiyor.';
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('Mail · ${s.email}'),
                                content: TextField(
                                  controller: _mail,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    labelText: 'Mesaj',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('İptal'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Gönder'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await jobs.emailStudent(
                                toEmail: s.email,
                                subject: '${jobs.company?.name} · KampüsteyimAPP',
                                html: '<p>${_mail.text}</p><p>${AppInfo.developer}</p>',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(jobs.status ?? 'Gönderildi')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.mail_outline),
                        ),
                        IconButton(
                          tooltip: 'Teklif gönder',
                          onPressed: () async {
                            _offer.text =
                                'Sizi staj / iş görüşmesine davet ediyoruz.';
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Direkt teklif'),
                                content: TextField(
                                  controller: _offer,
                                  maxLines: 4,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('İptal'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Gönder'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await jobs.sendOffer(
                                studentId: s.id,
                                message: _offer.text,
                                notifications:
                                    context.read<NotificationProvider>(),
                                auth: context.read<AuthProvider>(),
                              );
                            }
                          },
                          icon: const Icon(Icons.handshake_outlined),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompanyAiScreen extends StatelessWidget {
  const CompanyAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final jobs = context.watch<JobsProvider>();
    final auth = context.watch<AuthProvider>();
    return CompanyPortalShell(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Firma AI · Aday sıralaması'),
          backgroundColor: AppColors.surface,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (jobs.status != null)
              Text(jobs.status!, style: const TextStyle(color: AppColors.cyan)),
            const SizedBox(height: 8),
            if (jobs.busy) const LinearProgressIndicator(),
            if (jobs.ranked.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'Bir ilandan “AI sırala” seçerek başvuranları gerekçeli skorla sıralayın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...jobs.ranked.map((r) {
                final user = auth.findUser(r.studentId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
                              CircleAvatar(
                                backgroundColor: AppColors.navy,
                                child: Text(
                                  '${r.score.round()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (r.headline.isNotEmpty)
                                      Text(
                                        r.headline,
                                        style: const TextStyle(
                                          color: AppColors.cyan,
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                r.hasCv ? 'CV var' : 'CV yok',
                                style: TextStyle(
                                  color: r.hasCv
                                      ? AppColors.cyan
                                      : AppColors.crimson,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(r.reason),
                          if (r.strengths.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Güçlü yönler: ${r.strengths.join(' · ')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          if (r.gaps.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Eksikler: ${r.gaps.join(' · ')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () =>
                                    context.push('/user/${r.studentId}'),
                                child: const Text('Profil'),
                              ),
                              if (user != null)
                                TextButton(
                                  onPressed: () async {
                                    await jobs.sendOffer(
                                      studentId: r.studentId,
                                      message:
                                          'Merhaba ${r.name.split(' ').first}, AI değerlendirmemizde öne çıktınız. Görüşmek isteriz.',
                                      notifications: context
                                          .read<NotificationProvider>(),
                                      auth: context.read<AuthProvider>(),
                                    );
                                  },
                                  child: const Text('Teklif gönder'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
