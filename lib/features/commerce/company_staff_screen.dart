import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/panel_chrome.dart';
import '../auth/data/auth_provider.dart';
import '../jobs/company_portal.dart';
import 'staff_invite_panel.dart';

/// Firma yönetim kadrosu — ayrı ekran (organizatörden bağımsız).
class CompanyStaffScreen extends StatefulWidget {
  const CompanyStaffScreen({super.key});

  @override
  State<CompanyStaffScreen> createState() => _CompanyStaffScreenState();
}

class _CompanyStaffScreenState extends State<CompanyStaffScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<AuthProvider>().syncDirectoryFromFirestore());
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    if (me == null || !me.isCompany) {
      return const Scaffold(
        body: Center(child: Text('Firma hesabı gerekli')),
      );
    }
    return CompanyPortalShell(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Yönetim kadrosu')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const PanelWelcomeHeader(
              title: 'Yönetim kadrosu',
              subtitle: 'Üye ara, yetki ver ve davet gönder',
            ),
            const SizedBox(height: 12),
            StaffInvitePanel(orgId: me.id, orgType: 'company'),
          ],
        ),
      ),
    );
  }
}
