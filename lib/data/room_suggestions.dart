/// 空教室 suggestions built from the student's own timetable: which free
/// rooms are worth showing first, for the gaps that matter today.
///
/// The bell schedule splits the day into blocks (1-2, 3-4, 5-6, 7-8, 9-11).
/// For each block the school reports which rooms are free; this file turns
/// that plus today's classes into a few ordered sections:
///
///  * 课前自习 — a free block right before a class: rooms in the class's own
///    building first, and the class's own room if it is free (study there,
///    no walking).
///  * 现在 — the current or next block, for "I want a seat right now".
///  * 课后 — a free block right after a class, near where it ended.
///
/// Everything is local; the network work is one query per block.
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

/// Building name from a room like `N8618` → `N8`, or the school's building
/// label when the room code does not follow the `<letter><digit>` pattern.
String buildingKey(String room) {
  final m = RegExp(r'^([A-Za-z]+\d)').firstMatch(room.trim());
  return m?.group(1)?.toUpperCase() ?? room.trim();
}

String _roomKey(FreeRoom r) =>
    RegExp(r'^[A-Za-z]+\d').hasMatch(r.name) ? buildingKey(r.name) : r.building;

enum SuggestionKind { beforeClass, now, afterClass }

class RoomSuggestion {
  const RoomSuggestion({
    required this.kind,
    required this.block,
    required this.title,
    required this.reason,
    required this.rooms,
    this.sameRoom,
  });
  final SuggestionKind kind;
  final RoomBlock block;
  final String title;

  /// Why this section exists, e.g. `第 3-4 节在 N8618 上 Java`.
  final String reason;

  /// Ranked rooms (best first).
  final List<FreeRoom> rooms;

  /// The classroom of the next class itself, when it is free in [block].
  final FreeRoom? sameRoom;
}

/// Ranks [free] for someone heading to [anchor] (a room code): the same room,
/// then the same building, then the same campus area, larger rooms first.
List<FreeRoom> rankRooms(List<FreeRoom> free, {String? anchor}) {
  final key = anchor == null ? null : buildingKey(anchor);
  int score(FreeRoom r) {
    if (anchor != null && r.name == anchor) return 0;
    if (key != null && _roomKey(r) == key) return 1;
    // Same letter = same side of campus (N = 北校区 teaching blocks).
    if (key != null &&
        key.isNotEmpty &&
        r.name.isNotEmpty &&
        r.name[0].toUpperCase() == key[0]) {
      return 2;
    }
    return 3;
  }

  return [...free]..sort((a, b) {
    final s = score(a).compareTo(score(b));
    if (s != 0) return s;
    final seats = (b.seats ?? 0).compareTo(a.seats ?? 0);
    return seats != 0 ? seats : a.name.compareTo(b.name);
  });
}

/// The block containing or following [minutes] (CST) on a day whose bell
/// times come from [periodStart]/[periodEnd]; null after the last block.
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

/// Builds today's suggestions. [classes] are today's occurrences (from
/// [TermTimetable.classesOn]); [free] maps each block to its free rooms
/// (blocks not loaded yet are simply absent). [now] decides what is past.
List<RoomSuggestion> suggestRooms({
  required TermTimetable timetable,
  required DateTime date,
  required List<ClassOccurrence> classes,
  required Map<RoomBlock, List<FreeRoom>> free,
  required DateTime now,
  int limit = 8,
}) {
  final minutes = _cstMinutes(now);
  int? end(int p) => timetable.period(p, on: date)?.end;
  int? start(int p) => timetable.period(p, on: date)?.start;
  final today = _sameDay(now, date);

  bool busy(RoomBlock b) => classes.any(
    (o) => o.session.startPeriod <= b.to && o.session.endPeriod >= b.from,
  );
  bool past(RoomBlock b) {
    if (!today) return false;
    final e = end(b.to);
    return e != null && minutes >= e;
  }

  final out = <RoomSuggestion>[];
  final used = <RoomBlock>{};
  // Sports grounds and halls show up as "free rooms" but nobody studies there.
  List<FreeRoom> study(RoomBlock b) =>
      free[b]!.where((r) => !_notForStudy.hasMatch(r.name)).toList();
  String periods(CourseSession s) => s.startPeriod == s.endPeriod
      ? '第 ${s.startPeriod} 节'
      : '第 ${s.startPeriod}-${s.endPeriod} 节';

  // 课前自习: each free block directly before a class.
  for (var i = 0; i < kRoomBlocks.length - 1; i++) {
    final gap = kRoomBlocks[i];
    final next = kRoomBlocks[i + 1];
    if (busy(gap) || past(gap) || !free.containsKey(gap)) continue;
    final cls = classes
        .where((o) => next.covers(o.session.startPeriod))
        .map((o) => o.session)
        .firstOrNull;
    if (cls == null) continue;
    final rooms = study(gap);
    final same = rooms.where((r) => r.name == cls.room).firstOrNull;
    out.add(
      RoomSuggestion(
        kind: SuggestionKind.beforeClass,
        block: gap,
        title: '${gap.label}课前自习',
        reason: cls.room.isEmpty
            ? '下一节是${cls.displayName}'
            : '${periods(cls)}在 ${cls.room} 上${cls.displayName}',
        rooms: rankRooms(
          rooms,
          anchor: cls.room.isEmpty ? null : cls.room,
        ).take(limit).toList(),
        sameRoom: same,
      ),
    );
    used.add(gap);
  }

  // 现在: the block in progress or next, if free for the student.
  if (today) {
    final b = currentOrNextBlock(minutes, end);
    if (b != null && !used.contains(b) && !busy(b) && free.containsKey(b)) {
      final s = start(b.from);
      final previous = classes
          .where((o) => o.session.endPeriod < b.from)
          .map((o) => o.session)
          .lastOrNull;
      out.add(
        RoomSuggestion(
          kind: SuggestionKind.now,
          block: b,
          title: s != null && minutes >= s ? '现在有空的教室' : '${b.label}有空的教室',
          reason: previous == null || previous.room.isEmpty
              ? '这段时间你没课'
              : '离上一节 ${previous.room} 近的排在前面',
          rooms: rankRooms(
            study(b),
            anchor: previous?.room,
          ).take(limit).toList(),
        ),
      );
      used.add(b);
    }
  }

  // 课后: a free block right after a class, near where that class was.
  for (var i = 1; i < kRoomBlocks.length; i++) {
    final gap = kRoomBlocks[i];
    if (used.contains(gap) ||
        busy(gap) ||
        past(gap) ||
        !free.containsKey(gap)) {
      continue;
    }
    final prev = classes
        .map((o) => o.session)
        .where((s) => kRoomBlocks[i - 1].covers(s.endPeriod))
        .lastOrNull;
    if (prev == null) continue;
    out.add(
      RoomSuggestion(
        kind: SuggestionKind.afterClass,
        block: gap,
        title: '${gap.label}课后自习',
        reason: prev.room.isEmpty
            ? '${periods(prev)}是${prev.displayName}'
            : '${periods(prev)}在 ${prev.room}，附近的排在前面',
        rooms: rankRooms(
          study(gap),
          anchor: prev.room.isEmpty ? null : prev.room,
        ).take(limit).toList(),
      ),
    );
    used.add(gap);
  }
  return out;
}

final _notForStudy = RegExp(r'场|馆|操室|游泳|舞蹈');

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
