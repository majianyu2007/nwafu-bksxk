/// 空闲教室: rooms free on a day for a period range, from the school's
/// 空闲教室查询 app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../core/errors.dart';
import '../data/academic_calendar.dart' show schoolDate;
import '../data/edu_models.dart';
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

class FreeRoomsPage extends ConsumerStatefulWidget {
  const FreeRoomsPage({super.key});

  @override
  ConsumerState<FreeRoomsPage> createState() => _FreeRoomsPageState();
}

/// Common blocks of the bell schedule, in periods.
const _blocks = [
  (label: '1-2 节', from: 1, to: 2),
  (label: '3-4 节', from: 3, to: 4),
  (label: '5-6 节', from: 5, to: 6),
  (label: '7-8 节', from: 7, to: 8),
  (label: '9-11 节', from: 9, to: 11),
  (label: '上午', from: 1, to: 4),
  (label: '下午', from: 5, to: 8),
  (label: '全天', from: 1, to: 11),
];

class _FreeRoomsPageState extends ConsumerState<FreeRoomsPage> {
  late DateTime _date;
  late int _block;
  String? _campus;
  String? _building;
  final _search = TextEditingController();
  List<FreeRoom>? _rooms;
  AppError? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = schoolDate(now);
    final cst = now.toUtc().add(const Duration(hours: 8));
    final minutes = cst.hour * 60 + cst.minute;
    // Default to the block that starts next today.
    _block = minutes < 9 * 60 + 40
        ? 0
        : minutes < 11 * 60 + 50
        ? 1
        : minutes < 15 * 60 + 40
        ? 2
        : minutes < 17 * 60 + 40
        ? 3
        : 4;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final b = _blocks[_block];
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await ref
          .read(eduClientProvider)
          .ehall
          .freeRooms(_date, b.from, b.to);
      if (!mounted || request != _request) return;
      setState(() {
        _rooms = rooms;
        if (_campus != null && !rooms.any((r) => r.campus == _campus)) {
          _campus = null;
        }
        if (_building != null && !rooms.any((r) => r.building == _building)) {
          _building = null;
        }
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(
        () => _error = e is AppError
            ? e
            : AppError(AppErrorKind.unknown, message: '查询失败'),
      );
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(eduSessionProvider).signedIn;
    final theme = Theme.of(context);
    final rooms = _rooms ?? const <FreeRoom>[];
    final campuses = {for (final r in rooms) r.campus}.toList()..sort();
    final inCampus = rooms.where((r) => _campus == null || r.campus == _campus);
    final buildings = {for (final r in inCampus) r.building}.toList()..sort();
    final q = _search.text.trim();
    final shown =
        inCampus
            .where((r) => _building == null || r.building == _building)
            .where((r) => q.isEmpty || r.name.contains(q))
            .toList()
          ..sort((a, b) {
            final c = a.building.compareTo(b.building);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
    final today = schoolDate(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('空教室'),
        backgroundColor: Colors.transparent,
      ),
      body: !signedIn
          ? const Center(child: Text('登录统一身份认证后可查询'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: ((MediaQuery.sizeOf(context).width -
                              kReadableMaxWidth) /
                          2)
                      .clamp(16.0, double.infinity),
                  vertical: 12,
                ),
                children: [
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_dayLabel(today, i)),
                              selected:
                                  _date == today.add(Duration(days: i)),
                              onSelected: (_) {
                                setState(
                                  () => _date = today.add(Duration(days: i)),
                                );
                                _load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _blocks.length; i++)
                        ChoiceChip(
                          label: Text(_blocks[i].label),
                          selected: _block == i,
                          onSelected: (_) {
                            setState(() => _block = i);
                            _load();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (campuses.length > 1) ...[
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _campus,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '校区',
                            ),
                            items: [
                              const DropdownMenuItem(child: Text('全部')),
                              for (final c in campuses)
                                DropdownMenuItem(value: c, child: Text(c)),
                            ],
                            onChanged: (v) => setState(() {
                              _campus = v;
                              _building = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey('b$_campus'),
                          initialValue: _building,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '教学楼'),
                          items: [
                            const DropdownMenuItem(child: Text('全部')),
                            for (final b in buildings)
                              DropdownMenuItem(value: b, child: Text(b)),
                          ],
                          onChanged: (v) => setState(() => _building = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '教室，如 N8',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _error!.message,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_rooms != null && !_loading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${shown.length} 间空闲',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  for (final r in shown) _RoomTile(room: r),
                ],
              ),
            ),
    );
  }

  static String _dayLabel(DateTime today, int offset) {
    final d = today.add(Duration(days: offset));
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final prefix = switch (offset) {
      0 => '今天',
      1 => '明天',
      _ => '周${names[d.weekday - 1]}',
    };
    return '$prefix ${d.month}/${d.day}';
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});
  final FreeRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    [room.campus, room.building]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
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
