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

/// Öğrenci belgesi onay bekleyen / reddedilen kullanıcı ekranı.
/// Reddedilenler burada özel olarak belgeyi yeniden yükleyebilir.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  RegistrationSecurityConfig _security = RegistrationSecurityConfig.defaults;
  bool _showResubmit = false;
  String? _verifyType;
  String? _frontUrl;
  String? _backUrl;
  String? _pdfUrl;
  bool _uploading = false;
  String? _busySide;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    RegistrationSecurityConfig.load().then((s) {
      if (mounted) setState(() => _security = s);
    });
  }

  bool get _docsOk {
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

  Future<void> _submitResubmit() async {
    if (!_docsOk || _verifyType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belgeleri tamamla.')),
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
      if (ok) _showResubmit = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Yeni belgen gönderildi. Tekrar inceleme kuyruğuna alındı.'
              : (context.read<AuthProvider>().error ?? 'Gönderilemedi'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (user != null && user.isAccountApproved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/home');
      });
    }

    final rejected = user?.isAccountRejected == true;
    final reason = user?.registrationRejectReason.trim() ?? '';

    return GradientScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            const BrandHeader(compact: true, showAys: false),
            const SizedBox(height: 36),
            Icon(
              rejected ? Icons.cancel_outlined : Icons.hourglass_top_rounded,
              size: 56,
              color: rejected ? AppColors.crimson : AppColors.cyan,
            ),
            const SizedBox(height: 16),
            Text(
              rejected ? 'Başvurun reddedildi' : 'Onay bekleniyor',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              rejected
                  ? (reason.isNotEmpty
                      ? 'Sebep: $reason\n\nYeni belge yükleyip tekrar başvurabilirsin; çıkış yapmana gerek yok.'
                      : 'Öğrenci belgen veya bilgiler eşleşmedi. Yeni belge yükleyip tekrar başvurabilirsin.')
                  : 'Öğrenci belgen incelenirken ${AppInfo.appName}’e sınırlı erişimin var. '
                      'Onay veya red kararı e-posta ve cihaz bildirimiyle iletilir.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            if (rejected || _showResubmit) ...[
              const SizedBox(height: 24),
              if (!_showResubmit)
                FilledButton.icon(
                  onPressed: () => setState(() {
                    _showResubmit = true;
                    _verifyType = user?.studentVerificationType;
                  }),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Belgeyi yeniden yükle'),
                )
              else
                _ResubmitPanel(
                  security: _security,
                  verifyType: _verifyType,
                  frontUrl: _frontUrl,
                  backUrl: _backUrl,
                  pdfUrl: _pdfUrl,
                  uploading: _uploading,
                  busySide: _busySide,
                  submitting: _submitting,
                  onType: (t) => setState(() {
                    _verifyType = t;
                    _frontUrl = null;
                    _backUrl = null;
                    _pdfUrl = null;
                  }),
                  onUpload: _runUpload,
                  onSubmit: _submitResubmit,
                  onCancel: () => setState(() => _showResubmit = false),
                ),
            ] else ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => setState(() {
                  _showResubmit = true;
                  _verifyType = user?.studentVerificationType;
                }),
                child: const Text('Belgeyi değiştir / yeniden gönder'),
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

class _ResubmitPanel extends StatelessWidget {
  const _ResubmitPanel({
    required this.security,
    required this.verifyType,
    required this.frontUrl,
    required this.backUrl,
    required this.pdfUrl,
    required this.uploading,
    required this.busySide,
    required this.submitting,
    required this.onType,
    required this.onUpload,
    required this.onSubmit,
    required this.onCancel,
  });

  final RegistrationSecurityConfig security;
  final String? verifyType;
  final String? frontUrl;
  final String? backUrl;
  final String? pdfUrl;
  final bool uploading;
  final String? busySide;
  final bool submitting;
  final ValueChanged<String> onType;
  final Future<void> Function({
    required String side,
    required Future<XFile?> Function() pick,
    required bool expectPdf,
  }) onUpload;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cardOk = security.allowStudentCard;
    final pdfOk = security.allowStudentDocumentPdf;

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
              'Yeni belge yükle',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (cardOk)
              _Choice(
                selected: verifyType == 'card',
                label: 'Öğrenci kartı',
                onTap: () => onType('card'),
              ),
            if (cardOk && pdfOk) const SizedBox(height: 8),
            if (pdfOk)
              _Choice(
                selected: verifyType == 'document',
                label: 'PDF belge',
                onTap: () => onType('document'),
              ),
            if (verifyType == 'card') ...[
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
            if (verifyType == 'document') ...[
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
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
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
