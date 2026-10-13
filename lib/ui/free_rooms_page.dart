/// 空教室: the school's 空闲教室查询, organised around the student's day.
///
/// The top of the page answers "where can I study before/after my class"
/// from the timetable ([suggestRooms]); below it anyone can browse any block
/// of any day with building and name filters.
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
  RoomBlock? _block;
  String? _building;
  final _search = TextEditingController();
  final _rooms = <RoomBlock, List<FreeRoom>>{};
  final _errors = <RoomBlock, AppError>{};
  final _loading = <RoomBlock>{};
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _date = schoolDate(DateTime.now());
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

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    final timetable = ref.watch(timetableProvider).data;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = schoolDate(now);

    final suggestions = timetable == null
        ? const <RoomSuggestion>[]
        : suggestRooms(
            timetable: timetable,
            date: _date,
            classes: timetable.classesOn(_date),
            free: _rooms,
            now: now,
          );
    // Browsing defaults to the block the first suggestion is about, else the
    // current one.
    final browse =
        _block ??
        (suggestions.isNotEmpty ? suggestions.first.block : null) ??
        (_date == today
            ? currentOrNextBlock(
                    _cstMinutes(now),
                    (p) =>
                        timetable?.period(p, on: _date)?.end ??
                        _bell(p, _date)?.end,
                  ) ??
                  kRoomBlocks.last
            : kRoomBlocks.first);

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
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        ((MediaQuery.sizeOf(context).width -
                                    kReadableMaxWidth) /
                                2)
                            .clamp(16.0, double.infinity),
                    vertical: 12,
                  ),
                  children: [
                    _DayStrip(
                      today: today,
                      selected: _date,
                      onSelected: (d) {
                        setState(() {
                          _date = d;
                          _block = null;
                        });
                        _load();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (timetable != null)
                      ..._suggestionSection(context, suggestions),
                    _BrowseHeader(
                      block: browse,
                      loading: _loading,
                      onBlock: (b) => setState(() => _block = b),
                    ),
                    const SizedBox(height: 12),
                    ..._browseList(context, browse),
                  ],
                ),
              ),
      ),
    );
  }

  List<Widget> _suggestionSection(
    BuildContext context,
    List<RoomSuggestion> suggestions,
  ) {
    final theme = Theme.of(context);
    if (suggestions.isEmpty) {
      if (_loading.isNotEmpty) {
        return [
          const _SectionTitle('给你挑的'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
        ];
      }
      return [
        const _SectionTitle('给你挑的'),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            '这天没有课前课后的空档，可以在下面按时间段找',
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
          child: GlassCard(
            onTap: () => setState(() => _block = s.block),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      switch (s.kind) {
                        SuggestionKind.beforeClass => Icons.schedule,
                        SuggestionKind.now => Icons.event_seat_outlined,
                        SuggestionKind.afterClass => Icons.nightlight_outlined,
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
                    Text(_blockTime(s.block), style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(s.reason, style: theme.textTheme.bodyMedium),
                if (s.sameRoom != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${s.sameRoom!.name} 这段时间空着，可以直接在那儿等上课',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (s.rooms.isEmpty)
                  Text('这段时间没有空教室', style: theme.textTheme.bodySmall)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in s.rooms)
                        _RoomChip(
                          room: r,
                          highlight: r == s.sameRoom,
                          onTap: () => _showRoomDay(r.name),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 4),
    ];
  }

  /// One room across the day, like the school's 教室查询: a block where the
  /// room is missing from the free list is taken (a class or an exam).
  void _showRoomDay(String name) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                '${_date.month}月${_date.day}日',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final b in kRoomBlocks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(b.label),
                  subtitle: Text(_blockTime(b)),
                  trailing: switch (_rooms[b]) {
                    null => Text(
                      _errors.containsKey(b) ? '没查到' : '查询中',
                      style: theme.textTheme.bodySmall,
                    ),
                    final free when free.any((r) => r.name == name) =>
                      StatusPill(label: '空闲', color: Colors.green),
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

  String _blockTime(RoomBlock b) {
    final t = ref.read(timetableProvider).data;
    final start = t?.period(b.from, on: _date) ?? _bell(b.from, _date);
    final end = t?.period(b.to, on: _date) ?? _bell(b.to, _date);
    if (start == null || end == null) return '';
    return '${_hm(start.start)}–${_hm(end.end)}';
  }

  List<Widget> _browseList(BuildContext context, RoomBlock block) {
    final theme = Theme.of(context);
    final error = _errors[block];
    final rooms = _rooms[block];
    if (rooms == null) {
      if (error != null) {
        return [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: error.message,
            subtitle: error.hint ?? '下拉重试',
          ),
        ];
      }
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final buildings = {for (final r in rooms) _buildingOf(r)}.toList()..sort();
    final q = _search.text.trim().toUpperCase();
    final shown =
        rooms
            .where((r) => _building == null || _buildingOf(r) == _building)
            .where((r) => q.isEmpty || r.name.toUpperCase().contains(q))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return [
      TextField(
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: '找教室，如 N8 或 6A',
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: const Text('全部'),
                selected: _building == null,
                onSelected: (_) => setState(() => _building = null),
              ),
            ),
            for (final b in buildings)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(b),
                  selected: _building == b,
                  onSelected: (_) =>
                      setState(() => _building = _building == b ? null : b),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty && q.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            onTap: () => _showRoomDay(q),
            child: Text('$q 这段时间不空，点这里看它这天哪些时段空着'),
          ),
        ),
      Text('${shown.length} 间空着', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      for (final r in shown)
        _RoomTile(room: r, onTap: () => _showRoomDay(r.name)),
    ];
  }
}

String _buildingOf(FreeRoom r) => RegExp(r'^[A-Za-z]+\d').hasMatch(r.name)
    ? buildingKey(r.name)
    : (r.building.isEmpty ? '其他' : r.building);

/// The built-in NWAFU bell time of [period] on [date], for when no timetable
/// is cached yet.
ClassPeriod? _bell(int period, DateTime date) =>
    BellSeason.of(date).table.where((p) => p.index == period).firstOrNull;

int _cstMinutes(DateTime instant) {
  final cst = instant.toUtc().add(const Duration(hours: 8));
  return cst.hour * 60 + cst.minute;
}

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
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 7; i++)
            if (today.add(Duration(days: i)) case final d)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    '${switch (i) {
                      0 => '今天',
                      1 => '明天',
                      _ => '周${names[d.weekday - 1]}',
                    }} ${d.month}/${d.day}',
                  ),
                  selected: selected == d,
                  onSelected: (_) => onSelected(d),
                ),
              ),
        ],
      ),
    );
  }
}

