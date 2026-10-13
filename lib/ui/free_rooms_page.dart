/// 空教室: the school's 空闲教室查询, organised around the student's day.
///
/// Top: 给你挑的, rooms for the free stretches between, before and after
/// today's classes ([suggestRooms]). Below: every free room of the day,
/// grouped by building, each with a strip showing which blocks it is free in
/// (like the official 教室查询's time tabs), filterable by time and name.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../core/errors.dart';
import '../data/academic_calendar.dart' show schoolDate;
import '../data/edu_models.dart';
import '../data/room_suggestions.dart';
import '../data/timetable_logic.dart';
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

/// Results per (account, day, block), kept for the app session: the school
/// answers each query in ~4 s with every room, and free rooms do not change
/// within minutes.
final _cache = <String, ({DateTime at, Future<List<FreeRoom>> rooms})>{};
const _cacheFor = Duration(minutes: 15);

class FreeRoomsPage extends ConsumerStatefulWidget {
  const FreeRoomsPage({super.key});

  @override
  ConsumerState<FreeRoomsPage> createState() => _FreeRoomsPageState();
}

class _FreeRoomsPageState extends ConsumerState<FreeRoomsPage> {
  late DateTime _date;

  /// Blocks a room must be free in to be listed (empty = any).
  final _need = <RoomBlock>{};
  String? _building;
  bool _studyOnly = true;
  final _search = TextEditingController();
  final _rooms = <RoomBlock, List<FreeRoom>>{};
  final _errors = <RoomBlock, AppError>{};
  final _loading = <RoomBlock>{};
  final _open = <String>{};
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _date = schoolDate(ref.read(clockProvider).value ?? DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _key(RoomBlock b) {
    final account = ref.read(eduSessionProvider).account?.username ?? '';
    return '$account|${_date.toIso8601String()}|${b.from}-${b.to}';
  }

  /// Queries every block of [_date] at once; each fills in as it arrives.
  Future<void> _load({bool force = false}) async {
    final request = ++_request;
    setState(() {
      _rooms.clear();
      _errors.clear();
      _loading
        ..clear()
        ..addAll(kRoomBlocks);
    });
    final ehall = ref.read(eduClientProvider).ehall;
    await Future.wait([
      for (final b in kRoomBlocks)
        () async {
          final key = _key(b);
          final hit = _cache[key];
          final fresh =
              !force &&
              hit != null &&
              DateTime.now().difference(hit.at) < _cacheFor;
          final future = fresh
              ? hit.rooms
              : ehall.freeRooms(_date, b.from, b.to);
          if (!fresh) _cache[key] = (at: DateTime.now(), rooms: future);
          try {
            final rooms = await future;
            if (!mounted || request != _request) return;
            setState(() => _rooms[b] = rooms);
          } catch (e) {
            _cache.remove(key);
            if (!mounted || request != _request) return;
            setState(
              () => _errors[b] = e is AppError
                  ? e
                  : AppError(AppErrorKind.unknown, message: '查询失败'),
            );
          } finally {
            if (mounted && request == _request) {
              setState(() => _loading.remove(b));
            }
          }
        }(),
    ]);
  }

  /// Which loaded blocks [name] is free in.
  Set<RoomBlock> _freeBlocks(String name) => {
    for (final e in _rooms.entries)
      if (e.value.any((r) => r.name == name)) e.key,
  };

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    final timetable = ref.watch(timetableProvider).data;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = schoolDate(now);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = ((width - kReadableMaxWidth) / 2).clamp(12.0, 1e9);

    final suggestions = timetable == null
        ? const <RoomSuggestion>[]
        : suggestRooms(
            timetable: timetable,
            date: _date,
            classes: timetable.classesOn(_date),
            free: _rooms,
            now: now,
            home: homeBuilding(timetable, _rooms),
          );

    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('空教室'),
          backgroundColor: Colors.transparent,
        ),
        body: !signedIn
            ? const Center(child: Text('登录统一身份认证后可查询'))
            : RefreshIndicator(
                onRefresh: () => _load(force: true),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 32),
                  children: [
                    _DayStrip(
                      today: today,
                      selected: _date,
                      onSelected: (d) {
                        setState(() => _date = d);
                        _load();
                      },
                    ),
                    const SizedBox(height: 14),
                    if (timetable != null)
                      ..._suggestionSection(context, suggestions),
                    ..._browse(context, timetable),
                  ],
                ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 给你挑的
  // ---------------------------------------------------------------------------

