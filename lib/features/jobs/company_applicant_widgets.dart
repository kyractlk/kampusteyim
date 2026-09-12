import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/social_widgets.dart';
import '../auth/data/auth_provider.dart';
import '../cv/cv_models.dart';
import '../cv/cv_pdf.dart';
import 'company_offer_sheet.dart';
import 'job_models.dart';
import 'jobs_provider.dart';

/// Firma panelinden öğrenci CV’sini açar; platform profiline gitmez.
Future<void> openCompanyStudentCv(
  BuildContext context,
  String studentId, {
  String? fallbackName,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );
  try {
    final jobs = context.read<JobsProvider>();
    final auth = context.read<AuthProvider>();
    final list = await jobs.loadApplicantPreviews(
      applicantIds: [studentId],
      auth: auth,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final a = list.isEmpty
        ? ApplicantPreview(
            studentId: studentId,
            name: fallbackName ?? 'Aday',
            email: '',
          )
        : list.first;
    if (!a.hasCv) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CV bulunamadı'),
          content: Text(
            '${a.name.trim().isEmpty ? 'Öğrencinin' : a.name} CV’si bulunmamaktadır.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }
    await showApplicantCvSheet(context, a);
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Öğrencinin CV’si bulunmamaktadır.')),
    );
  }
}

Future<void> showApplicantCvSheet(
  BuildContext context,
  ApplicantPreview a,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ApplicantCvDownloadSheet(applicant: a),
  );
}

class _ApplicantCvDownloadSheet extends StatefulWidget {
  const _ApplicantCvDownloadSheet({required this.applicant});
  final ApplicantPreview applicant;

  @override
  State<_ApplicantCvDownloadSheet> createState() =>
      _ApplicantCvDownloadSheetState();
}

class _ApplicantCvDownloadSheetState extends State<_ApplicantCvDownloadSheet> {
  late CvLanguageOption _lang;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _lang = kCvWorldLanguages.first;
  }

  ApplicantPreview get a => widget.applicant;

  Future<void> _downloadPdf() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'CV hazırlanıyor…';
    });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable(
        'companyResolveApplicantCv',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final result = await callable.call(<String, dynamic>{
        'studentId': a.studentId,
        'languageCode': _lang.code,
        'languageName': _lang.name,
      });
      final map = Map<String, dynamic>.from(result.data as Map? ?? {});
      final polished =
          Map<String, dynamic>.from(map['polished'] as Map? ?? {});
      if (polished.isEmpty) {
        throw Exception('CV içeriği boş');
      }
      final accentRaw = map['accentArgb'];
      final accent = accentRaw is num
          ? accentRaw.toInt()
          : kCvAccentDefault;
      final reused = map['reused'] == true;
      final fileHint =
          '${a.name.replaceAll(RegExp(r'\s+'), '_')}_CV_${_lang.code.toUpperCase()}.pdf';

      if (mounted) {
        setState(() {
          _status = reused
              ? 'Kayıtlı ${_lang.name} CV indiriliyor…'
              : 'Yeni ${_lang.name} CV oluşturuldu · açılıyor…';
        });
      }

      await CvPdfBuilder.previewAndShare(
        polished: polished,
        languageName: '${map['languageName'] ?? _lang.name}',
        languageCode: '${map['languageCode'] ?? _lang.code}',
        fileHint: fileHint,
        accentArgb: isCvAccentAllowed(accent) ? accent : kCvAccentDefault,
      );

      if (mounted) {
        setState(() => _status = reused
            ? 'Hazır CV açıldı'
            : 'CV oluşturuldu ve açıldı');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _status = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'CV alınamadı (${e.code})'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CV alınamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOffer() async {
    final sent = await showCompanyOfferComposer(
      context,
      studentId: a.studentId,
      studentName: a.name,
      studentEmail: a.email,
      studentPhoto: a.photoUrl,
      presetMessage:
          'Merhaba ${a.name.split(' ').first},\n\n'
          'Başvurunuzu değerlendirdik. Görüşme için sizi davet ediyoruz.',
    );
    if (sent && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const Text(
            'CV PDF',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'Öğrencinin ATS özgeçmişini seçtiğiniz dilde PDF olarak açın veya indirin. '
            'Bu dilde daha önce üretilmişse doğrudan o dosya kullanılır.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _lang.code,
            decoration: const InputDecoration(
              labelText: 'Dil',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final l in kCvWorldLanguages)
                DropdownMenuItem(
                  value: l.code,
                  child: Text(l.name),
                ),
            ],
            onChanged: _busy
                ? null
                : (code) {
                    if (code == null) return;
                    setState(() {
                      _lang = kCvWorldLanguages.firstWhere(
                        (l) => l.code == code,
                        orElse: () => kCvWorldLanguages.first,
                      );
                    });
                  },
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(
              _status!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy || !a.hasCv ? null : _downloadPdf,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_busy ? 'Hazırlanıyor…' : 'PDF görüntüle / indir'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _sendOffer,
            child: const Text('Teklif gönder'),
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
        color: (hasCv ? AppColors.cyan : AppColors.crimson)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        hasCv ? 'CV var' : 'CV yok',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: hasCv ? AppColors.cyan : AppColors.crimson,
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
                    a.hasCv ? 'CV PDF indirilebilir' : 'CV eksik',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CvBadge(hasCv: a.hasCv),
                    const SizedBox(width: 4),
                    const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  ],
                ),
                onTap: () => showApplicantCvSheet(context, a),
              ),
            ),
          );
        }),
      ],
    );
  }
}
