import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/ui_prefs.dart';
import '../core/errors.dart';
import '../data/academic_calendar.dart' show schoolDate;
import '../data/edu_models.dart';
import '../data/timetable_logic.dart';
import 'edu_login_page.dart';
import 'layout.dart';
import 'timetable/course_sheets.dart';
import 'timetable/day_view.dart';
import 'timetable/timetable_style.dart';
import 'timetable/week_grid.dart';
import 'widgets.dart';
import 'widgets/glass.dart';
import 'free_rooms_page.dart';

/// Below this width the timetable opens in the day view unless the user
/// chose otherwise.
const double kDayViewBreakpoint = 600;

/// An offline-first view of the unified-identity timetable: a day timeline
/// on phones, a week grid on wider windows.
class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  String? _shownTerm;
  int? _selectedWeek;

  /// Weekday (1–7) shown by the day view; null = today / Monday.
  int? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(timetableProvider);
      if (ref.read(eduSessionProvider).signedIn &&
          state.data == null &&
          !state.loading &&
          state.error == null) {
        ref.read(timetableProvider.notifier).sync();
      }
    });
  }

  void _login() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const EduLoginPage()));
  }

  Future<void> _sync() async {
    if (!ref.read(eduSessionProvider).signedIn) {
      _login();
      return;
    }
    await ref
        .read(timetableProvider.notifier)
        .sync(term: ref.read(timetableProvider).data?.term);
    if (mounted) ref.invalidate(examsProvider);
  }

  void _selectWeek(TermTimetable data, int week) {
    setState(() {
      _shownTerm = data.term.code;
      _selectedWeek = week.clamp(1, math.max(1, data.weekCount));
    });
  }

  void _goToday(TermTimetable data, DateTime now) {
    setState(() {
      _shownTerm = data.term.code;
      _selectedWeek = data.displayWeek(now);
      _selectedDay = schoolDate(now).weekday;
    });
  }

  /// Day view swipe: step one day, crossing into the neighbouring week.
  void _stepDay(TermTimetable data, int week, int day, int delta) {
    var w = week;
    var d = day + delta;
    if (d < 1) {
      if (w <= 1) return;
      w--;
      d = 7;
    } else if (d > 7) {
      if (w >= data.weekCount) return;
      w++;
      d = 1;
    }
    setState(() {
      _shownTerm = data.term.code;
      _selectedWeek = w;
      _selectedDay = d;
    });
  }

  Future<void> _chooseWeek(
    TermTimetable data,
    int selected,
    int? current,
  ) async {
    final week = await showGlassSheet<int>(
      context,
      builder: (context) => TimetableSheet(
        title: '选择教学周',
        children: [
          Text(data.term.name),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var w = 1; w <= math.max(1, data.weekCount); w++)
                ChoiceChip(
                  label: Text('第 $w 周${w == current ? ' · 本周' : ''}'),
                  selected: w == selected,
                  onSelected: (_) => Navigator.pop(context, w),
                ),
            ],
          ),
        ],
      ),
    );
    if (week != null && mounted) _selectWeek(data, week);
  }

  void _preferences() {
    showGlassSheet<void>(
      context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final prefs = ref.watch(timetablePrefsProvider);
          final controller = ref.read(timetablePrefsProvider.notifier);
          final ui = ref.watch(uiPrefsProvider);
          final uiCtrl = ref.read(uiPrefsProvider.notifier);
          return TimetableSheet(
            title: '课表显示',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示周末'),
                subtitle: const Text('日视图里仍能看到周末的课'),
                value: prefs.showWeekend,
                onChanged: controller.setShowWeekend,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示非本周课程'),
                subtitle: const Text('斜纹淡色显示，本周不用上'),
                value: prefs.showOtherWeeks,
                onChanged: controller.setShowOtherWeeks,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('格子中显示教师'),
                value: ui.showTeacher,
                onChanged: uiCtrl.setShowTeacher,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('紧凑'),
                subtitle: const Text('行高更矮，长课名可能显示不全'),
                value: ui.compactTimetable,
                onChanged: uiCtrl.setCompactTimetable,
              ),
              if (ref.watch(timetableProvider).data case final data?)
                _WeekOneTile(data: data),
            ],
          );
        },
      ),
    );
  }

  Future<void> _chooseTerm(TimetableState state) async {
    final terms = <String, EduTerm>{
      if (state.data != null) state.data!.term.code: state.data!.term,
      for (final term in state.terms) term.code: term,
    }.values.toList();
    final term = await showGlassSheet<EduTerm>(
      context,
      builder: (context) => TimetableSheet(
        title: '切换学期',
        children: [
          if (terms.isEmpty) const Text('还没有学期列表，同步一次课表后再试。'),
          for (final term in terms)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(term.name),
              subtitle: Text(term.code),
              trailing: term == state.data?.term
                  ? const Icon(Icons.check_circle_outline)
                  : null,
              onTap: () => Navigator.pop(context, term),
            ),
          const SizedBox(height: 8),
          const Text('切换后先显示已保存的课表，再联网更新。'),
        ],
      ),
    );
    if (term != null && mounted && term != state.data?.term) {
      await ref.read(timetableProvider.notifier).switchTerm(term);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(timetableProvider);
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    final prefs = ref.watch(timetablePrefsProvider);
    final ui = ref.watch(uiPrefsProvider);
    final now = ref.watch(clockProvider).asData?.value ?? DateTime.now();
    final exams = state.data == null
        ? const <ExamEntry>[]
        : ref.watch(examsProvider).asData?.value ?? const <ExamEntry>[];
    final data = state.data;
    final scheme = Theme.of(context).colorScheme;
    final week = data == null
        ? 1
        : ((_shownTerm == data.term.code ? _selectedWeek : null) ??
                  data.displayWeek(now))
              .clamp(1, math.max(1, data.weekCount))
              .toInt();
    final currentWeek = data?.weekOf(schoolDate(now));
    final day =
        _selectedDay ??
        (data != null && currentWeek == week ? schoolDate(now).weekday : 1);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = pageGutter(constraints.maxWidth);
          final dayView =
              (ui.timetableView ??
                  (constraints.maxWidth < kDayViewBreakpoint
                      ? TimetableViewMode.day
                      : TimetableViewMode.week)) ==
              TimetableViewMode.day;
          return RefreshIndicator(
            onRefresh: _sync,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                gutter,
                12,
                gutter,
                32 + bottomInset,
              ),
              children: [
                _Header(
                  data: data,
                  loading: state.loading,
                  signedIn: signedIn,
                  dayView: dayView,
                  onTerm: () => _chooseTerm(state),
                  onPrefs: _preferences,
                  onSync: _sync,
                  onToggleView: () => ref
                      .read(uiPrefsProvider.notifier)
                      .setTimetableView(
                        dayView
                            ? TimetableViewMode.week
                            : TimetableViewMode.day,
                      ),
                  onAdd: data == null
                      ? null
                      : () => showCustomCourseEditor(
                          context,
                          data,
                          weekday: dayView ? day : null,
                        ),
                ),
                const SizedBox(height: 12),
                if (state.loading) ...[
                  const LinearProgressIndicator(semanticsLabel: '正在同步课表'),
                  const SizedBox(height: 12),
                ],
                if (state.error case final error?)
                  NoticeStrip(
                    margin: const EdgeInsets.only(bottom: 12),
                    text:
                        '${error.message}${error.hint == null ? '' : '\n${error.hint}'}'
                        '${data == null ? '' : '\n显示的是上次保存的课表。'}',
                    icon: Icons.cloud_off_outlined,
                    error: true,
                    action: TextButton(
                      onPressed: state.loading ? null : _sync,
                      child: const Text('重试'),
                    ),
                  ),
                if (data == null)
                  _Welcome(
                    signedIn: signedIn,
                    loading: state.loading,
                    onAction: signedIn ? _sync : _login,
                  )
                else ...[
                  // A phone's week grid needs the height; the cells already
                  // mark the current/next class.
                  if (dayView ||
                      constraints.maxWidth >= kDayViewBreakpoint) ...[
                    _TodayCard(data: data, now: now),
                    const SizedBox(height: 14),
                  ],
                  _WeekBar(
                    week: week,
                    currentWeek: currentWeek,
                    weekCount: data.weekCount,
                    onPrev: () => _selectWeek(data, week - 1),
                    onNext: () => _selectWeek(data, week + 1),
                    onChoose: () => _chooseWeek(data, week, currentWeek),
                    onToday: () => _goToday(data, now),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                    child: Text(
                      '${dateLabel(data.dayOf(week, 1))} — '
                      '${dateLabel(data.dayOf(week, 7))}'
                      '${dayView ? ' · 左右滑动切换日期' : ' · 左右滑动切换周次'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (currentWeek == null)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Text('今天不在本学期内'),
                    ),
                  const SizedBox(height: 12),
                  if (!dayView && !data.sessions.any((s) => s.runsInWeek(week)))
                    const NoticeStrip(
                      margin: EdgeInsets.only(bottom: 12),
                      text: '本周没有课',
                      icon: Icons.event_available_outlined,
                    ),
                  if (!dayView &&
                      !prefs.showWeekend &&
                      data.sessions.any(
                        (s) => s.weekday >= 6 && s.runsInWeek(week),
                      ))
                    NoticeStrip(
                      margin: const EdgeInsets.only(bottom: 12),
                      text: '本周周末有课（当前未显示周末）',
                      icon: Icons.event_note_outlined,
                      action: TextButton(
                        onPressed: () => ref
                            .read(timetablePrefsProvider.notifier)
                            .setShowWeekend(true),
                        child: const Text('显示周末'),
                      ),
                    ),
                  if (dayView) ...[
                    GlassCard(
                      padding: const EdgeInsets.all(6),
                      child: DateStrip(
                        data: data,
                        week: week,
                        selected: day,
                        now: now,
                        exams: exams,
                        onSelect: (d) => setState(() {
                          _shownTerm = data.term.code;
                          _selectedWeek = week;
                          _selectedDay = d;
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v.abs() < 200) return;
                        _stepDay(data, week, day, v < 0 ? 1 : -1);
                      },
                      child: DayTimeline(
                        data: data,
                        week: week,
                        weekday: day,
                        now: now,
                        exams: exams,
                        showOtherWeeks: prefs.showOtherWeeks,
                        onAdd: () =>
                            showCustomCourseEditor(context, data, weekday: day),
                      ),
                    ),
                  ] else
                    WeekPager(
                      key: ValueKey('${data.term.code}:${data.weekCount}'),
                      data: data,
                      week: week,
                      now: now,
                      prefs: prefs,
                      onWeekChanged: (value) => _selectWeek(data, value),
                    ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '学期安排',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TermExtras(data: data),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        Icons.offline_pin_outlined,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      Text(
                        syncLabel(data.syncedAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (!signedIn)
                        TextButton(
                          onPressed: _login,
                          child: const Text('登录以同步'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.loading,
    required this.signedIn,
    required this.dayView,
    required this.onTerm,
    required this.onPrefs,
    required this.onSync,
    required this.onToggleView,
    required this.onAdd,
  });
  final TermTimetable? data;
  final bool loading;
  final bool signedIn;
  final bool dayView;
  final VoidCallback onTerm;
  final VoidCallback onPrefs;
  final VoidCallback onSync;
  final VoidCallback onToggleView;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '课表',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (data != null)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: loading ? null : onTerm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            data!.term.shortName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        GlassSurface(
          borderRadius: BorderRadius.circular(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data != null) ...[
                IconButton(
                  tooltip: dayView ? '切换为周视图' : '切换为日视图',
                  onPressed: onToggleView,
                  icon: Icon(
                    dayView
                        ? Icons.calendar_view_week_outlined
                        : Icons.view_day_outlined,
                  ),
                ),
                IconButton(
                  tooltip: '添加课程',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                ),
              ],
              if (signedIn)
                IconButton(
                  tooltip: '空教室',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FreeRoomsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.meeting_room_outlined),
                ),
              IconButton(
                tooltip: '课表显示设置',
                onPressed: onPrefs,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: signedIn ? '同步课表' : '登录教务系统',
                onPressed: loading ? null : onSync,
                icon: Icon(signedIn ? Icons.sync : Icons.login),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.week,
    required this.currentWeek,
    required this.weekCount,
    required this.onPrev,
    required this.onNext,
    required this.onChoose,
    required this.onToday,
  });
  final int week;
  final int? currentWeek;
  final int weekCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onChoose;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final isCurrent = week == currentWeek;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              IconButton(
                tooltip: '上一周',
                onPressed: week > 1 ? onPrev : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: onChoose,
                  iconAlignment: IconAlignment.end,
                  label: Text(
                    '第 $week 周${isCurrent ? ' · 本周' : ''}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  icon: const Icon(Icons.expand_more),
                ),
              ),
              IconButton(
                tooltip: '下一周',
                onPressed: week < weekCount ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            minimumSize: const Size(56, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: onToday,
          child: const Text('今天'),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.signedIn,
    required this.loading,
    required this.onAction,
  });
  final bool signedIn;
  final bool loading;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      children: [
        Icon(
          Icons.calendar_month_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          loading ? '正在同步课表' : '登录后查看课表',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          '用统一身份认证登录，课表会保存在本机，'
          '没网也能看。',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: loading ? null : onAction,
          icon: Icon(signedIn ? Icons.sync : Icons.login),
          label: Text(signedIn ? '同步课表' : '登录教务系统'),
        ),
      ],
    ),
  );
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.data, required this.now});
  final TermTimetable data;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(courseColorsProvider);
    final status = DayStatus.of(data, now);
    final current = status.today
        .where((o) => !now.isBefore(o.start) && now.isBefore(o.end))
        .toList();
    final next = status.next;
    final today = schoolDate(now);
    final week = data.weekOf(today);
    final unknownTimes = week == null
        ? <CourseSession>[]
        : data
              .sessionsOn(week, today.weekday)
              .where(
                (s) =>
                    data.period(s.startPeriod) == null ||
                    data.period(s.endPeriod) == null,
              )
              .toList();
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return GlassCard(
      tint: scheme.primary,
      tintAmount: 0.10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今天 · ${dateLabel(today)} · ${kWeekdayNames[today.weekday - 1]}'
            '${week == null ? '' : ' · 第 $week 周'}',
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            current.isNotEmpty
                ? '正在上课'
                : unknownTimes.isNotEmpty
                ? '今天有课缺少上课时间'
                : status.today.isEmpty
                ? '今天没有已排课程'
                : status.remaining == 0
                ? '今天的课程已结束'
                : '接下来',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (current.length > 1) const Text('同一时段有多门课'),
          for (final occurrence in current)
            _TodayCourse(
              data: data,
              occurrence: occurrence,
              label: '进行中',
              color: colors.of(occurrence.session),
            ),
          if (next != null)
            _TodayCourse(
              data: data,
              occurrence: next,
              label: next.date == today ? '接下来' : '${dateLabel(next.date)} 下一课',
              color: colors.of(next.session),
            ),
          if (current.isEmpty && next == null && unknownTimes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('接下来 8 天没有课'),
            ),
          if (unknownTimes.isNotEmpty)
            Text(
              '今天有 ${unknownTimes.length} 门课缺少时间，'
              '以课表节次为准。',
            ),
          if (status.today.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '今天 ${status.today.length} 节课，还剩 ${status.remaining} 节',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayCourse extends StatelessWidget {
  const _TodayCourse({
    required this.data,
    required this.occurrence,
    required this.label,
    required this.color,
  });
  final TermTimetable data;
  final ClassOccurrence occurrence;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showCourseDetails(context, data, [
        occurrence.session,
      ], data.weekOf(occurrence.date) ?? 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label · ${occurrence.session.displayName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${timeLabel(data, occurrence.session, on: occurrence.date)}'
                    '${occurrence.session.room.isEmpty ? '' : ' · ${occurrence.session.room}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

class _TermExtras extends ConsumerWidget {
  const _TermExtras({required this.data});
  final TermTimetable data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(examsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invalid = data.sessions
        .where(
          (s) =>
              s.weekday < 1 ||
              s.weekday > 7 ||
              s.startPeriod < 1 ||
              s.endPeriod < s.startPeriod,
        )
        .toList();
    Widget section(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(padding: EdgeInsets.zero, child: child),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section(
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.assignment_outlined, color: scheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('考试', style: theme.textTheme.titleMedium),
                    ),
                    if (exams.isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                exams.when(
                  loading: () => const Text('正在获取考试安排…'),
                  error: (error, _) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          error is AppError ? error.message : '考试安排获取失败',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(examsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新查询'),
                      ),
                    ],
                  ),
                  data: (entries) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (entries.isEmpty) const Text('暂无考试安排'),
                      for (final exam in entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 3,
                                height: 40,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: scheme.error,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      exam.courseName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      [
                                        if (exam.date.isNotEmpty) exam.date,
                                        if (exam.time.isNotEmpty &&
                                            exam.time != exam.date)
                                          exam.time,
                                        if (exam.room.isNotEmpty) exam.room,
                                        if (exam.seat.isNotEmpty)
                                          '座位 ${exam.seat}',
                                        if (exam.kind.isNotEmpty) exam.kind,
                                      ].join(' · '),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (entries.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '以学校通知为准',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        section(
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.event_busy_outlined),
            title: Text('未排时间课程 · ${data.unscheduled.length}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (data.unscheduled.isEmpty) const Text('没有未排时间的课程'),
              for (final course in data.unscheduled)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(course.name),
                  subtitle: Text(
                    [
                      if (course.code.isNotEmpty) course.code,
                      if (course.teacher.isNotEmpty) course.teacher,
                      if (course.weeksLabel.isNotEmpty)
                        '周次：${course.weeksLabel}',
                      '${course.credit} 学分',
                    ].join(' · '),
                  ),
                ),
              if (invalid.isNotEmpty) ...[
                const Divider(),
                const Text('这些课没有固定上课时间，不在课表格子里：'),
                for (final s in invalid)
                  ListTile(
                    title: Text(s.displayName),
                    subtitle: Text(s.note.isEmpty ? '具体时间以老师通知为准' : s.note),
                    onTap: () => showCourseDetails(context, data, [s], 1),
                  ),
              ],
            ],
          ),
        ),
        section(
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.swap_horiz),
            title: Text('调课记录 · ${data.adjustments.length}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Text('课表已按调课结果更新，这里是调课明细。'),
              if (data.adjustments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('暂无调课'),
                ),
              for (final change in data.adjustments)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        change.courseName,
                        style: theme.textTheme.titleSmall,
                      ),
                      DetailRow('原安排', change.fromLabel),
                      DetailRow('新安排', change.toLabel),
                      DetailRow('申请时间', change.appliedAt),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (data.sessions.any((s) => s.custom))
          section(
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.edit_calendar_outlined),
              title: Text(
                '自定义课程 · ${data.sessions.where((s) => s.custom).length}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (final s in data.sessions.where((s) => s.custom))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.displayName),
                    subtitle: Text(
                      '${weekdayLabel(s.weekday)} ${timeLabel(data, s)} · ${s.weeksLabel}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () =>
                        showCustomCourseEditor(context, data, existing: s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 第一周从哪天开始: shows the Monday of teaching week 1 and lets the user
/// correct it when the school's data is off (e.g. a late start).
class _WeekOneTile extends ConsumerWidget {
  const _WeekOneTile({required this.data});
  final TermTimetable data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(timetableProvider.notifier);
    final server = ctl.serverWeekOne();
    final custom = server != null && server != data.firstMonday;
    final m = data.firstMonday;
    final today = schoolDate(DateTime.now());
    final week = data.weekOf(today);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('第一周'),
      subtitle: Text(
        '${m.month}月${m.day}日（周一）开始'
        '${week == null ? '' : '，今天是第 $week 周'}'
        '${custom ? ' · 已手动调整' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (custom)
            TextButton(
              onPressed: () => ctl.setWeekOne(null),
              child: const Text('恢复'),
            ),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                helpText: '选择第一周内的任意一天',
                initialDate: DateTime(m.year, m.month, m.day),
                firstDate: DateTime(m.year - 1),
                lastDate: DateTime(m.year + 1, 12, 31),
              );
              if (picked == null) return;
              final d = DateTime.utc(picked.year, picked.month, picked.day);
              await ctl.setWeekOne(
                d.subtract(Duration(days: d.weekday - DateTime.monday)),
              );
            },
            child: const Text('调整'),
          ),
        ],
      ),
    );
  }
}
