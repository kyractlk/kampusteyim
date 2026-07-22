import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';

/// Kısa link `/r/xxxxx` ile yeni şifre — kod ekranda gösterilmez.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.code});

  final String code;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _validCode => widget.code.trim().length >= 8;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validCode) {
      setState(() => _error = 'Bağlantı geçersiz. Yeni sıfırlama talep et.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('confirmPasswordReset');
      await callable.call({
        'code': widget.code.trim(),
        'newPassword': _password.text,
      });
      if (!mounted) return;
      setState(() => _done = true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Şifre güncellenemedi (${e.code})';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Şifre güncellenemedi: $e');
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.go('/login'),
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
                    child: !_validCode
                        ? Column(
                            children: [
                              const Icon(
                                Icons.link_off_rounded,
                                size: 44,
                                color: AppColors.crimson,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Geçersiz bağlantı',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Maildeki kısa link eksik veya bozuk. Yeni bir '
                                'şifre sıfırlama talebi oluştur.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              AppPrimaryButton(
                                label: 'Şifremi unuttum',
                                onPressed: () => context.go('/sifremi-unuttum'),
                              ),
                            ],
                          )
                        : _done
                            ? Column(
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 48,
                                    color: AppColors.cyan,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Şifre güncellendi',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Yeni şifrenle giriş yapabilirsin.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  AppPrimaryButton(
                                    label: 'Giriş yap',
                                    onPressed: () => context.go('/login'),
                                  ),
                                ],
                              )
                            : Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Yeni şifre belirle',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Kısa sıfırlama bağlantın doğrulandı. En az 6 karakter.',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    TextFormField(
                                      controller: _password,
                                      obscureText: _obscure,
                                      autofillHints: const [
                                        AutofillHints.newPassword,
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Yeni şifre',
                                        prefixIcon:
                                            const Icon(Icons.lock_outline),
                                        suffixIcon: IconButton(
                                          onPressed: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Şifre gerekli';
                                        }
                                        if (v.length < 6) {
                                          return 'En az 6 karakter';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _confirm,
                                      obscureText: _obscure,
                                      decoration: const InputDecoration(
                                        labelText: 'Şifre tekrar',
                                        prefixIcon: Icon(Icons.lock_outline),
                                      ),
                                      validator: (v) {
                                        if (v != _password.text) {
                                          return 'Şifreler eşleşmiyor';
                                        }
                                        return null;
                                      },
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: AppColors.crimson,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    AppPrimaryButton(
                                      label: 'Şifreyi kaydet',
                                      loading: _busy,
                                      onPressed: _submit,
                                    ),
                                  ],
                                ),
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
    );
  }
}
