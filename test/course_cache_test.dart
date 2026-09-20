// The course cache round-trips rows through gzip+base64 in SharedPreferences
// and forgets entries older than its max age.
import 'package:nwafu_bksxk/data/course_cache.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  test('rows round-trip and carry their age and total', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = CourseCache(Storage(await SharedPreferences.getInstance()));
    final key = CourseCache.key(accountId: 'A', batchCode: 'B', kind: 'XGXK');
    expect(cache.read(key), isNull);
    await cache.write(key, [
      {'teachingClassID': 'T1', 'courseName': '食品标准与法规', 'x': null},
    ], totalCount: 362);
    final got = cache.read(key)!;
    expect(got.rows.single['courseName'], '食品标准与法规');
    expect(got.totalCount, 362);
    expect(got.age.inSeconds, lessThan(5));
  });

  test('stale entries are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = Storage(await SharedPreferences.getInstance());
    final cache = CourseCache(storage, maxAge: Duration.zero);
    final key = CourseCache.key(accountId: 'A', batchCode: 'B', kind: 'FANKC', page: 2);
    await cache.write(key, const [{'courseNumber': '1'}]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(cache.read(key), isNull);
    await cache.clear();
    expect(storage.cacheGet(key), isNull);
  });
}
