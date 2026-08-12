import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import 'delivery_address_form.dart';

/// Profil → Teslimat adreslerim.
class DeliveryAddressesScreen extends StatelessWidget {
  const DeliveryAddressesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final addr = await showDeliveryAddressEditor(context);
    if (addr == null || !context.mounted) return;
    await context.read<AuthProvider>().upsertDeliveryAddress(addr);
  }

  Future<void> _edit(BuildContext context, DeliveryAddress a) async {
    final addr = await showDeliveryAddressEditor(context, initial: a);
    if (addr == null || !context.mounted) return;
    await context.read<AuthProvider>().upsertDeliveryAddress(addr);
  }

  Future<void> _delete(BuildContext context, DeliveryAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adresi sil'),
        content: Text('${a.title} silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthProvider>().deleteDeliveryAddress(a.id);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final list = user?.deliveryAddresses ?? const <DeliveryAddress>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Teslimat adreslerim'),
        actions: [
          IconButton(
            tooltip: 'Yeni adres',
            onPressed: () => _add(context),
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 48,
                      color: AppColors.navy,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Henüz kayıtlı adresin yok.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Market siparişlerinde kullanılacak teslimat adresini ekle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _add(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Adres ekle'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = list[i];
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _edit(context, a),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: a.isDefault
                              ? AppColors.cyan.withValues(alpha: 0.55)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.home_outlined,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        a.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (a.isDefault) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.cyan
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Varsayılan',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.navy,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  a.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  a.summaryLine,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    height: 1.35,
                                  ),
                                ),
                                Text(
                                  a.phone,
                                  style: const TextStyle(
                                    color: Colors.black45,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              final auth = context.read<AuthProvider>();
                              if (v == 'default') {
                                await auth.setDefaultDeliveryAddress(a.id);
                              } else if (v == 'edit') {
                                await _edit(context, a);
                              } else if (v == 'delete') {
                                await _delete(context, a);
                              }
                            },
                            itemBuilder: (_) => [
                              if (!a.isDefault)
                                const PopupMenuItem(
                                  value: 'default',
                                  child: Text('Varsayılan yap'),
                                ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Düzenle'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Sil'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: list.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add),
              label: const Text('Yeni adres'),
            ),
    );
  }
}
