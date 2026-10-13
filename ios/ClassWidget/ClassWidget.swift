import SwiftUI
import WidgetKit

// Home-screen timetable widget. Reads the JSON document the app writes
// (lib/data/home_widget_sync.dart, key "widget") from the shared App Group.
// When the group is not provisioned (some self-signed builds) or the app
// has not synced yet, it shows "打开 App 同步课表" instead of failing.
//
// Families: systemSmall = 1×1 next class, systemMedium = next class in detail
// with a countdown plus the two after it, systemLarge = today's list.

private let appGroup = "group.cn.edu.nwafu.nwafuBksxk"
private let dataKey = "widget"
private let syncHint = "打开 App 同步课表"

private let cst: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

// MARK: - Model

struct WidgetClass: Hashable {
  let name: String
  let room: String
  let time: String
  let sec: String
  let start: Date
  let end: Date
}

struct WidgetDay {
  let date: String
  let week: Int?
  let weekday: Int
  let classes: [WidgetClass]
}

struct WidgetDoc {
  let message: String
  let days: [WidgetDay]

  static let empty = WidgetDoc(message: syncHint, days: [])

  static func load() -> WidgetDoc {
    guard let defaults = UserDefaults(suiteName: appGroup),
      let raw = defaults.string(forKey: dataKey),
      let data = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .empty }
    var days: [WidgetDay] = []
    for d in json["days"] as? [[String: Any]] ?? [] {
      var classes: [WidgetClass] = []
      for c in d["classes"] as? [[String: Any]] ?? [] {
        guard let s = (c["start"] as? NSNumber)?.doubleValue,
          let e = (c["end"] as? NSNumber)?.doubleValue
        else { continue }
        classes.append(
          WidgetClass(
            name: c["name"] as? String ?? "",
            room: c["room"] as? String ?? "",
            time: c["time"] as? String ?? "",
            sec: c["sec"] as? String ?? "",
            start: Date(timeIntervalSince1970: s / 1000),
            end: Date(timeIntervalSince1970: e / 1000)))
      }
      days.append(
        WidgetDay(
          date: d["date"] as? String ?? "",
          week: (d["week"] as? NSNumber)?.intValue,
          weekday: (d["weekday"] as? NSNumber)?.intValue ?? 0,
          classes: classes))
    }
    return WidgetDoc(message: json["message"] as? String ?? "", days: days)
  }

  static func dayKey(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = cst
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }

  func today(at now: Date) -> WidgetDay? {
    let key = WidgetDoc.dayKey(now)
    return days.first { $0.date == key }
  }

  /// The class on now, else the next one (today or later), with its day.
  func current(at now: Date) -> (WidgetDay, WidgetClass)? {
    let key = WidgetDoc.dayKey(now)
    for d in days where d.date >= key {
      if let c = d.classes.first(where: { $0.end > now }) { return (d, c) }
    }
    return nil
  }

  /// Up to [count] classes after [after] on the same day.
  func following(_ after: WidgetClass, in day: WidgetDay, count: Int) -> [WidgetClass] {
    guard let i = day.classes.firstIndex(of: after) else { return [] }
    return Array(day.classes.dropFirst(i + 1).prefix(count))
  }

  func weekLabel(at now: Date) -> String {
    guard let w = today(at: now)?.week else { return "" }
    return "第\(w)周"
  }

  func emptyText(at now: Date) -> String {
    if !message.isEmpty { return message }
    let key = WidgetDoc.dayKey(now)
    if !days.contains(where: { $0.date >= key }) { return syncHint }
    if let t = today(at: now), !t.classes.isEmpty { return "今天的课已上完" }
    return "今天没有课"
  }

  /// Class starts/ends from [now] until [until], plus [until] itself.
  func boundaries(from now: Date, until: Date) -> [Date] {
    var out = Set<Date>()
    for d in days {
      for c in d.classes {
        if c.start > now && c.start < until { out.insert(c.start) }
        if c.end > now && c.end < until { out.insert(c.end) }
      }
    }
    out.insert(until)
    return out.sorted()
  }
}

private let weekdayNames = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

