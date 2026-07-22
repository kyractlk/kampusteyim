import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/social_widgets.dart';
import '../auth/data/auth_provider.dart';
import '../notifications/notification_provider.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

Future<void> showApplicantCvSheet(
  BuildContext context,
  ApplicantPreview a,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final cv = a.cvData;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Row(
                children: [
                  UserAvatar(
                    name: a.name,
                    photoUrl: a.photoUrl,
                    radius: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        if (a.headline.isNotEmpty)
                          Text(
                            a.headline,
                            style: const TextStyle(color: AppColors.cyan),
                          ),
                        Text(
                          a.email,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CvBadge(hasCv: a.hasCv),
                ],
              ),
              const SizedBox(height: 16),
              if (!a.hasCv)
                const Text(
                  'Bu adayın platformda yeterli CV kaydı yok.',
                  style: TextStyle(color: AppColors.crimson),
                )
              else ...[
                _CvSection('Hakkımda / Özet', a.about),
                _CvSection('Motivasyon mektubu', a.motivationLetter),
                if (cv != null) ...[
                  if (cv.education.isNotEmpty)
                    _CvSection(
                      'Eğitim',
                      cv.education
                          .map((e) =>
                              '• ${e.school} — ${e.degree} ${e.field}'.trim())
                          .join('\n'),
                    ),
                  if (cv.experiences.isNotEmpty)
                    _CvSection(
                      'Deneyim',
                      cv.experiences
                          .map((e) =>
                              '• ${e.position} @ ${e.company}\n  ${e.description}')
                          .join('\n\n'),
                    ),
                  if (cv.skills.isNotEmpty)
                    _CvSection(
                      'Yetkinlikler',
                      cv.skills.map((s) => '${s.name} (${s.level})').join(' · '),
                    ),
                  if (cv.projects.isNotEmpty)
                    _CvSection(
                      'Projeler',
                      cv.projects
                          .map((p) => '• ${p.name}: ${p.description}')
                          .join('\n'),
                    ),
                ],
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/user/${a.studentId}');
                      },
                      child: const Text('Platform profili'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final jobs = context.read<JobsProvider>();
                        final offer = TextEditingController(
                          text:
                              'Merhaba ${a.name.split(' ').first}, başvurunuzu değerlendirdik. Görüşme için sizi davet ediyoruz.',
                        );
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('Teklif gönder'),
                            content: TextField(
                              controller: offer,
                              maxLines: 4,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx, false),
                                child: const Text('İptal'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(dCtx, true),
                                child: const Text('Gönder'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await jobs.sendOffer(
                            studentId: a.studentId,
                            message: offer.text,
                            notifications:
                                context.read<NotificationProvider>(),
                            auth: context.read<AuthProvider>(),
                          );
                          if (context.mounted) Navigator.pop(ctx);
                        }
                        offer.dispose();
                      },
                      child: const Text('Teklif'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

class _CvSection extends StatelessWidget {
  const _CvSection(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(body),
          ),
        ],
      ),
    );
  }
}

class _CvBadge extends StatelessWidget {
  const _CvBadge({required this.hasCv});
  final bool hasCv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (hasCv ? AppColors.cyan : AppColors.crimson).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        hasCv ? 'CV var' : 'CV yok',
        style: TextStyle(
          color: hasCv ? AppColors.cyan : AppColors.crimson,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class JobApplicantsBlock extends StatefulWidget {
  const JobApplicantsBlock({super.key, required this.job});
  final JobListing job;

  @override
  State<JobApplicantsBlock> createState() => _JobApplicantsBlockState();
}

class _JobApplicantsBlockState extends State<JobApplicantsBlock> {
  List<ApplicantPreview>? _list;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JobApplicantsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.applicantIds.join() != widget.job.applicantIds.join()) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.job.applicantIds.isEmpty) {
      setState(() => _list = []);
      return;
    }
    setState(() => _loading = true);
    final jobs = context.read<JobsProvider>();
    final auth = context.read<AuthProvider>();
    final list = await jobs.loadApplicantPreviews(
      applicantIds: widget.job.applicantIds,
      auth: auth,
    );
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.job.applicantIds.isEmpty) {
      return const Text(
        'Henüz başvuru yok.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    if (_loading || _list == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Başvuranlar (${_list!.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._list!.map((a) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: UserAvatar(
                  name: a.name,
                  photoUrl: a.photoUrl,
                  radius: 22,
                ),
                title: Text(
                  a.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [
                    if (a.headline.isNotEmpty) a.headline,
                    if (a.handle.isNotEmpty) a.handle,
                    a.hasCv ? 'CV hazır' : 'CV eksik',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _CvBadge(hasCv: a.hasCv),
                onTap: () => showApplicantCvSheet(context, a),
              ),
            ),
          );
        }),
      ],
    );
  }
}
