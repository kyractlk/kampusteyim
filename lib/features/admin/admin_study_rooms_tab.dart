import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../study/study_models.dart';

/// Admin · çalışma odası oturum + chat kayıtları.
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

  @override
  void initState() {
    super.initState();
    _load();
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Oturumlar güvenlik için saklanır',
                  style: TextStyle(color: AppColors.textSecondary),
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
        ),
        Expanded(
          child: _loading && _rooms.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _rooms.isEmpty
                  ? const Center(child: Text('Henüz çalışma odası yok'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _rooms.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = _rooms[i];
                        final open = _openId == r.id;
                        return Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: r.status == 'active'
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
                              '${r.hostName} · ${r.status} · ${r.minutes} dk · '
                              '${r.participantIds.length} kişi · '
                              '${DateFormat('d MMM HH:mm', 'tr').format(r.createdAt)}'
                              '${r.isCommunity ? ' · topluluk' : ''}',
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
                                                fontWeight: FontWeight.w800,
                                                color: m.isAi
                                                    ? AppColors.cyan
                                                    : AppColors.textPrimary,
                                              ),
                                            ),
                                            TextSpan(text: m.text),
                                          ],
                                        ),
                                      ),
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
}
