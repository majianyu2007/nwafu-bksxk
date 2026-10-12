import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/ui/root_shell.dart';

void main() {
  test('notification payloads route to their tab', () {
    expect(notificationDestinationIndex('timetable'), 0);
    expect(notificationDestinationIndex('selected'), 1);
    expect(notificationDestinationIndex('monitor'), 2);
    expect(notificationDestinationIndex('grades'), 3);
    expect(notificationDestinationIndex(null), 0);
    expect(notificationDestinationIndex('unknown'), 0);
  });
}
