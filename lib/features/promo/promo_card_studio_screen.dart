import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../admin/admin_permissions.dart';
import '../admin/admin_provider.dart';
import '../auth/data/auth_provider.dart';
import 'promo_card_download.dart';
import 'promo_card_widget.dart';

enum _PromoSection { home, cards, stats }

class PromoCardStudioScreen extends StatefulWidget {
  const PromoCardStudioScreen({super.key});

  @override
  State<PromoCardStudioScreen> createState() => _PromoCardStudioScreenState();
}

class _PromoCardStudioScreenState extends State<PromoCardStudioScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _filter = TextEditingController();
  final _selected = <String>{};
  final _cardKeys = <String, GlobalKey>{};
  _PromoSection _section = _PromoSection.home;
  String _role = 'all';
  final _statsQuery = TextEditingController();
  String _statsKind = 'all';
  bool _busy = false;
  bool _obscure = true;
  String _status = '';
  List<_CardStat> _stats = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.isAuthenticated) {
        await auth.syncDirectoryFromFirestore();
        await _loadStats();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _filter.dispose();
    _statsQuery.dispose();
    super.dispose();
  }

  bool _isAdmin(AuthProvider auth, AdminProvider admin) {
    final me = auth.user;
    if (me == null) return false;
    return admin.can(me, AdminPermission.managePromo) || me.canAccessAdmin;
  }

  String? _orgScopeId(AppUser me) {
    if (me.isCommunity || me.isCompany) return me.id;
    if (me.panelAccess && (me.panelOrgId ?? '').trim().isNotEmpty) {
      return me.panelOrgId;
    }
    return null;
  }

  List<AppUser> _visibleUsers(AuthProvider auth, AdminProvider admin) {
    final me = auth.user;
    if (me == null) return const [];
    final q = _filter.text.trim().toLowerCase();
    Iterable<AppUser> list = auth.directory.where((u) {
      final uname = (u.username ?? '').toLowerCase();
      return uname.isNotEmpty && u.accountStatus != 'rejected' && !u.isBot;
    });
    if (!_isAdmin(auth, admin)) {
      final scope = _orgScopeId(me);
      if (scope == null) return const [];
      list = list.where((u) => u.id == scope || auth.idsFor(scope).contains(u.id));
    }
    if (_role == 'community') list = list.where((u) => u.isCommunity);
    if (_role == 'company') list = list.where((u) => u.isCompany);
    if (q.isNotEmpty) {
      list = list.where((u) {
        final hay =
            '${u.fullName} ${u.firstName} ${u.username} ${u.handle} ${u.email}'
                .toLowerCase();
        return hay.contains(q);
      });
    }
    final out = list.toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return out;
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final ok = await auth.signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    if (ok) {
      await auth.syncDirectoryFromFirestore();
      await _loadStats();
    }
    setState(() {
      _busy = false;
      _status = ok ? '' : (auth.error ?? 'Giriş başarısız');
    });
  }

  Future<void> _loadStats() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getPromoCardStats');
      final res = await callable.call();
      final map = Map<String, dynamic>.from(res.data as Map? ?? {});
      final raw = (map['items'] as List?) ?? const [];
      _stats = raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return _CardStat(
          accountId: '${m['accountId'] ?? ''}',
          username: '${m['username'] ?? ''}',
          name: '${m['name'] ?? ''}',
          scans: (m['scans'] as num?)?.toInt() ?? 0,
          ios: (m['ios'] as num?)?.toInt() ?? 0,
          android: (m['android'] as num?)?.toInt() ?? 0,
          follows: (m['follows'] as num?)?.toInt() ?? 0,
          isCommunity: m['isCommunity'] == true,
          isCompany: m['isCompany'] == true || '${m['role'] ?? ''}' == 'company',
        );
      }).toList()
        ..sort((a, b) => b.scans.compareTo(a.scans));
    } catch (e) {
      debugPrint('[promo] stats: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _downloadOne(AppUser user) async {
    setState(() {
      _busy = true;
      _status = '@${promoCardUsername(user)} hazırlanıyor…';
    });
    try {
      await _captureAndSave(user);
      if (mounted) setState(() => _status = '@${promoCardUsername(user)} indirildi');
    } catch (e) {
      if (mounted) setState(() => _status = 'İndirilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadSelected(List<AppUser> pool) async {
    final users = pool.where((u) => _selected.contains(u.id)).toList();
    if (users.isEmpty) {
      setState(() => _status = 'Önce hesap seç');
      return;
    }
    setState(() => _busy = true);
    var n = 0;
    for (final u in users) {
      if (!mounted) return;
      setState(() => _status = '${n + 1}/${users.length} · @${promoCardUsername(u)}');
      try {
        await _captureAndSave(u);
        n += 1;
        await Future<void>.delayed(const Duration(milliseconds: 180));
      } catch (e) {
        debugPrint('[promo] download ${u.username}: $e');
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = '$n kart indirildi';
      });
    }
  }

  Future<void> _captureAndSave(AppUser user) async {
    if (!kIsWeb) {
      throw Exception('Kart indirme şu an web’de çalışır');
    }
    final key = _cardKeys.putIfAbsent(user.id, GlobalKey.new);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final ctx = key.currentContext;
    if (ctx == null) throw Exception('Kart çizilemedi');
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('Kart henüz hazır değil');
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('PNG üretilemedi');
    await savePngBytes(
      data.buffer.asUint8List(),
      '${promoCardUsername(user)}_tanitim.png',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final admin = context.watch<AdminProvider>();
    final me = auth.user;
    if (me == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF061426),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF061426), AppColors.navy, Color(0xFF123456)],
            ),
          ),
          child: SafeArea(child: _loginView()),
        ),
      );
    }
    return _panelTheme(
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_titleFor(me, admin, auth)),
          leading: _section == _PromoSection.home
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => setState(() => _section = _PromoSection.home),
                ),
        ),
        body: _studio(auth, admin, me),
      ),
    );
  }

  String _titleFor(AppUser me, AdminProvider admin, AuthProvider auth) {
    return switch (_section) {
      _PromoSection.home => 'Tanıtım paneli',
      _PromoSection.cards => 'Kart oluştur',
      _PromoSection.stats => 'İstatistik',
    };
  }

  Widget _panelTheme({required Widget child}) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        chipTheme: ChipThemeData(
          selectedColor: AppColors.navy,
          backgroundColor: AppColors.surfaceMuted,
          labelStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _brandHead({String? subtitle}) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            AppAssets.kampusIcon,
            width: 72,
            height: 72,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.school_rounded,
              color: AppColors.cyan,
              size: 64,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Kampüsteyim'),
              TextSpan(text: 'APP', style: TextStyle(color: AppColors.cyan)),
            ],
          ),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 26,
            letterSpacing: -0.6,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ],
    );
  }

  Widget _loginView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _brandHead(subtitle: 'Tanıtım paneli'),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                decoration: _darkField('E-posta'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                onSubmitted: (_) => _login(),
                decoration: _darkField('Şifre').copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _login,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.navy,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Giriş yap'),
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_status, style: const TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _darkField(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white54),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan, width: 2),
      ),
    );
  }

  Widget _studio(AuthProvider auth, AdminProvider admin, AppUser me) {
    final isAdmin = _isAdmin(auth, admin);
    final orgId = _orgScopeId(me);
    if (!isAdmin && orgId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bu panel admin, topluluk ve firma hesapları içindir.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return switch (_section) {
      _PromoSection.home => _home(me, isAdmin),
      _PromoSection.cards => _cards(auth, admin, isAdmin),
      _PromoSection.stats => _statsView(isAdmin),
    };
  }

  Widget _home(AppUser me, bool isAdmin) {
    final role = isAdmin
        ? 'Admin'
        : me.isCompany
            ? 'Firma'
            : me.isCommunity
                ? 'Topluluk'
                : 'Kadro';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          'Merhaba ${me.firstName}',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$role · tanıtım kartı ve QR istatistikleri',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        _homeTile(
          icon: Icons.qr_code_2_rounded,
          title: 'Kart oluştur',
          subtitle: isAdmin
              ? 'Hesap seç, filtrele, dikey QR rozeti indir'
              : 'Kendi tanıtım kartını indir',
          onTap: () => setState(() => _section = _PromoSection.cards),
        ),
        const SizedBox(height: 12),
        _homeTile(
          icon: Icons.insights_rounded,
          title: 'İstatistik kontrol et',
          subtitle: isAdmin
              ? 'Tüm kartların okutulma ve takip sayıları'
              : 'QR okutulması ve gelen takipler',
          onTap: () async {
            setState(() => _section = _PromoSection.stats);
            await _loadStats();
          },
        ),
      ],
    );
  }

  Widget _homeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.navy, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cards(AuthProvider auth, AdminProvider admin, bool isAdmin) {
    final users = _visibleUsers(auth, admin);
    if (!isAdmin && users.isNotEmpty && _selected.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selected.isNotEmpty) return;
        setState(() => _selected.add(users.first.id));
      });
    }
    final selectedUsers = users.where((u) => _selected.contains(u.id)).toList();

    return Column(
      children: [
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              cursorColor: AppColors.navy,
              decoration: InputDecoration(
                hintText: 'Filtrele: gaun, ieee, ays…',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.navy),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.border, width: 1.4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.navy, width: 2),
                ),
              ),
            ),
          ),
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                _roleChip('Hepsi', 'all'),
                _roleChip('Topluluk', 'community'),
                _roleChip('Firma', 'company'),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text(
                '${_selected.length} seçili / ${users.length}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (isAdmin) ...[
                TextButton(
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(users.map((u) => u.id));
                  }),
                  child: const Text('Tümünü seç'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Temizle'),
                ),
              ],
            ],
          ),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              _status,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              ...users.map((u) => _userTile(u, isAdmin)),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      'Eşleşen hesap yok',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (selectedUsers.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final u in selectedUsers)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: RepaintBoundary(
                            key: _cardKeys.putIfAbsent(u.id, GlobalKey.new),
                            child: PromoBadgeCard(user: u),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (selectedUsers.length == 1)
                FilledButton(
                  onPressed: _busy ? null : () => _downloadOne(selectedUsers.first),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Kartı indir'),
                ),
              if (isAdmin && selectedUsers.length > 1)
                FilledButton(
                  onPressed: _busy ? null : () => _downloadSelected(users),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text('${selectedUsers.length} kartı indir'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<_CardStat> _visibleStats(bool isAdmin) {
    Iterable<_CardStat> list = _stats;
    if (isAdmin) {
      switch (_statsKind) {
        case 'community':
          list = list.where((s) => s.isCommunity);
        case 'company':
          list = list.where((s) => s.isCompany);
        case 'scans':
          list = list.where((s) => s.scans > 0);
        case 'follows':
          list = list.where((s) => s.follows > 0);
        case 'ios':
          list = list.where((s) => s.ios > 0);
        case 'android':
          list = list.where((s) => s.android > 0);
      }
      final q = _statsQuery.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        list = list.where((s) {
          final hay = '${s.name} ${s.username} ${s.accountId}'.toLowerCase();
          return hay.contains(q);
        });
      }
    }
    return list.toList();
  }

  Widget _statsKindChip(String label, String value) {
    final on = _statsKind == value;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => setState(() => _statsKind = value),
      selectedColor: AppColors.navy,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      labelStyle: TextStyle(
        color: on ? Colors.white : AppColors.navy,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _statsView(bool isAdmin) {
    final shown = _visibleStats(isAdmin);
    final totalScans = shown.fold<int>(0, (a, b) => a + b.scans);
    final totalFollows = shown.fold<int>(0, (a, b) => a + b.follows);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _kpi('Okutulma', '$totalScans'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpi('QR’dan takip', '$totalFollows'),
              ),
            ],
          ),
        ),
        if (isAdmin) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _statsQuery,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              cursorColor: AppColors.navy,
              decoration: InputDecoration(
                hintText: 'Ara: aystech, gaun, kayra…',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.navy),
                suffixIcon: _statsQuery.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _statsQuery.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border, width: 1.4),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.navy, width: 2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statsKindChip('Hepsi', 'all'),
                _statsKindChip('Topluluk', 'community'),
                _statsKindChip('Firma', 'company'),
                _statsKindChip('Okutulma', 'scans'),
                _statsKindChip('Takip', 'follows'),
                _statsKindChip('iOS', 'ios'),
                _statsKindChip('Android', 'android'),
              ],
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await _loadStats();
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Yenile'),
          ),
        ),
        Expanded(
          child: _stats.isEmpty
              ? const Center(
                  child: Text(
                    'Henüz tarama yok.\nKartı indirip QR okutulunca burada görünür.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                )
              : shown.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu arama / filtreye uygun kayıt yok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _statCard(shown[i], isAdmin),
                    ),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(_CardStat s, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.name.isEmpty ? '@${s.username}' : s.name,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
          ),
          if (s.username.isNotEmpty)
            Text(
              '@${s.username}${s.isCommunity ? ' · Topluluk' : s.isCompany ? ' · Firma' : ''}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill('${s.scans} okutulma'),
              _pill('${s.follows} takip'),
              if (isAdmin) _pill('iOS ${s.ios}'),
              if (isAdmin) _pill('Android ${s.android}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _roleChip(String label, String value) {
    final on = _role == value;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => setState(() => _role = value),
      selectedColor: AppColors.navy,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      labelStyle: TextStyle(
        color: on ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _userTile(AppUser u, bool isAdmin) {
    final selected = _selected.contains(u.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? AppColors.navy : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) {
          setState(() {
            if (!isAdmin) {
              _selected
                ..clear()
                ..add(u.id);
              return;
            }
            if (selected) {
              _selected.remove(u.id);
            } else {
              _selected.add(u.id);
            }
          });
        },
        activeColor: AppColors.navy,
        checkColor: Colors.white,
        title: Text(
          u.fullName,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '${u.handle} · ${u.isCommunity ? 'Topluluk' : u.isCompany ? 'Firma' : 'Hesap'}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CardStat {
  const _CardStat({
    required this.accountId,
    required this.username,
    required this.name,
    required this.scans,
    required this.ios,
    required this.android,
    required this.follows,
    this.isCommunity = false,
    this.isCompany = false,
  });

  final String accountId;
  final String username;
  final String name;
  final int scans;
  final int ios;
  final int android;
  final int follows;
  final bool isCommunity;
  final bool isCompany;
}
