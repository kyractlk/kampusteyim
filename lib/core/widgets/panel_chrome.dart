import 'package:flutter/material.dart';

import '../../data/campus_catalog.dart';
import '../../data/mock/mock_data.dart';
import '../theme/app_colors.dart';

/// Organizatör / ayar panelleri için yumuşak kart.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: color ?? AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class PanelSectionLabel extends StatelessWidget {
  const PanelSectionLabel(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Panel karşılama başlığı.
class PanelWelcomeHeader extends StatelessWidget {
  const PanelWelcomeHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      color: AppColors.navy.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              height: 1.4,
              color: AppColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ana menü ticker / kısayol kartı — tıklanınca ilgili bölüme gider.
class PanelNavTile extends StatelessWidget {
  const PanelNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? Colors.white : AppColors.navy;
    final bg = accent ? AppColors.navy : AppColors.surface;
    return PanelCard(
      color: bg,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent
                  ? Colors.white.withValues(alpha: 0.15)
                  : AppColors.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: fg,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: accent ? Colors.white70 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: accent ? Colors.white70 : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Stepli form üst çubuğu.
class PanelStepBar extends StatelessWidget {
  const PanelStepBar({
    super.key,
    required this.labels,
    required this.step,
  });

  final List<String> labels;
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i <= step
                    ? AppColors.navy
                    : AppColors.border,
              ),
            ),
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    i <= step ? AppColors.navy : AppColors.border,
                foregroundColor:
                    i <= step ? Colors.white : AppColors.textSecondary,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: i <= step
                      ? AppColors.navy
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Yüksek kontrastlı izin/toggle kutusu (lacivert seçilince beyaz yazı).
class PanelToggleCard extends StatelessWidget {
  const PanelToggleCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.navy : AppColors.border,
          width: 1.4,
        ),
      ),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.white : AppColors.navy,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.navy,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 20,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Türkiye illerinden çoklu seçim — katalog JSON’dan.
class CityTargetPicker extends StatefulWidget {
  const CityTargetPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.allowNationwide = true,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool allowNationwide;

  static const nationwide = 'Türkiye geneli';

  @override
  State<CityTargetPicker> createState() => _CityTargetPickerState();
}

class _CityTargetPickerState extends State<CityTargetPicker> {
  final _search = TextEditingController();
  List<String> _all = const [];
  bool _loading = true;

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
    try {
      final catalog = await CampusCatalog.load();
      final seen = <String>{};
      final list = <String>[];
      for (final c in catalog.cities) {
        final t = c.trim();
        if (t.isEmpty) continue;
        final key = t.toLowerCase().replaceAll('â', 'a');
        if (seen.add(key)) list.add(t);
      }
      list.sort((a, b) => a.compareTo(b));
      if (!mounted) return;
      setState(() {
        _all = list.isNotEmpty ? list : List<String>.from(MockData.cities);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = List<String>.from(MockData.cities);
        _loading = false;
      });
    }
  }

  bool get _nationwide =>
      widget.selected.contains(CityTargetPicker.nationwide);

  void _toggle(String city, bool on) {
    final next = {...widget.selected};
    if (city == CityTargetPicker.nationwide) {
      if (on) {
        widget.onChanged({CityTargetPicker.nationwide});
      } else {
        next.remove(CityTargetPicker.nationwide);
        widget.onChanged(next);
      }
      return;
    }
    next.remove(CityTargetPicker.nationwide);
    if (on) {
      next.add(city);
    } else {
      next.remove(city);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _all
        : _all.where((c) => c.toLowerCase().contains(q)).toList();
    final visible = filtered.take(q.isEmpty ? 12 : 24).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in widget.selected)
                  InputChip(
                    label: Text(c),
                    selected: true,
                    onDeleted: () => _toggle(c, false),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'İl ara',
            hintText: 'Ankara, İstanbul, Gaziantep…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (widget.allowNationwide)
              FilterChip(
                avatar: Icon(
                  Icons.public_rounded,
                  size: 16,
                  color: _nationwide ? Colors.white : AppColors.navy,
                ),
                label: const Text('Türkiye geneli'),
                selected: _nationwide,
                onSelected: (v) => _toggle(CityTargetPicker.nationwide, v),
              ),
            for (final c in visible)
              FilterChip(
                label: Text(c),
                selected: !_nationwide && widget.selected.contains(c),
                onSelected: _nationwide
                    ? null
                    : (v) => _toggle(c, v),
              ),
          ],
        ),
        if (q.isEmpty && _all.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_all.length} il · arayarak hepsini bulabilirsin',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

Future<DateTime?> pickPanelDateTime(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final now = DateTime.now();
  final seed = initial ?? now;
  final d = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: firstDate ?? now.subtract(const Duration(days: 1)),
    lastDate: lastDate ?? now.add(const Duration(days: 365 * 2)),
    locale: const Locale('tr'),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}
