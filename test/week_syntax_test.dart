import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/week_syntax.dart';

List<int> range(int a, int b, [int step = 1]) => [
  for (var i = a; i <= b; i += step) i,
];

void main() {
  test('parses the school\'s week expressions', () {
    expect(parseWeeks('1-16周'), range(1, 16));
    expect(parseWeeks('1-16周(单)'), range(1, 15, 2));
    expect(parseWeeks('1-16周（单）'), range(1, 15, 2));
    expect(parseWeeks('2-16双周'), range(2, 16, 2));
    expect(parseWeeks('1-16单周'), range(1, 15, 2));
    expect(parseWeeks('1,3,5周'), [1, 3, 5]);
    expect(parseWeeks('1，3、5'), [1, 3, 5]);
    expect(parseWeeks('1-8,10-16周'), [...range(1, 8), ...range(10, 16)]);
    expect(parseWeeks('18周'), [18]);
    expect(parseWeeks('第3周'), [3]);
    expect(parseWeeks(' 1 - 4 周 '), range(1, 4));
    expect(parseWeeks('1~4周'), range(1, 4));
  });

  test('a trailing filter applies to the whole list only when 周 is once', () {
    expect(parseWeeks('1-8,10-16周(双)'), [2, 4, 6, 8, 10, 12, 14, 16]);
    expect(parseWeeks('1-4周,9-12周(单)'), [1, 2, 3, 4, 9, 11]);
    expect(parseWeeks('1-4单,6-8双周'), [1, 3, 6, 8]);
  });

  test('rejects garbage and out-of-range weeks', () {
    for (final bad in ['', '周', 'abc', '5-3周', '0周', '1-99周', '2-2单周']) {
      expect(() => parseWeeks(bad), throwsFormatException, reason: bad);
      expect(tryParseWeeks(bad), isNull, reason: bad);
    }
  });

  test('formats compactly', () {
    expect(formatWeeks(range(1, 16)), '1-16周');
    expect(formatWeeks(range(1, 15, 2)), '1-15周(单)');
    expect(formatWeeks(range(2, 16, 2)), '2-16周(双)');
    expect(formatWeeks([1, 3]), '1,3周');
    expect(formatWeeks([...range(1, 8), ...range(10, 16)]), '1-8,10-16周');
    expect(formatWeeks([18]), '18周');
    expect(formatWeeks([3, 1, 2, 2]), '1-3周');
    expect(formatWeeks(const []), '');
  });

  test('format and parse round-trip', () {
    for (final w in [
      range(1, 16),
      range(1, 15, 2),
      range(2, 18, 2),
      [1, 3, 5, 9],
      [...range(1, 8), ...range(10, 16)],
      [18],
      [1, 2, 5, 7, 9],
    ]) {
      expect(parseWeeks(formatWeeks(w)), w, reason: formatWeeks(w));
    }
  });
}
