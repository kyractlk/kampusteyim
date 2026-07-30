import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../ads/ad_campaign_form.dart';
import '../auth/data/auth_provider.dart';

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
      await context.read<AuthProvider>().refreshCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Davet kabul edildi' : 'Davet reddedildi'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizasyon daveti')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_inv?['orgName'] ?? 'Organizasyon'}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Seni ${_inv?['orgType'] == 'company' ? 'firmaya' : 'topluluğa'} davet etti.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      if (_inv?['grantPanelAccess'] == true)
                        const ListTile(
                          leading: Icon(Icons.dashboard_outlined),
                          title: Text('Panele erişim'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      if (_inv?['grantBlueBadge'] == true)
                        const ListTile(
                          leading: Icon(Icons.verified_outlined),
                          title: Text('Mavi tick'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      const Spacer(),
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
                        Text('Durum: ${_inv?['status']}'),
                    ],
                  ),
                ),
    );
  }
}
