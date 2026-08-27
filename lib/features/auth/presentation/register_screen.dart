import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/storage/student_doc_upload.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../../../data/campus_catalog.dart';
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
  final _tckn = TextEditingController();
  final _barkod = TextEditingController();

  String? _emailTicket;
  bool _emailVerified = false;
  bool _sendingCode = false;
  bool _verifyingCode = false;

  String? _city;
  String? _university;
  String? _faculty;
  String? _department;
  CampusCatalog? _catalog;
  bool _campusLoading = true;
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
  bool _deferredSkip = false;

  String? _edevletTicket;
  bool _edevletBusy = false;
  String? _edevletError;
  bool _edevletFallbackUpload = false;
  /// null = henüz sorulmadı, true = öğrenci onayladı, false = reddetti → admin
  bool? _edevletUserConfirmed;
  String? _edevletUniversity;
  String? _edevletFaculty;
  String? _edevletDepartment;
  String? _edevletStatus;

  List<String> get _stepIds {
    final ids = <String>['account', 'personal', 'campus'];
    if (_security.showVerificationStep) ids.add('docs');
    ids.add('legal');
    return ids;
  }

  List<String> get _stepLabels {
    final labels = <String>['Hesap', 'Kişisel', 'Kampüs'];
    if (_security.showVerificationStep) labels.add('Doğrulama');
    labels.add('Onay');
    return labels;
  }

  String get _stepId => _stepIds[_step.clamp(0, _stepIds.length - 1)];

  @override
  void initState() {
    super.initState();
    CampusCatalog.load().then((c) {
      if (!mounted) return;
      setState(() {
        _catalog = c;
        _campusLoading = false;
        _city ??= c.cities.isNotEmpty ? c.cities.first : null;
        final unis = c.universitiesForCity(_city);
        _university ??= unis.isNotEmpty ? unis.first : null;
      });
    });
    LegalConsentTexts.load().then((t) {
      if (mounted) setState(() => _legal = t);
    });
    RegistrationSecurityConfig.load().then((s) {
      if (!mounted) return;
      setState(() {
        _security = s;
        _deferredSkip = false;
        _ensureVerifyType();
        if (_step >= _stepIds.length) _step = _stepIds.length - 1;
      });
    });
  }

  void _ensureVerifyType() {
    final edevlet = _security.allowEdevlet;
    final card = _security.allowStudentCard;
    final pdf = _security.allowStudentDocumentPdf;
    // e-Devlet varsa otomatik belge (barkod) — kullanıcı seçmez
    if (edevlet) {
      _verifyType = 'document';
      return;
    }
    if (_verifyType == 'card' && !card) _verifyType = null;
    if (_verifyType == 'document' && !pdf) _verifyType = null;
    if (_verifyType == null) {
      if (card && !pdf) {
        _verifyType = 'card';
      } else if (pdf && !card) {
        _verifyType = 'document';
      } else if (card) {
        _verifyType = 'card';
      } else if (pdf) {
        _verifyType = 'document';
      }
    }
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
    _tckn.dispose();
    _barkod.dispose();
    super.dispose();
  }

  bool get _edevletParsed => (_edevletTicket ?? '').length >= 20;
  bool get _edevletOk =>
      _edevletParsed && _edevletUserConfirmed == true;

  bool get _docsOk {
    if (!_security.showVerificationStep) return true;
    if (_security.allowSkipVerification && _deferredSkip) return true;
    if (_verifyType == 'card') {
      final needBack = _security.requireCardBothSides;
      return _frontUrl != null && (!needBack || _backUrl != null);
    }
    if (_verifyType == 'document') {
      if (_security.allowEdevlet) {
        if (_edevletOk) return true;
        if (_security.allowEdevletPdfFallback) {
          return _pdfUrl != null;
        }
        return false;
      }
      // Yalnız belge: PDF
      return _pdfUrl != null;
    }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
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
          content: Text(
            'KVKK ve pazarlama metinlerini okuyup kabul etmelisin.',
          ),
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final deferred = _security.allowSkipVerification && _deferredSkip;
    final require = _security.requireDocsNow && !deferred;
    final ok = await auth.register(
      email: _email.text,
      studentNo: _studentNo.text,
      password: _password.text,
      firstName: _firstName.text,
      lastName: _lastName.text,
      phone: _phone.text,
      city: _city ?? '',
      university: _university ?? '',
      faculty: _faculty ?? '',
      department: _department ?? '',
      username: _username.text,
      emailTicket: _emailTicket!,
      kvkkAccepted: _kvkk,
      marketingConsent: _marketing,
      requireVerification: require,
      studentVerificationType: deferred
          ? 'deferred'
          : (require
              ? (_edevletOk ? 'edevlet' : _verifyType)
              : (_edevletOk ? 'edevlet' : null)),
      studentIdFrontUrl: require && _verifyType == 'card' ? _frontUrl : null,
      studentIdBackUrl: require && _verifyType == 'card' ? _backUrl : null,
      studentIdDocUrl: require && !_edevletOk && _verifyType == 'document'
          ? _pdfUrl
          : null,
      edevletTicket: _edevletOk ? _edevletTicket : null,
    );
    if (!mounted) return;
    if (ok) {
      final pending = auth.user?.isAccountPending == true;
      final msg = (require && pending)
          ? 'Kayıt başarılı. Belgen admin onayına düştü; sonuç mail ile gelir. Giriş yapabilirsin.'
          : (_edevletOk
              ? 'Kayıt başarılı. e-Devlet doğrulaması tamam — giriş yapabilirsin.'
              : 'Kayıt başarılı. Giriş yapabilirsin.');
      await auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.go('/login');
    } else if (auth.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(auth.error!)));
    }
  }

  Future<void> _verifyEdevlet() async {
    final tckn = _tckn.text.replaceAll(RegExp(r'\D'), '');
    final barkod = _barkod.text.replaceAll(RegExp(r'\s'), '');
    if (tckn.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TC kimlik no 11 haneli olmalı.')),
      );
      return;
    }
    if (barkod.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belgedeki barkod numarasını gir.')),
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
      if (res.ok) {
        _edevletTicket = res.ticket;
        _edevletFallbackUpload = false;
        _edevletError = null;
        _edevletUserConfirmed = null; // öğrenciye sorulacak
        _edevletUniversity = res.university;
        _edevletFaculty = res.faculty;
        _edevletDepartment = res.department;
        _edevletStatus = res.studentStatus;
        if ((res.firstName ?? '').isNotEmpty) {
          _firstName.text = res.firstName!;
        }
        if ((res.lastName ?? '').isNotEmpty) {
          _lastName.text = res.lastName!;
        }
      } else {
        _edevletTicket = null;
        _edevletUserConfirmed = null;
        _edevletFallbackUpload = true;
        _edevletError = res.messages.isNotEmpty
            ? res.messages.join(' ')
            : 'Belge doğrulanamadı.';
        _edevletUniversity = null;
        _edevletFaculty = null;
        _edevletDepartment = null;
        _edevletStatus = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok
              ? 'Belgeden eğitim bilgileri alındı — lütfen doğrula.'
              : (_security.allowEdevletPdfFallback
                  ? 'e-Devlet doğrulanamadı — PDF yükleme açıldı (admin onayı).'
                  : 'e-Devlet doğrulanamadı. Yeni belge oluşturup tekrar dene.'),
        ),
      ),
    );
  }

  void _applyCampusFromBelge() {
    final uni = _edevletUniversity;
    if (uni == null || uni.isEmpty || _catalog == null) return;
    final cities = _catalog!.cities;
    String? matchedCity;
    String? matchedUni;
    for (final c in cities) {
      for (final u in _catalog!.universitiesForCity(c)) {
        if (_campusNameMatch(u, uni)) {
          matchedCity = c;
          matchedUni = u;
          break;
        }
      }
      if (matchedUni != null) break;
    }
    // Şehir listesinde yoksa tüm üniversite adlarını tara
    if (matchedUni == null) {
      for (final c in cities) {
        for (final u in _catalog!.universitiesForCity(c)) {
          if (_campusNameMatch(u, uni) || _campusNameMatch(uni, u)) {
            matchedCity = c;
            matchedUni = u;
            break;
          }
        }
        if (matchedUni != null) break;
      }
    }
    if (matchedUni == null) return;
    _city = matchedCity;
    _university = matchedUni;
    final facs = _catalog!.facultiesFor(matchedUni);
    final fac = _edevletFaculty;
    if (fac != null && facs.isNotEmpty) {
      CampusFaculty? mf;
      for (final f in facs) {
        if (_campusNameMatch(f.name, fac)) {
          mf = f;
          break;
        }
      }
      if (mf != null) {
        _faculty = mf.name;
        final deps = _catalog!.departmentsFor(
          universityName: matchedUni,
          facultyName: mf.name,
        );
        final dep = _edevletDepartment;
        if (dep != null && deps.isNotEmpty) {
          final md = deps.cast<String?>().firstWhere(
                (d) => d != null && _campusNameMatch(d, dep),
                orElse: () => null,
              );
          if (md != null) _department = md;
        }
      }
    }
  }

  void _confirmEdevletYes() {
    setState(() {
      _edevletUserConfirmed = true;
      _edevletFallbackUpload = false;
      _applyCampusFromBelge();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Onaylandı'
          '${_university != null ? ' · $_university' : ''}'
          '${_faculty != null ? ' · $_faculty' : ''}'
          '${_department != null ? ' · $_department' : ''}',
        ),
      ),
    );
  }

  void _confirmEdevletNo() {
    setState(() {
      _edevletUserConfirmed = false;
      _edevletTicket = null; // otomatik onay yok → admin
      _edevletFallbackUpload = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Bilgiler reddedildi — PDF yükle, başvurun admin onayına düşer.',
        ),
      ),
    );
  }

  bool _campusNameMatch(String a, String b) {
    String n(String s) => s
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final x = n(a);
    final y = n(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.contains(y) || y.contains(x);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('6 haneli kodu gir')));
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
          ticket != null ? 'E-posta doğrulandı' : (auth.error ?? 'Kod hatalı'),
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
          const SnackBar(content: Text('Devam için e-posta kodunu doğrula.')),
        );
        return;
      }
    } else if (_stepId == 'personal') {
      final userOk = RegExp(
        r'^[a-zA-Z0-9_]{3,24}$',
      ).hasMatch(_username.text.trim());
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
                    _StepIndicator(
                      step: _step,
                      labels: _stepLabels,
                    ).animate().fadeIn().slideY(begin: 0.15),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
                    onPressed: (_sendingCode || _emailVerified)
                        ? null
                        : _sendEmailCode,
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
                    : null,
              ),
              validator: (_) => _emailVerified ? null : 'Kodu doğrula',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: (_verifyingCode || _emailVerified)
                    ? null
                    : _verifyEmailCode,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.lime,
                  foregroundColor: AppColors.navy,
                  disabledBackgroundColor: _emailVerified
                      ? AppColors.lime
                      : null,
                  disabledForegroundColor: _emailVerified
                      ? AppColors.navy
                      : null,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                icon: _verifyingCode
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.navy,
                        ),
                      )
                    : Icon(
                        _emailVerified
                            ? Icons.verified
                            : Icons.check_circle_outline,
                      ),
                label: Text(
                  _emailVerified
                      ? 'E-posta doğrulandı'
                      : 'KODU DOĞRULA VE DEVAM ET',
                ),
              ),
            ),
            if (_security.requireStudentNo) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _studentNo,
                decoration: const InputDecoration(
                  labelText: 'Öğrenci numarası',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => v != null && v.trim().length >= 5
                    ? null
                    : 'En az 5 karakter',
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (_campusLoading || _catalog == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _city,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'İl',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                items: _catalog!.cities
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  final unis = _catalog!.universitiesForCity(v);
                  setState(() {
                    _city = v;
                    _university = unis.isNotEmpty ? unis.first : null;
                    _faculty = null;
                    _department = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _university,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Üniversite',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
                items: _catalog!
                    .universitiesForCity(_city)
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(u, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  final facs = _catalog!.facultiesFor(v);
                  setState(() {
                    _university = v;
                    _faculty = facs.isNotEmpty ? facs.first.name : null;
                    final deps = _catalog!.departmentsFor(
                      universityName: v,
                      facultyName: _faculty,
                    );
                    _department = deps.isNotEmpty ? deps.first : null;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _faculty ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fakülte / birim',
                  prefixIcon: Icon(Icons.apartment_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Seçilmedi (opsiyonel)'),
                  ),
                  ..._catalog!.facultiesFor(_university).map(
                        (f) => DropdownMenuItem(
                          value: f.name,
                          child: Text(
                            f.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                ],
                onChanged: (v) {
                  final fac = (v == null || v.isEmpty) ? null : v;
                  final deps = _catalog!.departmentsFor(
                    universityName: _university,
                    facultyName: fac,
                  );
                  setState(() {
                    _faculty = fac;
                    _department = deps.isNotEmpty ? deps.first : null;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _department ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bölüm / program',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Seçilmedi (opsiyonel)'),
                  ),
                  ..._catalog!
                      .departmentsFor(
                        universityName: _university,
                        facultyName: _faculty,
                      )
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                ],
                onChanged: (v) => setState(
                  () => _department = (v == null || v.isEmpty) ? null : v,
                ),
              ),
            ],
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
    final edevletOk = _security.allowEdevlet;
    final fallbackOk = _security.allowEdevletPdfFallback;
    // e-Devlet açıksa tip seçici yok. Yalnız belge modunda kart+PDF varsa seçici.
    final showTypePicker = !edevletOk && cardOk && pdfOk;

    final intro = switch (_security.verificationMode) {
      RegVerificationMode.edevletOnly =>
        'Öğrenci belgeni e-Devlet barkodu ile doğrula. Sistem bilgileri otomatik okur.',
      RegVerificationMode.edevletPlusDoc =>
        'e-Devlet barkodu + TC ile doğrula. Sistem eğitim bilgilerini otomatik alır. '
            'Doğrulama olmazsa PDF yükleme açılır (admin onayı).',
      RegVerificationMode.documentOnly =>
        'Öğrenci kartı veya PDF belge yükle. Başvuru admin onayına düşer.',
      RegVerificationMode.defer =>
        'İstersen şimdi doğrula; istersen “şimdilik geç” — belgeyi sonra isteyeceğiz.',
      RegVerificationMode.off => '',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Öğrenci doğrulama',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          intro,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        if (_security.allowSkipVerification) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _deferredSkip = !_deferredSkip;
              if (_deferredSkip) {
                _edevletTicket = null;
                _edevletUserConfirmed = null;
                _pdfUrl = null;
                _frontUrl = null;
                _backUrl = null;
              }
            }),
            icon: Icon(
              _deferredSkip
                  ? Icons.check_circle
                  : Icons.schedule_outlined,
            ),
            label: Text(
              _deferredSkip
                  ? 'Belge sonraya bırakıldı — devam edebilirsin'
                  : 'Şimdilik geç — belgeyi sonra iste',
            ),
          ),
        ],
        if (_deferredSkip) ...[
          const SizedBox(height: 8),
          const Text(
            'Kayıt sonrası hesabın açılır; doğrulamayı daha sonra tamamlaman istenir.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ] else ...[
          const SizedBox(height: 16),
          if (showTypePicker && cardOk) ...[
            _TypeTile(
              selected: _verifyType == 'card',
              title: 'Öğrenci kartı',
              subtitle: _security.requireCardBothSides
                  ? 'Ön ve arka yüz · admin onayı'
                  : 'Kart fotoğrafı · admin onayı',
              icon: Icons.badge_outlined,
              onTap: () => setState(() {
                _verifyType = 'card';
                _pdfUrl = null;
                _edevletTicket = null;
                _edevletFallbackUpload = false;
                _edevletError = null;
                _edevletUserConfirmed = null;
                _edevletUniversity = null;
                _edevletFaculty = null;
                _edevletDepartment = null;
                _edevletStatus = null;
              }),
            ),
            if (pdfOk) const SizedBox(height: 8),
          ],
          if (showTypePicker && pdfOk)
            _TypeTile(
              selected: _verifyType == 'document',
              title: 'PDF belge',
              subtitle: 'PDF yükle · admin onayı',
              icon: Icons.verified_outlined,
              onTap: () => setState(() {
                _verifyType = 'document';
                _frontUrl = null;
                _backUrl = null;
                _edevletUserConfirmed = null;
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
            if (edevletOk) ...[
              ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Barkod nasıl alınır?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                children: const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '1) turkiye.gov.tr veya e-Devlet mobil uygulamasına giriş yap.\n'
                      '2) Arama: “Öğrenci Belgesi Sorgula” (YÖK).\n'
                      '3) Belgeyi oluştur / görüntüle.\n'
                      '4) Belgedeki barkod numarasını (ör. YOKOG…) kopyala.\n'
                      '5) Aynı belgedeki T.C. kimlik no ile burada doğrula.\n\n'
                      'Not: Barkod tek kullanımlık / süresi dolmuş olabilir; '
                      '“bulunamadı” hatasında yeni belge oluştur.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                ],
              ),
              ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'KVKK — ne saklanır?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                children: const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Yasal dayanak: KVKK m.5/2-c (sözleşmenin kurulması/ifası) '
                      've m.5/2-f (meşru menfaat — sahte hesap önleme). '
                      'Aydınlatma: KVKK m.10.\n\n'
                      'Saklanır: üniversite, fakülte, bölüm, öğrencilik durumu, '
                      'sınıf; hesabındaki e-posta ve okul numarasıyla ilişkilendirilir.\n\n'
                      'Saklanmaz: T.C. kimlik no, anne/baba adı, doğum bilgileri, ham PDF.\n\n'
                      'Barkod + T.C. yalnızca anlık e-Devlet sorgusu içindir; '
                      'sonrasında T.C. düz metin tutulmaz.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tckn,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: 'TC kimlik no',
                  helperText: 'Yalnızca anlık doğrulama — saklanmaz',
                  counterText: '',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _barkod,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Belge barkod no',
                  helperText: 'Örn. YOKOG… — belgedeki barkod',
                  prefixIcon: Icon(Icons.qr_code_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _edevletBusy ? null : _verifyEdevlet,
                icon: _edevletBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(
                  _edevletBusy ? 'Doğrulanıyor…' : 'e-Devlet ile doğrula',
                ),
              ),
              if (_edevletParsed) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _edevletOk
                        ? AppColors.lime.withValues(alpha: 0.15)
                        : AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _edevletOk ? AppColors.lime : AppColors.cyan,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _edevletOk
                                ? Icons.check_circle
                                : Icons.school_outlined,
                            color:
                                _edevletOk ? AppColors.lime : AppColors.cyan,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _edevletOk
                                  ? 'Onayladın — kampüs bilgilerin güncellendi.'
                                  : 'Belgeden okunan eğitim bilgileri',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      if (_edevletStatus != null) ...[
                        const SizedBox(height: 8),
                        Text(_edevletStatus!,
                            style: const TextStyle(fontSize: 13)),
                      ],
                      if (_edevletUniversity != null)
                        Text(_edevletUniversity!,
                            style: const TextStyle(fontSize: 13)),
                      if (_edevletFaculty != null)
                        Text(_edevletFaculty!,
                            style: const TextStyle(fontSize: 13)),
                      if (_edevletDepartment != null)
                        Text(_edevletDepartment!,
                            style: const TextStyle(fontSize: 13)),
                      if (_edevletUserConfirmed == null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Bu bilgiler sizin için doğru mu?',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fallbackOk
                              ? 'Evet dersen kampüs profilin güncellenir ve hesap açılır. '
                                  'Hayır dersen PDF yükleyip admin onayına düşersin.'
                              : 'Evet dersen kampüs profilin güncellenir. '
                                  'Hayır dersen kayıt için admin destek gerekir.',
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _confirmEdevletYes,
                                child: const Text('Evet, doğru'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: fallbackOk
                                    ? _confirmEdevletNo
                                    : () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Bu modda PDF yedek kapalı. Kendi belgenle tekrar dene veya destek ile iletişim kur.',
                                            ),
                                          ),
                                        );
                                      },
                                child: const Text('Hayır'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_edevletError != null && !_edevletParsed) ...[
                const SizedBox(height: 12),
                Text(
                  _edevletError!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              if (fallbackOk &&
                  (_edevletFallbackUpload ||
                      (!_edevletOk && _pdfUrl != null) ||
                      _edevletUserConfirmed == false)) ...[
                const SizedBox(height: 16),
                const Text(
                  'Manuel yükleme (admin onayı)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
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
            ] else if (pdfOk) ...[
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
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
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
                    color: active ? AppColors.navy : AppColors.textSecondary,
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
