/// [CalendarAdapter] over device_calendar_plus (Android Calendar Provider,
/// iOS EventKit). Windows, Linux and macOS have no implementation in that
/// plugin and report unsupported.
library;

import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart';

import 'calendar_sync.dart';
import 'calendar_sync_stub.dart';

CalendarAdapter createDeviceCalendarAdapter() =>
    Platform.isAndroid || Platform.isIOS
    ? DevicePlusCalendarAdapter()
    : const UnsupportedCalendarAdapter();

class DevicePlusCalendarAdapter implements CalendarAdapter {
  DevicePlusCalendarAdapter([DeviceCalendar? plugin])
    : _p = plugin ?? DeviceCalendar.instance;
  final DeviceCalendar _p;

  @override
  bool get supported => true;

  @override
  Future<bool> requestAccess() async {
    try {
      final s = await _p.requestPermissions();
      return s == CalendarPermissionStatus.granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> createOrFindCalendar(String name, {String? knownId}) async {
    final all = await _p.listCalendars();
    if (knownId != null) {
      for (final c in all) {
        if (c.id == knownId && !c.readOnly) return c.id;
      }
    }
    for (final c in all) {
      if (c.name == name && !c.readOnly) return c.id;
    }
    return _p.createCalendar(name: name, colorHex: '#2E7D32');
  }

  @override
  Future<List<DeviceEvent>> listEvents(
    String calendarId,
    DateTime fromUtc,
    DateTime toUtc,
  ) async {
    final events = await _p.listEvents(
      fromUtc.toLocal(),
      toUtc.toLocal(),
      calendarIds: [calendarId],
    );
    return [
      for (final e in events)
        if (!e.isRecurring)
          DeviceEvent(
            id: e.instanceId,
            title: e.title,
            start: e.startDate.toUtc(),
            end: e.endDate.toUtc(),
            location: e.location ?? '',
            description: e.description ?? '',
            url: e.url ?? '',
            alarmMinutes: [
              for (final r in e.reminders ?? const <Duration>[]) r.inMinutes,
            ],
          ),
    ];
  }

  @override
  Future<String> upsert(
    String calendarId,
    CalendarEventData event, {
    String? existingId,
  }) async {
    final reminders = event.alarmMinutes == null
        ? null
        : [Duration(minutes: event.alarmMinutes!)];
    if (existingId != null) {
      await _p.updateEvent(
        instanceId: existingId,
        title: event.title,
        startDate: event.start.toLocal(),
        endDate: event.end.toLocal(),
        description: Patch.set(event.fullDescription),
        location: event.location.isEmpty
            ? const Patch.clear()
            : Patch.set(event.location),
        url: Patch.set(event.url),
        reminders: reminders == null
            ? const Patch.clear()
            : Patch.set(reminders),
      );
      return existingId;
    }
    return _p.createEvent(
      calendarId: calendarId,
      title: event.title,
      startDate: event.start.toLocal(),
      endDate: event.end.toLocal(),
      description: event.fullDescription,
      location: event.location.isEmpty ? null : event.location,
      url: event.url,
      reminders: reminders,
    );
  }

  @override
  Future<void> delete(String eventId) => _p.deleteEvent(instanceId: eventId);
}
