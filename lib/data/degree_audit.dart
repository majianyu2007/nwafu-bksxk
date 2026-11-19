/// 学业完成查询 (EMAP app `xywccx`): how far the student is through each
/// training plan (培养方案), as a tree of course groups (课组).
///
/// Verified against the live app on 2026-10-13 (read-only):
///  - `grpyfacx.do` (XH) lists the student's plans: PYFADM id, PYFAMC name,
///    ZSYQXF required total, XDLXDM_DISPLAY 主修/辅修. Its YWCXF is stale.
///  - `cxscfa.do` (XH, SCLBDM=04, PYFADM, BYNJDM=-) is the last audit run:
///    WCXF earned, YQXF required, CZSJ when it was computed. Numbers come
///    back as strings ("51.0").
///  - `cxscfakz.do` (+ XNXQDM) is one row per group: KZH id, FKZH parent
///    ("-1" = top level), KZM name, KCXZDM_DISPLAY 必修/选修/任选, WCXF/YQXF,
///    KXKCS courses open this term, SFTG "1" = passed, BZ sort order.
///  - `cxfakzyxxfgj.do` → rows[0].XKXF = credits selected this term, for one
///    group (with KZLXDM + KZH) or the whole plan (without).
///
/// The page's 重新计算 button posts a recalculation; this client never calls
/// it.
library;

import 'dart:convert';

double _num(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.trim()) ?? 0;
}

String _str(Object? v) => v == null ? '' : '$v'.trim();

/// One course group (课组) of a plan.
class DegreeGroup {
  DegreeGroup({
    required this.id,
    required this.parentId,
    required this.name,
    this.kind = '',
    this.nature = '',
    this.earned = 0,
    this.goal = 0,
    this.selected,
    this.openCourses,
    this.passed = false,
    this.order = 0,
    List<DegreeGroup>? children,
  }) : children = children ?? [];

  final String id;

  /// Parent group id; `-1` (or empty) for a top-level group.
  final String parentId;
  final String name;

  /// KZLXDM, needed to ask for the group's selected credits.
  final String kind;

  /// 必修 / 选修 / 任选 (may be empty for container groups).
  final String nature;
  final double earned;
  final double goal;

  /// Credits selected this term, when fetched.
  final double? selected;

  /// Courses of this group open for selection this term (KXKCS).
  final int? openCourses;

  /// The school's own verdict (SFTG = "1").
  final bool passed;
  final int order;
  final List<DegreeGroup> children;

  bool get isRoot => parentId.isEmpty || parentId == '-1';

  /// Credits still missing. Zero when the requirement is met or unknown.
  double get missing =>
      passed || goal <= 0 ? 0 : (goal - earned).clamp(0, goal);

  /// Still short of the requirement.
  bool get short => missing > 0;

  /// Earned / required, clamped to 0..1 (1 when passed or nothing required).
  double get progress =>
      passed || goal <= 0 ? 1 : (earned / goal).clamp(0, 1).toDouble();

  factory DegreeGroup.fromRow(Map<String, dynamic> r) {
    final open = int.tryParse(_str(r['KXKCS']));
    return DegreeGroup(
      id: _str(r['KZH']),
      parentId: _str(r['FKZH']),
      name: _str(r['KZM']),
      kind: _str(r['KZLXDM']),
      nature: _str(r['KCXZDM_DISPLAY']),
      earned: _num(r['WCXF']),
      goal: _num(r['YQXF']),
      openCourses: open,
      passed: _str(r['SFTG']) == '1',
      order: int.tryParse(_str(r['BZ'])) ?? 999,
    );
  }

  DegreeGroup copyWith({double? selected, List<DegreeGroup>? children}) =>
      DegreeGroup(
        id: id,
        parentId: parentId,
        name: name,
        kind: kind,
        nature: nature,
        earned: earned,
        goal: goal,
        selected: selected ?? this.selected,
        openCourses: openCourses,
        passed: passed,
        order: order,
        children: children ?? this.children,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'parent': parentId,
    'name': name,
    'kind': kind,
    'nature': nature,
    'earned': earned,
    'goal': goal,
    'selected': selected,
    'open': openCourses,
    'passed': passed,
    'order': order,
    'children': [for (final c in children) c.toJson()],
  };

  factory DegreeGroup.fromJson(Map<String, dynamic> j) => DegreeGroup(
    id: j['id'] as String,
    parentId: j['parent'] as String,
    name: j['name'] as String,
    kind: (j['kind'] as String?) ?? '',
    nature: (j['nature'] as String?) ?? '',
    earned: (j['earned'] as num).toDouble(),
    goal: (j['goal'] as num).toDouble(),
    selected: (j['selected'] as num?)?.toDouble(),
    openCourses: j['open'] as int?,
    passed: (j['passed'] as bool?) ?? false,
    order: (j['order'] as int?) ?? 999,
    children: [
      for (final c in (j['children'] as List? ?? const []))
        DegreeGroup.fromJson(c as Map<String, dynamic>),
    ],
  );
}

