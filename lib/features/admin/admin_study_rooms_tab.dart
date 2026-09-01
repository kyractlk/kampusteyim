import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../auth/data/auth_provider.dart';
import '../study/study_models.dart';
import 'admin_permissions.dart';
import 'admin_provider.dart';

/// Admin · çalışma odası oturum + chat + dinamik filtre.
class AdminStudyRoomsTab extends StatefulWidget {
  const AdminStudyRoomsTab({super.key});

  @override
  State<AdminStudyRoomsTab> createState() => _AdminStudyRoomsTabState();
}

class _AdminStudyRoomsTabState extends State<AdminStudyRoomsTab> {
  List<StudyRoom> _rooms = [];
  bool _loading = true;
  String? _openId;
  List<StudyChatMessage> _msgs = [];
  bool _loadingMsgs = false;

  final _search = TextEditingController();
  String _status = 'all'; // all | waiting | active | ended | host_away
  bool? _communityOnly; // null = all, true = community, false = student

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rooms = await StudyRoomService.listRecentForAdmin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<StudyRoom> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _rooms.where((r) {
      if (_status == 'host_away') {
        if (r.hostLeftAt == null || r.status == 'ended') return false;
      } else if (_status != 'all' && r.status != _status) {
        return false;
      }
      if (_communityOnly == true && !r.isCommunity) return false;
      if (_communityOnly == false && r.isCommunity) return false;
      if (q.isEmpty) return true;
      final hay = [
        r.code,
        r.title,
        r.hostName,
        r.hostId,
        r.id,
        r.status,
        if (r.endReason != null) r.endReason!,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openChat(String roomId) async {
    if (_openId == roomId) {
      setState(() {
        _openId = null;
        _msgs = [];
      });
      return;
    }
    setState(() {
      _openId = roomId;
      _loadingMsgs = true;
      _msgs = [];
    });
    try {
      _msgs = await StudyRoomService.loadMessages(roomId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat yüklenemedi: $e')),
        );
      }
    }
    if (mounted) setState(() => _loadingMsgs = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final me = context.watch<AuthProvider>().user;
    final admin = context.watch<AdminProvider>();
    final canDeleteMsg = admin.can(me, AdminPermission.moderateChats) ||
        admin.can(me, AdminPermission.moderateFeed);
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
                      'Kod / host adı / host id ile ara. Host çıkınca 1 saat sonra otomatik kapanır.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
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
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ara: host, kod, başlık, id…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('Tümü', _status == 'all', () {
                      setState(() => _status = 'all');
                    }),
                    _chip('Bekleyen', _status == 'waiting', () {
                      setState(() => _status = 'waiting');
                    }),
                    _chip('Aktif', _status == 'active', () {
                      setState(() => _status = 'active');
                    }),
                    _chip('Bitti', _status == 'ended', () {
                      setState(() => _status = 'ended');
                    }),
                    _chip('Host çıktı', _status == 'host_away', () {
                      setState(() => _status = 'host_away');
                    }),
                    _chip(
                      _communityOnly == true
                          ? 'Topluluk ✓'
                          : _communityOnly == false
                              ? 'Öğrenci ✓'
                              : 'Tür',
                      _communityOnly != null,
                      () {
                        setState(() {
                          if (_communityOnly == null) {
                            _communityOnly = true;
                          } else if (_communityOnly == true) {
                            _communityOnly = false;
                          } else {
                            _communityOnly = null;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${list.length} / ${_rooms.length} oda',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _rooms.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const Center(child: Text('Eşleşen çalışma odası yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = list[i];
                        final open = _openId == r.id;
                        final hostGone = r.hostLeftAt != null &&
                            r.status != 'ended';
                        return Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: hostGone
                                  ? AppColors.crimson.withValues(alpha: 0.45)
                                  : r.status == 'active'
                                      ? AppColors.cyan.withValues(alpha: 0.5)
                                      : AppColors.border,
                            ),
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: open,
                            onExpansionChanged: (v) {
                              if (v) _openChat(r.id);
                              if (!v && _openId == r.id) {
                                setState(() {
                                  _openId = null;
                                  _msgs = [];
                                });
                              }
                            },
                            title: Text(
                              '${r.code} · ${r.title}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Host: ${r.hostName}\n'
                              'id: ${r.hostId}\n'
                              '${r.status}'
                              '${hostGone ? ' · host ayrıldı' : ''}'
                              '${r.endReason != null ? ' · ${r.endReason}' : ''}'
                              ' · ${r.minutes} dk · ${r.participantIds.length} kişi · '
                              '${DateFormat('d MMM HH:mm', 'tr').format(r.createdAt)}'
                              '${r.isCommunity ? ' · topluluk' : ''}',
                              style: const TextStyle(height: 1.35, fontSize: 12),
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              if (_loadingMsgs && open)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(),
                                )
                              else if (_msgs.isEmpty)
                                const Text(
                                  'Chat mesajı yok',
                                  style:
                                      TextStyle(color: AppColors.textSecondary),
                                )
                              else
                                ..._msgs.map(
                                  (m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: m.isAi
                                                        ? 'AYS Guard: '
                                                        : '${m.senderName}: ',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: m.isAi
                                                          ? AppColors.cyan
                                                          : AppColors
                                                              .textPrimary,
                                                    ),
                                                  ),
                                                  TextSpan(text: m.text),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (canDeleteMsg &&
                                            m.type != 'system' &&
                                            !m.text.startsWith('Bu mesaj silindi'))
                                          IconButton(
                                            tooltip: 'Mesajı sil',
                                            iconSize: 18,
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () async {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                    'Mesajı sil',
                                                  ),
                                                  content: Text(
                                                    '${m.senderName}: ${m.text}',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                      child: const Text(
                                                        'Vazgeç',
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                      child: const Text('Sil'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok != true || !context.mounted) {
                                                return;
                                              }
                                              try {
                                                await StudyRoomService
                                                    .softDeleteMessage(
                                                  roomId: r.id,
                                                  messageId: m.id,
                                                  byUserId: me?.id ?? 'admin',
                                                );
                                                await _openChat(r.id);
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Silinemedi: $e',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: AppColors.crimson,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
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
