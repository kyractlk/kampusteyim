import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../data/mock/mock_data.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../commerce/commerce_service.dart';
import '../events/event_banner_picker.dart';
import '../feed/feed_provider.dart';

/// Organizatör firma: kampüs dışı etkinlik oluşturur → admin onayı.
class CompanyEventsScreen extends StatefulWidget {
  const CompanyEventsScreen({super.key});

  @override
  State<CompanyEventsScreen> createState() => _CompanyEventsScreenState();
}

class _CompanyEventsScreenState extends State<CompanyEventsScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final me = auth.user;
    if (me == null || !me.isCompany) {
      return const Scaffold(
        body: Center(child: Text('Firma hesabı gerekli')),
      );
    }
    if (!me.isEventOrganizer) {
      return Scaffold(
        appBar: AppBar(title: const Text('Etkinlikler')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bu hesap henüz etkinlik organizatörü değil. '
            'Admin panelinden “Etkinlik organizatörü yap” ile yetki verilmeli.',
            style: TextStyle(height: 1.45),
          ),
        ),
      );
    }

    final mine = context
        .watch<FeedProvider>()
        .events
        .where((e) => e.organizerCompanyId == me.id)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Kampüs dışı etkinliklerim')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, me),
        icon: const Icon(Icons.add),
        label: const Text('Etkinlik ekle'),
      ),
      body: mine.isEmpty
          ? const Center(
              child: Text('Henüz etkinlik yok. Yeni etkinlik ekle.'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: mine.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = mine[i];
                final date =
                    DateFormat('d MMM yyyy · HH:mm', 'tr').format(e.startsAt);
                return Card(
                  child: ListTile(
                    title: Text(e.title,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      '$date\n${e.city.isEmpty ? 'Gaziantep' : e.city} · ${e.status}'
                      '${e.refundsAllowed ? ' · iade var' : ' · iade yok'}',
                    ),
                    isThreeLine: true,
                    trailing: Chip(
                      label: Text(
                        e.status == 'approved'
                            ? 'Onaylı'
                            : e.status == 'rejected'
                                ? 'Red'
                                : 'Bekliyor',
                      ),
                    ),
                    onTap: () => _openEditor(context, me, existing: e),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openEditor(BuildContext context, AppUser me, {CampusEvent? existing}) async {
    final editing = existing != null;
    if (!editing) {
      try {
        final data = await CommerceService.getOrganizerDashboard();
        final s = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
        final iban = '${s['payoutIban'] ?? ''}'.trim();
        final holder = '${s['payoutIbanHolder'] ?? ''}'.trim();
        if (iban.isEmpty || holder.isEmpty) {
          if (!context.mounted) return;
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Önce IBAN kaydet'),
              content: const Text(
                'Etkinlik açmadan önce organizatör çekim IBAN’ını '
                'sisteme kaydetmelisin.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Organizatör paneli'),
                ),
              ],
            ),
          );
          if (go == true && context.mounted) {
            context.push('/firma/organizer');
          }
          return;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    final title = TextEditingController(text: existing?.title ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final location = TextEditingController(text: existing?.location ?? '');
    final mapUrl = TextEditingController(text: existing?.mapUrl ?? '');
    final rules = TextEditingController(text: existing?.rules ?? '');
    final capacity =
        TextEditingController(text: '${existing?.capacity ?? 100}');
    final drafts = <_PriceTierDraft>[
      if (existing != null && existing.priceTiers.isNotEmpty)
        ...existing.priceTiers.map(_PriceTierDraft.fromTier)
      else
        _PriceTierDraft(),
    ];
    var city = (existing?.city.isNotEmpty == true)
        ? existing!.city
        : MockData.cities.first;
    var startsAt =
        existing?.startsAt ?? DateTime.now().add(const Duration(days: 14));
    DateTime? deadline = existing?.applicationDeadline;
    var bannerUrl = existing?.imageUrl ?? '';
    var refundsAllowed = existing?.refundsAllowed == true;
    var bannerBusy = false;

    try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      editing ? 'Etkinliği düzenle' : 'Yeni kampüs dışı etkinlik',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      editing
                          ? 'İade politikası ve bilet tipi sonradan da değişebilir. Satılmış biletlerin tipi değişmez.'
                          : 'Kaydettikten sonra admin onayına düşer. Onaylanınca listelenir.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    EventBannerPreview(
                      url: bannerUrl,
                      uploading: bannerBusy,
                      onPick: () async {
                        setLocal(() => bannerBusy = true);
                        final url = await pickEventBanner(ctx);
                        setLocal(() {
                          bannerBusy = false;
                          if (url != null && url.isNotEmpty) bannerUrl = url;
                        });
                      },
                    ),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Başlık *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: desc,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: 'Açıklama *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: location,
                      decoration:
                          const InputDecoration(labelText: 'Yer / mekan *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: mapUrl,
                      decoration: const InputDecoration(
                        labelText: 'Harita linki (opsiyonel)',
                        hintText: 'https://maps.google.com/...',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: rules,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: 'Kurallar'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: city,
                      decoration: const InputDecoration(labelText: 'Şehir'),
                      items: [
                        for (final c in MockData.cities)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v != null) setLocal(() => city = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: capacity,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Kontenjan'),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Etkinlik tarihi'),
                      subtitle: Text(
                        DateFormat('d MMM yyyy · HH:mm', 'tr')
                            .format(startsAt),
                      ),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: startsAt,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 730)),
                        );
                        if (d == null || !ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(startsAt),
                        );
                        if (t == null) return;
                        setLocal(() {
                          startsAt = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            t.hour,
                            t.minute,
                          );
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Son başvuru (opsiyonel)'),
                      subtitle: Text(
                        deadline == null
                            ? 'Yok'
                            : DateFormat('d MMM yyyy · HH:mm', 'tr')
                                .format(deadline!),
                      ),
                      trailing: const Icon(Icons.timer_outlined),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: deadline ?? startsAt,
                          firstDate: DateTime.now(),
                          lastDate: startsAt,
                        );
                        if (d == null || !ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(
                            deadline ?? startsAt,
                          ),
                        );
                        if (t == null) return;
                        setLocal(() {
                          deadline = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            t.hour,
                            t.minute,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Bilet dönemleri',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setLocal(
                            () => drafts.add(_PriceTierDraft(
                              label: 'Dönem ${drafts.length + 1}',
                            )),
                          ),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Dönem ekle'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Her dönemde fiyat, stok ve bilet tipi (tek / çoklu giriş) ayrı seçilir.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < drafts.length; i++)
                      _PriceTierDraftCard(
                        index: i,
                        draft: drafts[i],
                        canRemove: drafts.length > 1,
                        onChanged: () => setLocal(() {}),
                        onRemove: () => setLocal(() {
                          drafts.removeAt(i).dispose();
                        }),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('İade yapılabilir'),
                      subtitle: Text(
                        refundsAllowed
                            ? 'İade onayında bilet iptal, kontenjan açılır, bakiyeden net tutar düşer (komisyon kalır).'
                            : 'İade yok — etkinlik sayfasında ve satış sözleşmesinde belirtilir.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: refundsAllowed,
                      onChanged: (v) => setLocal(() => refundsAllowed = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        editing ? 'Kaydet' : 'Admin onayına gönder',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true || !context.mounted) return;
    if (title.text.trim().isEmpty ||
        desc.text.trim().isEmpty ||
        location.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başlık, açıklama ve yer zorunlu')),
      );
      return;
    }

    final cap = int.tryParse(capacity.text) ?? 100;
    final tiers = <EventPriceTier>[];
    for (final d in drafts) {
      final t = d.toTier(
        fallbackStock: cap,
        saleEndsAt: deadline ?? startsAt,
      );
      if (t != null) tiers.add(t);
    }
    final event = CampusEvent(
      id: existing?.id ?? 'evt_${const Uuid().v4().substring(0, 10)}',
      title: title.text.trim(),
      description: desc.text.trim(),
      location: location.text.trim(),
      startsAt: startsAt,
      capacity: cap,
      audience: existing?.audience ?? 'campus',
      applicationDeadline: deadline,
      scope: 'offcampus',
      city: city,
      university: existing?.university ?? '',
      status: existing?.status ?? 'pending',
      organizerCompanyId: me.id,
      organizerCompanyName: me.fullName,
      mapUrl: mapUrl.text.trim(),
      rules: rules.text.trim(),
      priceTiers: tiers,
      paymentRequired: tiers.isNotEmpty,
      refundsAllowed: refundsAllowed,
      imageUrl: bannerUrl.isEmpty ? null : bannerUrl,
    );

    if (editing) {
      await context.read<FeedProvider>().updateEvent(event);
    } else {
      await context.read<FeedProvider>().addEvent(event);
    }
    await FirebaseFirestore.instance.collection('events').doc(event.id).set(
      event.toMap(),
      SetOptions(merge: true),
    );

    if (tiers.isNotEmpty) {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('syncEventMarketTickets')
            .call({'eventId': event.id});
      } catch (_) {}
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          editing
              ? 'Etkinlik güncellendi'
              : 'Etkinlik admin onayına gönderildi · bilet Market’e işlendi',
        ),
      ),
    );
    } finally {
      title.dispose();
      desc.dispose();
      location.dispose();
      mapUrl.dispose();
      rules.dispose();
      capacity.dispose();
      for (final d in drafts) {
        d.dispose();
      }
    }
  }
}

