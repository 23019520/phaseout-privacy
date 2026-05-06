// ─────────────────────────────────────────────────────────────
//  lib/widgets/app_picker.dart  — v4 final
//
//  FIXES:
//  - Now uses UsageChannel.getAllInstalledApps() which calls
//    PackageManager.getInstalledApplications() on the Kotlin side.
//    This returns EVERY launchable app, not just recently used ones.
//  - Icons loaded progressively after the list appears so the UI
//    isn't blocked while 100+ icons decode.
//  - Grid view and list view toggle (Oscar's feedback).
//  - Safe apps badge (Phone, Messages, Settings).
//  - No more system noise (Android, Encryption, prod) — filtered
//    by getLaunchIntentForPackage() on the Kotlin side.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';

// Packages that should be shown at the top with a "Safe" badge
const _safePackages = {
  'com.android.dialer',
  'com.samsung.android.dialer',
  'com.google.android.dialer',
  'com.android.mms',
  'com.samsung.android.messaging',
  'com.google.android.apps.messaging',
  'com.android.settings',
  'com.samsung.android.settings',
  'com.google.android.settings.intelligence',
};

class AppPicker extends StatefulWidget {
  final List<String>               selected;
  final ValueChanged<List<String>> onChanged;

  const AppPicker({super.key, required this.selected, required this.onChanged});

  @override
  State<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<AppPicker> {

  static const _usageChannel = MethodChannel('com.brightdev.phaseout/usage');

  final _search = TextEditingController();

  // All installed apps (label + package)
  List<AppInfo> _all      = [];
  List<AppInfo> _filtered = [];

  // Icons loaded progressively — package → bytes
  final Map<String, Uint8List?> _icons = {};

  bool _loading  = true;
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_filter);
    _loadApps();
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _loadApps() async {
    // Step 1: Load app list (fast — no icon decoding)
    final apps = await UsageChannel.getAllInstalledApps();

    // Sort: safe apps first, then alphabetical
    apps.sort((a, b) {
      final aSafe = _safePackages.contains(a.packageName);
      final bSafe = _safePackages.contains(b.packageName);
      if (aSafe && !bSafe) return -1;
      if (!aSafe && bSafe) return 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    if (mounted) {
      setState(() {
        _all      = apps;
        _filtered = apps;
        _loading  = false;
      });
    }

    // Step 2: Load icons progressively in the background
    // Load in batches of 10 to avoid flooding the MethodChannel
    for (var i = 0; i < apps.length; i += 10) {
      final batch = apps.skip(i).take(10).toList();
      for (final app in batch) {
        if (!mounted) return;
        try {
          final bytes = await _usageChannel.invokeMethod<Uint8List>(
              'getAppIcon', {'packageName': app.packageName});
          if (mounted) {
            setState(() => _icons[app.packageName] = bytes);
          }
        } catch (_) {
          _icons[app.packageName] = null;
        }
      }
      // Small delay between batches so UI stays responsive
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  void _filter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((a) =>
              a.label.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q)).toList();
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
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Search bar + view toggle
      Row(children: [
        Expanded(
          child: TextField(
            controller: _search,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText:    'Search apps',
              prefixIcon:  Icon(Icons.search_rounded,
                  color: AppTheme.textSecond, size: 18),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _gridView = !_gridView),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color:        AppTheme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border)),
            child: Icon(
              _gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              size: 18, color: AppTheme.textSecond)),
        ),
      ]),
      const SizedBox(height: 4),

      // Selection count
      if (widget.selected.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${widget.selected.length} app${widget.selected.length == 1 ? "" : "s"} selected',
            style: const TextStyle(fontSize: 11, color: AppTheme.accentLight)),
        ),

      // Loading state
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading all apps…',
                style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          ]))
      else if (_filtered.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No apps found',
              style: TextStyle(color: AppTheme.textHint)))
      else if (_gridView)
        _GridView(apps: _filtered, selected: widget.selected,
            icons: _icons, onToggle: _toggle,
            safePackages: _safePackages)
      else
        _ListView(apps: _filtered, selected: widget.selected,
            icons: _icons, onToggle: _toggle,
            safePackages: _safePackages),
    ]);
  }
}

