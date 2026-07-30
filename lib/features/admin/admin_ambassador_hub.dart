import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
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
                'Web başvuru: ${AppInfo.marketingUrl}/elcilik.html',
                style: const TextStyle(
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
                      ('embassies', 'Elçilikler'),
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

class _EmbassiesPanel extends StatelessWidget {
  const _EmbassiesPanel();

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
              label: const Text('Elçilik ekle'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('embassies')
                .orderBy('university')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Henüz elçilik yok.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final active = d['active'] != false;
                  return Card(
                    child: ListTile(
                      title: Text('${d['name'] ?? ''}'),
                      subtitle: Text(
                        '${d['university'] ?? ''} · ${d['city'] ?? ''}',
                      ),
                      trailing: Switch(
                        value: active,
                        onChanged: (v) async {
                          await FirebaseFirestore.instance
                              .collection('embassies')
                              .doc(docs[i].id)
                              .set({'active': v}, SetOptions(merge: true));
                        },
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

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final university = TextEditingController();
    final city = TextEditingController();
    final desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni elçilik'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Elçilik adı'),
              ),
              TextField(
                controller: university,
                decoration: const InputDecoration(labelText: 'Üniversite'),
              ),
              TextField(
                controller: city,
                decoration: const InputDecoration(labelText: 'Şehir'),
              ),
              TextField(
                controller: desc,
                decoration: const InputDecoration(labelText: 'Açıklama'),
                maxLines: 3,
              ),
            ],
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
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('adminUpsertEmbassy');
      await callable.call({
        'name': name.text.trim(),
        'university': university.text.trim(),
        'city': city.text.trim(),
        'description': desc.text.trim(),
        'active': true,
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
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
                        '${active ? 'yayında' : 'pasif'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Linki kopyala',
                            icon: const Icon(Icons.link),
                            onPressed: () {
                              final url =
                                  '${AppInfo.marketingUrl}/elcilik.html?form=$slug';
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
