import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../data/campus_catalog.dart';
import 'admin_leads_tab.dart';

/// Başvurular hub — Landing + Elçilik başvuruları.
class AdminApplicationsHubTab extends StatefulWidget {
  const AdminApplicationsHubTab({super.key});

  @override
  State<AdminApplicationsHubTab> createState() =>
      _AdminApplicationsHubTabState();
}

class _AdminApplicationsHubTabState extends State<AdminApplicationsHubTab> {
  String _sub = 'leads';

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
                'Başvurular',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'Landing formları ve kampüs elçiliği başvuruları ayrı kuyruklarda.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Landing başvuruları'),
                      selected: _sub == 'leads',
                      onSelected: (_) => setState(() => _sub = 'leads'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Elçilik başvuruları'),
                      selected: _sub == 'ambassador',
                      onSelected: (_) =>
                          setState(() => _sub = 'ambassador'),
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
            'ambassador' => const _AmbassadorApplicationsPanel(),
            _ => const AdminLeadsTab(),
          },
        ),
      ],
    );
  }
}

class _AmbassadorApplicationsPanel extends StatelessWidget {
  const _AmbassadorApplicationsPanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ambassador_applications')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Hata: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text('Henüz elçilik başvurusu yok.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final id = docs[i].id;
            final status = '${d['status'] ?? 'open'}';
            final name = '${d['name'] ?? ''}';
            final email = '${d['email'] ?? ''}';
            final uni = '${d['university'] ?? ''}';
            final formTitle = '${d['formTitle'] ?? d['formSlug'] ?? ''}';
            return Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              child: ExpansionTile(
                title: Text(
                  name.isEmpty ? email : name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '$uni · $formTitle · $status',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('E-posta: $email'),
                        Text('Telefon: ${d['phone'] ?? ''}'),
                        const SizedBox(height: 8),
                        Text(
                          'Yanıtlar',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        ..._answers(d['answers']).map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${e.$1}: ${e.$2}'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: status == 'approved'
                                  ? null
                                  : () => _setStatus(context, id, 'approved'),
                              child: const Text('Onayla'),
                            ),
                            OutlinedButton(
                              onPressed: status == 'rejected'
                                  ? null
                                  : () => _setStatus(context, id, 'rejected'),
                              child: const Text('Reddet'),
                            ),
                            TextButton(
                              onPressed: () => _setStatus(context, id, 'done'),
                              child: const Text('Arşivle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<(String, String)> _answers(dynamic raw) {
    if (raw is! Map) return const [];
    return raw.entries
        .map((e) => ('${e.key}', '${e.value}'))
        .toList();
  }

  Future<void> _setStatus(BuildContext context, String id, String status) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminUpdateAmbassadorApplication');
      await callable.call({'applicationId': id, 'status': status});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum: $status')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncellenemedi: $e')),
        );
      }
    }
  }
}

/// Kampüs elçiliği yönetimi: elçilikler, elçiler, form builder.
class AdminAmbassadorHubTab extends StatefulWidget {
  const AdminAmbassadorHubTab({super.key});

  @override
  State<AdminAmbassadorHubTab> createState() => _AdminAmbassadorHubTabState();
}

class _AdminAmbassadorHubTabState extends State<AdminAmbassadorHubTab> {
  String _sub = 'embassies';

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
                'Kampüs Elçiliği',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Web başvuru: ${AppInfo.marketingUrl}/elcilik',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Önce form oluşturup yayına al → “İlan aç” ile elçilik sayfasına yönlendir.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in [
                      ('embassies', 'Açık pozisyonlar'),
                      ('ambassadors', 'Elçiler'),
                      ('forms', 'Başvuru formları'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.$2),
                          selected: _sub == e.$1,
                          onSelected: (_) => setState(() => _sub = e.$1),
                        ),
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
            'ambassadors' => const _AmbassadorsPanel(),
            'forms' => const _FormsPanel(),
            _ => const _EmbassiesPanel(),
          },
        ),
      ],
    );
  }
}

class _EmbassiesPanel extends StatefulWidget {
  const _EmbassiesPanel();

  @override
  State<_EmbassiesPanel> createState() => _EmbassiesPanelState();
}

