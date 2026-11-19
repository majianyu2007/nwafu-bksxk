/// 空教室 suggestions built from the student's own timetable.
///
/// The bell schedule splits the day into blocks (1-2, 3-4, 5-6, 7-8, 9-11).
/// The school reports, per block, which rooms are free. From that and the
/// day's classes this file finds the student's **free stretches** (runs of
/// blocks without a class) and, for each, ranks study rooms:
///
///  1. the next class's own room, when it is free for the whole stretch
///     (stay there, no walking: the "早十有课，早八先去那间" case);
///  2. other rooms **in the same building** as that class, free for the whole
///     stretch first, ordinary-sized classrooms before huge halls.
///
/// Rooms in other buildings are never suggested: whether a walk is worth it
/// is the student's call (some do not want to change buildings at all), and
/// the school gives no map to judge distance. When the building has nothing
/// free the suggestion says so and the list below is there to browse.
///
/// Sports grounds, rehearsal and lecture halls, labs and computer rooms are
/// listed by the school as "free" but are not study rooms; they are left out
/// of suggestions (the browse list still shows them).
library;

import 'academic_calendar.dart' show schoolDate;
import 'edu_models.dart';
import 'timetable_logic.dart';

final _roomCodeRe = RegExp(r'^([A-Za-z]+\d)');
final _roomTailRe = RegExp(r'[A-Za-z]?\d.*$');

/// The day's blocks, by period.
class RoomBlock {
  const RoomBlock(this.label, this.from, this.to);
  final String label;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is RoomBlock && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

const kRoomBlocks = [
  RoomBlock('1-2 节', 1, 2),
  RoomBlock('3-4 节', 3, 4),
  RoomBlock('5-6 节', 5, 6),
  RoomBlock('7-8 节', 7, 8),
  RoomBlock('9-11 节', 9, 11),
];

/// Where each free room is, from the school's own building field: room name
/// → building. Built from every block's list, so a room that is free at any
/// time of the day is known.
class RoomDirectory {
  RoomDirectory(Iterable<List<FreeRoom>> lists) {
    for (final list in lists) {
      for (final r in list) {
        if (_rooms.containsKey(r.name)) continue;
        _rooms[r.name] = r;
        final p = _prefix(r.name);
        if (p != null) {
          _byPrefix.putIfAbsent(p.toUpperCase(), () => r.building);
        }
      }
    }
  }

  final _rooms = <String, FreeRoom>{};
  final _byPrefix = <String, String?>{};

  /// The building of [room] (a timetable room name). Rooms never free today
  /// are matched by prefix: `N8618` → a room starting with `N8`,
  /// `理科楼A402` → a room starting with `理科楼`.
  String? buildingOf(String room) {
    final trimmed = room.trim();
    if (trimmed.isEmpty) return null;
    final known = _rooms[trimmed];
    if (known != null) return known.building;
    final prefix = _prefix(trimmed);
    if (prefix == null) return null;
    final upper = prefix.toUpperCase();
    if (_byPrefix.containsKey(upper)) return _byPrefix[upper];
    for (final r in _rooms.values) {
      if (r.name.toUpperCase().startsWith(upper)) {
        return _byPrefix[upper] = r.building;
      }
    }
    return _byPrefix[upper] = null;
  }

  static String? _prefix(String room) {
    final trimmed = room.trim();
    final code = _roomCodeRe.firstMatch(trimmed);
    if (code != null) return code.group(1)!.toUpperCase();
    final base = trimmed.replaceFirst(_roomTailRe, '');
    return base.length >= 2 ? base : null;
  }
}

/// Computes how many consecutive blocks starting at [startBlock] a room is
/// continuously free for (returns `(count, lastBlock)`).
({int count, RoomBlock? lastBlock}) consecutiveFreeRun(
  String roomName,
  RoomBlock startBlock,
  Map<RoomBlock, Set<String>> freeNamesByBlock,
) {
  final idx = kRoomBlocks.indexOf(startBlock);
  if (idx < 0) return (count: 0, lastBlock: null);
  var count = 0;
  RoomBlock? last;
  for (var i = idx; i < kRoomBlocks.length; i++) {
    final b = kRoomBlocks[i];
    if (freeNamesByBlock[b]?.contains(roomName) == true) {
      count++;
      last = b;
    } else {
      break;
    }
  }
  return (count: count, lastBlock: last);
}

/// Short building key used by the browse filter: `N8618` → `N8`, else the
/// school's building label.
String buildingKey(String room) {
  final trimmed = room.trim();
  final m = _roomCodeRe.firstMatch(trimmed);
  return m?.group(1)?.toUpperCase() ?? trimmed;
}

final _notStudyBuilding = RegExp(r'体育|活动中心|博览园|曹新庄|实验动物|解剖|图书馆|学生处');
final _notStudyRoom = RegExp(r'场|馆|排练|报告厅|实验室|机房|画室|琴房|舞蹈');

/// Whether a free room is a sensible place to sit and study.
bool isStudyRoom(FreeRoom r) =>
    !_notStudyBuilding.hasMatch(r.building) &&
    !_notStudyRoom.hasMatch(r.name) &&
    (r.seats == null || (r.seats! >= 20 && r.seats! <= 260));

enum SuggestionKind { beforeClass, between, afterClass, freeDay }

/// A room and the blocks of the stretch it is free in.
class RankedRoom {
  const RankedRoom(this.room, this.freeIn);
  final FreeRoom room;
  final List<RoomBlock> freeIn;
}

class RoomSuggestion {
  const RoomSuggestion({
    required this.kind,
    required this.blocks,
    required this.title,
    required this.reason,
    required this.rooms,
    this.sameRoom,
    this.anchorRoom,
    this.building,
  });
  final SuggestionKind kind;

