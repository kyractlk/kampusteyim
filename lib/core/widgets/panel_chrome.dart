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