class _BrowseHeader extends StatelessWidget {
  const _BrowseHeader({
    required this.block,
    required this.loading,
    required this.onBlock,
  });
  final RoomBlock block;
  final Set<RoomBlock> loading;
  final ValueChanged<RoomBlock> onBlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('按时间段查'),
        SegmentedButton<RoomBlock>(
          showSelectedIcon: false,
          segments: [
            for (final b in kRoomBlocks)
              ButtonSegment(
                value: b,
                label: Text(
                  b.label.replaceAll(' 节', ''),
                  style: loading.contains(b)
                      ? TextStyle(color: Theme.of(context).disabledColor)
                      : null,
                ),
              ),
          ],
          selected: {block},
          onSelectionChanged: (s) => onBlock(s.first),
        ),
      ],
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.room,
    required this.onTap,
    this.highlight = false,
  });
  final FreeRoom room;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: highlight
          ? Icon(Icons.star, size: 16, color: scheme.primary)
          : null,
      label: Text(
        room.seats != null && room.seats! > 0
            ? '${room.name} · ${room.seats}座'
            : room.name,
      ),
      side: highlight ? BorderSide(color: scheme.primary) : null,
      onPressed: onTap,
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});
  final FreeRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: onTap,
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: room.name));
          showToast(context, '已复制 ${room.name}');
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      room.campus,
                      room.building,
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (room.seats != null && room.seats! > 0)
              Text('${room.seats} 座', style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
