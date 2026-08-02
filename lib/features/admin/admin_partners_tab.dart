import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/safe_network_image.dart';
import '../partners/partner_models.dart';
import '../partners/partners_provider.dart';

/// Admin: iş ortakları CRUD — logo + yazı + boyut.
class AdminPartnersTab extends StatelessWidget {
  const AdminPartnersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final partners = context.watch<PartnersProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Ortak ekle'),
      ),
      body: partners.items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MtIcon(MtIcons.partners, size: 40, color: AppColors.navy),
                    SizedBox(height: 12),
                    Text(
                      'Henüz iş ortağı yok',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Logo + isim + açıklama ekle; boyutunu kaydırıcıyla ayarla.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: partners.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = partners.items[i];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    leading: p.logoUrl.startsWith('http')
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SafeNetworkImage(
                              url: p.logoUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          )
                        : const MtIcon(MtIcons.partners, size: 28),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      p.blurb.isEmpty
                          ? 'Boyut ${p.logoSize.toInt()}px'
                          : '${p.blurb}\nBoyut ${p.logoSize.toInt()}px',
                      maxLines: 3,
                    ),
                    isThreeLine: p.blurb.isNotEmpty,
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Yukarı',
                          onPressed: () =>
                              context.read<PartnersProvider>().move(p.id, up: true),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                        IconButton(
                          tooltip: 'Aşağı',
                          onPressed: () => context
                              .read<PartnersProvider>()
                              .move(p.id, up: false),
                          icon: const Icon(Icons.arrow_downward_rounded),
                        ),
                        IconButton(
                          tooltip: 'Düzenle',
                          onPressed: () => _edit(context, existing: p),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Sil',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Ortağı sil'),
                                content: Text('${p.name} kaldırılsın mı?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Vazgeç'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.crimson,
                                    ),
                                    child: const Text('Sil'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await context
                                  .read<PartnersProvider>()
                                  .remove(p.id);
                            }
                          },
                          icon: const MtIcon(
                            MtIcons.trash,
                            size: 20,
                            color: AppColors.crimson,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _edit(
    BuildContext context, {
    BusinessPartner? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final blurb = TextEditingController(text: existing?.blurb ?? '');
    final link = TextEditingController(text: existing?.linkUrl ?? '');
    var logoUrl = existing?.logoUrl ?? '';
    var logoSize = existing?.logoSize ?? 64;
    var uploading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'İş ortağı ekle' : 'Düzenle'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'İsim / marka',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: blurb,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Kısa yazı',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: link,
                        decoration: const InputDecoration(
                          labelText: 'Web sitesi (opsiyonel)',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          if (logoUrl.startsWith('http'))
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SafeNetworkImage(
                                url: logoUrl,
                                width: logoSize.clamp(40, 96),
                                height: logoSize.clamp(40, 96),
                                fit: BoxFit.contain,
                              ),
                            )
                          else
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const MtIcon(MtIcons.partners, size: 28),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: uploading
                                  ? null
                                  : () async {
                                      final partners =
                                          context.read<PartnersProvider>();
                                      setLocal(() => uploading = true);
                                      try {
                                        final f = await MediaUpload.pickImage();
                                        if (f == null) return;
                                        final url = await partners.uploadLogo(f);
                                        if (!ctx.mounted) return;
                                        setLocal(() => logoUrl = url);
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                        }
                                      } finally {
                                        if (ctx.mounted) {
                                          setLocal(() => uploading = false);
                                        }
                                      }
                                    },
                              icon: uploading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.image_outlined),
                              label: Text(
                                logoUrl.isEmpty
                                    ? 'Logo yükle'
                                    : 'Logoyu değiştir',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Logo boyutu'),
                          Expanded(
                            child: Slider(
                              value: logoSize,
                              min: 36,
                              max: 120,
                              divisions: 21,
                              label: '${logoSize.round()} px',
                              onChanged: (v) => setLocal(() => logoSize = v),
                            ),
                          ),
                          Text('${logoSize.round()}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await context.read<PartnersProvider>().upsert(
                            id: existing?.id,
                            name: name.text,
                            blurb: blurb.text,
                            logoUrl: logoUrl,
                            linkUrl: link.text,
                            logoSize: logoSize,
                            sortOrder: existing?.sortOrder,
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
