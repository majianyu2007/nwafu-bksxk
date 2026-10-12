/// Chinese teaching-week expressions, as the school writes them and as the
/// custom-course editor accepts them: `1-16周`, `1-16周(单)`, `2-16双周`,
/// `1,3,5周`, `1-8,10-16周`, `18周`.
library;

/// Parses [text] into ascending, de-duplicated 1-based weeks. Throws
/// [FormatException] on anything it cannot read, so the editor can show an
/// error instead of saving an empty course.
///
/// Accepted: comma lists (`,` `，` `、`) of `N` or `N-M` (`-` `–` `—` `~`
/// `～` `至`), each optionally followed by `周`, and an odd/even filter
/// written as `单`/`双`, `单周`/`双周`, `(单)`/`（双）` either per range or once
/// at the end (`1-16周(单)` filters the whole list). A leading `第` is
/// allowed.
List<int> parseWeeks(String text, {int maxWeek = 60}) {
  var s = text.replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty) throw const FormatException('周次为空');
  s = s
      .replaceAll(RegExp('[，、;；]'), ',')
      .replaceAll(RegExp('[–—~～至]'), '-')
      .replaceAll('（', '(')
      .replaceAll('）', ')');

  // A trailing filter after the last 周 applies to every part.
  String? globalParity;
  final tail = RegExp(r'周\(?([单双])\)?$').firstMatch(s);
  // Only when 周 appears once (`1-8,10-16周(单)`); in `1-8周,10-16周(单)`
  // the filter belongs to its own part.
  if (tail != null && s.indexOf('周') == tail.start) {
    globalParity = tail[1];
    s = '${s.substring(0, tail.start)}周';
  }

  final part = RegExp(
    r'^第?(\d+)(?:-(\d+))?(?:\(?([单双])\)?)?周?(?:\(?([单双])\)?)?$',
  );
  final out = <int>{};
  for (final raw in s.split(',')) {
    if (raw.isEmpty) continue;
    final m = part.firstMatch(raw);
    if (m == null) throw FormatException('无法识别的周次：$raw');
    final a = int.parse(m[1]!);
    final b = m[2] == null ? a : int.parse(m[2]!);
    if (a < 1 || b < a || b > maxWeek) {
      throw FormatException('周次超出范围：$raw');
    }
    final parity = m[3] ?? m[4] ?? globalParity;
    for (var w = a; w <= b; w++) {
      if (parity == '单' && w.isEven) continue;
      if (parity == '双' && w.isOdd) continue;
      out.add(w);
    }
  }
  if (out.isEmpty) throw FormatException('没有有效的周次：$text');
  return out.toList()..sort();
}

/// [parseWeeks] that returns null instead of throwing.
List<int>? tryParseWeeks(String text, {int maxWeek = 60}) {
  try {
    return parseWeeks(text, maxWeek: maxWeek);
  } on FormatException {
    return null;
  }
}

/// Compact label for [weeks]: `1-16周`, `1-15周(单)`, `2-16周(双)`,
/// `1-8,10-16周`, `18周`. A list that is exactly every odd (or even) week
/// over a span of three or more weeks gets the (单)/(双) form; anything else
/// becomes consecutive runs. Empty input gives an empty string.
String formatWeeks(List<int> weeks) {
  final w = weeks.toSet().toList()..sort();
  if (w.isEmpty) return '';
  if (w.length >= 3) {
    var stepTwo = true;
    for (var i = 1; i < w.length; i++) {
      if (w[i] - w[i - 1] != 2) {
        stepTwo = false;
        break;
      }
    }
    if (stepTwo) return '${w.first}-${w.last}周(${w.first.isOdd ? '单' : '双'})';
  }
  final runs = <String>[];
  var start = w.first;
  var prev = w.first;
  for (final x in w.skip(1)) {
    if (x == prev + 1) {
      prev = x;
      continue;
    }
    runs.add(start == prev ? '$start' : '$start-$prev');
    start = prev = x;
  }
  runs.add(start == prev ? '$start' : '$start-$prev');
  return '${runs.join(',')}周';
}
