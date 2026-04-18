// ─────────────────────────────────────────────────────────────
//  lib/widgets/app_picker.dart
//  PhaseOut — App picker with real icons, 7-day query
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../services/app_label_service.dart';

class AppPicker extends StatefulWidget {
  final List<String>               selected;
  final ValueChanged<List<String>> onChanged;

  const AppPicker({super.key, required this.selected, required this.onChanged});

  @override
  State<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<AppPicker> {

  static const MethodChannel _iconChannel =
      MethodChannel('com.brightdev.phaseout/usage');

  final _search = TextEditingController();
  List<_AppEntry> _all      = [];
  List<_AppEntry> _filtered = [];
  bool            _loading  = true;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_filter);
  }

  Future<void> _load() async {
    try {
      // 7-day window — returns all recently used apps, not just today
      final now     = DateTime.now();
      final startMs = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final endMs   = now.millisecondsSinceEpoch;
      final stats   = await UsageChannel.getStatsForRange(startMs, endMs);

      if (stats.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final entries = <_AppEntry>[];
      for (final pkg in stats.keys) {
        if (pkg.contains('launcher') || pkg == 'com.brightdev.phaseout') continue;
        final label = await AppLabelService.resolve(pkg);

        Uint8List? iconBytes;
        try {
          iconBytes = await _iconChannel.invokeMethod<Uint8List>(
              'getAppIcon', {'packageName': pkg});
        } catch (_) {}

        entries.add(_AppEntry(
          package:   pkg,
          label:     label,
          iconBytes: iconBytes,
          minutes:   stats[pkg] ?? 0,
        ));
      }

      entries.sort((a, b) => a.label.compareTo(b.label));

      if (mounted) {
        setState(() { _all = entries; _filtered = entries; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty ? _all
          : _all.where((e) =>
              e.label.toLowerCase().contains(q) ||
              e.package.toLowerCase().contains(q)).toList();
    });
  }

  void _toggle(String pkg) {
    final updated = List<String>.from(widget.selected);
    if (updated.contains(pkg)) {
      updated.remove(pkg);
    } else {
      updated.add(pkg);
    }
    widget.onChanged(updated);
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: _search,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText:   'Search apps',
          prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecond),
        ),
      ),
      const SizedBox(height: 12),
      if (_loading)
        const Padding(padding: EdgeInsets.all(24),
          child: Column(children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading apps…', style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
          ]))
      else if (_filtered.isEmpty)
        const Padding(padding: EdgeInsets.all(24),
          child: Text('No apps found', style: TextStyle(color: AppTheme.textHint)))
      else
        ListView.builder(
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          itemCount:  _filtered.length,
          itemBuilder: (_, i) {
            final app      = _filtered[i];
            final selected = widget.selected.contains(app.package);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _AppIcon(iconBytes: app.iconBytes,
                  label: app.label, selected: selected),
              title: Text(app.label,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
              subtitle: Text(
                app.minutes > 0 ? _fmt(app.minutes) : app.package,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
              trailing: Checkbox(
                value: selected, onChanged: (_) => _toggle(app.package),
                activeColor: AppTheme.accent, checkColor: Colors.white,
                side: const BorderSide(color: AppTheme.textHint)),
              onTap: () => _toggle(app.package),
            );
          },
        ),
    ]);
  }

  String _fmt(int m) => m < 60 ? '${m}m this week' : '${m ~/ 60}h ${m % 60}m this week';
}

class _AppIcon extends StatelessWidget {
  final Uint8List? iconBytes;
  final String     label;
  final bool       selected;
  const _AppIcon({required this.iconBytes, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withValues(alpha: 0.15) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: selected ? Border.all(color: AppTheme.accent.withValues(alpha: 0.4)) : null,
      ),
      child: iconBytes != null
          ? ClipRRect(borderRadius: BorderRadius.circular(9),
              child: Image.memory(iconBytes!, width: 40, height: 40, fit: BoxFit.cover))
          : Center(child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: selected ? AppTheme.accentLight : AppTheme.textSecond))),
    );
  }
}

class _AppEntry {
  final String package, label;
  final Uint8List? iconBytes;
  final int minutes;
  const _AppEntry({required this.package, required this.label,
      required this.minutes, this.iconBytes});
}