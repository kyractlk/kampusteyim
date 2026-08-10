import 'dart:async';

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
import 'company_mail_gate.dart';
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
                          if (!context.mounted) return;
                          // Firebase Auth oturumu ile JobsProvider’ı kesin bağla
                          if (auth.user != null) {
                            await context
                                .read<JobsProvider>()
                                .bindCompanyFromUser(auth.user!);
                          }
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

Future<void> launchFirmaAi(BuildContext context, JobsProvider jobs) async {
  final candidates = jobs.companyJobs
      .where((j) => j.status == JobStatus.open && j.applicantIds.isNotEmpty)
      .toList()
    ..sort((a, b) => b.applicantIds.length.compareTo(a.applicantIds.length));
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI sıralama için başvurulu açık ilan gerekli.'),
      ),
    );
    return;
  }
  JobListing? selected = candidates.first;
  if (candidates.length > 1 && context.mounted) {
    selected = await showDialog<JobListing>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Hangi ilanı sıralayalım?'),
        children: [
          for (final j in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, j),
              child: Text(
                '${j.title} · ${j.applicantIds.length} başvuru',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
  if (selected == null || !context.mounted) return;
  unawaited(jobs.rankApplicantsWithAi(selected));
  context.push('/firma/ai');
}

class CompanyDashboardScreen extends StatelessWidget {
  const CompanyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final jobs = context.watch<JobsProvider>();
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    final isOrganizer = me?.isEventOrganizer == true;
    if (jobs.company == null) {
      if (me != null && me.isCompany) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<JobsProvider>().bindCompanyFromUser(me);
        });
      }
      return const CompanyLoginScreen();
    }

    // Auth ile firma id sapmışsa düzelt
    final uid = me?.id;
    if (uid != null && uid.isNotEmpty && jobs.company!.id != uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<JobsProvider>().bindCompanyFromUser(me!);
      });
    }

    return CompanyPortalShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppBreakpoints.wide;
          final openCount = jobs.companyOpenCount;
          final applicants = jobs.companyApplicantCount;
          final aiReady = jobs.companyAiReadyCount;
          final closedCount = jobs.companyClosedCount;

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
                        Text(
                          isOrganizer
                              ? 'Firma Online · organizatör paneli'
                              : 'Firma Online · işveren paneli',
                          style: const TextStyle(
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
                PopupMenuButton<String>(
                  tooltip: 'Menü',
                  onSelected: (v) {
                    switch (v) {
                      case 'ads':
                        context.push('/firma/ads');
                      case 'events':
                        context.push('/firma/events');
                      case 'organizer':
                        context.push('/firma/organizer');
                      case 'students':
                        context.push('/firma/students');
                      case 'settings':
                        context.push('/firma/settings');
                      case 'ai':
                        launchFirmaAi(context, jobs);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'ads',
                      child: Text('Reklamlar'),
                    ),
                    if (isOrganizer) ...[
                      const PopupMenuItem(
                        value: 'events',
                        child: Text('Etkinlikler'),
                      ),
                      const PopupMenuItem(
                        value: 'organizer',
                        child: Text('Organizatör'),
                      ),
                    ],
                    const PopupMenuItem(
                      value: 'students',
                      child: Text('Öğrenci tara'),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Text('Mail imzası'),
                    ),
                    const PopupMenuItem(
                      value: 'ai',
                      child: Text('Firma AI'),
                    ),
                  ],
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
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.campaign_outlined, size: 18),
                          label: const Text('Reklamlar'),
                          onPressed: () => context.push('/firma/ads'),
                        ),
                        if (isOrganizer) ...[
                          ActionChip(
                            avatar: const Icon(Icons.event_outlined, size: 18),
                            label: const Text('Etkinlikler'),
                            onPressed: () => context.push('/firma/events'),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                            ),
                            label: const Text('Organizatör'),
                            onPressed: () => context.push('/firma/organizer'),
                          ),
                        ],
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 12, wide ? 16 : 12, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _FirmaStat(
                              label: 'Açık ilan',
                              value: '$openCount',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FirmaStat(
                              label: 'Başvuru',
                              value: '$applicants',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FirmaStat(
                              label: 'AI hazır',
                              value: '$aiReady',
                              onTap: aiReady > 0
                                  ? () => launchFirmaAi(context, jobs)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FirmaStat(
                              label: 'Kapalı',
                              value: '$closedCount',
                            ),
                          ),
                        ],
                      ),
                      if (!jobs.hasMailSignature) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          decoration: BoxDecoration(
                            color: AppColors.crimson.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.crimson.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.draw_outlined,
                                color: AppColors.crimson,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Mail imzanızı ayarlayın',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Mail, teklif ve ilan bildirimi için zorunlu',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () =>
                                    context.push('/firma/settings'),
                                child: const Text('Ayarla'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 260,
                              child: _SideNav(
                                jobs: jobs,
                                isOrganizer: isOrganizer,
                              ),
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
  const _FirmaStat({
    required this.label,
    required this.value,
    this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: onTap != null
              ? AppColors.navy.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.jobs, required this.isOrganizer});
  final JobsProvider jobs;
  final bool isOrganizer;

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
          leading: const Icon(Icons.campaign_outlined),
          title: const Text('Reklamlar'),
          subtitle: const Text('Görsel yükle · yayın talebi'),
          onTap: () => context.push('/firma/ads'),
        ),
        if (isOrganizer) ...[
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Etkinlikler'),
            onTap: () => context.push('/firma/events'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Organizatör'),
            subtitle: const Text('Bilet · bakiye · çekim'),
            onTap: () => context.push('/firma/organizer'),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('Öğrenci tara'),
          onTap: () => context.push('/firma/students'),
        ),
        ListTile(
          leading: const Icon(Icons.draw_outlined),
          title: const Text('Mail imzası'),
          subtitle: Text(
            jobs.hasMailSignature ? 'Hazır' : 'Ayarlanmadı',
          ),
          onTap: () => context.push('/firma/settings'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Firma AI'),
          subtitle: const Text('Başvuruları sırala'),
          onTap: () => launchFirmaAi(context, jobs),
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

class _JobsPane extends StatefulWidget {
  const _JobsPane({required this.jobs});
  final JobsProvider jobs;

  @override
  State<_JobsPane> createState() => _JobsPaneState();
}

class _JobsPaneState extends State<_JobsPane> {
  String _filter = 'all'; // all | open | closed

  @override
  Widget build(BuildContext context) {
    final jobs = widget.jobs;
    final all = jobs.companyJobs;
    final list = switch (_filter) {
      'open' => all.where((j) => j.status == JobStatus.open).toList(),
      'closed' => all.where((j) => j.status == JobStatus.closed).toList(),
      _ => all,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: Text(
                  'Tümü',
                  style: TextStyle(
                    color: _filter == 'all' ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: _filter == 'all',
                selectedColor: AppColors.navy,
                checkmarkColor: Colors.white,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  'Açık',
                  style: TextStyle(
                    color:
                        _filter == 'open' ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: _filter == 'open',
                selectedColor: AppColors.navy,
                checkmarkColor: Colors.white,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                onSelected: (_) => setState(() => _filter = 'open'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(
                  'Kapalı',
                  style: TextStyle(
                    color: _filter == 'closed'
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                selected: _filter == 'closed',
                selectedColor: AppColors.navy,
                checkmarkColor: Colors.white,
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                onSelected: (_) => setState(() => _filter = 'closed'),
              ),
              const Spacer(),
              Text(
                '${list.length} ilan',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('Bu filtrede ilan yok.'))
              : ListView.builder(
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
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          title: Text(
                            job.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${job.status.name} · ${job.applicantIds.length} başvuru · ${job.typeLabel}'
                            '${job.department.isNotEmpty ? ' · ${job.department}' : ''}'
                            ' · ${job.workModeLabel}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          children: [
                            Text(job.description),
                            const SizedBox(height: 8),
                            Text(
                              'Gereksinimler: ${job.requirements}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (job.deadline != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Son başvuru: '
                                '${job.deadline!.day.toString().padLeft(2, '0')}.'
                                '${job.deadline!.month.toString().padLeft(2, '0')}.'
                                '${job.deadline!.year}'
                                '${job.isExpired ? ' · süresi doldu' : ''}',
                                style: TextStyle(
                                  color: job.isExpired
                                      ? AppColors.crimson
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            if (job.tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: job.tags
                                    .map(
                                      (t) => Chip(
                                        label: Text(t),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      context.push('/firma/job/${job.id}'),
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
                                          unawaited(
                                            jobs.rankApplicantsWithAi(job),
                                          );
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
                ),
        ),
      ],
    );
  }
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
  late final TextEditingController _dept;
  late final TextEditingController _tags;

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
    _dept = TextEditingController(text: job.department);
    _tags = TextEditingController(text: job.tags.join(', '));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _req.dispose();
    _loc.dispose();
    _dept.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: job.deadline ?? now.add(const Duration(days: 21)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => job.deadline = picked);
  }

  @override
  Widget build(BuildContext context) {
    return CompanyPortalShell(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.jobId == 'new' ? 'Yeni ilan' : 'İlanı düzenle'),
        ),
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
                          child: Text(switch (t) {
                            JobType.internship => 'Staj',
                            JobType.fulltime => 'Tam zamanlı',
                            JobType.parttime => 'Part-time',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => job.type = v ?? job.type),
                  decoration: const InputDecoration(labelText: 'Tür'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<JobWorkMode>(
                  // ignore: deprecated_member_use
                  value: job.workMode,
                  items: JobWorkMode.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(switch (m) {
                            JobWorkMode.onsite => 'Ofis',
                            JobWorkMode.hybrid => 'Hibrit',
                            JobWorkMode.remote => 'Uzaktan',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => job.workMode = v ?? job.workMode),
                  decoration: const InputDecoration(labelText: 'Çalışma modeli'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dept,
                  decoration: const InputDecoration(
                    labelText: 'Birim / departman',
                    hintText: 'ör. Yazılım, Pazarlama',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _loc,
                  decoration: const InputDecoration(labelText: 'Konum'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    job.deadline == null
                        ? 'Son başvuru tarihi (opsiyonel)'
                        : 'Son başvuru: '
                            '${job.deadline!.day.toString().padLeft(2, '0')}.'
                            '${job.deadline!.month.toString().padLeft(2, '0')}.'
                            '${job.deadline!.year}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (job.deadline != null)
                        IconButton(
                          tooltip: 'Temizle',
                          onPressed: () => setState(() => job.deadline = null),
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        onPressed: _pickDeadline,
                        icon: const Icon(Icons.event),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Etiketler',
                    hintText: 'virgülle ayır: Flutter, SQL, İngilizce',
                  ),
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
                    job.department = _dept.text.trim();
                    job.tags = _tags.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    if (job.title.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('İlan başlığı gerekli')),
                      );
                      return;
                    }
                    final jobsProv = context.read<JobsProvider>();
                    final notif = context.read<NotificationProvider>();
                    final auth = context.read<AuthProvider>();
                    final canNotify =
                        await ensureCompanyMailSignature(context);
                    if (!context.mounted) return;
                    await jobsProv.saveJob(
                      job,
                      notifications: notif,
                      students: auth.directory,
                      notifyStudents: canNotify,
                    );
                    if (!context.mounted) return;
                    final msg = jobsProv.status == 'MAIL_SIGNATURE_REQUIRED'
                        ? 'İlan kaydedildi. Bildirim için önce mail imzasını ayarlayın.'
                        : (jobsProv.status ?? 'İlan kaydedildi');
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
                    onTap: () => openCompanyStudentCv(
                      context,
                      s.id,
                      fallbackName: s.fullName,
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'CV görüntüle',
                          onPressed: () => openCompanyStudentCv(
                            context,
                            s.id,
                            fallbackName: s.fullName,
                          ),
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
                              if (!await ensureCompanyMailSignature(context)) {
                                return;
                              }
                              if (!context.mounted) return;
                              await jobs.emailStudent(
                                toEmail: s.email,
                                subject: '${jobs.company?.name} · KampüsteyimAPP',
                                html: '<p>${_mail.text}</p>',
                                bodyText: _mail.text,
                                studentName: s.firstName,
                              );
                              if (context.mounted) {
                                final msg = jobs.status ==
                                        'MAIL_SIGNATURE_REQUIRED'
                                    ? 'Önce mail imzasını ayarlayın'
                                    : (jobs.status ?? 'Gönderildi');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(msg)),
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
                              if (!await ensureCompanyMailSignature(context)) {
                                return;
                              }
                              if (!context.mounted) return;
                              await jobs.sendOffer(
                                studentId: s.id,
                                message: _offer.text,
                                notifications:
                                    context.read<NotificationProvider>(),
                                auth: context.read<AuthProvider>(),
                                studentEmail: s.email,
                                studentName: s.firstName,
                              );
                              if (context.mounted &&
                                  jobs.status == 'MAIL_SIGNATURE_REQUIRED') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Önce mail imzasını ayarlayın',
                                    ),
                                  ),
                                );
                              }
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
    final rankedJob = jobs.jobById(jobs.lastRankedJobId);
    final aiJobs = jobs.companyJobs
        .where((j) => j.status == JobStatus.open && j.applicantIds.isNotEmpty)
        .toList();

    return CompanyPortalShell(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Firma AI · Aday sıralaması'),
          backgroundColor: AppColors.surface,
          actions: [
            TextButton(
              onPressed: () => launchFirmaAi(context, jobs),
              child: const Text('İlan seç'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (aiJobs.isNotEmpty)
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: jobs.lastRankedJobId != null &&
                        aiJobs.any((j) => j.id == jobs.lastRankedJobId)
                    ? jobs.lastRankedJobId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Sıralanacak ilan',
                  border: OutlineInputBorder(),
                ),
                items: aiJobs
                    .map(
                      (j) => DropdownMenuItem(
                        value: j.id,
                        child: Text(
                          '${j.title} (${j.applicantIds.length})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  final job = jobs.jobById(id);
                  if (job != null) unawaited(jobs.rankApplicantsWithAi(job));
                },
              ),
            if (rankedJob != null) ...[
              const SizedBox(height: 10),
              Text(
                rankedJob.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
            if (jobs.status != null) ...[
              const SizedBox(height: 8),
              Text(jobs.status!, style: const TextStyle(color: AppColors.cyan)),
            ],
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
                                onPressed: () => openCompanyStudentCv(
                                  context,
                                  r.studentId,
                                  fallbackName: r.name,
                                ),
                                child: const Text('CV görüntüle'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (!await ensureCompanyMailSignature(
                                    context,
                                  )) {
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  final auth = context.read<AuthProvider>();
                                  final user = auth.findUser(r.studentId);
                                  await jobs.sendOffer(
                                    studentId: r.studentId,
                                    message:
                                        'Merhaba ${r.name.split(' ').first}, AI değerlendirmemizde öne çıktınız. Görüşmek isteriz.',
                                    notifications: context
                                        .read<NotificationProvider>(),
                                    auth: auth,
                                    studentEmail: user?.email,
                                    studentName: r.name,
                                  );
                                  if (!context.mounted) return;
                                  final msg = jobs.status ?? 'Teklif gönderildi';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                  if (jobs.status ==
                                      'MAIL_SIGNATURE_REQUIRED') {
                                    context.push('/firma/settings');
                                  }
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

