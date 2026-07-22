import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../../admin/admin_provider.dart';
import '../../jobs/jobs_provider.dart';
import '../../maintenance/maintenance_provider.dart';
import '../data/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(
      email: _email.text,
      password: _password.text,
    );
    if (!mounted) return;
    if (ok) {
      final user = auth.user;
      if (user != null && user.isCompany) {
        await context.read<JobsProvider>().bindCompanyFromUser(user);
      }
      if (!mounted) return;
      final maint = context.read<MaintenanceProvider>();
      final admin = context.read<AdminProvider>();
      if (maint.blocksApp && admin.canAccessDuringMaintenance(user)) {
        context.go('/admin');
      } else if (maint.blocksApp) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bakım devam ediyor · personel yetkisi gerekli'),
          ),
        );
        context.go('/home');
      } else {
        context.go(AuthProvider.homeRouteFor(user));
      }
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().isBusy;

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
                            context.go('/home');
                          }
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Akışa dön'),
                      ),
                    ),
                    const BrandHeader(),
                    const SizedBox(height: 28),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Giriş yap',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kampüs hesabınla giriş yap.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-posta',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'E-posta gerekli';
                              }
                              if (!v.contains('@')) return 'Geçerli e-posta gir';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Şifre gerekli';
                              if (v.length < 6) {
                                return 'En az 6 karakter (ör. 123456)';
                              }
                              return null;
                            },
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      final email = _email.text.trim();
                                      final q = email.isEmpty
                                          ? ''
                                          : '?email=${Uri.encodeComponent(email)}';
                                      context.push('/sifremi-unuttum$q');
                                    },
                              child: const Text('Şifremi unuttum'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppPrimaryButton(
                            label: 'Giriş Yap',
                            loading: busy,
                            onPressed: _submit,
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 180.ms, duration: 400.ms)
                        .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: busy ? null : () => context.go('/register'),
                      child: const Text('Hesabın yok mu? Kayıt ol'),
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
