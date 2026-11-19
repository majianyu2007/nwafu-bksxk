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

/// Adaptive UI scaling preset. [auto] scales gently for very narrow phones,
/// landscape phones, and large desktop monitors without fighting accessibility
/// text settings.
enum UiScaleMode {
  auto('自动'),
  compact('紧凑'),
  standard('标准'),
  comfortable('宽松');

  const UiScaleMode(this.label);
  final String label;
}

class UiPrefs {
  const UiPrefs({
    this.glass = true,
    this.timetableView,
    this.compactTimetable = false,
    this.showTeacher = false,
    this.hideGrades = false,
    this.courseColors = const {},
    this.scaleMode = UiScaleMode.auto,
    this.favoriteLibraryAreas = const {},
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

  /// Responsive UI scale & density preset.
  final UiScaleMode scaleMode;

  /// Pinned favorite library reading area / seminar room IDs.
  final Set<String> favoriteLibraryAreas;

  UiPrefs copyWith({
    bool? glass,
    TimetableViewMode? timetableView,
    bool clearView = false,
    bool? compactTimetable,
    bool? showTeacher,
    bool? hideGrades,
    Map<String, int>? courseColors,
    UiScaleMode? scaleMode,
    Set<String>? favoriteLibraryAreas,
  }) => UiPrefs(
    glass: glass ?? this.glass,
    timetableView: clearView ? null : timetableView ?? this.timetableView,
    compactTimetable: compactTimetable ?? this.compactTimetable,
    showTeacher: showTeacher ?? this.showTeacher,
    hideGrades: hideGrades ?? this.hideGrades,
    courseColors: courseColors ?? this.courseColors,
    scaleMode: scaleMode ?? this.scaleMode,
    favoriteLibraryAreas: favoriteLibraryAreas ?? this.favoriteLibraryAreas,
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
  static const _kScaleMode = 'ui.scale_mode.v1';
  static const _kFavLib = 'ui.lib_fav_areas.v1';

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
    final rawScale = p.getString(_kScaleMode);
    final scaleMode = UiScaleMode.values.firstWhere(
      (m) => m.name == rawScale,
      orElse: () => UiScaleMode.auto,
    );
    final favLib = (p.getStringList(_kFavLib) ?? const <String>[]).toSet();
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
      scaleMode: scaleMode,
      favoriteLibraryAreas: favLib,
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

  Future<void> setTimetableView(TimetableViewMode? v) {
    state = v == null
        ? state.copyWith(clearView: true)
        : state.copyWith(timetableView: v);
    return _save(
      (p) => v == null ? p.remove(_kView) : p.setString(_kView, v.name),
    );
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

  Future<void> setScaleMode(UiScaleMode v) {
    state = state.copyWith(scaleMode: v);
    return _save((p) => p.setString(_kScaleMode, v.name));
  }

  Future<void> toggleFavoriteLibraryArea(String areaId) {
    final next = {...state.favoriteLibraryAreas};
    if (!next.remove(areaId)) next.add(areaId);
    state = state.copyWith(favoriteLibraryAreas: next);
    return _save((p) => p.setStringList(_kFavLib, next.toList()));
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

/// Active UI scale preset (Settings → 外观 → 界面缩放).
final uiScaleModeProvider = Provider<UiScaleMode>(
  (ref) => ref.watch(uiPrefsProvider.select((p) => p.scaleMode)),
);
