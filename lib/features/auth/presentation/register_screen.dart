import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/storage/student_doc_upload.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../../../data/mock/mock_data.dart';
import '../../legal/consent_check_row.dart';
import '../../legal/legal_consent_models.dart';
import '../data/auth_provider.dart';
import '../registration_security_config.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _studentNo = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _emailCode = TextEditingController();

  String? _emailTicket;
  bool _emailVerified = false;
  bool _sendingCode = false;
  bool _verifyingCode = false;

  String? _city = MockData.cities.first;
  String? _university = MockData.universities.first;
  bool _obscure = true;
  int _step = 0;
  bool _kvkk = false;
  bool _marketing = false;
  LegalConsentTexts _legal = LegalConsentTexts.defaults;
  RegistrationSecurityConfig _security = RegistrationSecurityConfig.defaults;

  /// card | document
  String? _verifyType;
  String? _frontUrl;
  String? _backUrl;
  String? _pdfUrl;
  bool _uploading = false;
  String? _busySide;

  List<String> get _stepIds {
    final ids = <String>['account', 'personal', 'campus'];
    if (_security.requireStudentVerification) ids.add('docs');
    ids.add('legal');
    return ids;
  }

  List<String> get _stepLabels {
    final labels = <String>['Hesap', 'Kişisel', 'Kampüs'];
    if (_security.requireStudentVerification) labels.add('Belge');
    labels.add('Onay');
    return labels;
  }

  String get _stepId => _stepIds[_step.clamp(0, _stepIds.length - 1)];

  @override
  void initState() {
    super.initState();
    LegalConsentTexts.load().then((t) {
      if (mounted) setState(() => _legal = t);
    });
    RegistrationSecurityConfig.load().then((s) {
      if (!mounted) return;
      setState(() {
        _security = s;
        if (_step >= _stepIds.length) _step = _stepIds.length - 1;
      });
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _studentNo.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _username.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  bool get _docsOk {
    if (!_security.requireStudentVerification) return true;
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
    if (_uploading) return;
    try {
      final file = await pick();
      if (file == null || !mounted) return;

      setState(() {
        _uploading = true;
        _busySide = side;
      });
      final url = await StudentDocUpload.uploadSecure(
        file: file,
        side: side,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        studentNo: _studentNo.text.trim(),
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
      if (mounted) {
        setState(() {
          _uploading = false;
          _busySide = null;
        });
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_emailTicket == null || !_emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce e-posta doğrulama kodunu gir.')),
      );
      return;
    }
    if (!_docsOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doğrulama belgelerini tamamla.')),
      );
      return;
    }
    if (!_kvkk || !_marketing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KVKK ve pazarlama metinlerini okuyup kabul etmelisin.'),
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final require = _security.requireStudentVerification;
    final ok = await auth.register(
      email: _email.text,
      studentNo: _studentNo.text,
      password: _password.text,
      firstName: _firstName.text,
      lastName: _lastName.text,
      phone: _phone.text,
      city: _city ?? '',
      university: _university ?? '',
      username: _username.text,
      emailTicket: _emailTicket!,
      kvkkAccepted: _kvkk,
      marketingConsent: _marketing,
      requireVerification: require,
      studentVerificationType: require ? _verifyType : null,
      studentIdFrontUrl: require && _verifyType == 'card' ? _frontUrl : null,
      studentIdBackUrl: require && _verifyType == 'card' ? _backUrl : null,
      studentIdDocUrl: require && _verifyType == 'document' ? _pdfUrl : null,
    );
    if (!mounted) return;
    if (ok) {
      if (require) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Başvurun alındı. Belgen admin onayına düştü; sonuç mail ve bildirimle gelir.',
            ),
          ),
        );
        context.go('/pending-approval');
      } else {
        context.go('/home');
      }
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error!)),
      );
    }
  }

  Future<void> _sendEmailCode() async {
    if (!_email.text.contains('@')) {
      _formKey.currentState?.validate();
      return;
    }
    setState(() => _sendingCode = true);
    final auth = context.read<AuthProvider>();
    final hint = await auth.sendRegistrationEmailCode(_email.text);
    if (!mounted) return;
    setState(() {
      _sendingCode = false;
      if (hint != null) {
        _emailVerified = false;
        _emailTicket = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(hint ?? auth.error ?? 'Kod gönderilemedi')),
    );
  }

  Future<void> _verifyEmailCode() async {
    final code = _emailCode.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('6 haneli kodu gir')),
      );
      return;
    }
    setState(() => _verifyingCode = true);
    final auth = context.read<AuthProvider>();
    final ticket = await auth.verifyRegistrationEmailCode(
      email: _email.text,
      code: code,
    );
    if (!mounted) return;
    setState(() {
      _verifyingCode = false;
      if (ticket != null) {
        _emailTicket = ticket;
        _emailVerified = true;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ticket != null
              ? 'E-posta doğrulandı'
              : (auth.error ?? 'Kod hatalı'),
        ),
      ),
    );
  }

  void _next() {
    if (_stepId == 'account') {
      final emailOk = _email.text.contains('@');
      final passOk = _password.text.length >= 6;
      if (!emailOk || !passOk) {
        _formKey.currentState!.validate();
        return;
      }
      if (_security.requireStudentNo && _studentNo.text.trim().length < 5) {
        _formKey.currentState!.validate();
        return;
      }
      if (!_emailVerified || _emailTicket == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Devam için e-posta kodunu doğrula.'),
          ),
        );
        return;
      }
    } else if (_stepId == 'personal') {
      final userOk =
          RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(_username.text.trim());
      if (_firstName.text.trim().isEmpty ||
          _lastName.text.trim().isEmpty ||
          !userOk) {
        _formKey.currentState!.validate();
        return;
      }
      if (_security.requirePhone && _phone.text.trim().length < 10) {
        _formKey.currentState!.validate();
        return;
      }
    } else if (_stepId == 'docs') {
      if (!_docsOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doğrulama adımını tamamla.')),
        );
        return;
      }
    }
    setState(() => _step = (_step + 1).clamp(0, _stepIds.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isBusy;
    final last = _stepIds.length - 1;

    return GradientScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(compact: true, showAys: false),
                    const SizedBox(height: 20),
                    _StepIndicator(step: _step, labels: _stepLabels)
                        .animate()
                        .fadeIn()
                        .slideY(begin: 0.15),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      child: Container(
                        key: ValueKey('${_stepId}_$_step'),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: _buildStep(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_step < last)
                      AppPrimaryButton(
                        label: 'Devam',
                        onPressed: _uploading ? null : _next,
                      )
                    else
                      AppPrimaryButton(
                        label: 'Kaydı Tamamla',
                        loading: busy || _uploading,
                        onPressed: (_uploading || busy || !_emailVerified)
                            ? null
                            : _submit,
                      ),
                    if (_step > 0) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => _step -= 1),
                        child: const Text('Geri'),
                      ),
                    ],
                    TextButton(
                      onPressed: busy ? null : () => context.go('/login'),
                      child: const Text('Zaten hesabın var mı? Giriş yap'),
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

  Widget _buildStep() {
    switch (_stepId) {
      case 'account':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hesap',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              enabled: !_emailVerified,
              decoration: const InputDecoration(
                labelText: 'E-posta',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              onChanged: (_) {
                if (_emailVerified || _emailTicket != null) {
                  setState(() {
                    _emailVerified = false;
                    _emailTicket = null;
                  });
                }
              },
              validator: (v) =>
                  v != null && v.contains('@') ? null : 'Geçerli e-posta gir',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_sendingCode || _emailVerified) ? null : _sendEmailCode,
                    icon: _sendingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(_emailVerified ? 'Doğrulandı' : 'Kod gönder'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCode,
              keyboardType: TextInputType.number,
              enabled: !_emailVerified,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'E-posta doğrulama kodu',
                prefixIcon: const Icon(Icons.pin_outlined),
                counterText: '',
                suffixIcon: _emailVerified
                    ? const Icon(Icons.verified, color: AppColors.lime)
                    : IconButton(
                        onPressed: _verifyingCode ? null : _verifyEmailCode,
                        icon: _verifyingCode
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                      ),
              ),
              validator: (_) => _emailVerified ? null : 'Kodu doğrula',
            ),
            if (_security.requireStudentNo) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _studentNo,
                decoration: const InputDecoration(
                  labelText: 'Öğrenci numarası',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) =>
                    v != null && v.trim().length >= 5 ? null : 'En az 5 karakter',
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Şifre',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                ),
              ),
              validator: (v) =>
                  v != null && v.length >= 6 ? null : 'En az 6 karakter',
            ),
          ],
        );
      case 'personal':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kişisel',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _firstName,
              decoration: const InputDecoration(
                labelText: 'Ad',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  v != null && v.trim().isNotEmpty ? null : 'Zorunlu',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastName,
              decoration: const InputDecoration(
                labelText: 'Soyad',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  v != null && v.trim().isNotEmpty ? null : 'Zorunlu',
            ),
            if (_security.requirePhone) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => v != null && v.trim().length >= 10
                    ? null
                    : 'Geçerli telefon',
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Kullanıcı adı',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: (v) {
                if (v == null ||
                    !RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(v.trim())) {
                  return '3–24 karakter; a-z, 0-9, _';
                }
                return null;
              },
            ),
          ],
        );
      case 'campus':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kampüs',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _city,
              decoration: const InputDecoration(
                labelText: 'İl',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: MockData.cities
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _city = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _university,
              decoration: const InputDecoration(
                labelText: 'Üniversite',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              items: MockData.universities
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _university = v),
            ),
          ],
        );
      case 'docs':
        return _buildVerificationStep();
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Yasal onaylar',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ConsentCheckRow(
              title: _legal.kvkkTitle,
              body: _legal.kvkkBody,
              accepted: _kvkk,
              onAccepted: () => setState(() => _kvkk = true),
            ),
            const SizedBox(height: 8),
            ConsentCheckRow(
              title: _legal.marketingTitle,
              body: _legal.marketingBody,
              accepted: _marketing,
              onAccepted: () => setState(() => _marketing = true),
            ),
          ],
        );
    }
  }

  Widget _buildVerificationStep() {
    final cardOk = _security.allowStudentCard;
    final pdfOk = _security.allowStudentDocumentPdf;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Öğrenci doğrulama',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Öğrenci kartı veya resmi belge yükle. Belgedeki bilgiler ad, soyad ve '
          'öğrenci numarasıyla eşleşmeli. Başvuru admin onayına düşer.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        if (cardOk)
          _TypeTile(
            selected: _verifyType == 'card',
            title: 'Öğrenci kartı',
            subtitle: _security.requireCardBothSides
                ? 'Ön ve arka yüz fotoğrafı'
                : 'Kart fotoğrafı',
            icon: Icons.badge_outlined,
            onTap: () => setState(() {
              _verifyType = 'card';
              _pdfUrl = null;
            }),
          ),
        if (cardOk && pdfOk) const SizedBox(height: 8),
        if (pdfOk)
          _TypeTile(
            selected: _verifyType == 'document',
            title: 'Öğrenci belgesi',
            subtitle: 'Resmi belge PDF',
            icon: Icons.picture_as_pdf_outlined,
            onTap: () => setState(() {
              _verifyType = 'document';
              _frontUrl = null;
              _backUrl = null;
            }),
          ),
        if (_verifyType == 'card') ...[
          const SizedBox(height: 16),
          _SideUploadCard(
            label: 'Ön yüz',
            done: _frontUrl != null,
            busy: _uploading && _busySide == 'front',
            onCamera: _uploading
                ? null
                : () => _runUpload(
                      side: 'front',
                      pick: StudentDocUpload.captureCardImage,
                      expectPdf: false,
                    ),
            onGallery: _uploading
                ? null
                : () => _runUpload(
                      side: 'front',
                      pick: StudentDocUpload.pickCardImage,
                      expectPdf: false,
                    ),
          ),
          if (_security.requireCardBothSides) ...[
            const SizedBox(height: 10),
            _SideUploadCard(
              label: 'Arka yüz',
              done: _backUrl != null,
              busy: _uploading && _busySide == 'back',
              onCamera: _uploading
                  ? null
                  : () => _runUpload(
                        side: 'back',
                        pick: StudentDocUpload.captureCardImage,
                        expectPdf: false,
                      ),
              onGallery: _uploading
                  ? null
                  : () => _runUpload(
                        side: 'back',
                        pick: StudentDocUpload.pickCardImage,
                        expectPdf: false,
                      ),
            ),
          ],
        ],
        if (_verifyType == 'document') ...[
          const SizedBox(height: 16),
          _SideUploadCard(
            label: 'PDF belge',
            done: _pdfUrl != null,
            busy: _uploading && _busySide == 'pdf',
            pdfOnly: true,
            onCamera: null,
            onGallery: _uploading
                ? null
                : () => _runUpload(
                      side: 'pdf',
                      pick: StudentDocUpload.pickPdf,
                      expectPdf: true,
                    ),
          ),
        ],
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.cyan.withValues(alpha: 0.12)
          : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppColors.cyan : AppColors.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.cyan),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideUploadCard extends StatelessWidget {
  const _SideUploadCard({
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
  final VoidCallback? onGallery;
  final VoidCallback? onCamera;
  final bool pdfOnly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.upload_file_outlined,
                color: done ? AppColors.lime : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (busy) ...[
                const Spacer(),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          if (!done && !busy) ...[
            const SizedBox(height: 10),
            if (!pdfOnly && onCamera != null)
              FilledButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Kamera'),
              ),
            if (!pdfOnly && onCamera != null) const SizedBox(height: 6),
            if (onGallery != null)
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: Icon(
                  pdfOnly
                      ? Icons.picture_as_pdf_outlined
                      : Icons.photo_library_outlined,
                  size: 18,
                ),
                label: Text(pdfOnly ? 'PDF seç' : 'Galeriden seç'),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.labels});
  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    return Row(
      children: List.generate(n, (i) {
        final active = i <= step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < n - 1 ? 4 : 0),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: 280.ms,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.cyan : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active
                            ? AppColors.navy
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
