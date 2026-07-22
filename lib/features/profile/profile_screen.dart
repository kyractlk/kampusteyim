import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/brand_svgs.dart';
import '../../core/icons/mt_icons.dart';
import '../../core/storage/media_upload.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/widgets/app_circle_logo.dart';
import '../../core/widgets/social_widgets.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';
import '../feed/feed_screen.dart';
import '../jobs/jobs_provider.dart';
import '../moderation/moderation_models.dart';
import '../moderation/report_sheet.dart';
import '../notifications/notification_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Profil için giriş yapmalısın.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.push('/login'),
                child: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      );
    }
    return UserProfileView(userId: user.id, isSelf: true);
  }
}

class UserProfileView extends StatefulWidget {
  const UserProfileView({
    super.key,
    required this.userId,
    this.isSelf = false,
  });

  final String userId;
  final bool isSelf;

  @override
  State<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends State<UserProfileView> {
  bool _loadingRemote = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.findUser(widget.userId) != null) return;
      setState(() => _loadingRemote = true);
      await auth.ensureUserLoaded(widget.userId);
      if (mounted) setState(() => _loadingRemote = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final feed = context.watch<FeedProvider>();
    final user = auth.findUser(widget.userId);
    if (user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: _loadingRemote
              ? const CircularProgressIndicator()
              : const Text('Kullanıcı bulunamadı'),
        ),
      );
    }

    final posts = feed.postsByAuthors(auth.idsFor(widget.userId));
    final me = auth.user;
    final following = me != null && auth.follows(user.id);
    final isSelf = widget.isSelf || me?.id == user.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(user.handle),
        actions: [
          IconButton(
            tooltip: 'Profili paylaş',
            onPressed: () => AppShare.shareUser(
              context: context,
              user: user,
            ),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          if (!isSelf)
            PopupMenuButton<String>(
              tooltip: 'Diğer',
              onSelected: (v) async {
                if (v == 'report') {
                  await showReportSheet(
                    context: context,
                    targetType: ReportTargetType.account,
                    targetId: widget.userId,
                    targetOwnerId: widget.userId,
                  );
                  return;
                }
                if (v == 'block') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Engelle'),
                      content: Text(
                        '${user.fullName} engellenecek. Gönderilerini, '
                        'hikâyelerini ve profilini göremezsin; o da seni '
                        'göremez. Takip ilişkisi kaldırılır.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Vazgeç'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.crimson,
                          ),
                          child: const Text('Engelle'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    await auth.blockUser(user.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Kullanıcı engellendi. Gizlilik ayarlarından kaldırabilirsin.',
                          ),
                        ),
                      );
                      context.pop();
                    }
                  }
                }
                if (v == 'unblock') {
                  await auth.unblockUser(user.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Engel kaldırıldı')),
                    );
                  }
                }
              },
              itemBuilder: (ctx) {
                final blocked = me != null && me.blocks(user.id);
                return [
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Şikayet et'),
                  ),
                  PopupMenuItem(
                    value: blocked ? 'unblock' : 'block',
                    child: Text(blocked ? 'Engeli kaldır' : 'Engelle'),
                  ),
                ];
              },
            ),
          if (isSelf) ...[
            if (user.isAdmin)
              IconButton(
                tooltip: 'Ana Admin',
                onPressed: () => context.push('/admin'),
                icon: const MtIcon(MtIcons.admin, size: 22),
              ),
            if (user.isCommunity)
              IconButton(
                tooltip: 'Topluluk paneli',
                onPressed: () => context.push('/community'),
                icon: const MtIcon(MtIcons.community, size: 22),
              ),
            if (user.isCompany)
              IconButton(
                tooltip: 'Firma paneli',
                onPressed: () async {
                  await context.read<JobsProvider>().bindCompanyFromUser(user);
                  if (context.mounted) context.push('/firma/dashboard');
                },
                icon: const Icon(Icons.business_center_outlined, size: 22),
              ),
            if (!user.isCompany)
              IconButton(
                tooltip: 'CV-AI',
                onPressed: () => context.push('/cv-ai'),
                icon: const Icon(Icons.description_outlined),
              ),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: () => context.push('/profile/edit'),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Çıkış',
              onPressed: () async {
                context.read<JobsProvider>().companyLogout();
                await auth.signOut();
                if (context.mounted) context.go('/home');
              },
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.navy, AppColors.navySoft, Color(0xFF1E4A6E)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                UserAvatar(
                  name: user.fullName,
                  photoUrl: user.communityLogoUrl ?? user.photoUrl,
                  radius: 40,
                  isCommunity: user.isCommunity,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        user.fullName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    if (user.showGoldBadge) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(gold: true, size: 18),
                    ] else if (user.showBlueBadge) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(gold: false, size: 18),
                    ],
                    if (user.isBot) ...[
                      const SizedBox(width: 6),
                      const BotBadge(size: 18),
                    ],
                  ],
                ),
                Text(
                  user.handle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                ),
                if (user.hasAffiliation) ...[
                  const SizedBox(height: 8),
                  AffiliationBadge(
                    orgName: user.affiliatedCommunityName?.trim() ?? '',
                    logoUrl: user.affiliatedOrgLogoUrl ??
                        (user.affiliatedCommunityId != null
                            ? (auth
                                    .findUser(user.affiliatedCommunityId!)
                                    ?.communityLogoUrl ??
                                auth
                                    .findUser(user.affiliatedCommunityId!)
                                    ?.photoUrl)
                            : null),
                    orgId: user.affiliatedCommunityId,
                    light: true,
                  ),
                ],
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    user.bio,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Stat(
                      label: 'Takipçi',
                      value: '${user.followers.length}',
                      onTap: () =>
                          context.push('/user/${user.id}/followers'),
                    ),
                    _Stat(
                      label: 'Takip',
                      value: '${user.following.length}',
                      onTap: () =>
                          context.push('/user/${user.id}/following'),
                    ),
                    _Stat(label: 'Gönderi', value: '${posts.length}'),
                  ],
                ),
                if (!isSelf) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: () async {
                        if (!AuthGate.requireAuth(
                          context,
                          message: 'Takip için giriş yapmalısın.',
                        )) {
                          return;
                        }
                        final already = following;
                        final pending = me != null &&
                            auth.hasOutgoingFollowRequest(user.id);
                        if (already) {
                          await auth.toggleFollow(user.id);
                          return;
                        }
                        if (user.isPrivateAccount) {
                          if (pending) {
                            await auth.cancelFollowRequest(user.id);
                          } else {
                            await auth.requestFollow(user.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Takip isteği gönderildi'),
                                ),
                              );
                            }
                          }
                          return;
                        }
                        await auth.toggleFollow(user.id);
                        if (!context.mounted) return;
                        if (!already && me != null) {
                          context.read<NotificationProvider>().pushSocial(
                                toUserId: user.id,
                                title: 'Yeni takipçi',
                                body:
                                    '${me.fullName} seni takip etmeye başladı',
                                emoji: 'FOLLOW',
                                type: 'follow',
                                actorId: me.id,
                              );
                        }
                      },
                      child: Text(
                        following
                            ? 'Takipten çık'
                            : (me != null &&
                                    auth.hasOutgoingFollowRequest(user.id))
                                ? 'İstek gönderildi'
                                : (user.isPrivateAccount
                                    ? 'İstek gönder'
                                    : 'Takip et'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.06),
          if (isSelf) ...[
            if (user.isCompany) ...[
              const SizedBox(height: 12),
              Material(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await context.read<JobsProvider>().bindCompanyFromUser(user);
                    if (context.mounted) context.push('/firma/dashboard');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.business_center_outlined, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Firma paneli',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'İlan yayınla, başvuruları incele, öğrencilere teklif gönder',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (!user.isCompany) ...[
            const SizedBox(height: 12),
            Material(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/cv-ai'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CV-AI',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'ATS uyumlu profesyonel CV · tüm dünya dilleri',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            ],
            if (!user.isCompany) ...[
              const SizedBox(height: 10),
              Material(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/staj-ai'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.work_outline, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Staj-AI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Firma ilanları, teklifler ve başvurular',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Çalışma odası'),
              subtitle: const Text('Oda aç, katıl, chat + sayaç'),
              onTap: () => context.push('/profile/study-timer'),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Geri bildirim bırak'),
              subtitle: const Text('Öneri / hata · admin paneline düşer'),
              onTap: () => context.push('/profile/feedback'),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Bildirim izinleri'),
              subtitle: const Text('Push, ilan, beğeni ve daha fazlası'),
              onTap: () => context.push('/profile/notifications'),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: const Icon(Icons.lock_outline),
              title: const Text('Gizlilik'),
              subtitle: const Text(
                'Arama, gizli hesap, izleyici modu, engeller',
              ),
              onTap: () => context.push('/privacy'),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: const Icon(Icons.info_outline),
              title: const Text('Uygulama bilgisi'),
              subtitle: const Text('AYS Tech · Kayra Çatalkaya'),
              onTap: () => context.push('/about'),
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.crimson),
              ),
              leading: const Icon(Icons.delete_forever_outlined,
                  color: AppColors.crimson),
              title: const Text('Hesabımı sil'),
              subtitle: const Text('E-posta kodu ile çift onay'),
              onTap: () => context.push('/profile/delete-account'),
            ),
          ],
          if (user.links.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.links.map((l) {
                final svg = BrandSvgs.forLabel(l.label);
                final href = BrandLinkUtils.href(
                      kind: 'website',
                      raw: l.url,
                    ) ??
                    (l.url.startsWith('http') ? l.url : null);
                return ActionChip(
                  avatar: BrandSvgIcon(svg, size: 16),
                  label: Text(l.label),
                  onPressed: href == null
                      ? null
                      : () async {
                          final uri = Uri.tryParse(href);
                          if (uri != null) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Gönderiler',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Henüz gönderi yok.'),
            )
          else
            ...posts.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PostCard(post: p),
              ),
            ),
          if (isSelf) ...[
            const SizedBox(height: 20),
            Opacity(
              opacity: 0.45,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Altyapı',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(width: 8),
                  const AppCircleLogo(logo: AppLogo.ays, size: 28, showBorder: false),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _bio;
  late final TextEditingController _linkLabel;
  late final TextEditingController _linkUrl;
  late final TextEditingController _username;
  late List<ProfileLink> _links;
  String? _photoUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user!;
    _bio = TextEditingController(text: user.bio);
    _photoUrl = user.photoUrl;
    _username = TextEditingController(text: user.username ?? '');
    _linkLabel = TextEditingController();
    _linkUrl = TextEditingController();
    _links = List.of(user.links);
  }

  @override
  void dispose() {
    _bio.dispose();
    _linkLabel.dispose();
    _linkUrl.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _uploading = true);
    try {
      final file = await MediaUpload.pickImage();
      if (file == null) {
        setState(() => _uploading = false);
        return;
      }
      final authUid =
          fa.FirebaseAuth.instance.currentUser?.uid ?? user.id;
      final url = await MediaUpload.uploadXFile(
        file: file,
        folder: 'users/$authUid/profile',
        firstName: user.firstName,
        lastName: user.lastName,
        studentNo: user.studentNo,
        isVideo: false,
      );
      setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili düzenle'),
        actions: [
          TextButton(
            onPressed: _uploading
                ? null
                : () async {
                    final auth = context.read<AuthProvider>();
                    if (_username.text.trim().isNotEmpty &&
                        _username.text.trim().toLowerCase() !=
                            (user?.username ?? '')) {
                      final err =
                          await auth.changeUsername(_username.text.trim());
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(err)));
                      }
                    }
                    auth.updateProfile(
                      bio: _bio.text.trim(),
                      photoUrl: _photoUrl,
                      links: _links,
                      clearPhoto: (_photoUrl ?? '').isEmpty,
                    );
                    if (context.mounted) context.pop();
                  },
            child: const Text('Kaydet'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user?.needsUsernameChange == true)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.crimson.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Geçici kullanıcı adın var. Kalıcı bir ad seçmen gerekiyor.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: (_photoUrl ?? '').isNotEmpty
                          ? NetworkImage(_photoUrl!)
                          : null,
                      child: (_photoUrl ?? '').isEmpty
                          ? const Icon(Icons.person, size: 44)
                          : null,
                    ),
                    IconButton.filled(
                      onPressed: _uploading ? null : _pickPhoto,
                      icon: _uploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fotoğraf seç / yükle · max 75 MB',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Kullanıcı adı',
              prefixText: '@',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bio,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Biyografi',
              prefixIcon: Icon(Icons.info_outline),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Linkler',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ..._links.asMap().entries.map((e) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(e.value.label),
              subtitle: Text(e.value.url),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _links.removeAt(e.key)),
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _linkLabel,
                  decoration: const InputDecoration(labelText: 'Etiket'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _linkUrl,
                  decoration: const InputDecoration(labelText: 'URL'),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_linkLabel.text.trim().isEmpty ||
                      _linkUrl.text.trim().isEmpty) {
                    return;
                  }
                  setState(() {
                    _links.add(ProfileLink(
                      label: _linkLabel.text.trim(),
                      url: _linkUrl.text.trim(),
                    ));
                    _linkLabel.clear();
                    _linkUrl.clear();
                  });
                },
                icon: const Icon(Icons.add_circle, color: AppColors.cyan),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
    if (onTap == null) return column;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: column,
      ),
    );
  }
}
