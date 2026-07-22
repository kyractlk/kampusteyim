import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';

/// Girişten bağımsız «Şifremi unuttum» sayfası.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _busy = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('requestPasswordReset');
      await callable.call({'email': _email.text.trim()});
      if (!mounted) return;
      setState(() => _sent = true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'İstek gönderilemedi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/login');
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Girişe dön'),
                      ),
                    ),
                    const BrandHeader(compact: true),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: _sent
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(
                                  Icons.mark_email_read_outlined,
                                  size: 48,
                                  color: AppColors.cyan,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Mail gönderildi',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Hesap varsa ${_email.text.trim()} adresine '
                                  'kısa bir KampüsteyimAPP linki gitti '
                                  '(ör. gaunengineering.com.tr/r/…). '
                                  'Tıklanmazsa tarayıcıya yapıştırabilirsin.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                AppPrimaryButton(
                                  label: 'Girişe dön',
                                  onPressed: () => context.go('/login'),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Şifremi unuttum',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Kayıtlı e-postanı yaz. Sıfırlama linki '
                                  'Firebase sayfasına değil, KampüsteyimAPP’e gider.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'E-posta',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'E-posta gerekli';
                                    }
                                    if (!v.contains('@')) {
                                      return 'Geçerli e-posta gir';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                AppPrimaryButton(
                                  label: 'Sıfırlama maili gönder',
                                  loading: _busy,
                                  onPressed: _submit,
                                ),
                              ],
                            ),
                    )
                        .animate()
                        .fadeIn(delay: 120.ms, duration: 400.ms)
                        .slideY(begin: 0.06, curve: Curves.easeOutCubic),
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
