/// The signed-in shell: navigation across Home, Courses, Monitor, Selected
/// and Settings for the shown account, an account switcher, and the
/// account-wide side effects (notification bridges, re-login dialogs, the
/// one-time 落选 popup).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/monitor_providers.dart';
import '../app/providers.dart';
import '../data/background.dart';
import '../data/models.dart';
import '../data/notifications.dart';
import 'courses_page.dart';
import 'home_page.dart';
import 'layout.dart';
import 'login_page.dart';
import 'monitor_page.dart';
import 'relogin_dialog.dart';
import 'selected_page.dart';
import 'settings_page.dart';
import 'batch_pick_dialog.dart';
import 'widgets.dart';

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

class _RootShellState extends ConsumerState<RootShell>
    implements BackgroundHost {
  int _index = 0;
  final _onboarded = <String>{};
  final _unsuccessfulChecked = <String>{};
  final _reloginShowing = <String>{};

  @override
  void initState() {
    super.initState();
    NotificationService.instance.init(onTap: _openNotificationTarget);
    AppBackground.instance.attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterSignIn());
  }

  @override
  void showApp() {
    if (mounted) setState(() {});
  }

  @override
  void quitApp() {
    for (final id in ref.read(signedInAccountsProvider)) {
      ref.read(sessionScopeProvider(id)).engine.stop();
    }
  }

  @override
  String get statusLine {
    var running = 0;
    for (final id in ref.read(signedInAccountsProvider)) {
      if (ref.read(sessionScopeProvider(id)).engine.isRunning) running++;
    }
    return running == 0 ? '' : '$running 个账号监控中';
  }

  /// Runs once per signed-in account: the round picker and the 落选 popup,
  /// in that order, as the official site does after login.
  Future<void> _afterSignIn() async {
    final id = ref.read(activeAccountIdProvider);
    if (id == null || !mounted) return;
    // Collect this account's monitor events from now on, not from the first
    // time the Monitor tab builds.
    ref.read(monitorLogOfProvider(id));
    if (_onboarded.add(id)) {
      final batches = ref.read(sessionControllerProvider(id)).batches;
      if (batches.isNotEmpty && mounted) await showBatchPickDialog(context, ref);
    }
    if (!mounted) return;
    if (_unsuccessfulChecked.add(id)) await _checkUnsuccessful(id);
  }

  /// The official grab page opens a 落选课程提醒 popup listing the rows the
  /// student has not acknowledged (unsuccessful.do isRead=0) and posts their
  /// wids back on 确认. The app does the same, and also remembers the wids
  /// locally so the popup never repeats for rows the server keeps sending.
  Future<void> _checkUnsuccessful(String id) async {
    final session = ref.read(sessionControllerProvider(id));
    final student = session.student;
    final batch = session.activeBatch;
    if (student == null || batch == null) return;
    final scope = ref.read(sessionScopeProvider(id));
    final storage = ref.read(storageProvider);
    List<UnsuccessfulEntry> rows;
    try {
      rows = await scope.course.fetchUnsuccessful(
          studentCode: student.studentCode, batchCode: batch.code);
    } catch (_) {
      return;
    }
    final acked = storage.acknowledgedUnsuccessful(id);
    rows = rows.where((r) => !r.confirmed && !acked.contains(r.wid)).toList();
    if (rows.isEmpty || !mounted) return;
    NotificationService.instance
        .unsuccessful(count: rows.length, first: rows.first.displayTitle);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UnsuccessfulDialog(rows: rows),
    );
    if (confirmed != true) return;
    final wids = rows.map((r) => r.wid).where((w) => w.isNotEmpty).toList();
    await storage.addAcknowledgedUnsuccessful(id, wids);
    try {
      await scope.course.acknowledgeUnsuccessful(
          studentCode: student.studentCode, wids: wids);
    } catch (_) {
      // Remembered locally either way; the server copy is best effort.
    }
  }

  /// Ask for a login without tearing the shell down. One dialog per account.
  Future<void> _showRelogin(String id) async {
    if (!_reloginShowing.add(id) || !mounted) return;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReloginDialog(accountId: id),
      );
    } finally {
      _reloginShowing.remove(id);
    }
  }

  void _openNotificationTarget(String? payload) {
    if (!mounted) return;
    _selectPage(notificationDestinationIndex(payload));
  }

  @override
  void dispose() {
    NotificationService.instance.detachTapHandler(_openNotificationTarget);
    super.dispose();
  }

  void _selectPage(int index) {
    if (_index != index) setState(() => _index = index);
  }

  Future<void> _addAccount() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const LoginPage(addingAccount: true),
    ));
    if (mounted) _afterSignIn();
  }

  void _switchAccount(String id) {
    ref.read(activeAccountIdProvider.notifier).state = id;
    // Keep the courses page keyed to the account it shows.
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterSignIn());
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(signedInAccountsProvider);
    final activeId = ref.watch(activeAccountIdProvider);
    final multi = ref.watch(multiAccountProvider);
    ref.watch(backgroundDriverProvider);
    for (final id in signedIn) {
      // Keep every account's notification bridge alive, and watch its phase
      // so a dropped session asks for a login even when it is not on screen.
      ref.watch(notificationBridgeProvider(id));
      ref.listen<AuthPhase>(
          sessionControllerProvider(id).select((s) => s.phase), (_, next) {
        if (next == AuthPhase.expired) _showRelogin(id);
      });
    }
    final activeWatches = ref.watch(watchCountProvider);
    // Pages are rebuilt from scratch when the shown account changes so no
    // per-page state (loaded lists, selection) leaks between accounts.
    final pages = [
      const HomePage(),
      CoursesPage(key: ValueKey('courses-$activeId')),
      const MonitorPage(),
      const SelectedPage(),
      const SettingsPage(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= kRailBreakpoint;
        final tabs = multi
            ? AccountTabs(
                signedIn: signedIn,
                activeId: activeId,
                onSwitch: _switchAccount,
                onAdd: _addAccount,
                onClose: (id) => leaveAccount(ref, id),
              )
            : null;
        final content = SafeArea(
          bottom: !useRail,
          child: Column(
            children: [
              if (tabs != null) tabs,
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kContentMaxWidth),
                    child: SizedBox.expand(
                      child: IndexedStack(index: _index, children: pages),
                    ),
                  ),
                ),
              ),
            ],
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
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Image.asset('assets/icons/tray_color_256.png',
                          width: 36, height: 36),
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

