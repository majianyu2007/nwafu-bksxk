/// The signed-in shell: bottom navigation across Home, Courses, Monitor, Selected,
/// and Settings, with a persistent header showing student + active batch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../data/notifications.dart';
import 'courses_controller.dart';
import 'courses_page.dart';
import 'home_page.dart';
import 'layout.dart';
import 'monitor_page.dart';
import 'relogin_dialog.dart';
import 'selected_page.dart';
import 'settings_page.dart';
import 'batch_pick_dialog.dart';

@visibleForTesting
int notificationDestinationIndex(String? payload) => switch (payload) {
      'selected' => 3,
      'monitor' => 2,
      _ => 0,
    };

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  static const _pages = [
    HomePage(),
    CoursesPage(),
    MonitorPage(),
    SelectedPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    NotificationService.instance.init(onTap: _openNotificationTarget);
    // Start collecting monitor events now, not when the Monitor tab first
    // builds its log widget.
    ref.read(monitorLogProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOnboard());
  }

  /// One-shot post-login prompt. The official site always asks the student to
  /// choose a round; we keep it non-blocking ("稍后再说") but still surface it
  /// once even when a selectable round was auto-picked.
  void _maybeOnboard() {
    if (_onboardingChecked || !mounted) return;
    _onboardingChecked = true;
    final batches = ref.read(sessionProvider).batches;
    if (batches.isEmpty) return;
    showBatchPickDialog(context, ref);
  }

  int _index = 0;
  bool _onboardingChecked = false;
  bool _reloginShowing = false;

  /// The session dropped and silent re-login gave up: ask for a login without
  /// tearing the shell down. One dialog at a time.
  Future<void> _showRelogin() async {
    if (_reloginShowing || !mounted) return;
    _reloginShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const ReloginDialog(),
      );
    } finally {
      _reloginShowing = false;
    }
  }

  void _openNotificationTarget(String? payload) {
    if (!mounted) return;
    _selectPage(notificationDestinationIndex(payload));
  }

  @override
  void dispose() {
    // Taps that arrive while no shell is mounted are buffered and replayed by
    // the next shell's init(); a stale handler would silently drop them.
    NotificationService.instance.detachTapHandler(_openNotificationTarget);
    super.dispose();
  }

  void _selectPage(int index) {
    if (index == 1) {
      // The page loads itself on mount and reloads on selection changes; only
      // kick off a fetch here if nothing has been loaded yet (e.g. after an
      // early failure), so switching tabs never re-downloads the whole list.
      final courses = ref.read(coursesProvider);
      if (!courses.loadedOnce && !courses.loading) {
        ref.read(coursesProvider.notifier).load();
      }
    }
    if (_index != index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    // Keep the notification bridge alive for the app's lifetime.
    ref.watch(notificationBridgeProvider);
    ref.listen<AuthPhase>(sessionProvider.select((s) => s.phase), (_, next) {
      if (next == AuthPhase.expired) _showRelogin();
    });
    // Badge the Monitor tab with the count of active watches.
    final activeWatches = ref.watch(watchCountProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= kRailBreakpoint;
        final content = SafeArea(
          bottom: !useRail,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: SizedBox.expand(
                child: IndexedStack(index: _index, children: _pages),
              ),
            ),
          ),
        );

        if (useRail) {
          final extended = constraints.maxWidth >= kExtendedRailBreakpoint;
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: extended,
                    minExtendedWidth: 196,
                    selectedIndex: _index,
                    onDestinationSelected: _selectPage,
                    labelType: extended
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Icon(
                        Icons.school_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 30,
                      ),
                    ),
                    destinations: [
                      const NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: Text('首页'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.menu_book_outlined),
                        selectedIcon: Icon(Icons.menu_book),
                        label: Text('选课'),
                      ),
                      NavigationRailDestination(
                        icon:
                            _MonitorIcon(count: activeWatches, selected: false),
                        selectedIcon:
                            _MonitorIcon(count: activeWatches, selected: true),
                        label: const Text('监控'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.account_circle_outlined),
                        selectedIcon: Icon(Icons.account_circle),
                        label: Text('我的'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('设置'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }

        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectPage,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              const NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: '选课',
              ),
              NavigationDestination(
                icon: _MonitorIcon(count: activeWatches, selected: false),
                selectedIcon:
                    _MonitorIcon(count: activeWatches, selected: true),
                label: '监控',
              ),
              const NavigationDestination(
                icon: Icon(Icons.account_circle_outlined),
                selectedIcon: Icon(Icons.account_circle),
                label: '我的',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonitorIcon extends StatelessWidget {
  const _MonitorIcon({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.radar : Icons.radar_outlined);
    if (count == 0) return icon;
    return Badge(label: Text('$count'), child: icon);
  }
}
