/// 空教室 suggestions built from the student's own timetable.
///
/// The bell schedule splits the day into blocks (1-2, 3-4, 5-6, 7-8, 9-11).
/// The school reports, per block, which rooms are free. From that and the
/// day's classes this file finds the student's **free stretches** (runs of
/// blocks without a class) and, for each, ranks study rooms:
///
///  1. the next class's own room, when it is free for the whole stretch
///     (study there, no walking: the "早十有课，早八先去那间" case);
///  2. rooms free for the whole stretch before rooms free for part of it;
///  3. the same building as the class next to the stretch, then the same
///     campus, then the rest;
///  4. ordinary classrooms of a normal size before huge halls.
///
/// Sports grounds, rehearsal and lecture halls, labs and computer rooms are
/// listed by the school as "free" but are not study rooms; they are left out
/// of suggestions (the browse list still shows them).
library;

import 'edu_models.dart';
import 'timetable_logic.dart';

/// The day's blocks, by period.
class RoomBlock {
  const RoomBlock(this.label, this.from, this.to);
  final String label;
  final int from;
  final int to;

  bool covers(int period) => period >= from && period <= to;

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
/// → (building, campus). Built from every block's list, so a room that is
/// free at any time of the day is known.
class RoomDirectory {
  RoomDirectory(Iterable<List<FreeRoom>> lists) {
    for (final list in lists) {
      for (final r in list) {
        _rooms.putIfAbsent(r.name, () => r);
      }
    }
  }

  final _rooms = <String, FreeRoom>{};

  /// The building of [room] (a timetable room name). Rooms never free today
  /// are matched by prefix: `N8618` → a room starting with `N8`,
  /// `理科楼A402` → a room starting with `理科楼`.
  String? buildingOf(String room) {
    final known = _rooms[room];
    if (known != null) return known.building;
    final prefix = _prefix(room);
    if (prefix == null) return null;
    for (final r in _rooms.values) {
      if (r.name.startsWith(prefix)) return r.building;
    }
    return null;
  }

  String? campusOf(String room) {
    final known = _rooms[room];
    if (known != null) return known.campus;
    final building = buildingOf(room);
    if (building == null) return null;
    for (final r in _rooms.values) {
      if (r.building == building) return r.campus;
    }
    return null;
  }

  static String? _prefix(String room) {
    final code = RegExp(r'^([A-Za-z]+\d)').firstMatch(room);
    if (code != null) return code.group(1)!.toUpperCase();
    final base = room.replaceFirst(RegExp(r'[A-Za-z]?\d.*$'), '');
    return base.length >= 2 ? base : null;
  }
}

/// Short building key used by the browse filter: `N8618` → `N8`, else the
/// school's building label.
String buildingKey(String room) {
  final m = RegExp(r'^([A-Za-z]+\d)').firstMatch(room.trim());
  return m?.group(1)?.toUpperCase() ?? room.trim();
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

  RoomBlock get block => blocks.first;
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
  int limit = 6,
}) {
  final minutes = _cstMinutes(now);
  final today = _sameDay(now, date);
  final sessions = [for (final o in classes) o.session]
    ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  final dir = RoomDirectory(free.values);

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
    // A long morning before the first class or evening after the last one
    // is not one study session: keep the two blocks next to the class.
    var stretch = run;
    if (prev == null && stretch.length > 2) {
      stretch = stretch.sublist(stretch.length - 2);
    }
    if (next == null && stretch.length > 2) stretch = stretch.sublist(0, 2);
    stretch = [
      for (final b in stretch)
        if (!past(b) && free.containsKey(b)) b,
    ];
    if (stretch.isEmpty) continue;

    final anchor = next ?? prev!;
    final kind = prev == null
        ? SuggestionKind.beforeClass
        : next == null
        ? SuggestionKind.afterClass
        : SuggestionKind.between;
    final ranked = _rank(
      stretch,
      free,
      dir,
      anchorRoom: anchor.room.isEmpty ? null : anchor.room,
    );
    final same = next == null || next.room.isEmpty
        ? null
        : ranked
              .where(
                (r) =>
                    r.room.name == next.room &&
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
        reason: anchor.room.isEmpty
            ? '${next == null ? '上' : '下'}一节是${anchor.displayName}'
            : next != null
            ? '${periods(next)}在 ${next.room} 上${next.displayName}'
            : '${periods(anchor)}在 ${anchor.room}，附近的排在前面',
        rooms: ranked.take(limit).toList(),
        sameRoom: same,
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
          reason: home == null ? '这天没有课' : '这天没有课，$home 的排在前面',
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
  final campus = anchorRoom == null ? null : dir.campusOf(anchorRoom);
  final byName = <String, RankedRoom>{};
  for (final b in stretch) {
    for (final r in free[b]!) {
      if (!isStudyRoom(r) && r.name != anchorRoom) continue;
      final seen = byName[r.name];
      byName[r.name] = RankedRoom(r, [...?seen?.freeIn, b]);
    }
  }
  // The class's own room leads only when it is free for the whole stretch;
  // otherwise it is just another room in that building.
  int place(RankedRoom r) {
    if (anchorRoom != null &&
        r.room.name == anchorRoom &&
        r.freeIn.length == stretch.length) {
      return 0;
    }
    if (building != null && r.room.building == building) return 1;
    if (campus != null && r.room.campus == campus) return 2;
    return 3;
  }

  // 40–150 seats is an ordinary classroom; very small or huge rooms last.
  int size(FreeRoom r) {
    final s = r.seats ?? 60;
    return s >= 40 && s <= 150 ? 0 : 1;
  }

  // Own room, then free for the whole stretch, then nearness, then size.
  return byName.values.toList()..sort((a, b) {
    for (final c in [
      (place(a) == 0 ? 0 : 1).compareTo(place(b) == 0 ? 0 : 1),
      b.freeIn.length.compareTo(a.freeIn.length),
      place(a).compareTo(place(b)),
      size(a.room).compareTo(size(b.room)),
    ]) {
      if (c != 0) return c;
    }
    return a.room.name.compareTo(b.room.name);
  });
}

String _stretchLabel(List<RoomBlock> s) =>
    s.length == 1 ? s.first.label : '${s.first.from}-${s.last.to} 节';

/// The building the student has most classes in (by school building), or
/// null when it cannot be told.
String? homeBuilding(
  TermTimetable timetable,
  Map<RoomBlock, List<FreeRoom>> free,
) {
  final dir = RoomDirectory(free.values);
  final counts = <String, int>{};
  for (final s in timetable.sessions) {
    if (s.room.isEmpty) continue;
    final b = dir.buildingOf(s.room);
    if (b != null) counts[b] = (counts[b] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
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
  final cst = now.toUtc().add(const Duration(hours: 8));
  return cst.year == date.year &&
      cst.month == date.month &&
      cst.day == date.day;
}