/// Browser-style account tabs across the top: one tab per signed-in account
/// (initial, name, a green dot while its monitor runs, red when its session
/// expired), a close button on the active tab, and a "+" tab.
class AccountTabs extends ConsumerWidget {
  const AccountTabs({
    super.key,
    required this.signedIn,
    required this.activeId,
    required this.onSwitch,
    required this.onAdd,
    required this.onClose,
  });

  final List<String> signedIn;
  final String? activeId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onAdd;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      color: scheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
              children: [
                for (final id in signedIn)
                  _AccountTab(
                    id: id,
                    selected: id == activeId,
                    onTap: () => onSwitch(id),
                    onClose: () => _confirmClose(context, ref, id),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '添加账号',
            icon: const Icon(Icons.add),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClose(BuildContext context, WidgetRef ref, String id) async {
    final s = ref.read(sessionControllerProvider(id));
    final running = ref.read(sessionScopeProvider(id)).engine.isRunning;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('退出 ${s.displayName}'),
        content: Text(running ? '该账号的监控正在运行，退出后会停止。' : '退出该账号的登录？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) onClose(id);
  }
}

class _AccountTab extends ConsumerWidget {
  const _AccountTab(
      {required this.id,
      required this.selected,
      required this.onTap,
      required this.onClose});
  final String id;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(sessionControllerProvider(id));
    final expired = s.phase == AuthPhase.expired;
    final running = ref.watch(monitorChangesProvider(id)).hasValue &&
        ref.read(sessionScopeProvider(id)).engine.isRunning;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
            child: Row(
              children: [
                _Avatar(id: id, size: 22),
                const SizedBox(width: 8),
                Text(
                  s.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: expired ? scheme.error : scheme.onSurface,
                  ),
                ),
                if (running) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.circle, size: 8, color: Colors.green),
                ],
                const SizedBox(width: 4),
                if (selected)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: '退出该账号',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A coloured circle with the account's first initial, with a badge for a
/// running monitor or an expired session.
class _Avatar extends ConsumerWidget {
  const _Avatar({required this.id, required this.size});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(sessionControllerProvider(id));
    final name = s.displayName;
    final initial = name.isEmpty ? '?' : name.characters.first;
    final expired = s.phase == AuthPhase.expired;
    final running = ref.watch(monitorChangesProvider(id)).hasValue &&
        ref.read(sessionScopeProvider(id)).engine.isRunning;
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: expired ? scheme.errorContainer : scheme.primaryContainer,
      child: Text(initial,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: expired ? scheme.onErrorContainer : scheme.onPrimaryContainer)),
    );
    if (!running && !expired) return avatar;
    return Badge(
      smallSize: 10,
      backgroundColor: expired ? scheme.error : Colors.green,
      child: avatar,
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

/// The 落选课程提醒 popup: date, course, teacher, outcome per row.
class _UnsuccessfulDialog extends StatelessWidget {
  const _UnsuccessfulDialog({required this.rows});
  final List<UnsuccessfulEntry> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('${rows.length} 门课程落选'),
      content: SizedBox(
        width: 520,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, i) {
            final r = rows[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.displayTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (r.teacherName.isNotEmpty) r.teacherName,
                            if (r.time.length >= 10) r.time.substring(0, 10),
                          ].join('  '),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                      label: r.reason.isEmpty ? '落选' : r.reason,
                      color: scheme.error),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