// ── List view ─────────────────────────────────────────────────
class _ListView extends StatelessWidget {
  final List<AppInfo>              apps;
  final List<String>               selected;
  final Map<String, Uint8List?>    icons;
  final Set<String>                safePackages;
  final ValueChanged<String>       onToggle;

  const _ListView({required this.apps, required this.selected,
      required this.icons, required this.safePackages, required this.onToggle});

  @override
  Widget build(BuildContext context) => ListView.builder(
    shrinkWrap: true,
    physics:    const NeverScrollableScrollPhysics(),
    itemCount:  apps.length,
    itemBuilder: (_, i) {
      final app   = apps[i];
      final sel   = selected.contains(app.packageName);
      final isSafe = safePackages.contains(app.packageName);
      final icon  = icons[app.packageName];

      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: _Icon(bytes: icon, label: app.label, selected: sel),
        title: Row(children: [
          Expanded(child: Text(app.label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary))),
          if (isSafe)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99)),
              child: const Text('Safe', style: TextStyle(
                  fontSize: 9, color: AppTheme.success,
                  fontWeight: FontWeight.w600))),
        ]),
        trailing: Checkbox(
          value:       sel,
          onChanged:   (_) => onToggle(app.packageName),
          activeColor: AppTheme.accent,
          checkColor:  Colors.white,
          side: const BorderSide(color: AppTheme.textHint)),
        onTap: () => onToggle(app.packageName),
      );
    },
  );
}

// ── Grid view ─────────────────────────────────────────────────
class _GridView extends StatelessWidget {
  final List<AppInfo>              apps;
  final List<String>               selected;
  final Map<String, Uint8List?>    icons;
  final Set<String>                safePackages;
  final ValueChanged<String>       onToggle;

  const _GridView({required this.apps, required this.selected,
      required this.icons, required this.safePackages, required this.onToggle});

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap:  true,
    physics:     const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount:   4,
      mainAxisSpacing:  16,
      crossAxisSpacing: 12,
      childAspectRatio: 0.75,
    ),
    itemCount:   apps.length,
    itemBuilder: (_, i) {
      final app    = apps[i];
      final sel    = selected.contains(app.packageName);
      final isSafe = safePackages.contains(app.packageName);
      final icon   = icons[app.packageName];

      return GestureDetector(
        onTap: () => onToggle(app.packageName),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 58, height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: sel
                    ? Border.all(color: AppTheme.accentLight, width: 2.5)
                    : Border.all(color: Colors.transparent, width: 2.5)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: icon != null
                    ? Image.memory(icon, width: 58, height: 58, fit: BoxFit.cover)
                    : Container(color: AppTheme.surface2,
                        child: Center(child: Text(
                          app.label.isNotEmpty ? app.label[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accentLight)))))),
            // Selected checkmark
            if (sel)
              Positioned(top: 2, right: 2,
                child: Container(width: 18, height: 18,
                  decoration: BoxDecoration(color: AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.navy, width: 1.5)),
                  child: const Icon(Icons.check, size: 11, color: Colors.white))),
            // Safe badge
            if (isSafe && !sel)
              Positioned(bottom: 0, right: 0,
                child: Container(width: 16, height: 16,
                  decoration: BoxDecoration(color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.navy, width: 1.5)),
                  child: const Icon(Icons.check, size: 9, color: Colors.white))),
          ]),
          const SizedBox(height: 5),
          Text(app.label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize:   10,
              color: sel ? AppTheme.accentLight : AppTheme.textSecond,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
        ]),
      );
    },
  );
}

// ── App icon widget ───────────────────────────────────────────
class _Icon extends StatelessWidget {
  final Uint8List? bytes;
  final String     label;
  final bool       selected;
  const _Icon({required this.bytes, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.12)
          : AppTheme.surface2,
      borderRadius: BorderRadius.circular(10),
      border: selected
          ? Border.all(color: AppTheme.accentLight.withValues(alpha: 0.5))
          : null),
    child: bytes != null
        ? ClipRRect(borderRadius: BorderRadius.circular(9),
            child: Image.memory(bytes!, width: 40, height: 40, fit: BoxFit.cover))
        : Center(child: Text(
            label.isNotEmpty ? label[0].toUpperCase() : '?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                color: selected ? AppTheme.accentLight : AppTheme.textSecond))),
  );
}