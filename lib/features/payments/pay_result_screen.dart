import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';

/// PayTR / ödeme dönüş ekranı — ok & fail.
class PayResultScreen extends StatefulWidget {
  const PayResultScreen({
    super.key,
    required this.status,
    this.orderId,
    this.product,
  });

  final String status;
  final String? orderId;
  final String? product;

  @override
  State<PayResultScreen> createState() => _PayResultScreenState();
}

class _PayResultScreenState extends State<PayResultScreen> {
  @override
  void initState() {
    super.initState();
    if (_ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthProvider>().refreshCurrentUser();
      });
    }
  }

  bool get _ok {
    final s = widget.status.toLowerCase();
    return s == 'ok' || s == 'success';
  }

  String get _productLabel {
    return switch (widget.product) {
      'plus' => 'Kampüsteyim Plus',
      'merch' => 'Market siparişi',
      'event' => 'Etkinlik bileti',
      'ad' => 'Reklam',
      _ => 'Ödeme',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ok;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ok
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.error.withValues(alpha: 0.12),
                ),
                child: Icon(
                  ok ? Icons.check_rounded : Icons.close_rounded,
                  size: 48,
                  color: ok ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                ok ? 'Ödeme başarılı' : 'Ödeme tamamlanamadı',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                ok
                    ? (widget.product == 'plus'
                        ? 'Plus üyeliğin hesabına işleniyor. Ayrıcalıkların kısa sürede aktif olur.'
                        : widget.product == 'merch'
                            ? 'Siparişin alındı. Kargo hazırlanınca bilgilendirileceksin.'
                            : 'Ödemen alındı. Teşekkürler!')
                    : 'İşlem iptal edildi veya banka reddetti. Market’ten tekrar deneyebilirsin.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                [
                  _productLabel,
                  if ((widget.orderId ?? '').isNotEmpty)
                    'Sipariş: ${widget.orderId!.length > 12 ? '${widget.orderId!.substring(0, 12)}…' : widget.orderId}',
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    context.go('/home');
                  },
                  child: Text(ok ? 'Ana sayfaya dön' : 'Ana sayfa'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  if (ok && widget.product == 'plus') {
                    context.go('/profile/settings');
                  } else if (!ok) {
                    context.go('/market');
                  } else {
                    context.go('/market');
                  }
                },
                child: Text(
                  ok
                      ? (widget.product == 'plus'
                          ? 'Plus ayarları'
                          : 'Market')
                      : 'Tekrar dene',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
