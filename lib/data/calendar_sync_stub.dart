import 'calendar_sync.dart';

/// Web: there is no device calendar to write to.
CalendarAdapter createDeviceCalendarAdapter() =>
    const UnsupportedCalendarAdapter();

class UnsupportedCalendarAdapter implements CalendarAdapter {
  const UnsupportedCalendarAdapter();
  @override
  bool get supported => false;
  Never _no() => throw const CalendarUnavailable('当前平台不支持系统日历同步');
  @override
  Future<bool> requestAccess() async => false;
  @override
  Future<String> createOrFindCalendar(String name, {String? knownId}) async =>
      _no();
  @override
  Future<List<DeviceEvent>> listEvents(
    String calendarId,
    DateTime fromUtc,
    DateTime toUtc,
  ) async => _no();
  @override
  Future<String> upsert(
    String calendarId,
    CalendarEventData event, {
    String? existingId,
  }) async => _no();
  @override
  Future<void> delete(String eventId) async => _no();
}
