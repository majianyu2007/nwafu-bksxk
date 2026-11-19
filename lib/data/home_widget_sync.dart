/// Feeds the home-screen widgets (Android: ClassWidgetSmall 1×1,
/// NextClassWidget 2×1, ClassWidgetToday 2×2; iOS: the WidgetKit extension
/// in ios/ClassWidget). Both read one JSON document under [kWidgetDataKey]
/// with a week of dated classes (absolute start/end instants), so each
/// widget picks the current/next class at every redraw without the app
/// running. On iOS the data lives in the App Group [kWidgetAppGroup]; when
/// that group is not provisioned (some self-signed builds) the write lands
/// in the app's own defaults and the widget shows its "open the app" hint.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'academic_calendar.dart' show schoolDate;
import 'edu_models.dart';
import 'timetable_logic.dart';

/// The single key both platforms read.
const kWidgetDataKey = 'widget';

/// Must match the App Group in ios/Runner/Runner.entitlements and
/// ios/ClassWidget/ClassWidget.entitlements, and `ClassWidget.swift`.
const kWidgetAppGroup = 'group.cn.edu.nwafu.nwafuBksxk';

/// WidgetKit kind of the iOS widget (`ClassWidget.swift`).
const kIosWidgetKind = 'ClassWidget';

/// Android providers, all redrawn on every data change.
const kAndroidWidgetProviders = [
  'cn.edu.nwafu.nwafu_bksxk.NextClassWidget',
  'cn.edu.nwafu.nwafu_bksxk.ClassWidgetSmall',
  'cn.edu.nwafu.nwafu_bksxk.ClassWidgetToday',
];

/// How many school days ahead the document covers, so the widgets stay
/// right for a week even if neither the app nor the background task runs.
const kWidgetDays = 7;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The widget document (exposed for tests). Shape (`v` 2):
///
/// ```json
/// {"v":2,"updated":<ms>,"message":"","term":"2026-27 秋",
///  "days":[{"date":"2026-10-13","week":6,"weekday":2,
///           "classes":[{"name":"高等数学","room":"N8618","teacher":"王强",
///                       "time":"08:00-09:35","sec":"1-2节",
///                       "start":<ms>,"end":<ms>}]}]}
/// ```
///
/// `date` is the China-Standard-Time calendar day; `week` is null outside
/// the term; `start`/`end` are epoch milliseconds. `message` is non-empty
/// when there is nothing to show (signed out).
Map<String, Object?> widgetPayload(
  TermTimetable? t,
  DateTime now, {
  int days = kWidgetDays,
}) {
  final out = <String, Object?>{
    'v': 2,
    'updated': now.millisecondsSinceEpoch,
    'message': t == null ? '登录后显示课表' : '',
    'term': t?.term.shortName ?? '',
  };
  final list = <Map<String, Object?>>[];
  if (t != null) {
    final today = schoolDate(now);
    for (var offset = 0; offset < days; offset++) {
      final date = today.add(Duration(days: offset));
      final week = t.weekOf(date);
      final classes = <Map<String, Object>>[];
      if (week != null) {
        for (final s in t.sessionsOn(week, date.weekday)) {
          final first = t.period(s.startPeriod, on: date);
          final last = t.period(s.endPeriod, on: date);
          if (first == null || last == null) continue;
          final start = schoolInstant(date, first.start);
          final end = schoolInstant(date, last.end);
          classes.add({
            'name': s.displayName,
            'room': s.room,
            'teacher': s.teacher,
            'time': '${first.startLabel}-${last.endLabel}',
            'sec': s.startPeriod == s.endPeriod
                ? '${s.startPeriod}节'
                : '${s.startPeriod}-${s.endPeriod}节',
            'start': start.millisecondsSinceEpoch,
            'end': end.millisecondsSinceEpoch,
          });
        }
      }
      list.add({
        'date': _ymd(date),
        'week': week,
        'weekday': date.weekday,
        'classes': classes,
      });
    }
  }
  out['days'] = list;
  return out;
}

String widgetPayloadJson(TermTimetable? t, DateTime now) =>
    jsonEncode(widgetPayload(t, now));

bool get _widgetPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<void> _widgetUpdateQueue = Future<void>.value();
int _widgetUpdateGen = 0;

/// Writes the widget document and asks every widget to redraw. Serialized so a
/// rapid term switch cannot overwrite newer data with an older write. Safe to
/// call from the background isolate; never throws.
Future<void> updateHomeWidget(TermTimetable? t) {
  if (!_widgetPlatform) return Future.value();
  final gen = ++_widgetUpdateGen;
  final next = _widgetUpdateQueue.then((_) async {
    if (gen != _widgetUpdateGen) return;
    await _writeHomeWidget(t);
  });
  _widgetUpdateQueue = next.catchError((Object _) {});
  return next;
}

Future<void> _writeHomeWidget(TermTimetable? t) async {
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  if (ios) {
    try {
      await HomeWidget.setAppGroupId(kWidgetAppGroup);
    } catch (_) {
      // No App Group on this build: the widget cannot see our data.
      return;
    }
  }
  try {
    await HomeWidget.saveWidgetData<String>(
      kWidgetDataKey,
      widgetPayloadJson(t, DateTime.now()),
    );
  } catch (_) {
    return;
  }
  if (ios) {
    try {
      await HomeWidget.updateWidget(iOSName: kIosWidgetKind);
    } catch (_) {}
    return;
  }
  for (final name in kAndroidWidgetProviders) {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    } catch (_) {
      // No widget of this size placed, or the launcher refused.
    }
  }
}
