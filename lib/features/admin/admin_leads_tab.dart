import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// Landing başvuruları: topluluk / şirket / reklam.
class AdminLeadsTab extends StatefulWidget {
  const AdminLeadsTab({super.key});

  @override
  State<AdminLeadsTab> createState() => _AdminLeadsTabState();
}

class _AdminLeadsTabState extends State<AdminLeadsTab> {
  List<_Lead> _items = [];
  bool _loading = true;
  String _type = 'all'; // all | community | company | advertising
  String _status = 'open'; // open | done | all

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lead_applications')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
      _items = snap.docs.map((d) => _Lead.fromDoc(d.id, d.data())).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<_Lead> get _filtered => _items.where((e) {
        if (_type != 'all' && e.type != _type) return false;
        if (_status != 'all' && e.status != _status) return false;
        return true;
      }).toList();

  Future<void> _setStatus(_Lead lead, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('lead_applications')
          .doc(lead.id)
          .set({
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      setState(() {
        final i = _items.indexWhere((e) => e.id == lead.id);
        if (i >= 0) {
          _items[i] = lead.copyWith(status: status);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncellenemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Landing başvuruları (topluluk · şirket · reklam)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('Tümü', _type == 'all', () {
                      setState(() => _type = 'all');
                    }),
                    _chip('Topluluk', _type == 'community', () {
                      setState(() => _type = 'community');
                    }),
                    _chip('Şirket', _type == 'company', () {
                      setState(() => _type = 'company');
                    }),
                    _chip('Reklam', _type == 'advertising', () {
                      setState(() => _type = 'advertising');
                    }),
                    _chip('Destek', _type == 'support', () {
                      setState(() => _type = 'support');
                    }),
                    const SizedBox(width: 8),
                    _chip('Açık', _status == 'open', () {
                      setState(() => _status = 'open');
                    }),
                    _chip('Kapalı', _status == 'done', () {
                      setState(() => _status = 'done');
                    }),
                    _chip('Hepsi', _status == 'all', () {
                      setState(() => _status = 'all');
                    }),
                  ],
                ),
              ),
              Text(
                '${list.length} başvuru',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(child: Text('Başvuru yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final l = list[i];
                        return Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: l.status == 'open'
                                  ? AppColors.cyan.withValues(alpha: 0.45)
                                  : AppColors.border,
                            ),
                          ),
                          child: ExpansionTile(
                            title: Text(
                              '${l.typeLabel} · ${l.orgName.isEmpty ? l.name : l.orgName}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              '${l.name} · ${l.email}\n'
                              '${l.city.isNotEmpty ? '${l.city} · ' : ''}'
                              '${l.university.isNotEmpty ? '${l.university} · ' : ''}'
                              '${DateFormat('d MMM HH:mm', 'tr').format(l.createdAt)}'
                              '${l.status == 'open' ? ' · açık' : ' · kapalı'}',
                              style: const TextStyle(fontSize: 12, height: 1.35),
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            children: [
                              if (l.phone.isNotEmpty)
                                _kv('Telefon', l.phone),
                              if (l.website.isNotEmpty)
                                _kv('Web', l.website),
                              if (l.interest.isNotEmpty)
                                _kv('İstek', l.interest),
                              if (l.message.isNotEmpty)
                                _kv('Mesaj', l.message),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => launchUrl(
                                        Uri.parse('mailto:${l.email}'),
                                      ),
                                      icon: const Icon(Icons.mail_outline,
                                          size: 18),
                                      label: const Text('E-posta'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _setStatus(
                                        l,
                                        l.status == 'open' ? 'done' : 'open',
                                      ),
                                      child: Text(
                                        l.status == 'open'
                                            ? 'Kapat'
                                            : 'Yeniden aç',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: v),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _Lead {
  const _Lead({
    required this.id,
    required this.type,
    required this.status,
    required this.name,
    required this.email,
    required this.phone,
    required this.orgName,
    required this.city,
    required this.university,
    required this.website,
    required this.interest,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String status;
  final String name;
  final String email;
  final String phone;
  final String orgName;
  final String city;
  final String university;
  final String website;
  final String interest;
  final String message;
  final DateTime createdAt;

  String get typeLabel => switch (type) {
        'community' => 'Topluluk',
        'company' => 'Şirket',
        'advertising' => 'Reklam',
        'support' => 'Destek',
        _ => type,
      };

  _Lead copyWith({String? status}) => _Lead(
        id: id,
        type: type,
        status: status ?? this.status,
        name: name,
        email: email,
        phone: phone,
        orgName: orgName,
        city: city,
        university: university,
        website: website,
        interest: interest,
        message: message,
        createdAt: createdAt,
      );

  factory _Lead.fromDoc(String id, Map<String, dynamic> m) {
    return _Lead(
      id: id,
      type: '${m['type'] ?? ''}',
      status: '${m['status'] ?? 'open'}',
      name: '${m['name'] ?? ''}',
      email: '${m['email'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      orgName: '${m['orgName'] ?? ''}',
      city: '${m['city'] ?? ''}',
      university: '${m['university'] ?? ''}',
      website: '${m['website'] ?? ''}',
      interest: '${m['interest'] ?? ''}',
      message: '${m['message'] ?? ''}',
      createdAt:
          DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}
