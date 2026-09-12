import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../promo/promo_card_download.dart';
import '../points/points_models.dart';

/// Admin: puan QR oluştur, indir, okutanları gör, CSV al.
class AdminQrHuntTab extends StatefulWidget {
  const AdminQrHuntTab({super.key});

  @override
  State<AdminQrHuntTab> createState() => _AdminQrHuntTabState();
}

class _AdminQrHuntTabState extends State<AdminQrHuntTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await PointsService.adminListPointsQr();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _createOrEdit([Map<String, dynamic>? existing]) async {
    final titleCtrl = TextEditingController(text: '${existing?['title'] ?? ''}');
    final slugCtrl = TextEditingController(text: '${existing?['slug'] ?? ''}');
    final pointsCtrl =
        TextEditingController(text: '${existing?['points'] ?? 50}');
    final maxCtrl =
        TextEditingController(text: '${existing?['maxClaims'] ?? 100}');
    final mysteryCtrl = TextEditingController(
      text: '${existing?['mysteryLine'] ?? 'Gizemli bir şey buldun'}',
    );
    var active = existing?['active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Puan QR oluştur' : 'QR düzenle'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'İç ad (etkinlik vb.)',
                      helperText: 'Sadece panelde görünür',
                    ),
                  ),
                  TextField(
                    controller: slugCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Slug',
                      helperText: 'URL / sistem kodu · örn. bahar-senligi',
                    ),
                  ),
                  TextField(
                    controller: pointsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Verilecek KP',
                      helperText: 'QR çıktısında yazılmaz',
                    ),
                  ),
                  TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ödül dönüşüm sınırı',
                      helperText: '0 = sınırsız toplam okutma',
                    ),
                  ),
                  TextField(
                    controller: mysteryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Gizemli satır (çıktı)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif'),
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await PointsService.adminUpsertPointsQr({
        if (existing?['id'] != null) 'id': existing!['id'],
        'title': titleCtrl.text.trim(),
        'slug': slugCtrl.text.trim(),
        'points': int.tryParse(pointsCtrl.text.trim()) ?? 0,
        'maxClaims': int.tryParse(maxCtrl.text.trim()) ?? 0,
        'mysteryLine': mysteryCtrl.text.trim(),
        'active': active,
        'perUserLimit': 1,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR kaydedildi')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  String _csvCell(Object? v) {
    final s = '${v ?? ''}'.replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _showClaims(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final claims = await PointsService.adminListPointsQrClaims(id);
      if (!mounted) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Okutanlar · ${item['title'] ?? item['slug']}'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: claims.isEmpty
                ? const Center(child: Text('Henüz okutma yok'))
                : ListView.separated(
                    itemCount: claims.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = claims[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${c['userName'] ?? c['username'] ?? c['uid']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${c['userEmail'] ?? ''} · +${c['points']} KP',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final buf = StringBuffer(
                  'ad,kullanici,eposta,uid,puan,slug,tarih\n',
                );
                for (final c in claims) {
                  buf.writeln(
                    [
                      _csvCell(c['userName']),
                      _csvCell(c['username']),
                      _csvCell(c['userEmail']),
                      _csvCell(c['uid']),
                      c['points'] ?? 0,
                      _csvCell(c['slug'] ?? item['slug']),
                      _csvCell(c['createdAt']),
                    ].join(','),
                  );
                }
                await Clipboard.setData(ClipboardData(text: buf.toString()));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('CSV panoya kopyalandı')),
                  );
                }
              },
              child: const Text('CSV kopyala'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _downloadQr(Map<String, dynamic> item) async {
    final link = '${item['deepLink'] ?? ''}';
    if (link.isEmpty) return;
    final key = GlobalKey();
    final mystery = '${item['mysteryLine'] ?? 'Gizemli bir şey buldun'}';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR çıktı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: key,
                child: _MysteryQrCard(data: link, mysteryLine: mystery),
              ),
              const SizedBox(height: 12),
              const Text(
                'Çıktıda puan yazılmaz. PNG indir veya linki kopyala.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Deeplink kopyalandı')),
                );
              }
            },
            child: const Text('Link kopyala'),
          ),
          TextButton(
            onPressed: () {
              final png =
                  'https://api.qrserver.com/v1/create-qr-code/?size=600x600&margin=16&data=${Uri.encodeComponent(link)}';
              launchUrl(Uri.parse(png), mode: LaunchMode.externalApplication);
            },
            child: const Text('PNG aç'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await Future<void>.delayed(const Duration(milliseconds: 60));
                final boundary =
                    key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                if (boundary == null) throw Exception('QR henüz hazır değil');
                final image = await boundary.toImage(pixelRatio: 3);
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                if (bytes == null) throw Exception('PNG üretilemedi');
                await savePngBytes(
                  bytes.buffer.asUint8List(),
                  'qr_${item['slug'] ?? 'hunt'}.png',
                );
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('QR indirildi')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$e')),
                  );
                }
              }
            },
            child: const Text('İndir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Yenile')),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'QR’ı bul · puanı kap',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Puan QR’ı oluştur'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Slug etkinlik adı gibi iç kullanım içindir. QR çıktısında puan görünmez; '
          'üye olmayanlar deeplink ile indirmeye gider.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('Henüz puan QR’ı yok')),
          )
        else
          ..._items.map((item) {
            final max = (item['maxClaims'] as num?)?.toInt() ?? 0;
            final count = (item['claimCount'] as num?)?.toInt() ?? 0;
            final active = item['active'] != false;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['title'] ?? item['slug']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.lime.withValues(alpha: 0.2)
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            active ? 'Aktif' : 'Kapalı',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: active ? AppColors.navy : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'slug: ${item['slug']} · ${item['points']} KP · '
                      'okutma $count${max > 0 ? '/$max' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _downloadQr(item),
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('QR indir'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showClaims(item),
                          icon: const Icon(Icons.people_outline, size: 18),
                          label: const Text('Okutanlar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _createOrEdit(item),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Düzenle'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('QR silinsin mi?'),
                                content: Text('${item['title'] ?? item['slug']}'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Vazgeç'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Sil'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true) return;
                            try {
                              await PointsService.adminDeletePointsQr('${item['id']}');
                              await _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Sil'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _MysteryQrCard extends StatelessWidget {
  const _MysteryQrCard({required this.data, required this.mysteryLine});

  final String data;
  final String mysteryLine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F3A), Color(0xFF163356)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'QR’ı bul · puanı kap',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            mysteryLine,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.navy,
              ),
              embeddedImage: const AssetImage(AppAssets.kampusIcon),
              embeddedImageStyle: const QrEmbeddedImageStyle(
                size: Size(36, 36),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'KampüsteyimAPP',
            style: TextStyle(
              color: AppColors.cyan.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
