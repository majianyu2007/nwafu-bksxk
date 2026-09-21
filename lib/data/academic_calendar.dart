import 'models.dart';

/// Calendar dates are represented as UTC midnights, not instants. This keeps
/// week arithmetic independent of the device's timezone and daylight saving.
DateTime calendarDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

DateTime teachingMonday(DateTime date) {
  final day = calendarDate(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// The university uses China Standard Time even on devices outside China.
DateTime schoolDate(DateTime instant) =>
    calendarDate(instant.toUtc().add(const Duration(hours: 8)));

class AcademicTerm {
  const AcademicTerm({required this.id, required this.label});

  final String id;
  final String label;

  factory AcademicTerm.fromBatch(ElectiveBatch batch) {
    final code = batch.raw['schoolTerm']?.toString().trim() ?? '';
    final label = batch.schoolTermName;
    return AcademicTerm(
      id: _normaliseTerm(code) ??
          _normaliseTerm(label) ??
          (code.isNotEmpty ? 'term:$code' : 'batch:${batch.code}'),
      label: label.isNotEmpty ? label : (code.isNotEmpty ? code : batch.name),
    );
  }

  static String? _normaliseTerm(String value) {
    final code = RegExp(r'^(\d{4})[-/](\d{4})[-/]([12])$').firstMatch(value);
    if (code != null) return '${code[1]}-${code[2]}-${code[3]}';
    final name =
        RegExp(r'(\d{4})\s*[-—–/]\s*(\d{4})\s*学年\s*([秋春])').firstMatch(value);
    if (name == null) return null;
    return '${name[1]}-${name[2]}-${name[3] == '秋' ? 1 : 2}';
  }
}

enum CalendarSource { reported, manual }

class AcademicCalendar {
  AcademicCalendar({
    required DateTime firstMonday,
    required this.weekCount,
    required this.source,
  }) : firstMonday = calendarDate(firstMonday) {
    if (this.firstMonday.weekday != DateTime.monday) {
      throw ArgumentError.value(firstMonday, 'firstMonday', '必须是周一');
    }
    if (weekCount < 1 || weekCount > 53) {
      throw ArgumentError.value(weekCount, 'weekCount', '须在 1–53 周之间');
    }
  }

  final DateTime firstMonday;
  final int weekCount;
  final CalendarSource source;

  /// This is a dated user report, NOT an official calendar. It is deliberately
  /// restricted to its term; later terms require their own calibration.
  static AcademicCalendar? reportedFor(AcademicTerm term) {
    if (term.id != '2026-2027-1') return null;
    return AcademicCalendar.fromWeek(
      date: DateTime.utc(2026, 9, 21),
      week: 3,
      weekCount: 20,
      source: CalendarSource.reported,
    );
  }

  factory AcademicCalendar.fromWeek({
    required DateTime date,
    required int week,
    required int weekCount,
    CalendarSource source = CalendarSource.manual,
  }) {
    if (week < 1 || week > weekCount) {
      throw ArgumentError.value(week, 'week', '须在学期周数范围内');
    }
    return AcademicCalendar(
      firstMonday:
          teachingMonday(date).subtract(Duration(days: (week - 1) * 7)),
      weekCount: weekCount,
      source: source,
    );
  }

  DateTime mondayOf(int week) =>
      firstMonday.add(Duration(days: (week - 1) * 7));

  /// Null before teaching begins and after the configured final Sunday. Never
  /// label a clamped first/last week as the current teaching week.
  int? weekOn(DateTime date) {
    final elapsed = calendarDate(date).difference(firstMonday).inDays;
    if (elapsed < 0 || elapsed >= weekCount * 7) return null;
    return elapsed ~/ 7 + 1;
  }

  bool hasNotStarted(DateTime date) => calendarDate(date).isBefore(firstMonday);

  int browsingWeekOn(DateTime date) =>
      weekOn(date) ?? (hasNotStarted(date) ? 1 : weekCount);

  String get sourceLabel => switch (source) {
        CalendarSource.reported => '用户反馈校准：2026-09-21 为第 3 周；非官方校历，暂按 20 周，可调整',
        CalendarSource.manual => '本机手动校准 · 按日期自动推进',
      };

  Map<String, dynamic> toJson() => {
        'firstMonday': firstMonday.toIso8601String(),
        'weekCount': weekCount,
        'source': source.name,
      };

  factory AcademicCalendar.fromJson(Map<String, dynamic> json) =>
      AcademicCalendar(
        firstMonday: DateTime.parse(json['firstMonday'] as String),
        weekCount: json['weekCount'] as int,
        source: CalendarSource.values.byName(json['source'] as String),
      );
}
