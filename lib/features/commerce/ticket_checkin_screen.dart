import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import 'commerce_service.dart';

/// Organizatör kapı QR doğrulama — kamera + elle kod.
class TicketCheckInScreen extends StatefulWidget {
  const TicketCheckInScreen({super.key});

  @override
  State<TicketCheckInScreen> createState() => _TicketCheckInScreenState();
}

class _TicketCheckInScreenState extends State<TicketCheckInScreen> {
  final _manual = TextEditingController();
  final _recent = <Map<String, dynamic>>[];
  MobileScannerController? _camera;
  bool _busy = false;
  String? _flash;
  bool _flashOk = false;
  bool _flashInvalid = false;
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
  }

  @override
  void dispose() {
    _manual.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _verify(String raw) async {
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
    setState(() {
      _busy = true;
      _flash = null;
      _flashInvalid = false;
    });
    try {
      var result = await CommerceService.checkInTicket(payload);
      if (!mounted) return;
      if (result['needsConfirm'] == true) {
        final next = result['nextEntry'] ?? '';
        final remain = result['remaining'] ?? '';
        final name = '${result['userName'] ?? ''}'.trim();
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Çoklu giriş'),
            content: Text(
              '${name.isEmpty ? 'Bu bilet' : name} daha önce okutuldu.\n\n'
              '$next. girişi okutmak üzeresin (kalan $remain). Onaylıyor musun?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Evet, okut'),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          result = await CommerceService.checkInTicket(payload, confirm: true);
        } else {
          setState(() {
            _flashOk = false;
            _flashInvalid = false;
            _flash = 'İkinci giriş iptal edildi';
          });
          return;
        }
      }
      if (!mounted) return;
      final already = result['already'] == true;
      final invalid = result['invalid'] == true;
      final ok = result['ok'] == true && !invalid;
      HapticFeedback.mediumImpact();
      setState(() {
        _flashOk = ok;
        _flashInvalid = invalid;
        _flash = invalid
            ? '${result['message'] ?? 'Geçersiz'}'
            : already
                ? (result['remaining'] == 0 || result['remaining'] == '0'
                    ? 'Bu biletin giriş hakkı doldu'
                    : 'Bu okutma zaten kayıtlarda')
                : ok
                    ? '${result['message'] ?? (result['entryType'] == 'multi' ? 'Giriş ${result['entriesUsed']}/${result['entryLimit']} · kalan ${result['remaining']}' : 'Giriş onaylandı')}'
                    : '${result['message'] ?? 'Doğrulanamadı'}';
        _recent.insert(0, {
          'ok': ok,
          'already': already,
          'invalid': invalid,
          'name': '${result['userName'] ?? result['userEmail'] ?? ''}',
          'event': '${result['eventTitle'] ?? ''}',
          'tier': '${result['tierLabel'] ?? ''}',
          'code': '${result['shortCode'] ?? ''}',
          'at': DateTime.now().toIso8601String(),
        });
        if (_recent.length > 20) _recent.removeLast();
      });
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _flashOk = false;
        _flashInvalid = true;
        _flash = 'Geçersiz · $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilet doğrula'),
        actions: [
          if (_camera != null)
            IconButton(
              tooltip: 'Fener',
              onPressed: () => _camera!.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                Expanded(flex: 3, child: _scannerPane()),
                Expanded(flex: 2, child: _sidePane()),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 3, child: _scannerPane()),
                Expanded(flex: 2, child: _sidePane()),
              ],
            ),
    );
  }

  Widget _scannerPane() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_camera != null)
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final raw = barcodes.first.rawValue ?? '';
              if (raw.isNotEmpty) _verify(raw);
            },
          )
        else
          Container(
            color: AppColors.navy,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Web’de kamera tarayıcı yerine bilet kodunu yazın.\n'
              'Kapıda mobil uygulamayı kullanın.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, height: 1.45),
            ),
          ),
        if (_camera != null)
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 3),
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
              color: _flashInvalid
                  ? const Color(0xFF991B1B)
                  : _flashOk
                      ? const Color(0xFF166534)
                      : const Color(0xFF92400E),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      _flashInvalid
                          ? Icons.cancel_rounded
                          : _flashOk
                              ? Icons.verified_rounded
                              : Icons.info_outline,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _flash!,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sidePane() {
    return Container(
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Hızlı doğrulama',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Katılımcının bilet QR’ını kare içine alın. '
            'Kod okunmazsa aşağıdaki alana yapıştırın.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manual,
            decoration: InputDecoration(
              labelText: 'Bilet kodu',
              hintText: 'ABC-123 veya QR',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Doğrula',
                onPressed: () => _verify(_manual.text),
                icon: const Icon(Icons.check_circle_outline),
              ),
            ),
            onSubmitted: _verify,
          ),
          const SizedBox(height: 16),
          const Text(
            'Son okutmalar',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            const Text(
              'Henüz tarama yok.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ..._recent.map((r) {
            final ok = r['ok'] == true;
            final already = r['already'] == true;
            final invalid = r['invalid'] == true;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                invalid
                    ? Icons.cancel_rounded
                    : already
                        ? Icons.replay
                        : ok
                            ? Icons.verified
                            : Icons.error_outline,
                color: invalid
                    ? const Color(0xFF991B1B)
                    : ok
                        ? AppColors.lime
                        : Colors.redAccent,
              ),
              title: Text(
                '${r['name']}'.trim().isEmpty ? 'Katılımcı' : '${r['name']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                [
                  if ('${r['event']}'.isNotEmpty) '${r['event']}',
                  if ('${r['tier']}'.isNotEmpty) '${r['tier']}',
                  if ('${r['code']}'.isNotEmpty) '${r['code']}',
                  invalid
                      ? 'geçersiz'
                      : already
                          ? 'daha önce okutuldu'
                          : (ok ? 'giriş' : 'red'),
                ].join(' · '),
              ),
            );
          }),
        ],
      ),
    );
  }
}
