import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import 'points_models.dart';

/// Kampüs QR’larından KP toplama — kamera + elle kod.
class PointsQrHuntScreen extends StatefulWidget {
  const PointsQrHuntScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<PointsQrHuntScreen> createState() => _PointsQrHuntScreenState();
}

class _PointsQrHuntScreenState extends State<PointsQrHuntScreen> {
  final _manual = TextEditingController();
  MobileScannerController? _camera;
  bool _busy = false;
  String? _flash;
  bool _flashOk = false;
  DateTime? _lastScanAt;
  String? _lastPayload;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _camera = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        autoStart: true,
      );
    }
    final code = (widget.initialCode ?? '').trim();
    if (code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claim(code));
    }
  }

  @override
  void dispose() {
    _manual.dispose();
    _camera?.dispose();
    super.dispose();
  }

  static String? extractCode(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final pathMatch =
        RegExp(r'/points/qr-claim/([a-zA-Z0-9_-]+)').firstMatch(t);
    if (pathMatch != null) return pathMatch.group(1);
    final uri = Uri.tryParse(t);
    if (uri != null) {
      final pathParam = uri.queryParameters['path'];
      if (pathParam != null && pathParam.isNotEmpty) {
        final m =
            RegExp(r'/points/qr-claim/([a-zA-Z0-9_-]+)').firstMatch(pathParam);
        if (m != null) return m.group(1);
      }
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.length >= 2 && segs[0] == 'q') return segs[1];
      if (segs.length >= 3 &&
          segs[0] == 'points' &&
          segs[1] == 'qr-claim') {
        return segs[2];
      }
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{2,64}$').hasMatch(t)) return t;
    return null;
  }

  Future<void> _onRaw(String raw) async {
    final payload = raw.trim();
    if (payload.isEmpty || _busy) return;
    final now = DateTime.now();
    if (_lastPayload == payload &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPayload = payload;
    _lastScanAt = now;
    final code = extractCode(payload);
    if (code == null) {
      setState(() {
        _flashOk = false;
        _flash = 'Bu bir puan QR’ı değil';
      });
      return;
    }
    await _claim(code);
  }

  Future<void> _claim(String code) async {
    if (_busy) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      if (!mounted) return;
      context.push('/login?next=${Uri.encodeComponent('/points/qr-claim/$code')}');
      return;
    }
    setState(() {
      _busy = true;
      _flash = null;
    });
    try {
      final res = await PointsService.claimPointsQr(code);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final pts = res['points'] ?? 0;
      final bal = res['balance'];
      setState(() {
        _flashOk = true;
        _flash = bal == null
            ? '+$pts KP kazandın!'
            : '+$pts KP · bakiye $bal';
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _flashOk = false;
        _flash = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _flashOk = false;
        _flash = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('QR’ı bul · puanı kap'),
        actions: [
          if (_camera != null)
            IconButton(
              tooltip: 'Fener',
              onPressed: () => _camera!.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_camera != null)
                  MobileScanner(
                    controller: _camera,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isEmpty) return;
                      final raw = barcodes.first.rawValue ?? '';
                      if (raw.isNotEmpty) _onRaw(raw);
                    },
                  )
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Web’de kamerayı kullanmak yerine kodu yaz.\n'
                        'Kampüste mobil uygulamayla tara.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, height: 1.45),
                      ),
                    ),
                  ),
                if (_camera != null)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: AppColors.cyan,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_busy)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_flash != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Material(
                      color: _flashOk
                          ? AppColors.lime
                          : AppColors.crimson,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _flash!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _flashOk ? AppColors.navy : Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Kampüsteki gizemli QR’ları tara, KP kazan.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Üye değilsen QR seni uygulamayı indirmeye yönlendirir.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _manual,
                    decoration: const InputDecoration(
                      labelText: 'Kodu elle gir',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onRaw,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _onRaw(_manual.text),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Puanı kap'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