class _PriceTierDraft {
  _PriceTierDraft({
    String label = 'Erken kayıt',
    String amount = '0',
    String stock = '100',
    this.entryType = 'single',
    String entryLimit = '2',
    this.soldCount = 0,
    this.saleEndsAt,
  })  : label = TextEditingController(text: label),
        amount = TextEditingController(text: amount),
        stock = TextEditingController(text: stock),
        entryLimit = TextEditingController(text: entryLimit);

  factory _PriceTierDraft.fromTier(EventPriceTier t) {
    return _PriceTierDraft(
      label: t.label.isNotEmpty ? t.label : 'Bilet',
      amount: t.amount.toStringAsFixed(0),
      stock: '${t.stock ?? 100}',
      entryType: t.isMultiEntry ? 'multi' : 'single',
      entryLimit: '${t.isMultiEntry ? t.entryLimit : 2}',
      soldCount: t.soldCount,
      saleEndsAt: t.saleEndsAt,
    );
  }

  final TextEditingController label;
  final TextEditingController amount;
  final TextEditingController stock;
  final TextEditingController entryLimit;
  String entryType;
  int soldCount;
  DateTime? saleEndsAt;

  EventPriceTier? toTier({required int fallbackStock, DateTime? saleEndsAt}) {
    final n = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    if (n <= 0) return null;
    var limit = int.tryParse(entryLimit.text.trim()) ?? 2;
    if (entryType != 'multi') limit = 1;
    if (entryType == 'multi' && limit < 2) limit = 2;
    if (limit > 99) limit = 99;
    return EventPriceTier(
      label: label.text.trim().isEmpty ? 'Bilet' : label.text.trim(),
      amount: n,
      stock: int.tryParse(stock.text.trim()) ?? fallbackStock,
      saleEndsAt: this.saleEndsAt ?? saleEndsAt,
      entryType: entryType,
      entryLimit: limit,
      soldCount: soldCount,
    );
  }

  void dispose() {
    label.dispose();
    amount.dispose();
    stock.dispose();
    entryLimit.dispose();
  }
}

class _PriceTierDraftCard extends StatelessWidget {
  const _PriceTierDraftCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _PriceTierDraft draft;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dönem ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Dönemi sil',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            TextField(
              controller: draft.label,
              decoration: const InputDecoration(labelText: 'Dönem adı'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Fiyat ₺'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stok',
                      helperText: 'Bitince “Stok bitti”',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Bilet tipi',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tek giriş'),
                  selected: draft.entryType == 'single',
                  onSelected: (_) {
                    draft.entryType = 'single';
                    onChanged();
                  },
                ),
                ChoiceChip(
                  label: const Text('Çoklu giriş'),
                  selected: draft.entryType == 'multi',
                  onSelected: (_) {
                    draft.entryType = 'multi';
                    onChanged();
                  },
                ),
              ],
            ),
            if (draft.entryType == 'multi') ...[
              const SizedBox(height: 8),
              TextField(
                controller: draft.entryLimit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Kaç kez okutulabilir',
                  helperText: 'Örn. 3 → üç kez giriş, sonra bilet kapanır',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