  /// The free stretch, in order.
  final List<RoomBlock> blocks;
  final String title;

  /// Why this section exists, e.g. `第 3-4 节在 N8618 上 Java`.
  final String reason;

  /// Ranked rooms (best first).
  final List<RankedRoom> rooms;

  /// The next class's own room, when it is free for the whole stretch.
  final FreeRoom? sameRoom;

  /// The room of the class this stretch is about, e.g. `N8618`.
  final String? anchorRoom;

  /// The school building of [anchorRoom], when known.
  final String? building;
}

/// Builds the day's suggestions. [classes] are the day's occurrences;
/// [free] maps each loaded block to its free rooms. [now] decides what is
/// past. [home] is the building the student has most classes in, used on a
/// day without classes.
List<RoomSuggestion> suggestRooms({
  required TermTimetable timetable,
  required DateTime date,
  required List<ClassOccurrence> classes,
  required Map<RoomBlock, List<FreeRoom>> free,
  required DateTime now,
  String? home,
  RoomDirectory? directory,
  int limit = 6,
}) {
  final minutes = _cstMinutes(now);
  final today = _sameDay(now, date);
  final sessions = [for (final o in classes) o.session]
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  final dir = directory ?? RoomDirectory(free.values);

  bool busy(RoomBlock b) =>
      sessions.any((s) => s.startPeriod <= b.to && s.endPeriod >= b.from);
  bool past(RoomBlock b) {
    if (!today) return false;
    final e = timetable.period(b.to, on: date)?.end;
    return e != null && minutes >= e;
  }

  // Runs of consecutive blocks without a class.
  final runs = <List<RoomBlock>>[];
  for (final b in kRoomBlocks) {
    if (busy(b)) {
      runs.add([]);
    } else {
      if (runs.isEmpty) runs.add([]);
      runs.last.add(b);
    }
  }

  String periods(CourseSession s) => s.startPeriod == s.endPeriod
      ? '第 ${s.startPeriod} 节'
      : '第 ${s.startPeriod}-${s.endPeriod} 节';

  final out = <RoomSuggestion>[];
  for (final run in runs.where((r) => r.isNotEmpty)) {
    final prev = sessions.where((s) => s.endPeriod < run.first.from).lastOrNull;
    final next = sessions.where((s) => s.startPeriod > run.last.to).firstOrNull;
    if (prev == null && next == null) continue;
    // Split on past/unloaded holes into contiguous sub-runs so a missing middle
    // block is never mislabelled as one continuous stretch.
    final subRuns = <List<RoomBlock>>[];
    for (final b in run) {
      if (!past(b) && free.containsKey(b)) {
        if (subRuns.isEmpty) subRuns.add([]);
        subRuns.last.add(b);
      } else if (subRuns.isNotEmpty && subRuns.last.isNotEmpty) {
        subRuns.add([]);
      }
    }
    final activeSubs = subRuns.where((s) => s.isNotEmpty).toList();
    if (activeSubs.isEmpty) continue;
    // Pick the sub-run closest to the anchor class (last for beforeClass,
    // first for afterClass, longest/first for between).
    var stretch = prev == null ? activeSubs.last : activeSubs.first;
    // A long morning before the first class or evening after the last one
    // is not one study session: keep the two blocks closest to the class/now.
    if (prev == null && stretch.length > 2) {
      stretch = stretch.sublist(stretch.length - 2);
    }
    if (next == null && stretch.length > 2) stretch = stretch.sublist(0, 2);

    final anchor = next ?? prev!;
    final anchorRoom = anchor.room.trim();
    final nextRoom = next?.room.trim() ?? '';
    final kind = prev == null
        ? SuggestionKind.beforeClass
        : next == null
        ? SuggestionKind.afterClass
        : SuggestionKind.between;
    final ranked = _rank(
      stretch,
      free,
      dir,
      anchorRoom: anchorRoom.isEmpty ? null : anchorRoom,
    );
    final same = next == null || nextRoom.isEmpty
        ? null
        : ranked
              .where(
                (r) =>
                    r.room.name == nextRoom &&
                    r.freeIn.length == stretch.length,
              )
              .firstOrNull
              ?.room;
    final label = _stretchLabel(stretch);
    out.add(
      RoomSuggestion(
        kind: kind,
        blocks: stretch,
        title: switch (kind) {
          SuggestionKind.beforeClass => '$label 课前',
          SuggestionKind.between => '$label 空档',
          _ => '$label 课后',
        },
        reason: anchorRoom.isEmpty
            ? '${next == null ? '上' : '下'}一节是${anchor.displayName}'
            : '${periods(anchor)} ${anchor.displayName}',
        rooms: ranked.take(limit).toList(),
        sameRoom: same,
        anchorRoom: anchorRoom.isEmpty ? null : anchorRoom,
        building: anchorRoom.isEmpty ? null : dir.buildingOf(anchorRoom),
      ),
    );
  }

  // A day without classes: the current or next block, near where the
  // student usually has class.
  if (sessions.isEmpty) {
    final b = kRoomBlocks
        .where((b) => !past(b) && free.containsKey(b))
        .firstOrNull;
    if (b != null) {
      out.add(
        RoomSuggestion(
          kind: SuggestionKind.freeDay,
          blocks: [b],
          title: '${b.label} 没课',
          reason: home == null ? '这天没有课' : '这天没有课，看看常去的$home',
          building: home,
          rooms: _rank(
            [b],
            free,
            dir,
            anchorBuilding: home,
          ).take(limit).toList(),
        ),
      );
    }
  }
  return out;
}

List<RankedRoom> _rank(
  List<RoomBlock> stretch,
  Map<RoomBlock, List<FreeRoom>> free,
  RoomDirectory dir, {
  String? anchorRoom,
  String? anchorBuilding,
}) {
  final building =
      anchorBuilding ??
      (anchorRoom == null ? null : dir.buildingOf(anchorRoom));
  if (anchorRoom == null && building == null) return const [];
  final byName = <String, (FreeRoom, List<RoomBlock>)>{};
  for (final b in stretch) {
    for (final r in free[b]!) {
      final isAnchor = r.name == anchorRoom;
      if (!isAnchor && (building == null || r.building != building)) continue;
      if (!isAnchor && !isStudyRoom(r)) continue;
      final entry = byName[r.name];
      if (entry == null) {
        byName[r.name] = (r, [b]);
      } else {
        entry.$2.add(b);
      }
    }
  }
  final near = [for (final e in byName.values) RankedRoom(e.$1, e.$2)];

  // 40–150 seats is an ordinary classroom; very small or huge rooms last.
  int size(FreeRoom r) {
    final s = r.seats ?? 60;
    return s >= 40 && s <= 150 ? 0 : 1;
  }

  // The class's own room leads when free for the whole stretch; then rooms
  // free for longer, then ordinary sizes.
  bool own(RankedRoom r) =>
      r.room.name == anchorRoom && r.freeIn.length == stretch.length;
  return near..sort((a, b) {
    final c0 = (own(a) ? 0 : 1).compareTo(own(b) ? 0 : 1);
    if (c0 != 0) return c0;
    final c1 = b.freeIn.length.compareTo(a.freeIn.length);
    if (c1 != 0) return c1;
    final c2 = size(a.room).compareTo(size(b.room));
    if (c2 != 0) return c2;
    return a.room.name.compareTo(b.room.name);
  });
}

String _stretchLabel(List<RoomBlock> s) =>
    s.length == 1 ? s.first.label : '${s.first.from}-${s.last.to} 节';

/// The building the student has most classes in (by school building), or
/// null when it cannot be told.
String? homeBuilding(
  TermTimetable timetable,
  Map<RoomBlock, List<FreeRoom>> free, {
  RoomDirectory? directory,
}) {
  final dir = directory ?? RoomDirectory(free.values);
  final counts = <String, int>{};
  for (final s in timetable.sessions) {
    if (s.room.isEmpty) continue;
    final b = dir.buildingOf(s.room);
    if (b != null) counts[b] = (counts[b] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  String? best;
  var bestCount = 0;
  counts.forEach((k, v) {
    if (v > bestCount) {
      best = k;
      bestCount = v;
    }
  });
  return best;
}

/// The block containing or following [minutes] (CST), given each period's
/// end; null after the last block.
RoomBlock? currentOrNextBlock(
  int minutes,
  int? Function(int period) periodEnd,
) {
  for (final b in kRoomBlocks) {
    final end = periodEnd(b.to);
    if (end != null && minutes < end) return b;
  }
  return null;
}

int _cstMinutes(DateTime instant) {
  final cst = instant.toUtc().add(const Duration(hours: 8));
  return cst.hour * 60 + cst.minute;
}

bool _sameDay(DateTime now, DateTime date) {
  final cst = schoolDate(now);
  return cst.year == date.year &&
      cst.month == date.month &&
      cst.day == date.day;
}