/// Builds the group tree from flat `cxscfakz.do` rows. A group whose parent
/// is missing from the list is shown at the top level rather than dropped.
/// Siblings are ordered by BZ, then name.
List<DegreeGroup> buildDegreeTree(List<DegreeGroup> flat) {
  final ids = {for (final g in flat) g.id};
  final byParent = <String, List<DegreeGroup>>{};
  for (final g in flat) {
    final parent = g.isRoot || !ids.contains(g.parentId) || g.parentId == g.id
        ? ''
        : g.parentId;
    (byParent[parent] ??= []).add(g);
  }
  List<DegreeGroup> build(String parent, Set<String> path) {
    final list = [...?byParent[parent]]
      ..sort((a, b) {
        final o = a.order.compareTo(b.order);
        return o != 0 ? o : a.name.compareTo(b.name);
      });
    return [
      for (final g in list)
        // A cycle in the server data would otherwise recurse forever.
        if (!path.contains(g.id))
          g.copyWith(children: build(g.id, {...path, g.id})),
    ];
  }

  return build('', const {});
}

/// One training plan with its audit.
class DegreePlan {
  const DegreePlan({
    required this.id,
    required this.name,
    this.kind = '',
    required this.goal,
    required this.earned,
    this.selected,
    this.computedAt = '',
    this.groups = const [],
  });

  final String id;
  final String name;

  /// 主修 / 辅修.
  final String kind;
  final double goal;
  final double earned;

  /// Credits selected this term across the plan.
  final double? selected;

  /// When the school last computed the audit (CZSJ), as the server wrote it.
  final String computedAt;

  /// Top-level groups (with children).
  final List<DegreeGroup> groups;

  double get missing =>
      goal <= 0 ? 0 : (goal - earned).clamp(0, goal).toDouble();

  double get progress =>
      goal <= 0 ? 1 : (earned / goal).clamp(0, 1).toDouble();

  /// Every group in the tree, depth first.
  Iterable<DegreeGroup> get allGroups sync* {
    Iterable<DegreeGroup> walk(List<DegreeGroup> list) sync* {
      for (final g in list) {
        yield g;
        yield* walk(g.children);
      }
    }

    yield* walk(groups);
  }

  static bool _hasShortDescendant(DegreeGroup g) {
    for (final c in g.children) {
      if (c.short || _hasShortDescendant(c)) return true;
    }
    return false;
  }

  /// Lowest-level groups still short, for the "还差" summary.
  List<DegreeGroup> get shortLeaves => [
    for (final g in allGroups)
      if (g.short && !_hasShortDescendant(g)) g,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'goal': goal,
    'earned': earned,
    'selected': selected,
    'computedAt': computedAt,
    'groups': [for (final g in groups) g.toJson()],
  };

  factory DegreePlan.fromJson(Map<String, dynamic> j) => DegreePlan(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: (j['kind'] as String?) ?? '',
    goal: (j['goal'] as num).toDouble(),
    earned: (j['earned'] as num).toDouble(),
    selected: (j['selected'] as num?)?.toDouble(),
    computedAt: (j['computedAt'] as String?) ?? '',
    groups: [
      for (final g in j['groups'] as List)
        DegreeGroup.fromJson(g as Map<String, dynamic>),
    ],
  );

  /// Combines the plan row, its audit row and its group rows.
  factory DegreePlan.fromRows({
    required Map<String, dynamic> plan,
    Map<String, dynamic>? audit,
    required List<Map<String, dynamic>> groups,
    double? selected,
    Map<String, double> groupSelected = const {},
  }) {
    final flat = [
      for (final r in groups)
        if (DegreeGroup.fromRow(r) case final g when g.id.isNotEmpty)
          groupSelected.containsKey(g.id)
              ? g.copyWith(selected: groupSelected[g.id])
              : g,
    ];
    final goal = _num(audit?['YQXF']);
    final planName = _str(plan['PYFAMC']);
    return DegreePlan(
      id: _str(plan['PYFADM']),
      name: planName.isNotEmpty ? planName : _str(audit?['PYFAMC']),
      kind: _str(plan['XDLXDM_DISPLAY']),
      goal: goal > 0 ? goal : _num(plan['ZSYQXF']),
      earned: audit == null ? _num(plan['YWCXF']) : _num(audit['WCXF']),
      selected: selected,
      computedAt: _str(audit?['CZSJ']),
      groups: buildDegreeTree(flat),
    );
  }
}

/// Every plan of the student, as last fetched.
class DegreeAudit {
  const DegreeAudit({required this.plans, required this.syncedAt});
  final List<DegreePlan> plans;
  final DateTime syncedAt;

  String encode() => jsonEncode({
    'plans': [for (final p in plans) p.toJson()],
    'syncedAt': syncedAt.toIso8601String(),
  });

  static DegreeAudit? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return DegreeAudit(
        plans: [
          for (final p in j['plans'] as List)
            DegreePlan.fromJson(p as Map<String, dynamic>),
        ],
        syncedAt: DateTime.parse(j['syncedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// `cxfakzyxxfgj.do` rows → the selected credits, or null when absent.
double? selectedCreditsFrom(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return null;
  final v = rows.first['XKXF'];
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v'.trim());
}