private func classBadge(_ day: WidgetDay, _ c: WidgetClass, now: Date) -> String {
  if c.start <= now { return "上课中" }
  if day.date == WidgetDoc.dayKey(now) { return "下一节" }
  if day.date == WidgetDoc.dayKey(now.addingTimeInterval(86400)) { return "明天" }
  return day.weekday >= 1 && day.weekday <= 7 ? weekdayNames[day.weekday] : "之后"
}

private func dateLabel(_ now: Date) -> String {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = cst
  let c = cal.dateComponents([.month, .day, .weekday], from: now)
  let wd = ((c.weekday ?? 1) + 5) % 7 + 1
  return "\(c.month ?? 0)月\(c.day ?? 0)日 \(weekdayNames[wd])"
}

private func nextMidnight(after now: Date) -> Date {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = cst
  let start = cal.startOfDay(for: now)
  return cal.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86400)
}

// MARK: - Timeline

struct ClassEntry: TimelineEntry {
  let date: Date
  let doc: WidgetDoc
}

struct ClassProvider: TimelineProvider {
  func placeholder(in context: Context) -> ClassEntry {
    ClassEntry(date: Date(), doc: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (ClassEntry) -> Void) {
    let doc = WidgetDoc.load()
    completion(ClassEntry(date: Date(), doc: context.isPreview && doc.days.isEmpty ? .sample : doc))
  }

  /// One entry now and one at each class start/end until midnight (CST);
  /// then WidgetKit asks again. The app and the background refresh also
  /// reload the timeline whenever the data changes.
  func getTimeline(in context: Context, completion: @escaping (Timeline<ClassEntry>) -> Void) {
    let now = Date()
    let doc = WidgetDoc.load()
    let midnight = nextMidnight(after: now)
    var entries = [ClassEntry(date: now, doc: doc)]
    for d in doc.boundaries(from: now, until: midnight).prefix(40) {
      entries.append(ClassEntry(date: d, doc: doc))
    }
    completion(Timeline(entries: entries, policy: .after(midnight)))
  }
}

extension WidgetDoc {
  static var sample: WidgetDoc {
    let now = Date()
    let key = WidgetDoc.dayKey(now)
    return WidgetDoc(
      message: "",
      days: [
        WidgetDay(
          date: key, week: 6, weekday: 3,
          classes: [
            WidgetClass(
              name: "高等数学", room: "教一 301", time: "08:00-09:35", sec: "1-2节",
              start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800)),
            WidgetClass(
              name: "大学英语", room: "N8618", time: "10:05-11:40", sec: "3-4节",
              start: now.addingTimeInterval(3600), end: now.addingTimeInterval(9000)),
            WidgetClass(
              name: "植物学", room: "生命楼 204", time: "14:00-15:35", sec: "5-6节",
              start: now.addingTimeInterval(14400), end: now.addingTimeInterval(19800)),
          ])
      ])
  }
}

// MARK: - Views

private struct Chip: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(Color.accentColor)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(Capsule().fill(Color.accentColor.opacity(0.15)))
      .lineLimit(1)
  }
}

private struct Countdown: View {
  let c: WidgetClass
  let now: Date
  var body: some View {
    if c.start <= now {
      HStack(spacing: 2) {
        Text(timerInterval: now...c.end, countsDown: true)
          .monospacedDigit()
        Text("后下课")
      }
    } else if c.start.timeIntervalSince(now) < 3 * 3600 {
      HStack(spacing: 2) {
        Text(timerInterval: now...c.start, countsDown: true)
          .monospacedDigit()
        Text("后上课")
      }
    }
  }
}

