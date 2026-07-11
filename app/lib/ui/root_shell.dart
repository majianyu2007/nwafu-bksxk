/// The signed-in shell: bottom navigation across Home, Courses, Monitor, Selected,
/// and Settings, with a persistent header showing student + active batch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import 'courses_page.dart';
import 'home_page.dart';
import 'monitor_page.dart';
import 'selected_page.dart';
import 'settings_page.dart';

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const _pages = [
    HomePage(),
    CoursesPage(),
    MonitorPage(),
    SelectedPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // Badge the Monitor tab with the count of active watches.
    final activeWatches = ref.watch(watchCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: '已选',
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
