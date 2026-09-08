import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../auth/data/auth_provider.dart';
import 'org_invite_service.dart';

class OrgInviteScreen extends StatefulWidget {
  const OrgInviteScreen({super.key, required this.inviteId});
  final String inviteId;

  @override
  State<OrgInviteScreen> createState() => _OrgInviteScreenState();
}

class _OrgInviteScreenState extends State<OrgInviteScreen> {
  Map<String, dynamic>? _inv;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loggedIn = context.read<AuthProvider>().isAuthenticated;
    if (!loggedIn) {
      setState(() {
        _loading = false;
        _error = 'login';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inv = await OrgInviteService.getInvite(widget.inviteId);
      setState(() => _inv = inv);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      await OrgInviteService.respond(
        inviteId: widget.inviteId,
        accept: accept,
      );
      if (!mounted) return;
      await context.read<AuthProvider>().refreshCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Davet kabul edildi' : 'Davet reddedildi'),
        ),
      );
      if (context.canPop()) {
        Navigator.pop(context);
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final next = '/invites/${widget.inviteId}';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Organizasyon daveti')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'login'
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.mail_outline, size: 48, color: AppColors.navy),
                      const SizedBox(height: 16),
                      const Text(
                        'Daveti yanıtlamak için giriş yap.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => context.go(
                          '/login?next=${Uri.encodeComponent(next)}',
                        ),
                        child: const Text('Giriş yap'),
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      children: [
                        PanelCard(
                          color: AppColors.navy,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Seni kadroya davet ettiler',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_inv?['orgName'] ?? 'Organizasyon'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _inv?['orgType'] == 'company'
                                    ? 'Firma paneli daveti'
                                    : 'Topluluk paneli daveti',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        PanelCard(
                          child: Column(
                            children: [
                              if (_inv?['grantPanelAccess'] == true)
                                const ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.dashboard_outlined),
                                  title: Text('Panele erişim'),
                                  subtitle: Text(
                                    'Duyuru, etkinlik ve kadro yönetimi',
                                  ),
                                ),
                              if (_inv?['grantBlueBadge'] == true)
                                const ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.verified_outlined),
                                  title: Text('Mavi tick'),
                                  subtitle: Text('Profilinde doğrulanmış rozet'),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if ('${_inv?['status']}' == 'pending') ...[
                          FilledButton(
                            onPressed: _busy ? null : () => _respond(true),
                            child: const Text('Kabul et'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _respond(false),
                            child: const Text('Reddet'),
                          ),
                        ] else
                          PanelCard(
                            child: Text(
                              'Bu davet ${_statusTr('${_inv?['status']}')}.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
    );
  }

  String _statusTr(String raw) {
    switch (raw) {
      case 'accepted':
        return 'kabul edildi';
      case 'declined':
        return 'reddedildi';
      case 'revoked':
        return 'iptal edildi';
      default:
        return raw;
    }
  }
}
