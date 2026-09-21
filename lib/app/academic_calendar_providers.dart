import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/academic_calendar.dart';
import '../data/storage.dart';
import 'providers.dart';

class AcademicCalendarController extends StateNotifier<AcademicCalendar?> {
  AcademicCalendarController(this.storage, this.termKey, AcademicTerm term)
      : super(_load(storage, termKey) ?? AcademicCalendar.reportedFor(term));

  final Storage storage;
  final String termKey;

  static AcademicCalendar? _load(Storage storage, String key) {
    final raw = storage.academicCalendarJson(key);
    if (raw == null) return null;
    try {
      return AcademicCalendar.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(AcademicCalendar calendar) async {
    await storage.setAcademicCalendarJson(
        termKey, jsonEncode(calendar.toJson()));
    if (mounted) state = calendar;
  }
}

/// Origin + actual academic term, shared across rounds and accounts at the
/// same university. If term metadata is absent, isolate the unknown batch.
final academicCalendarProvider = StateNotifierProvider.autoDispose.family<
    AcademicCalendarController,
    AcademicCalendar?,
    ({String origin, String termId})>((ref, scope) {
  return AcademicCalendarController(
    ref.watch(storageProvider),
    jsonEncode([scope.origin, scope.termId]),
    AcademicTerm(id: scope.termId, label: scope.termId),
  );
});

class SchoolDateController extends StateNotifier<DateTime>
    with WidgetsBindingObserver {
  SchoolDateController() : super(schoolDate(DateTime.now())) {
    WidgetsBinding.instance.addObserver(this);
    _update();
  }

  Timer? _timer;

  void _update() {
    _timer?.cancel();
    final now = DateTime.now().toUtc();
    final today = schoolDate(now);
    if (state != today) state = today;
    final nextMidnight = today.add(const Duration(days: 1, hours: -8));
    _timer = Timer(nextMidnight.difference(now), _update);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _update();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final schoolDateProvider =
    StateNotifierProvider.autoDispose<SchoolDateController, DateTime>(
        (ref) => SchoolDateController());