class _EmbassiesPanelState extends State<_EmbassiesPanel> {
  CampusCatalog? _catalog;
  String? _catalogError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CampusCatalog.load().then((c) {
      if (mounted) setState(() => _catalog = c);
    }).catchError((e) {
      if (mounted) {
        setState(() => _catalogError = '$e');
      }
    });
  }

  String _fold(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return '';
    s = s
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('Ş', 'ş')
        .replaceAll('Ğ', 'ğ')
        .replaceAll('Ü', 'ü')
        .replaceAll('Ö', 'ö')
        .replaceAll('Ç', 'ç')
        .toLowerCase()
        .replaceAll('i\u0307', 'i')
        .replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  String? _matchCity(CampusCatalog catalog, String? raw) {
    final n = _fold(raw);
    if (n.isEmpty) return null;
    for (final c in catalog.cities) {
      if (_fold(c) == n) return c;
    }
    return raw?.trim().isNotEmpty == true ? raw!.trim() : null;
  }

  String? _matchUni(CampusCatalog catalog, String? city, String? raw) {
    final n = _fold(raw);
    if (n.isEmpty) return null;
    final pool = <String>{
      ...catalog.universitiesForCity(city),
      ...catalog.byName.keys,
    };
    for (final u in pool) {
      if (_fold(u) == n) return u;
    }
    // Kısaltma / alias: "GIBTU" → isimde geçiyorsa
    for (final u in pool) {
      final f = _fold(u);
      if (f.contains(n) || n.contains(f)) return u;
    }
    return raw?.trim().isNotEmpty == true ? raw!.trim() : null;
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _catalog != null || _catalogError != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Açık pozisyonlar · şehir/üniversite + kontenjan',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_catalog == null && _catalogError == null)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.icon(
                onPressed: !canAdd || _busy
                    ? null
                    : () => _createOrEdit(context),
                icon: const Icon(Icons.add),
                label: const Text('Pozisyon ekle'),
              ),
            ],
          ),
        ),
        if (_catalogError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              'Katalog yüklenemedi — serbest metinle ekleyebilirsin.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('embassies').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Liste okunamadı: ${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  final ca = '${a.data()['city'] ?? ''}';
                  final cb = '${b.data()['city'] ?? ''}';
                  final c = ca.compareTo(cb);
                  if (c != 0) return c;
                  return '${a.data()['name'] ?? ''}'
                      .compareTo('${b.data()['name'] ?? ''}');
                });
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'Henüz açık pozisyon yok.\n“Pozisyon ekle” ile şehir/üniversite seç.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  final active = d['active'] != false;
                  final nationwide = d['nationwide'] == true;
                  final slotsTotal = (d['slotsTotal'] as num?)?.toInt() ?? 1;
                  final slotsFilled = (d['slotsFilled'] as num?)?.toInt() ?? 0;
                  final apps = (d['applicationCount'] as num?)?.toInt() ?? 0;
                  final open = slotsTotal <= 0
                      ? 'sınırsız'
                      : '${(slotsTotal - slotsFilled).clamp(0, slotsTotal)} / $slotsTotal';
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${d['name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${nationwide ? 'Türkiye geneli' : '${d['city'] ?? ''} · ${d['university'] ?? ''}'}\n'
                        'Kontenjan: $open · Başvuru: $apps'
                        '${active ? '' : ' · PASİF'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Düzenle',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: _busy
                                ? null
                                : () => _createOrEdit(
                                      context,
                                      id: doc.id,
                                      existing: d,
                                    ),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red.shade700,
                            onPressed: _busy
                                ? null
                                : () => _delete(context, doc.id, '${d['name'] ?? ''}'),
                          ),
                          Switch(
                            value: active,
                            onChanged: _busy
                                ? null
                                : (v) => _setActive(doc.id, v),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _setActive(String id, bool active) async {
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminUpsertEmbassy');
      await callable.call({'id': id, 'active': active, 'patchActiveOnly': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum güncellenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pozisyonu sil'),
        content: Text(
          '"$name" kalıcı olarak silinsin mi?\nLanding’den de kalkar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminDeleteEmbassy');
      await callable.call({'id': id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pozisyon silindi')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silinemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createOrEdit(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? existing,
  }) async {
    final catalog = _catalog;
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final desc =
        TextEditingController(text: '${existing?['description'] ?? ''}');
    final slotsCtrl = TextEditingController(
      text: '${(existing?['slotsTotal'] as num?)?.toInt() ?? 1}',
    );
    final filledCtrl = TextEditingController(
      text: '${(existing?['slotsFilled'] as num?)?.toInt() ?? 0}',
    );
    var nationwide = existing?['nationwide'] == true ||
        _fold('${existing?['city'] ?? ''}') == _fold('Türkiye geneli');

    String cityText = '';
    String uniText = '';
    if (!nationwide) {
      cityText = catalog != null
          ? (_matchCity(catalog, '${existing?['city'] ?? ''}') ??
              '${existing?['city'] ?? ''}')
          : '${existing?['city'] ?? ''}';
      uniText = catalog != null
          ? (_matchUni(catalog, cityText, '${existing?['university'] ?? ''}') ??
              '${existing?['university'] ?? ''}')
          : '${existing?['university'] ?? ''}';
    }
    final cityCtrl = TextEditingController(text: cityText);
    final uniCtrl = TextEditingController(text: uniText);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final citySuggestions = catalog?.cities ?? const <String>[];
            final uniSuggestions = catalog == null
                ? const <String>[]
                : catalog.universitiesForCity(
                    _matchCity(catalog, cityCtrl.text) ?? cityCtrl.text,
                  );
            return AlertDialog(
              title: Text(id == null ? 'Açık pozisyon ekle' : 'Pozisyonu düzenle'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Pozisyon / elçilik adı *',
                          hintText: 'ör. GAÜN Kampüs Elçisi',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Türkiye geneli'),
                        subtitle: const Text(
                          'Şehir/üniversite şartı yok — ulusal pozisyon',
                        ),
                        value: nationwide,
                        onChanged: (v) => setLocal(() {
                          nationwide = v;
                          if (v) {
                            cityCtrl.clear();
                            uniCtrl.clear();
                          }
                        }),
                      ),
                      if (!nationwide) ...[
                        Autocomplete<String>(
                          initialValue: TextEditingValue(text: cityCtrl.text),
                          optionsBuilder: (tv) {
                            final q = _fold(tv.text);
                            if (q.isEmpty) {
                              return citySuggestions.take(40);
                            }
                            return citySuggestions
                                .where((c) => _fold(c).contains(q))
                                .take(40);
                          },
                          onSelected: (v) {
                            cityCtrl.text = v;
                            uniCtrl.clear();
                            setLocal(() {});
                          },
                          fieldViewBuilder:
                              (context, textCtrl, focus, onSubmit) {
                            // Senkron tut
                            if (textCtrl.text != cityCtrl.text &&
                                !focus.hasFocus) {
                              textCtrl.text = cityCtrl.text;
                            }
                            return TextField(
                              controller: textCtrl,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Şehir *',
                                hintText: 'Yazarak ara / seç',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                cityCtrl.text = v;
                                setLocal(() {});
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Autocomplete<String>(
                          initialValue: TextEditingValue(text: uniCtrl.text),
                          optionsBuilder: (tv) {
                            final q = _fold(tv.text);
                            final pool = uniSuggestions.isNotEmpty
                                ? uniSuggestions
                                : (catalog?.byName.keys.toList() ??
                                    const <String>[]);
                            if (q.isEmpty) return pool.take(40);
                            return pool
                                .where((u) => _fold(u).contains(q))
                                .take(40);
                          },
                          onSelected: (v) {
                            uniCtrl.text = v;
                            setLocal(() {});
                          },
                          fieldViewBuilder:
                              (context, textCtrl, focus, onSubmit) {
                            if (textCtrl.text != uniCtrl.text &&
                                !focus.hasFocus) {
                              textCtrl.text = uniCtrl.text;
                            }
                            return TextField(
                              controller: textCtrl,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Üniversite *',
                                hintText: 'Katalogdan seç veya özel ad yaz',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) {
                                uniCtrl.text = v;
                              },
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: slotsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Toplam kontenjan',
                                helperText: '0 = sınırsız',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: filledCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Dolu (onaylı)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: desc,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama (landing’de görünür)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
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
                  onPressed: () {
                    if (name.text.trim().isEmpty) return;
                    if (!nationwide &&
                        (cityCtrl.text.trim().isEmpty ||
                            uniCtrl.text.trim().isEmpty)) {
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    final payloadName = name.text.trim();
    final payloadDesc = desc.text.trim();
    final payloadCity = cityCtrl.text.trim();
    final payloadUni = uniCtrl.text.trim();
    final payloadSlots = int.tryParse(slotsCtrl.text.trim()) ?? 1;
    final payloadFilled = int.tryParse(filledCtrl.text.trim()) ?? 0;
    final payloadNationwide = nationwide;
    name.dispose();
    desc.dispose();
    slotsCtrl.dispose();
    filledCtrl.dispose();
    cityCtrl.dispose();
    uniCtrl.dispose();

    if (ok != true) return;
    if (payloadName.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pozisyon adı gerekli')),
        );
      }
      return;
    }
    if (!payloadNationwide &&
        (payloadCity.isEmpty || payloadUni.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şehir ve üniversite seç / yaz')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminUpsertEmbassy');
      await callable.call({
        if (id != null) 'id': id,
        'name': payloadName,
        'nationwide': payloadNationwide,
        'city': payloadNationwide ? 'Türkiye geneli' : payloadCity,
        'university':
            payloadNationwide ? 'Türkiye geneli' : payloadUni,
        'description': payloadDesc,
        'slotsTotal': payloadSlots,
        'slotsFilled': payloadFilled,
        'formSlug': 'kampus-elcisi',
        'active': existing?['active'] != false,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pozisyon kaydedildi · elcilik sayfasında görünür',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AmbassadorsPanel extends StatefulWidget {
  const _AmbassadorsPanel();

  @override
  State<_AmbassadorsPanel> createState() => _AmbassadorsPanelState();
}

class _AmbassadorsPanelState extends State<_AmbassadorsPanel> {
  final _userCtrl = TextEditingController();
  String? _embassyId;
  bool _busy = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Elçi ata',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 6),
        const Text(
          'Kullanıcıya yalnızca Kampüs Elçisi rozeti + unvan verilir (gold tick verilmez).',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _userCtrl,
          decoration: const InputDecoration(
            labelText: 'Kullanıcı (ad / e-posta / @handle / uid)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('embassies')
              .where('active', isEqualTo: true)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            return DropdownButtonFormField<String>(
              initialValue: _embassyId,
              decoration: const InputDecoration(
                labelText: 'Elçilik',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final d in docs)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text('${d.data()['name'] ?? d.id}'),
                  ),
              ],
              onChanged: (v) => setState(() => _embassyId = v),
            );
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _assign,
          child: Text(_busy ? 'Kaydediliyor…' : 'Elçi olarak ata'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Aktif elçiler',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('isCampusAmbassador', isEqualTo: true)
              .limit(100)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Text('Henüz elçi yok.');
            }
            return Column(
              children: [
                for (final d in docs)
                  Card(
                    child: ListTile(
                      title: Text(
                        '${d.data()['firstName'] ?? ''} ${d.data()['lastName'] ?? ''}'
                            .trim(),
                      ),
                      subtitle: Text(
                        '@${d.data()['username'] ?? d.id} · '
                        '${d.data()['badgeTitle'] ?? 'Kampüs Elçisi'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _revoke(d.id),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _assign() async {
    setState(() => _busy = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminSetCampusAmbassador');
      await callable.call({
        'userKey': _userCtrl.text.trim(),
        'embassyId': _embassyId,
        'active': true,
        'badgeTitle': 'Kampüs Elçisi',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elçi atandı')),
        );
        _userCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(String uid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminSetCampusAmbassador');
      await callable.call({
        'userKey': uid,
        'active': false,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaldırılamadı: $e')),
        );
      }
    }
  }
}

class _FormsPanel extends StatelessWidget {
  const _FormsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const Text('Form oluştur'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('ambassador_forms')
                .orderBy('updatedAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Form yok. Oluşturun.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final slug = '${d['slug'] ?? ''}';
                  final active = d['active'] == true;
                  final fields = (d['fields'] as List?) ?? const [];
                  return Card(
                    child: ListTile(
                      title: Text('${d['title'] ?? slug}'),
                      subtitle: Text(
                        'slug: $slug · ${fields.length} alan · '
                        '${active ? 'yayında' : 'pasif'}'
                        '${d['listingOpen'] == true ? ' · ilan açık' : ''}',
                      ),
                      isThreeLine: d['listingOpen'] == true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: active
                                ? 'İlanı aç (elçilik sayfası)'
                                : 'Önce formu yayına al',
                            icon: Icon(
                              Icons.campaign_outlined,
                              color: active
                                  ? AppColors.cyan
                                  : AppColors.textSecondary,
                            ),
                            onPressed: () => _openListing(
                              context,
                              formId: docs[i].id,
                              slug: slug,
                              active: active,
                              title: '${d['title'] ?? slug}',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Linki kopyala',
                            icon: const Icon(Icons.link),
                            onPressed: () {
                              final url =
                                  '${AppInfo.marketingUrl}/elcilik?form=$slug';
                              Clipboard.setData(ClipboardData(text: url));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Kopyalandı: $url')),
                              );
                            },
                          ),
                          Switch(
                            value: active,
                            onChanged: (v) async {
                              await FirebaseFirestore.instance
                                  .collection('ambassador_forms')
                                  .doc(docs[i].id)
                                  .set(
                                {'active': v},
                                SetOptions(merge: true),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openListing(
    BuildContext context, {
    required String formId,
    required String slug,
    required bool active,
    required String title,
  }) async {
    if (!active) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Önce formu yayına al (sağdaki anahtar). Sonra ilan açılabilir.',
          ),
        ),
      );
      return;
    }
    final url = '${AppInfo.marketingUrl}/elcilik?form=$slug';
    try {
      await FirebaseFirestore.instance
          .collection('ambassador_forms')
          .doc(formId)
          .set({
        'listingOpen': true,
        'listingOpenedAt': DateTime.now().toIso8601String(),
        'listingUrl': url,
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('ambassador_landing')
          .set({
        'activeFormSlug': slug,
        'listingTitle': title,
        'listingUrl': url,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İlan kaydı yazılamadı: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Elçilik ilanı açıldı · $url')),
    );
  }

  Future<void> _create(BuildContext context) async {
    final title = TextEditingController(text: 'Kampüs Elçiliği Başvurusu');
    final slug = TextEditingController(text: 'kampus-elcisi');
    final fieldsRaw = TextEditingController(
      text:
          'fullName|Ad Soyad|text|1\n'
          'email|E-posta|email|1\n'
          'phone|Telefon|tel|1\n'
          'university|Üniversite|text|1\n'
          'city|Şehir|text|1\n'
          'motivation|Neden elçi olmak istiyorsun?|textarea|1\n'
          'experience|Kulüp / etkinlik deneyimin|textarea|0\n'
          'instagram|Instagram|text|0',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Başvuru formu'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Başlık'),
                ),
                TextField(
                  controller: slug,
                  decoration: const InputDecoration(
                    labelText: 'Slug (URL)',
                    hintText: 'kampus-elcisi',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Alanlar (her satır: id|etiket|tip|zorunlu)\n'
                  'tip: text, email, tel, textarea, select',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                TextField(
                  controller: fieldsRaw,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
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
    );
    if (ok != true) return;
    final fields = <Map<String, dynamic>>[];
    for (final line in fieldsRaw.text.split('\n')) {
      final p = line.trim().split('|');
      if (p.length < 3) continue;
      fields.add({
        'id': p[0].trim(),
        'label': p[1].trim(),
        'type': p[2].trim(),
        'required': p.length < 4 ? true : p[3].trim() == '1',
      });
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminUpsertAmbassadorForm');
      await callable.call({
        'title': title.text.trim(),
        'slug': slug.text.trim(),
        'fields': fields,
        'active': true,
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Form kaydedilemedi: $e')),
        );
      }
    }
  }
}
