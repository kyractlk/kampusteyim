import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';

/// PayTR / Shopier ödeme sayfası — uygulama içi WebView.
/// Kart girişi → sonuç → ana sayfa; dış tarayıcı açılmaz.
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({
    super.key,
    required this.payUrl,
    this.orderId,
    this.product,
  });

  final String payUrl;
  final String? orderId;
  final String? product;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  var _loading = true;
  var _handledResult = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (kDebugMode) {
              debugPrint('[pay-webview] ${err.errorCode} ${err.description}');
            }
            if (err.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _error = 'Sayfa yüklenemedi. Bağlantını kontrol et.';
              });
            }
          },
          onNavigationRequest: (req) {
            if (_isPayResultUrl(req.url)) {
              unawaited(_finishFromUrl(req.url));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && _isPayResultUrl(url)) {
              unawaited(_finishFromUrl(url));
            }
          },
        ),
      );

    // PayTR 3D Secure / banka iframe — üçüncü parti çerezler gerekli.
    if (!kIsWeb && Platform.isAndroid) {
      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        unawaited(
          platform.setMediaPlaybackRequiresUserGesture(false),
        );
        AndroidWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        ).setAcceptThirdPartyCookies(platform, true);
      }
    }

    _controller = controller;

    final uri = Uri.tryParse(widget.payUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      _error = 'Geçersiz ödeme bağlantısı.';
      _loading = false;
    } else {
      _controller.loadRequest(uri);
    }
  }

  bool _isPayResultUrl(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('pay-result')) return true;
    if (lower.contains('kampusteyim.app') &&
        (lower.contains('status=ok') ||
            lower.contains('status=fail') ||
            lower.contains('status=success') ||
            lower.contains('pay=ok') ||
            lower.contains('pay=fail'))) {
      return true;
    }
    return false;
  }

  Future<void> _finishFromUrl(String raw) async {
    if (_handledResult || !mounted) return;
    _handledResult = true;

    final uri = Uri.tryParse(raw);
    final q = uri?.queryParameters ?? const <String, String>{};
    final status = (q['status'] ?? q['pay'] ?? 'fail').toLowerCase();
    final ok = status == 'ok' || status == 'success';
    final orderId = q['orderId'] ?? widget.orderId;
    final product = q['product'] ?? widget.product;

    try {
      await context.read<AuthProvider>().refreshCurrentUser();
    } catch (_) {}

    if (!mounted) return;

    // Sonuç ekranı yerine doğrudan onay + ana sayfa (tüm süreç uygulamada).
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ödeme onaylandı')),
      );
      context.go('/home');
      return;
    }

    context.go(
      Uri(
        path: '/pay-result',
        queryParameters: {
          'status': status,
          if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
          if (product != null && product.isNotEmpty) 'product': product,
        },
      ).toString(),
    );
  }

  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ödemeyi iptal et?'),
        content: const Text(
          'Kart bilgisini girdikten sonra kapatırsan işlem tamamlanmayabilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Devam et'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Çık'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Güvenli ödeme'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmClose,
          ),
          actions: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _loading = true;
                            _handledResult = false;
                          });
                          final uri = Uri.tryParse(widget.payUrl);
                          if (uri != null) _controller.loadRequest(uri);
                        },
                        child: const Text('Tekrar dene'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const LinearProgressIndicator(minHeight: 2),
                ],
              ),
      ),
    );
  }
}
