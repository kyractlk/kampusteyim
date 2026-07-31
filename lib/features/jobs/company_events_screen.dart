import 'package:cloud_firestore/cloud_firestore.dart';
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
        onPressed: () => _openCreate(context, me),
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
                      '$date\n${e.city.isEmpty ? 'Gaziantep' : e.city} · ${e.status}',
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
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openCreate(BuildContext context, AppUser me) async {
    // Etkinlik açmadan önce çekim IBAN zorunlu
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

    if (!context.mounted) return;
    final title = TextEditingController();
    final desc = TextEditingController();
    final location = TextEditingController();
    final mapUrl = TextEditingController();
    final rules = TextEditingController();
    final capacity = TextEditingController(text: '100');
    final priceLabel = TextEditingController(text: 'Erken kayıt');
    final priceAmount = TextEditingController(text: '0');
    var city = MockData.cities.first;
    var startsAt = DateTime.now().add(const Duration(days: 14));
    DateTime? deadline;

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
                    const Text(
                      'Yeni kampüs dışı etkinlik',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Kaydettikten sonra admin onayına düşer. Onaylanınca listelenir.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const Text(
                      'Fiyat dilimi',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceLabel,
                            decoration:
                                const InputDecoration(labelText: 'Dilimler'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: priceAmount,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: '₺'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Admin onayına gönder'),
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

    final amount = double.tryParse(priceAmount.text.replaceAll(',', '.')) ?? 0;
    final event = CampusEvent(
      id: 'evt_${const Uuid().v4().substring(0, 10)}',
      title: title.text.trim(),
      description: desc.text.trim(),
      location: location.text.trim(),
      startsAt: startsAt,
      capacity: int.tryParse(capacity.text) ?? 100,
      audience: 'campus',
      applicationDeadline: deadline,
      scope: 'offcampus',
      city: city,
      university: '',
      status: 'pending',
      organizerCompanyId: me.id,
      organizerCompanyName: me.fullName,
      mapUrl: mapUrl.text.trim(),
      rules: rules.text.trim(),
      priceTiers: amount > 0
          ? [
              EventPriceTier(
                label: priceLabel.text.trim().isEmpty
                    ? 'Bilet'
                    : priceLabel.text.trim(),
                amount: amount,
              ),
            ]
          : const [],
      paymentRequired: amount > 0,
    );

    await context.read<FeedProvider>().addEvent(event);
    // Firestore'a status alanının yazıldığından emin ol
    await FirebaseFirestore.instance.collection('events').doc(event.id).set(
      event.toMap(),
      SetOptions(merge: true),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Etkinlik admin onayına gönderildi'),
      ),
    );
  }
}
