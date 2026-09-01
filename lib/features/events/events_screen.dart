import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/icons/mt_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_nav.dart';
import '../../core/utils/app_share.dart';
import '../../core/utils/auth_gate.dart';
import '../../core/utils/campus_affinity.dart';
import '../../core/widgets/media_viewer.dart';
import '../../core/widgets/safe_network_image.dart';
import '../../data/campus_catalog.dart';
import '../../models/models.dart';
import '../auth/data/auth_provider.dart';
import '../feed/feed_provider.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _offCampusCity = '';
  List<String> _cities = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    CampusCatalog.load().then((c) {
      if (!mounted) return;
      final me = context.read<AuthProvider>().user;
      final myCity = me?.city.trim() ?? '';
      setState(() {
        _cities = c.cities;
        if (_offCampusCity.isEmpty) {
          if (myCity.isNotEmpty &&
              c.cities.any((x) => CampusAffinity.sameLabel(x, myCity))) {
            _offCampusCity = c.cities.firstWhere(
              (x) => CampusAffinity.sameLabel(x, myCity),
            );
          } else if (c.cities.isNotEmpty) {
            _offCampusCity = c.cities.first;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<CampusEvent> _campusEvents(
    List<CampusEvent> all,
    AuthProvider auth,
  ) {
    final me = auth.user;
    final uni = me?.university.trim() ?? '';
    final city = me?.city.trim() ?? '';
    final list = all.where((e) {
      if (!e.isApproved || !e.isCampusScoped) return false;
      if (uni.isEmpty) return true;
      if (e.university.trim().isNotEmpty) {
        return CampusAffinity.sameLabel(e.university, uni);
      }
      // Eski kayıt: topluluk hesabının üniversitesine bak.
      final cid = e.communityId;
      if (cid == null) return true;
      final org = auth.findUser(cid);
      if (org == null) return true;
      return CampusAffinity.sameLabel(org.university, uni);
    }).toList();

    // Aynı şehirdeki kampüs etkinlikleri üstte, sonra tarih
    list.sort((a, b) {
      if (city.isNotEmpty) {
        final aCity = CampusAffinity.sameLabel(a.city, city) ? 1 : 0;
        final bCity = CampusAffinity.sameLabel(b.city, city) ? 1 : 0;
        if (aCity != bCity) return bCity.compareTo(aCity);
      }
      return a.startsAt.compareTo(b.startsAt);
    });
    return list;
  }

  List<CampusEvent> _offCampusEvents(List<CampusEvent> all) {
    final filter = _offCampusCity.trim();
    return all.where((e) {
      if (!e.isApproved || e.isCampusScoped) return false;
      if (filter.isEmpty) return true;
      final city = e.city.trim();
      if (city.isEmpty) return false;
      return CampusAffinity.sameLabel(city, filter);
    }).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<FeedProvider>().events;
    final auth = context.watch<AuthProvider>();
    final campus = _campusEvents(all, auth);
    final off = _offCampusEvents(all);
    final cityItems = _cities.isNotEmpty
        ? _cities
        : (auth.user?.city.trim().isNotEmpty == true
            ? [auth.user!.city.trim()]
            : <String>[]);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Etkinlikler'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.navy,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.cyan,
          tabs: [
            Tab(text: 'Okulumdaki (${campus.length})'),
            Tab(text: 'Kampüs dışı (${off.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _EventList(
            events: campus,
            emptyTitle: 'Okulunda henüz etkinlik yok',
            emptySubtitle:
                'Üniversite kulüplerinin veya adminin eklediği etkinlikler burada görünür.',
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: cityItems.isEmpty
                    ? const Text(
                        'Şehir listesi yükleniyor…',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    : DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: cityItems.contains(_offCampusCity)
                            ? _offCampusCity
                            : cityItems.first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText:
                              'Hangi şehrin etkinliklerini görmek istersin?',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final c in cityItems)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _offCampusCity = v);
                        },
                      ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Kampüs dışı etkinlikler, admin onaylı organizatör firmaların '
                  'etkinlikleridir. Kendi şehrin varsayılan seçilir.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
              Expanded(
                child: _EventList(
                  events: off,
                  emptyTitle: 'Bu şehirde kampüs dışı etkinlik yok',
                  emptySubtitle:
                      'Organizatör firmalar etkinlik ekleyip admin onayı alınca burada listelenir.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({
    required this.events,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<CampusEvent> events;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy_outlined,
                  size: 42, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = events[index];
        final blocked = event.applyBlockedReason(
          user: user,
          follows: (cid) => auth.follows(cid),
        );
        final canApply = blocked.isEmpty;
        final date =
            DateFormat('d MMMM yyyy · HH:mm', 'tr').format(event.startsAt);
        final deadlineLabel = event.applicationDeadline == null
            ? null
            : DateFormat('d MMM · HH:mm', 'tr')
                .format(event.applicationDeadline!);
        final priceLabel = event.priceTiers.isEmpty
            ? null
            : event.priceTiers
                .map((t) =>
                    '${t.label}: ${t.amount.toStringAsFixed(t.amount % 1 == 0 ? 0 : 2)} ${t.currency}')
                .join(' · ');

        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => AppNav.openEvent(context, event.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (event.imageUrl != null)
                  GestureDetector(
                    onTap: () => openMediaViewer(
                      context,
                      urls: [event.imageUrl!],
                      isVideo: const [false],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      child: AspectRatio(
                        aspectRatio: 16 / 7,
                        child: SafeNetworkImage(
                          url: event.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.surfaceMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.organizerLabel.isNotEmpty)
                        AffiliationBadge(
                          orgName: event.organizerLabel,
                          logoUrl: event.communityLogoUrl,
                          orgId: event.communityId ?? event.organizerCompanyId,
                          verifiedGold: event.communityId != null,
                          compact: true,
                        ),
                      if (event.organizerLabel.isNotEmpty)
                        const SizedBox(height: 8),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.location,
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (deadlineLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Son başvuru: $deadlineLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.crimson,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (priceLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          priceLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${event.heldSlots}/${event.capacity} · ${event.audienceLabel}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: !canApply
                                ? null
                                : () {
                                    if (!AuthGate.requireAuth(context)) return;
                                    AppNav.openEvent(context, event.id);
                                  },
                            child: Text(
                              canApply ? 'Başvur' : blocked,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Paylaş',
                            onPressed: () => AppShare.shareLink(
                              context: context,
                              url: AppShare.event(event.id),
                              subject: event.title,
                              preview: event.title,
                            ),
                            icon: const Icon(Icons.ios_share, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 280.ms, delay: (40 * index).ms)
            .slideY(begin: 0.04, curve: Curves.easeOut);
      },
    );
  }
}
