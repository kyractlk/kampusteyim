import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';

/// Tanıtım sistemleri hub — alt menüler (ileride genişler).
class AdminPromoHubTab extends StatefulWidget {
  const AdminPromoHubTab({super.key});

  @override
  State<AdminPromoHubTab> createState() => _AdminPromoHubTabState();
}

class _AdminPromoHubTabState extends State<AdminPromoHubTab> {
  /// kampusteyim | (gelecek alt menüler)
  String _sub = 'kampusteyim';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tanıtım sistemleri',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kampüs tanıtım araçları. Yeni alt menüler buraya eklenecek.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _subChip(
                      'KampüsteyimAPP tanıtımları',
                      _sub == 'kampusteyim',
                      () => setState(() => _sub = 'kampusteyim'),
                    ),
                    _subChip(
                      'Yakında…',
                      false,
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Yeni tanıtım alt menüleri yakında eklenecek.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_sub) {
            'kampusteyim' => const _KampusteyimPromoPanel(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Widget _subChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _KampusteyimPromoPanel extends StatefulWidget {
  const _KampusteyimPromoPanel();

  @override
  State<_KampusteyimPromoPanel> createState() => _KampusteyimPromoPanelState();
}

class _KampusteyimPromoPanelState extends State<_KampusteyimPromoPanel> {
  final _play = TextEditingController();
  final _apple = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _total = 0;
  int _ios = 0;
  int _android = 0;
  int _other = 0;
  String _qrTarget = '${AppInfo.marketingUrl}/get.html';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _play.dispose();
    _apple.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final promo = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('promo')
          .get();
      final stats = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('promo_stats')
          .get();
      final p = promo.data() ?? {};
      final s = stats.data() ?? {};
      _play.text = '${p['playStoreUrl'] ?? ''}';
      _apple.text = '${p['appStoreUrl'] ?? ''}';
      _qrTarget =
          '${p['qrTargetUrl'] ?? '${AppInfo.marketingUrl}/get.html'}';
      _total = (s['total'] as num?)?.toInt() ?? 0;
      _ios = (s['ios'] as num?)?.toInt() ?? 0;
      _android = (s['android'] as num?)?.toInt() ?? 0;
      _other = (s['other'] as num?)?.toInt() ?? 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('updatePromoConfig');
      final res = await callable.call({
        'playStoreUrl': _play.text.trim(),
        'appStoreUrl': _apple.text.trim(),
        'qrTargetUrl': _qrTarget.trim(),
      });
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      if (data['qrTargetUrl'] != null) {
        _qrTarget = '${data['qrTargetUrl']}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tanıtım linkleri kaydedildi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _qrImageUrl {
    final data = Uri.encodeComponent(_qrTarget);
    return 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&margin=10&data=$data';
  }

  Widget _qrPreview({double size = 200}) {
    final data = _qrTarget.trim();
    if (data.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(child: Text('QR hedefi yok')),
      );
    }
    return QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.navy,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.navy,
      ),
      errorStateBuilder: (context, error) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            'QR üretilemedi\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  Future<void> _printQr() async {
    final url = _qrTarget;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR çıktı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColoredBox(
                color: Colors.white,
                child: _qrPreview(size: 240),
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                'Link panoya kopyalandı. Ekran görüntüsü alarak veya '
                'aşağıdan harici QR görselini açarak çıktı alabilirsin.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(_qrImageUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('PNG aç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text(
          'İndirme linkleri',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Landing’deki Google Play / App Store rozetleri ve QR yönlendirmesi '
          'bu linkleri kullanır. QR okutulunca iOS → App Store, Android → Play.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _play,
          decoration: const InputDecoration(
            labelText: 'Google Play URL',
            hintText: 'https://play.google.com/store/apps/details?id=…',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _apple,
          decoration: const InputDecoration(
            labelText: 'App Store URL',
            hintText: 'https://apps.apple.com/…',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
        const SizedBox(height: 22),
        const Text(
          'Akıllı QR',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _qrTarget,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Center(
          child: Material(
            color: Colors.white,
            elevation: 1,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _qrPreview(size: 200),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _qrTarget)),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Link kopyala'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _printQr,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('QR çıktı'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Okutulma istatistikleri',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _stat('Toplam', '$_total'),
            _stat('iOS', '$_ios'),
            _stat('Android', '$_android'),
            _stat('Diğer', '$_other'),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('İstatistikleri yenile'),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}
