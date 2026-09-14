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
import 'monitor_page.dart';
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

  void _openNotificationTarget(String? payload) {
    if (!mounted) return;
    _selectPage(notificationDestinationIndex(payload));
  }

  void _selectPage(int index) {
    if (index == 1) ref.read(coursesProvider.notifier).load();
    if (_index != index) setState(() => _index = index);
  }


  @override
  Widget build(BuildContext context) {
    // Keep the notification bridge alive for the app's lifetime.
    ref.watch(notificationBridgeProvider);
    // Badge the Monitor tab with the count of active watches.
    final activeWatches = ref.watch(watchCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _pages),
      ),
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
            selectedIcon: _MonitorIcon(count: activeWatches, selected: true),
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
