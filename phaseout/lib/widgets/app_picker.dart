// ─────────────────────────────────────────────────────────────
//  lib/widgets/app_picker.dart
//
//  FIXED: Now uses device_apps package which calls Android's
//  PackageManager directly — guaranteed to return ALL user apps
//  with launch intents, not just recently used ones.
//
//  Key settings used:
//    includeAppIcons: true       — icons as bytes, no channel calls
//    includeSystemApps: false    — skip Android internals
//    onlyAppsWithLaunchIntent: true — only apps user can actually open
//
//  Home screen / launcher packages are also excluded so focus
//  mode never blocks the user from going home.
// ─────────────────────────────────────────────────────────────

import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';
import '../app_theme.dart';

// Packages that are always safe and shown at the top with a badge
const _kSafePackages = <String>{
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

// Launchers / home screens — never show these in focus picker
// Blocking them would trap the user on the overlay
const _kLauncherPackages = <String>{
  'com.android.launcher',
  'com.android.launcher2',
  'com.android.launcher3',
  'com.samsung.android.launcher',
  'com.google.android.apps.nexuslauncher',
  'com.miui.home',
  'com.huawei.android.launcher',
  'com.oneplus.launcher',
  'com.oppo.launcher',
  'com.vivo.launcher',
  'com.tcl.launcher',
  'com.sec.android.app.launcher',
};

class AppPicker extends StatefulWidget {
  final List<String>               selected;
  final ValueChanged<List<String>> onChanged;

  const AppPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<AppPicker> {
  final _searchCtrl = TextEditingController();

  List<ApplicationWithIcon> _all      = [];
  List<ApplicationWithIcon> _filtered = [];
  bool                      _loading  = true;
  bool                      _gridView = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _loadApps();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    // device_apps fetches everything natively — no channel needed
    // onlyAppsWithLaunchIntent: true ensures only tappable apps
    // includeSystemApps: false keeps it clean (Settings etc handled via _kSafePackages manually if needed)
    final apps = await DeviceApps.getInstalledApplications(
      includeAppIcons:          true,
      includeSystemApps:        false,
      onlyAppsWithLaunchIntent: true,
    );

    // Cast to ApplicationWithIcon (guaranteed since includeAppIcons: true)
    final withIcons = apps
        .whereType<ApplicationWithIcon>()
        .where((a) =>
            a.packageName != 'com.brightdev.phaseout' && // exclude self
            !_kLauncherPackages.contains(a.packageName)) // exclude launchers
        .toList();

    // Sort: safe apps first, then alphabetical by app name
    withIcons.sort((a, b) {
      final aSafe = _kSafePackages.contains(a.packageName);
      final bSafe = _kSafePackages.contains(b.packageName);
      if (aSafe && !bSafe) return -1;
      if (!aSafe && bSafe) return 1;
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });

    if (mounted) {
      setState(() {
        _all      = withIcons;
        _filtered = withIcons;
        _loading  = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((a) =>
              a.appName.toLowerCase().contains(q) ||
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Search + view toggle row
        Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText:  'Search apps…',
                hintStyle: const TextStyle(
                    color: AppTheme.textHint, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textSecond, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
                filled:    true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Grid / list toggle
          GestureDetector(
            onTap: () => setState(() => _gridView = !_gridView),
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(
                _gridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
                size: 20, color: AppTheme.textSecond),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // Selection count
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${widget.selected.length} app${widget.selected.length == 1 ? '' : 's'} selected',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.accentLight),
            ),
          ),

        // App list or grid
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Loading apps…',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textHint)),
              ],
            )),
          )
        else if (_filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text('No apps found.',
                style: TextStyle(
                    color: AppTheme.textHint, fontSize: 13)),
          )
        else if (_gridView)
          _GridView(
            apps:     _filtered,
            selected: widget.selected,
            onToggle: _toggle,
          )
        else
          _ListView(
            apps:     _filtered,
            selected: widget.selected,
            onToggle: _toggle,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  List view
// ─────────────────────────────────────────────────────────────
class _ListView extends StatelessWidget {
  final List<ApplicationWithIcon> apps;
  final List<String>              selected;
  final ValueChanged<String>      onToggle;
  const _ListView({
    required this.apps,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap:  true,
      physics:     const NeverScrollableScrollPhysics(),
      itemCount:   apps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final app    = apps[i];
        final isSel  = selected.contains(app.packageName);
        final isSafe = _kSafePackages.contains(app.packageName);

        return GestureDetector(
          onTap: () => onToggle(app.packageName),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSel
                    ? AppTheme.accent.withValues(alpha: 0.4)
                    : AppTheme.border,
              ),
            ),
            child: Row(children: [
              // Icon — from device_apps as bytes
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  app.icon,
                  width: 40, height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _Initial(app.appName),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Row(children: [
                Flexible(child: Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w500,
                      color:      AppTheme.textPrimary),
                )),
                if (isSafe) ...[
                  const SizedBox(width: 6),
                  const _SafeBadge(),
                ],
              ])),
              const SizedBox(width: 8),
              // Checkbox
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isSel ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSel ? AppTheme.accent : AppTheme.border,
                    width: 1.5,
                  ),
                ),
                child: isSel
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Grid view
// ─────────────────────────────────────────────────────────────
class _GridView extends StatelessWidget {
  final List<ApplicationWithIcon> apps;
  final List<String>              selected;
  final ValueChanged<String>      onToggle;
  const _GridView({
    required this.apps,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
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
        final app   = apps[i];
        final isSel = selected.contains(app.packageName);

        return GestureDetector(
          onTap: () => onToggle(app.packageName),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 58, height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: isSel
                        ? AppTheme.accentLight
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.memory(
                    app.icon,
                    width: 58, height: 58,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _Initial(app.appName, size: 58),
                  ),
                ),
              ),
              if (isSel)
                Positioned(top: 2, right: 2,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.navy, width: 1.5)),
                    child: const Icon(Icons.check,
                        size: 11, color: Colors.white))),
            ]),
            const SizedBox(height: 5),
            Text(
              app.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   10,
                color: isSel
                    ? AppTheme.accentLight
                    : AppTheme.textSecond,
                fontWeight: isSel
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Shared sub-widgets
// ─────────────────────────────────────────────────────────────

class _Initial extends StatelessWidget {
  final String name;
  final double size;
  const _Initial(this.name, {this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    color: AppTheme.surface2,
    alignment: Alignment.center,
    child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          color: AppTheme.textHint),
    ),
  );
}

class _SafeBadge extends StatelessWidget {
  const _SafeBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
    ),
    child: const Text('safe',
      style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600,
          color: AppTheme.accentLight, letterSpacing: 0.3)),
  );
}