  List<Widget> _suggestionSection(
    BuildContext context,
    List<RoomSuggestion> suggestions,
  ) {
    final theme = Theme.of(context);
    if (suggestions.isEmpty) {
      if (_loading.isNotEmpty) {
        return const [
          _SectionTitle('给你挑的'),
          Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
            child: LinearProgressIndicator(),
          ),
        ];
      }
      return [
        const _SectionTitle('给你挑的'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
          child: Text(
            '这天课排得满，没有能去自习的空档。下面可以按时间段找。',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ];
    }
    return [
      const _SectionTitle('给你挑的'),
      for (final s in suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SuggestionCard(
            suggestion: s,
            time: _stretchTime(s.blocks),
            freeBlocks: _freeBlocks,
            onRoom: _showRoomDay,
          ),
        ),
      const SizedBox(height: 6),
    ];
  }

  String _stretchTime(List<RoomBlock> blocks) {
    final t = ref.read(timetableProvider).data;
    final start =
        t?.period(blocks.first.from, on: _date) ??
        _bell(blocks.first.from, _date);
    final end =
        t?.period(blocks.last.to, on: _date) ?? _bell(blocks.last.to, _date);
    if (start == null || end == null) return '';
    return '${_hm(start.start)}–${_hm(end.end)}';
  }

  // ---------------------------------------------------------------------------
  // 全部空教室
  // ---------------------------------------------------------------------------

  List<Widget> _browse(BuildContext context, TermTimetable? timetable) {
    final theme = Theme.of(context);
    final loaded = _rooms.isNotEmpty;
    // Every room free in at least one block, once.
    final all = <String, FreeRoom>{};
    for (final list in _rooms.values) {
      for (final r in list) {
        all.putIfAbsent(r.name, () => r);
      }
    }
    final q = _search.text.trim().toUpperCase();
    final shown =
        all.values
            .where((r) => !_studyOnly || isStudyRoom(r))
            .where((r) => _building == null || r.building == _building)
            .where((r) => q.isEmpty || r.name.toUpperCase().contains(q))
            .where((r) => _freeBlocks(r.name).containsAll(_need))
            .toList()
          ..sort((a, b) {
            final f = _freeBlocks(
              b.name,
            ).length.compareTo(_freeBlocks(a.name).length);
            return f != 0 ? f : a.name.compareTo(b.name);
          });
    final groups = <String, List<FreeRoom>>{};
    for (final r in shown) {
      (groups[r.building.isEmpty ? '其他' : r.building] ??= []).add(r);
    }
    final buildings = {
      for (final r in all.values)
        if (!_studyOnly || isStudyRoom(r)) r.building,
    }.where((b) => b.isNotEmpty).toList()..sort();

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: _SectionTitle('全部空教室')),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Text(
              '右侧五格 = 1-2 至 9-11 节，绿色为空',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      _TimeFilter(
        need: _need,
        loading: _loading,
        timeOf: (b) => _stretchTime([b]),
        onChanged: (b) =>
            setState(() => _need.contains(b) ? _need.remove(b) : _need.add(b)),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '教室名，如 N8 或 理科楼',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          _BuildingButton(
            buildings: buildings,
            selected: _building,
            onSelected: (b) => setState(() => _building = b),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                !loaded
                    ? '正在查询…'
                    : _need.isEmpty
                    ? '${shown.length} 间这天有空'
                    : '${shown.length} 间在所选时段都空着',
                style: theme.textTheme.bodySmall,
              ),
            ),
            FilterChip(
              label: const Text('只看普通教室'),
              selected: _studyOnly,
              visualDensity: VisualDensity.compact,
              onSelected: (v) => setState(() => _studyOnly = v),
            ),
          ],
        ),
      ),
      if (_errors.length == kRoomBlocks.length)
        EmptyState(
          icon: Icons.cloud_off_outlined,
          title: _errors.values.first.message,
          subtitle: _errors.values.first.hint ?? '下拉重试',
        )
      else if (!loaded)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        for (final e in groups.entries)
          _BuildingGroup(
            building: e.key,
            rooms: e.value,
            open:
                _open.contains(e.key) ||
                q.isNotEmpty ||
                _building != null ||
                groups.length == 1,
            onToggle: () => setState(
              () => _open.contains(e.key)
                  ? _open.remove(e.key)
                  : _open.add(e.key),
            ),
            freeBlocks: _freeBlocks,
            onRoom: _showRoomDay,
          ),
    ];
  }

  /// One room across the day, like the school's 教室查询: a block where the
  /// room is missing from the free list is taken (a class or an exam).
  void _showRoomDay(String name) {
    final theme = Theme.of(context);
    final room = [
      for (final l in _rooms.values) ...l,
    ].where((r) => r.name == name).firstOrNull;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: name));
                      showToast(context, '已复制 $name');
                    },
                  ),
                ],
              ),
              Text(
                [
                  '${_date.month}月${_date.day}日',
                  if (room != null) ...[
                    room.campus,
                    room.building,
                    if ((room.seats ?? 0) > 0) '${room.seats} 座',
                  ],
                ].where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final b in kRoomBlocks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(b.label),
                  subtitle: Text(_stretchTime([b])),
                  trailing: switch (_rooms[b]) {
                    null => Text(
                      _errors.containsKey(b) ? '没查到' : '查询中',
                      style: theme.textTheme.bodySmall,
                    ),
                    final free when free.any((r) => r.name == name) =>
                      const StatusPill(label: '空闲', color: Colors.green),
                    _ => StatusPill(
                      label: '占用',
                      color: theme.colorScheme.error,
                    ),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The built-in NWAFU bell time of [period] on [date], for when no timetable
/// is cached yet.
ClassPeriod? _bell(int period, DateTime date) =>
    BellSeason.of(date).table.where((p) => p.index == period).firstOrNull;

String _hm(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.today,
    required this.selected,
    required this.onSelected,
  });
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            if (today.add(Duration(days: i)) case final d)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: selected == d
                        ? scheme.primary
                        : scheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(d),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            switch (i) {
                              0 => '今天',
                              1 => '明天',
                              _ => '周${names[d.weekday - 1]}',
                            },
                            style: TextStyle(
                              fontSize: 11.5,
                              color: selected == d
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected == d ? scheme.onPrimary : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Five dots for 1-2 … 9-11: filled where the room is free.
class _FreeStrip extends StatelessWidget {
  const _FreeStrip({required this.free, this.highlight = const {}});
  final Set<RoomBlock> free;
  final Set<RoomBlock> highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in kRoomBlocks)
          Container(
            width: 14,
            height: 6,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: free.contains(b)
                  ? (highlight.contains(b)
                        ? scheme.primary
                        : Colors.green.withValues(alpha: 0.75))
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({
    required this.room,
    required this.free,
    required this.onTap,
    this.highlight = const {},
    this.star = false,
    this.showBuilding = true,
  });
  final FreeRoom room;
  final Set<RoomBlock> free;
  final Set<RoomBlock> highlight;
  final VoidCallback onTap;
  final bool star;
  final bool showBuilding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = [
      if (showBuilding) room.building,
      if ((room.seats ?? 0) > 0) '${room.seats} 座',
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: room.name));
        showToast(context, '已复制 ${room.name}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            if (star) ...[
              Icon(
                Icons.star_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _FreeStrip(free: free, highlight: highlight),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.time,
    required this.freeBlocks,
    required this.onRoom,
  });
  final RoomSuggestion suggestion;
  final String time;
  final Set<RoomBlock> Function(String) freeBlocks;
  final ValueChanged<String> onRoom;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final theme = Theme.of(context);
    final rooms = _more ? s.rooms : s.rooms.take(3).toList();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (s.kind) {
                  SuggestionKind.beforeClass => Icons.wb_twilight_outlined,
                  SuggestionKind.between => Icons.coffee_outlined,
                  SuggestionKind.afterClass => Icons.nightlight_outlined,
                  SuggestionKind.freeDay => Icons.event_seat_outlined,
                },
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(widget.time, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          Text(s.reason, style: theme.textTheme.bodySmall),
          if (s.sameRoom != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${s.sameRoom!.name} 这段时间空着，可以直接去那儿等上课',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 4),
          if (s.rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('这段时间没有空教室', style: theme.textTheme.bodySmall),
            )
          else
            for (final r in rooms)
              _RoomRow(
                room: r.room,
                free: widget.freeBlocks(r.room.name),
                highlight: s.blocks.toSet(),
                star: r.room == s.sameRoom,
                onTap: () => widget.onRoom(r.room.name),
              ),
          if (s.rooms.length > 3)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _more = !_more),
                child: Text(_more ? '收起' : '再看 ${s.rooms.length - 3} 间'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeFilter extends StatelessWidget {
  const _TimeFilter({
    required this.need,
    required this.loading,
    required this.timeOf,
    required this.onChanged,
  });
  final Set<RoomBlock> need;
  final Set<RoomBlock> loading;
  final String Function(RoomBlock) timeOf;
  final ValueChanged<RoomBlock> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final b in kRoomBlocks)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: need.contains(b)
                    ? scheme.primaryContainer
                    : scheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onChanged(b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Text(
                          b.label.replaceAll(' 节', ''),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: loading.contains(b)
                                ? Theme.of(context).disabledColor
                                : need.contains(b)
                                ? scheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                        FittedBox(
                          child: Text(
                            timeOf(b).split('–').first,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BuildingButton extends StatelessWidget {
  const _BuildingButton({
    required this.buildings,
    required this.selected,
    required this.onSelected,
  });
  final List<String> buildings;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '选教学楼',
      onSelected: (v) => onSelected(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('全部教学楼')),
        for (final b in buildings) PopupMenuItem(value: b, child: Text(b)),
      ],
      child: Chip(
        avatar: const Icon(Icons.apartment_outlined, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(
            selected ?? '教学楼',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _BuildingGroup extends StatelessWidget {
  const _BuildingGroup({
    required this.building,
    required this.rooms,
    required this.open,
    required this.onToggle,
    required this.freeBlocks,
    required this.onRoom,
  });
  final String building;
  final List<FreeRoom> rooms;
  final bool open;
  final VoidCallback onToggle;
  final Set<RoomBlock> Function(String) freeBlocks;
  final ValueChanged<String> onRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        building,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text('${rooms.length} 间', style: theme.textTheme.bodySmall),
                    Icon(open ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (open)
              for (final r in rooms)
                _RoomRow(
                  room: r,
                  free: freeBlocks(r.name),
                  showBuilding: false,
                  onTap: () => onRoom(r.name),
                ),
          ],
        ),
      ),
    );
  }
}
