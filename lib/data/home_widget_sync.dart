/// Feeds the Android home-screen widget (NextClassWidget.kt): today's and
/// tomorrow's classes with absolute start/end times, so the widget can show
/// the current or next class at each refresh without the app running.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'academic_calendar.dart' show schoolDate;
import 'edu_models.dart';
import 'timetable_logic.dart';

String _hm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// The JSON the widget reads (exposed for tests).
String widgetClassesJson(TermTimetable? t, DateTime now) {
  if (t == null) return '[]';
  final today = schoolDate(now);
  final out = <Map<String, Object>>[];
  for (final (offset, date) in [
    (0, today),
    (1, today.add(const Duration(days: 1))),
  ]) {
    final week = t.weekOf(date);
    if (week == null) continue;
    for (final s in t.sessionsOn(week, date.weekday)) {
      final o = t.occurrence(s, date);
      final first = t.period(s.startPeriod, on: date);
      final last = t.period(s.endPeriod, on: date);
      if (o == null || first == null || last == null) continue;
      out.add({
        'name': s.displayName,
        'room': s.room,
        'time': '${_hm(first.start)}-${_hm(last.end)}',
        'start': o.start.millisecondsSinceEpoch,
        'end': o.end.millisecondsSinceEpoch,
        'tomorrow': offset == 1,
      });
    }
  }
  return jsonEncode(out);
}

Future<void> updateHomeWidget(TermTimetable? t) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await HomeWidget.saveWidgetData<String>(
      'classes',
      widgetClassesJson(t, DateTime.now()),
    );
    await HomeWidget.saveWidgetData<String>(
      'empty',
      t == null ? '登录后显示课表' : '',
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'cn.edu.nwafu.nwafu_bksxk.NextClassWidget',
    );
  } catch (_) {
    // No widget placed, or the launcher refused; nothing to do.
  }
}