struct SmallView: View {
  let entry: ClassEntry
  var body: some View {
    let now = entry.date
    VStack(alignment: .leading, spacing: 3) {
      if let (day, c) = entry.doc.current(at: now) {
        Text(classBadge(day, c, now: now))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.accentColor)
        Text(String(c.time.split(separator: "-").first ?? ""))
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .monospacedDigit()
        Spacer(minLength: 0)
        Text(c.name)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(2)
        Text(c.room)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text(entry.doc.weekLabel(at: now))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Color.accentColor)
        Spacer(minLength: 0)
        Text(entry.doc.emptyText(at: now))
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

private struct ClassRow: View {
  let c: WidgetClass
  let now: Date
  let isNext: Bool
  var body: some View {
    let live = c.start <= now && c.end > now
    let past = c.end <= now
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(live ? Color.accentColor : (isNext ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3)))
        .frame(width: 4)
      VStack(alignment: .leading, spacing: 1) {
        Text(c.name)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
        Text([c.time, c.room].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      if live {
        Chip(text: "上课中")
      }
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.accentColor.opacity(live ? 0.16 : (isNext ? 0.08 : 0))))
    .opacity(past ? 0.45 : 1)
  }
}

struct MediumView: View {
  let entry: ClassEntry
  var body: some View {
    let now = entry.date
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        if let (day, c) = entry.doc.current(at: now) {
          HStack(spacing: 6) {
            Chip(text: classBadge(day, c, now: now))
            Text(entry.doc.weekLabel(at: now))
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Text(c.name)
            .font(.system(size: 18, weight: .bold))
            .lineLimit(2)
          Text([c.time, c.room].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Countdown(c: c, now: now)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        } else {
          Text(dateLabel(now))
            .font(.system(size: 13, weight: .semibold))
          Spacer(minLength: 0)
          Text(entry.doc.emptyText(at: now))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

      if let (day, c) = entry.doc.current(at: now) {
        let rest = entry.doc.following(c, in: day, count: 2)
        if !rest.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("之后")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            ForEach(rest, id: \.self) { n in
              VStack(alignment: .leading, spacing: 1) {
                Text(n.name)
                  .font(.system(size: 13, weight: .semibold))
                  .lineLimit(1)
                Text([String(n.time.split(separator: "-").first ?? ""), n.room]
                  .filter { !$0.isEmpty }.joined(separator: " · "))
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
  }
}

struct LargeView: View {
  let entry: ClassEntry
  var body: some View {
    let now = entry.date
    let today = entry.doc.today(at: now)?.classes ?? []
    let done = !today.isEmpty && today.allSatisfy { $0.end <= now }
    let tomorrowKey = WidgetDoc.dayKey(now.addingTimeInterval(86400))
    let tomorrow = entry.doc.days.first { $0.date == tomorrowKey }?.classes ?? []
    let showTomorrow = (today.isEmpty || done) && !tomorrow.isEmpty
    let list = showTomorrow ? tomorrow : today
    let shown = Array(list.drop(while: { list.count > 6 && $0.end <= now }).prefix(6))
    let nextStart = shown.first(where: { $0.start > now })?.start
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(showTomorrow ? "明天" : dateLabel(now))
          .font(.system(size: 15, weight: .bold))
        Spacer()
        let w = entry.doc.weekLabel(at: now)
        if !w.isEmpty { Chip(text: w) }
      }
      if shown.isEmpty {
        Spacer()
        Text(entry.doc.emptyText(at: now))
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        Spacer()
      } else {
        ForEach(shown, id: \.self) { c in
          ClassRow(c: c, now: now, isNext: c.start == nextStart)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

struct ClassWidgetView: View {
  @Environment(\.widgetFamily) var family
  let entry: ClassEntry

  var body: some View {
    switch family {
    case .systemSmall: SmallView(entry: entry)
    case .systemLarge: LargeView(entry: entry)
    default: MediumView(entry: entry)
    }
  }
}

private extension View {
  /// iOS 17+ widgets must declare their background; earlier systems pad it.
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        LinearGradient(
          colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    } else {
      padding()
        .background(
          LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
  }
}

struct ClassWidget: Widget {
  // Must match kIosWidgetKind in lib/data/home_widget_sync.dart.
  let kind = "ClassWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ClassProvider()) { entry in
      ClassWidgetView(entry: entry)
        .widgetBackground()
    }
    .configurationDisplayName("课表")
    .description("当前或下一节课，以及今天的课程。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct ClassWidgetBundle: WidgetBundle {
  var body: some Widget {
    ClassWidget()
  }
}
