import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_info.dart';
import '../../../core/storage/student_doc_upload.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../data/auth_provider.dart';
import '../registration_security_config.dart';

/// Öğrenci belgesi onay bekleyen / reddedilen / henüz doğrulanmamış kilit ekranı.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _tckn = TextEditingController();
  final _barkod = TextEditingController();

  RegistrationSecurityConfig _security = RegistrationSecurityConfig.defaults;
  bool _showForm = false;
  String? _verifyType;
  String? _frontUrl;
  String? _backUrl;
  String? _pdfUrl;
  bool _uploading = false;
  String? _busySide;
  bool _submitting = false;

  String? _edevletTicket;
  bool _edevletBusy = false;
  String? _edevletError;
  bool _edevletFallbackUpload = false;
  bool? _edevletUserConfirmed;
  String? _edevletUniversity;
  String? _edevletFaculty;
  String? _edevletDepartment;
  String? _edevletStatus;

  @override
  void initState() {
    super.initState();
    RegistrationSecurityConfig.load().then((s) {
      if (!mounted) return;
      setState(() {
        _security = s;
        _syncDefaultType();
      });
    });
  }

  @override
  void dispose() {
    _tckn.dispose();
    _barkod.dispose();
    super.dispose();
  }

  void _syncDefaultType() {
    if (_security.allowStudentCard) {
      _verifyType = 'card';
    } else if (_security.allowStudentDocumentPdf) {
      _verifyType = 'document';
    } else {
      _verifyType = 'document';
    }
  }

  bool get _edevletParsed => (_edevletTicket ?? '').length >= 20;
  bool get _edevletOk => _edevletParsed && _edevletUserConfirmed == true;

  bool get _docsOk {
    if (_edevletOk) return true;
    if (_verifyType == 'card') {
      final needBack = _security.requireCardBothSides;
      return _frontUrl != null && (!needBack || _backUrl != null);
    }
    if (_verifyType == 'document') return _pdfUrl != null;
    return false;
  }

  Future<void> _runUpload({
    required String side,
    required Future<XFile?> Function() pick,
    required bool expectPdf,
  }) async {
    try {
      final file = await pick();
      if (file == null || !mounted) return;
      final auth = context.read<AuthProvider>();
      final user = auth.user;
      setState(() {
        _uploading = true;
        _busySide = side;
      });
      final url = await StudentDocUpload.uploadSecure(
        file: file,
        side: side,
        firstName: user?.firstName ?? 'aday',
        lastName: user?.lastName ?? 'ogrenci',
        studentNo: user?.studentNo ?? 'pending',
        security: _security,
        expectPdf: expectPdf,
      );
      if (!mounted) return;
      setState(() {
        if (side == 'front') _frontUrl = url;
        if (side == 'back') _backUrl = url;
        if (side == 'pdf') _pdfUrl = url;
        _uploading = false;
        _busySide = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _busySide = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _verifyEdevlet() async {
    final barkod = _barkod.text.trim();
    final tckn = _tckn.text.trim();
    if (barkod.isEmpty || tckn.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barkod ve 11 haneli T.C. kimlik no gerekli.')),
      );
      return;
    }
    setState(() {
      _edevletBusy = true;
      _edevletError = null;
      _edevletUserConfirmed = null;
    });
    final auth = context.read<AuthProvider>();
    final res = await auth.verifyEdevletBelge(barkod: barkod, tckn: tckn);
    if (!mounted) return;
    setState(() {
      _edevletBusy = false;
      if (res.ok && (res.ticket ?? '').length >= 20) {
        _edevletTicket = res.ticket;
        _edevletFallbackUpload = false;
        _edevletError = null;
        _edevletUniversity = res.university;
        _edevletFaculty = res.faculty;
        _edevletDepartment = res.department;
        _edevletStatus = res.studentStatus;
      } else {
        _edevletTicket = null;
        _edevletFallbackUpload = _security.allowEdevletPdfFallback;
        _edevletError = res.messages.isNotEmpty
            ? res.messages.join('\n')
            : 'Belge doğrulanamadı.';
        _edevletUniversity = null;
        _edevletFaculty = null;
        _edevletDepartment = null;
        _edevletStatus = null;
      }
    });
  }

  Future<void> _confirmEdevlet(bool yes) async {
    if (!yes) {
      setState(() {
        _edevletUserConfirmed = false;
        _edevletTicket = null;
        _edevletFallbackUpload = _security.allowEdevletPdfFallback;
      });
      return;
    }
    final ticket = _edevletTicket;
    if (ticket == null) return;
    setState(() {
      _edevletUserConfirmed = true;
      _submitting = true;
    });
    final ok = await context.read<AuthProvider>().completeEdevletVerification(ticket);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      context.go(context.read<AuthProvider>().homeRoute);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.read<AuthProvider>().error ?? 'e-Devlet kayda işlenemedi',
        ),
      ),
    );
  }

  Future<void> _submitDocs() async {
    if (_edevletOk) {
      await _confirmEdevlet(true);
      return;
    }
    if (!_docsOk || _verifyType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doğrulama adımlarını tamamla.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().resubmitStudentVerification(
          verificationType: _verifyType!,
          studentIdFrontUrl: _frontUrl,
          studentIdBackUrl: _backUrl,
          studentIdDocUrl: _pdfUrl ?? _frontUrl,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (ok) _showForm = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Belgen gönderildi. İnceleme kuyruğuna alındı.'
              : (context.read<AuthProvider>().error ?? 'Gönderilemedi'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    _security = auth.registrationSecurity;

    if (user != null && !auth.mustCompleteStudentVerification) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(auth.homeRoute);
      });
    }

    final rejected = user?.isAccountRejected == true;
    final pending = user?.isAccountPending == true;
    final neverVerified = user != null &&
        !user.isStudentIdentityVerified &&
        !pending &&
        !rejected;
    final reason = user?.registrationRejectReason.trim() ?? '';
    final showForm = rejected || neverVerified || _showForm;

    final title = rejected
        ? 'Başvurun reddedildi'
        : pending
            ? 'Onay bekleniyor'
            : 'Öğrenci doğrulaması gerekli';
    final body = rejected
        ? (reason.isNotEmpty
            ? 'Sebep: $reason\n\nSistemdeki güncel doğrulama adımlarını tamamla; çıkış yapmana gerek yok.'
            : 'Öğrenci belgen veya bilgiler eşleşmedi. Güncel doğrulama prosedürünü uygula.')
        : pending
            ? 'Öğrenci belgen incelenirken ${AppInfo.appName}’e erişimin kilitli. '
                'Onay veya red kararı e-posta ve cihaz bildirimiyle iletilir.'
            : 'Hesabın doğrulanmamış. Sistemde öğrenci doğrulaması açık; '
                'ilgili prosedürü tamamlamadan uygulamaya devam edemezsin.';

    return GradientScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            const BrandHeader(compact: true, showAys: false),
            const SizedBox(height: 36),
            Icon(
              rejected
                  ? Icons.cancel_outlined
                  : pending
                      ? Icons.hourglass_top_rounded
                      : Icons.verified_user_outlined,
              size: 56,
              color: rejected ? AppColors.crimson : AppColors.cyan,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _security.verificationMode.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showForm) ...[
              const SizedBox(height: 24),
              _VerificationPanel(
                security: _security,
                tckn: _tckn,
                barkod: _barkod,
                verifyType: _verifyType,
                frontUrl: _frontUrl,
                backUrl: _backUrl,
                pdfUrl: _pdfUrl,
                uploading: _uploading,
                busySide: _busySide,
                submitting: _submitting,
                edevletBusy: _edevletBusy,
                edevletError: _edevletError,
                edevletFallback: _edevletFallbackUpload,
                edevletParsed: _edevletParsed,
                edevletOk: _edevletOk,
                edevletConfirmed: _edevletUserConfirmed,
                edevletUniversity: _edevletUniversity,
                edevletFaculty: _edevletFaculty,
                edevletDepartment: _edevletDepartment,
                edevletStatus: _edevletStatus,
                onType: (t) => setState(() {
                  _verifyType = t;
                  _frontUrl = null;
                  _backUrl = null;
                  _pdfUrl = null;
                }),
                onUpload: _runUpload,
                onVerifyEdevlet: _verifyEdevlet,
                onConfirmEdevlet: _confirmEdevlet,
                onSubmit: _submitDocs,
                onCancel: neverVerified || rejected
                    ? null
                    : () => setState(() => _showForm = false),
              ),
            ] else ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => setState(() {
                  _showForm = true;
                  _syncDefaultType();
                }),
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Doğrulamayı tamamla'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () async {
                await auth.signOut();
                if (context.mounted) context.go('/login');
              },
              child: const Text('Çıkış yap'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationPanel extends StatelessWidget {
  const _VerificationPanel({
    required this.security,
    required this.tckn,
    required this.barkod,
    required this.verifyType,
    required this.frontUrl,
    required this.backUrl,
    required this.pdfUrl,
    required this.uploading,
    required this.busySide,
    required this.submitting,
    required this.edevletBusy,
    required this.edevletError,
    required this.edevletFallback,
    required this.edevletParsed,
    required this.edevletOk,
    required this.edevletConfirmed,
    required this.edevletUniversity,
    required this.edevletFaculty,
    required this.edevletDepartment,
    required this.edevletStatus,
    required this.onType,
    required this.onUpload,
    required this.onVerifyEdevlet,
    required this.onConfirmEdevlet,
    required this.onSubmit,
    this.onCancel,
  });

  final RegistrationSecurityConfig security;
  final TextEditingController tckn;
  final TextEditingController barkod;
  final String? verifyType;
  final String? frontUrl;
  final String? backUrl;
  final String? pdfUrl;
  final bool uploading;
  final String? busySide;
  final bool submitting;
  final bool edevletBusy;
  final String? edevletError;
  final bool edevletFallback;
  final bool edevletParsed;
  final bool edevletOk;
  final bool? edevletConfirmed;
  final String? edevletUniversity;
  final String? edevletFaculty;
  final String? edevletDepartment;
  final String? edevletStatus;
  final ValueChanged<String> onType;
  final Future<void> Function({
    required String side,
    required Future<XFile?> Function() pick,
    required bool expectPdf,
  }) onUpload;
  final VoidCallback onVerifyEdevlet;
  final ValueChanged<bool> onConfirmEdevlet;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cardOk = security.allowStudentCard;
    final pdfOk = security.allowStudentDocumentPdf;
    final edevletOkFlag = security.allowEdevlet;
    final showDocs = security.verificationMode == RegVerificationMode.documentOnly ||
        edevletFallback ||
        (!edevletOkFlag && (cardOk || pdfOk));
    final showTypePicker = showDocs && !edevletOkFlag && cardOk && pdfOk;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Doğrulama prosedürü',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (edevletOkFlag) ...[
              const SizedBox(height: 12),
              TextField(
                controller: barkod,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'e-Devlet barkod',
                  hintText: 'YOKOG…',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tckn,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: 'T.C. kimlik no',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: edevletBusy || submitting ? null : onVerifyEdevlet,
                icon: edevletBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.policy_outlined),
                label: Text(
                  edevletBusy ? 'Doğrulanıyor…' : 'e-Devlet ile doğrula',
                ),
              ),
              if (edevletError != null) ...[
                const SizedBox(height: 8),
                Text(edevletError!, style: const TextStyle(color: AppColors.crimson)),
              ],
              if (edevletParsed) ...[
                const SizedBox(height: 12),
                Text(
                  [
                    if (edevletStatus != null) edevletStatus,
                    if (edevletUniversity != null) edevletUniversity,
                    if (edevletFaculty != null) edevletFaculty,
                    if (edevletDepartment != null) edevletDepartment,
                  ].whereType<String>().join('\n'),
                  style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
                ),
                if (edevletConfirmed != true) ...[
                  const SizedBox(height: 8),
                  const Text('Bu bilgiler sana mı ait?'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: submitting ? null : () => onConfirmEdevlet(true),
                          child: const Text('Evet, onayla'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: submitting ? null : () => onConfirmEdevlet(false),
                          child: const Text('Hayır'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
            if (showTypePicker) ...[
              const SizedBox(height: 12),
              _Choice(
                selected: verifyType == 'card',
                label: 'Öğrenci kartı',
                onTap: () => onType('card'),
              ),
              const SizedBox(height: 8),
              _Choice(
                selected: verifyType == 'document',
                label: 'PDF belge',
                onTap: () => onType('document'),
              ),
            ],
            if (showDocs && verifyType == 'card' && cardOk) ...[
              const SizedBox(height: 12),
              _UploadRow(
                label: 'Ön yüz',
                done: frontUrl != null,
                busy: uploading && busySide == 'front',
                onGallery: () => onUpload(
                  side: 'front',
                  pick: StudentDocUpload.pickCardImage,
                  expectPdf: false,
                ),
                onCamera: () => onUpload(
                  side: 'front',
                  pick: StudentDocUpload.captureCardImage,
                  expectPdf: false,
                ),
              ),
              if (security.requireCardBothSides) ...[
                const SizedBox(height: 8),
                _UploadRow(
                  label: 'Arka yüz',
                  done: backUrl != null,
                  busy: uploading && busySide == 'back',
                  onGallery: () => onUpload(
                    side: 'back',
                    pick: StudentDocUpload.pickCardImage,
                    expectPdf: false,
                  ),
                  onCamera: () => onUpload(
                    side: 'back',
                    pick: StudentDocUpload.captureCardImage,
                    expectPdf: false,
                  ),
                ),
              ],
            ],
            if (showDocs &&
                (verifyType == 'document' || edevletFallback) &&
                pdfOk) ...[
              const SizedBox(height: 12),
              _UploadRow(
                label: 'PDF',
                done: pdfUrl != null,
                busy: uploading && busySide == 'pdf',
                pdfOnly: true,
                onGallery: () => onUpload(
                  side: 'pdf',
                  pick: StudentDocUpload.pickPdf,
                  expectPdf: true,
                ),
              ),
            ],
            if (!edevletOk && showDocs) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: submitting || uploading ? null : onSubmit,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('İncelemeye gönder'),
              ),
            ],
            if (onCancel != null)
              TextButton(onPressed: onCancel, child: const Text('Vazgeç')),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.cyan.withValues(alpha: 0.12)
          : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.cyan : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({
    required this.label,
    required this.done,
    required this.busy,
    required this.onGallery,
    this.onCamera,
    this.pdfOnly = false,
  });

  final String label;
  final bool done;
  final bool busy;
  final VoidCallback onGallery;
  final VoidCallback? onCamera;
  final bool pdfOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? AppColors.lime : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.upload_file_outlined,
                size: 18,
                color: done ? AppColors.lime : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (busy) ...[
                const Spacer(),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (!done && !busy) ...[
            const SizedBox(height: 8),
            if (!pdfOnly && onCamera != null)
              FilledButton.tonal(
                onPressed: onCamera,
                child: const Text('Kamera'),
              ),
            if (!pdfOnly && onCamera != null) const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onGallery,
              child: Text(pdfOnly ? 'PDF seç' : 'Galeriden seç'),
            ),
          ],
        ],
      ),
    );
  }
}
