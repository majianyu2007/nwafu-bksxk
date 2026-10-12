/// Presentation-only preferences (glass effect, timetable view, per-course
/// colours, hidden grades). Kept out of `Storage` on purpose: they never
/// affect data, so they live in their own SharedPreferences keys.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The opened SharedPreferences. `main()` overrides it so the first frame
/// already has the saved values; without an override (widget tests) the
/// controller loads them asynchronously.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

enum TimetableViewMode { day, week }

class UiPrefs {
  const UiPrefs({
    this.glass = true,
    this.timetableView,
    this.compactTimetable = false,
    this.showTeacher = false,
    this.hideGrades = false,
    this.courseColors = const {},
  });

  /// Translucent "liquid glass" chrome. Off = solid surfaces, no blur.
  final bool glass;

  /// Null = automatic (day view below 600 dp, week grid otherwise).
  final TimetableViewMode? timetableView;
  final bool compactTimetable;
  final bool showTeacher;
  final bool hideGrades;

  /// `account|courseKey` → ARGB colour chosen by the user.
  final Map<String, int> courseColors;

  UiPrefs copyWith({
    bool? glass,
    TimetableViewMode? timetableView,
    bool clearView = false,
    bool? compactTimetable,
    bool? showTeacher,
    bool? hideGrades,
    Map<String, int>? courseColors,
  }) => UiPrefs(
    glass: glass ?? this.glass,
    timetableView: clearView ? null : timetableView ?? this.timetableView,
    compactTimetable: compactTimetable ?? this.compactTimetable,
    showTeacher: showTeacher ?? this.showTeacher,
    hideGrades: hideGrades ?? this.hideGrades,
    courseColors: courseColors ?? this.courseColors,
  );
}

class UiPrefsController extends StateNotifier<UiPrefs> {
  UiPrefsController(SharedPreferences? prefs)
    : _prefs = prefs,
      super(prefs == null ? const UiPrefs() : _read(prefs)) {
    if (prefs == null) {
      unawaited(
        SharedPreferences.getInstance().then((p) {
          _prefs = p;
          if (mounted) state = _read(p);
        }, onError: (_) {}),
      );
    }
  }

  SharedPreferences? _prefs;

  static const _kGlass = 'ui.glass.v1';
  static const _kView = 'ui.timetable_view.v1';
  static const _kCompact = 'ui.timetable_compact.v1';
  static const _kTeacher = 'ui.timetable_teacher.v1';
  static const _kHideGrades = 'ui.hide_grades.v1';
  static const _kColors = 'ui.course_colors.v1';

  static UiPrefs _read(SharedPreferences p) {
    var colors = const <String, int>{};
    try {
      final raw = p.getString(_kColors);
      if (raw != null) {
        colors = {
          for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
            if (e.value is int) e.key: e.value as int,
        };
      }
    } catch (_) {}
    return UiPrefs(
      glass: p.getBool(_kGlass) ?? true,
      timetableView: switch (p.getString(_kView)) {
        'day' => TimetableViewMode.day,
        'week' => TimetableViewMode.week,
        _ => null,
      },
      compactTimetable: p.getBool(_kCompact) ?? false,
      showTeacher: p.getBool(_kTeacher) ?? false,
      hideGrades: p.getBool(_kHideGrades) ?? false,
      courseColors: colors,
    );
  }

  Future<void> _save(Future<bool> Function(SharedPreferences p) write) async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    _prefs = p;
    await write(p);
  }

  Future<void> setGlass(bool v) {
    state = state.copyWith(glass: v);
    return _save((p) => p.setBool(_kGlass, v));
  }

  Future<void> setTimetableView(TimetableViewMode v) {
    state = state.copyWith(timetableView: v);
    return _save((p) => p.setString(_kView, v.name));
  }

  Future<void> setCompactTimetable(bool v) {
    state = state.copyWith(compactTimetable: v);
    return _save((p) => p.setBool(_kCompact, v));
  }

  Future<void> setShowTeacher(bool v) {
    state = state.copyWith(showTeacher: v);
    return _save((p) => p.setBool(_kTeacher, v));
  }

  Future<void> setHideGrades(bool v) {
    state = state.copyWith(hideGrades: v);
    return _save((p) => p.setBool(_kHideGrades, v));
  }

  /// Sets (or with null clears) the colour of a course for one account.
  Future<void> setCourseColor(String account, String courseKey, int? argb) {
    final key = courseColorKey(account, courseKey);
    final next = {...state.courseColors};
    argb == null ? next.remove(key) : next[key] = argb;
    state = state.copyWith(courseColors: next);
    return _save((p) => p.setString(_kColors, jsonEncode(next)));
  }
}

String courseColorKey(String account, String courseKey) =>
    '$account|$courseKey';

final uiPrefsProvider = StateNotifierProvider<UiPrefsController, UiPrefs>(
  (ref) => UiPrefsController(ref.watch(sharedPreferencesProvider)),
);

/// Whether the glass effect is on (Settings → 外观 → 玻璃效果).
final glassEnabledProvider = Provider<bool>(
  (ref) => ref.watch(uiPrefsProvider.select((p) => p.glass)),
);
