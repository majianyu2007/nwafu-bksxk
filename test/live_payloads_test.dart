// Locks the data-layer behaviours that were wrong against the live server
// (verified with real bksxk.nwafu.edu.cn payloads on 2026-09-14):
//  - capacitySuffix is "" on this deployment, so a capacity poll must still go
//    out, and its sparse payload (nearly every field null, isFull never set)
//    must not blank the class it refreshes;
//  - batch.do leaves canSelect null; the per-student value and noSelectReason
//    come from the profile's electiveBatchList;
//  - teacherName arrives as "姓名(职称)|工号|,…" on whole-school rows;
//  - textbook rows are packed as a JSON string under `wid`;
//  - teachingTime.do rows carry dayOfWeek/sections/week bits.
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/api_client.dart';
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/course_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:test/test.dart';

/// Records GET calls and answers each with a canned envelope.
class _CannedClient extends ApiClient {
  _CannedClient(this.answers) : super(origin: 'http://localhost');
  final Map<String, ApiResult> answers;
  final calls = <(String, Map<String, dynamic>?)>[];

  @override
  Future<ApiResult> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
    bool addTimestamp = true,
    bool allowRelogin = true,
  }) async {
    calls.add((path, query));
    return answers[path] ??
        ApiResult(
            code: '0',
            msg: 'unexpected $path',
            data: null,
            dataList: const [],
            totalCount: 0);
  }
}

/// The shape capacity.do really returns: counts as strings, everything else
/// null, no isFull.
Map<String, dynamic> capacityPayload(
        {required String capacity, required String selected}) =>
    {
      'numberOfFemale': '41',
      'schoolClassMap': null,
      'recommendSchoolClass': null,
      'isFull': null,
      'numberOfSelected': selected,
      'classCapacity': capacity,
      'teacherName': null,
      'teachingPlace': null,
      'isConflict': null,
      'conflictDesc': null,
      'hasTest': null,
      'hasBook': null,
      'capacitySuffix': null,
      'limitGender': '0',
    };

TeachingClass listRow({String selected = '144', String capacity = '165'}) =>
    TeachingClass.fromJson({
      'teachingClassID': '202620271118100461',
      'courseNumber': '1181004',
      'courseName': '形势与政策',
      'courseIndex': '61',
      'teacherName': '武春芳',
      'teachingPlace': '11周,14-16周 星期二 第1节-第2节 N8T09',
      'classCapacity': capacity,
      'numberOfSelected': selected,
      'isFull': '0',
      'isConflict': '1',
      'conflictDesc': '与已选课程时间冲突',
      'hasTest': '0',
      'hasBook': '1',
      'capacitySuffix': '',
    });

void main() {
  group('capacity refresh', () {
    test('polls even when capacitySuffix is empty and sends the empty suffix',
        () async {
      final client = _CannedClient({
        Api.capacity: ApiResult(
          code: '1',
          msg: '',
          data: capacityPayload(capacity: '165', selected: '150'),
          dataList: const [],
          totalCount: 0,
        ),
      });
      final fresh = await CourseService(client).refreshCapacity(listRow(), 'S');

      expect(client.calls, hasLength(1));
      final (path, query) = client.calls.single;
      expect(path, Api.capacity);
      expect(query?['capacitySuffix'], '');
      expect(query?['teachingClassId'], '202620271118100461');
      expect(fresh.numberOfSelected, 150);
      expect(fresh.remaining, 15);
    });

    test('a sparse payload keeps every field it leaves null', () {
      final merged = listRow()
          .mergeCapacity(capacityPayload(capacity: '165', selected: '160'));
      expect(merged.teacherName, '武春芳');
      expect(merged.teachingPlace, contains('N8T09'));
      expect(merged.isConflict, isTrue);
      expect(merged.conflictDesc, '与已选课程时间冲突');
      expect(merged.hasBook, isTrue);
      expect(merged.numberOfSelected, 160);
      expect(merged.classCapacity, 165);
      expect(merged.isFull, isFalse);
    });

    test('fullness is derived from the counts because isFull is never sent',
        () {
      final full = listRow()
          .mergeCapacity(capacityPayload(capacity: '165', selected: '165'));
      expect(full.isFull, isTrue);
      expect(full.remaining, 0);
      expect(full.isGrabbable, isFalse);

      final freed =
          full.mergeCapacity(capacityPayload(capacity: '165', selected: '164'));
      expect(freed.isFull, isFalse,
          reason: 'a seat opening must clear the stale full flag');
      expect(freed.remaining, 1);
    });

    test('detail overlay never erases list-row fields with nulls', () {
      final detailed = listRow().mergeDetail({
        'teacherNameList': '武春芳(副教授)|2008117206|',
        'examType': '2',
        'classCapacity': null,
        'numberOfSelected': null,
        'isConflict': null,
        'hasBook': '1',
      });
      expect(detailed.classCapacity, 165);
      expect(detailed.numberOfSelected, 144);
      expect(detailed.isConflict, isTrue);
      expect(detailed.teacherWithTitle, '武春芳(副教授)');
      expect(detailed.examType, '2');
    });
  });

  group('round availability', () {
    final batchRows = <Map<String, dynamic>>[
      {
        'code': 'B1',
        'name': '补选一',
        'batchType': '01',
        'canSelect': null,
        'tacticCode': '01',
        'displayXGXK': '0',
        'displayFANKC': '1'
      },
      {
        'code': 'B2',
        'name': '补选二',
        'batchType': '01',
        'canSelect': null,
        'tacticCode': '02',
        'displayXGXK': '1'
      },
    ];
    final profile = <String, dynamic>{
      'code': '2025013665',
      'electiveBatchList': [
        {'code': 'B1', 'canSelect': '1', 'noSelectReason': null},
        {'code': 'B2', 'canSelect': '0', 'noSelectReason': '不在选课轮次范围内'},
      ],
      'expElectiveBatchList': [],
    };

    test('canSelect and noSelectReason come from the profile', () {
      final merged = mergeBatchAvailability(batchRows, profile);
      expect(merged.map((b) => b.code), ['B1', 'B2']);
      expect(merged[0].canSelect, isTrue);
      expect(merged[0].noSelectReason, isEmpty);
      expect(merged[1].canSelect, isFalse);
      expect(merged[1].noSelectReason, '不在选课轮次范围内');
      // batch.do values still win where present.
      expect(merged[0].name, '补选一');
      expect(merged[1].allowsDrop, isFalse);
      expect(merged[0].allowsDrop, isTrue);
    });

    test('display flags gate the category tabs; absent flags hide nothing', () {
      final merged = mergeBatchAvailability(batchRows, profile);
      expect(merged[0].showsKind(CourseKind.xgxk), isFalse);
      expect(merged[0].showsKind(CourseKind.fankc), isTrue);
      expect(merged[0].showsKind(CourseKind.tykc), isTrue,
          reason: 'flag absent');
      expect(merged[1].showsKind(CourseKind.xgxk), isTrue);
    });

    test('profile-only rounds are appended; a missing profile changes nothing',
        () {
      final extra = mergeBatchAvailability(batchRows, {
        'electiveBatchList': [
          {'code': 'B3', 'name': '实验轮次', 'batchType': '02', 'canSelect': '1'},
        ],
      });
      expect(extra.map((b) => b.code), ['B1', 'B2', 'B3']);
      expect(extra[2].canSelect, isTrue);

      final bare = mergeBatchAvailability(batchRows, const {});
      expect(bare, hasLength(2));
      expect(bare[0].canSelect, isFalse);
    });

    test('notice confirmation is only needed when the round asks for it', () {
      expect(
          ElectiveBatch.fromJson({'code': 'B', 'needConfirm': '0'})
              .needsNoticeConfirmation,
          isFalse);
      expect(
          ElectiveBatch.fromJson(
                  {'code': 'B', 'needConfirm': '1', 'isConfirmed': null})
              .needsNoticeConfirmation,
          isTrue);
      expect(
          ElectiveBatch.fromJson(
                  {'code': 'B', 'needConfirm': '1', 'isConfirmed': '1'})
              .needsNoticeConfirmation,
          isFalse);
    });
  });

  group('flat course rows (publicCourse / queryCourse)', () {
    Map<String, dynamic> flat(String course, String index, {String type = '学科前沿与科技创新-2025版'}) => {
          'teachingClassID': '2026$course$index',
          'courseNumber': course,
          'courseName': '课程$course',
          'courseIndex': index,
          'credit': '1',
          'courseNatureName': '任选',
          'departmentName': '农学院',
          'publicCourseTypeName': type,
          'classCapacity': '40',
          'numberOfSelected': '0',
          'numberOfFirstVolunteer': '18',
          'isFull': '0',
          'isConflict': '1',
          'teachingMethod': index == '02' ? '面授讲课+SPOC/MOOC' : '面授讲课',
        };

    test('one flat row per class is grouped into one course per course number', () async {
      final client = _CannedClient({});
      final service = CourseService(client);
      final rows = [
        for (final r in [flat('1010004', '01'), flat('1010004', '02'), flat('1010010', '01'), flat('1010004', '03')])
          CourseRow.fromJson(r),
      ];
      // CourseRow.fromJson yields no classes for flat rows; the service wraps
      // them first, which is what _asCourseRow does for rows without tcList.
      expect(rows.first.teachingClasses, isEmpty, reason: 'the bug the grouping fixes');

      final wrapped = [
        for (final r in [flat('1010004', '01'), flat('1010004', '02'), flat('1010010', '01'), flat('1010004', '03')])
          CourseRow(
            courseNumber: r['courseNumber'] as String,
            courseName: r['courseName'] as String,
            credit: '1',
            courseNatureName: '任选',
            departmentName: '农学院',
            number: 1,
            selected: false,
            teachingClasses: [TeachingClass.fromJson(r)],
            raw: r,
          ),
      ];
      final grouped = CourseService.groupFlatRows(wrapped);
      expect(grouped.map((r) => r.courseNumber), ['1010004', '1010010']);
      expect(grouped.first.teachingClasses.length, 3);
      expect(grouped.first.number, 3);
      expect(grouped.first.publicCourseType, '学科前沿与科技创新-2025版');
      expect(grouped.first.teachingClasses[1].isOnline, isTrue);
      expect(grouped.first.teachingClasses[0].isOnline, isFalse);
      expect(grouped.first.teachingClasses.first.firstVolunteers, 18);
      // service is only constructed to prove the method is reachable there
      expect(service, isNotNull);
    });
  });

  group('field normalisation', () {
    test('teacher names drop ids and per-slot duplicates, keep titles', () {
      expect(teacherDisplayName('王强(副教授)|2020110185|,王强(副教授)|2020110185|'),
          '王强(副教授)');
      expect(
        teacherDisplayName('刘全中(副教授)|2008115807|,李宗军(副研究员)|2022110113|'),
        '刘全中(副教授)、李宗军(副研究员)',
      );
      expect(teacherDisplayName('武春芳'), '武春芳');
      expect(teacherDisplayName(null), '');
    });

    test('whole-school rows without counts report unknown capacity, not full',
        () {
      final row = TeachingClass.fromJson({
        'teachingClassID': '202620271102011501',
        'courseName': '数据分析与图示',
        'teacherName': '王强(副教授)|2020110185|',
        'classCapacity': null,
        'numberOfSelected': null,
        'isFull': null,
      });
      expect(row.hasCapacityInfo, isFalse);
      expect(row.teacherName, '王强(副教授)');
    });

    test('textbook rows packed in wid are unpacked', () {
      final option = TextbookOption.fromJson({
        'wid':
            '{"ZZZ":"无","ISBN":"1674678301","WDGYY":"02","SM":"《时事报告大学生版》专题讲稿","JCBH":"ae65c32f59b9469a80bdfc28d431c95e","JXBID":"202620271118100461","SFDG":"0"}',
      });
      expect(option.bookCode, 'ae65c32f59b9469a80bdfc28d431c95e');
      expect(option.bookName, '《时事报告大学生版》专题讲稿');
      expect(option.isbn, '1674678301');
      expect(option.author, '无');
      expect(option.ordered, isFalse);
      expect(option.declineReasonCode, '02');
      expect(option.reasonCodes, isEmpty);
      final withReasons = option
          .copyWith(reasonCodes: [TextbookReason(code: '01', name: '借用')]);
      expect(withReasons.reasonCodes.single.code, '01');
      expect(withReasons.bookCode, option.bookCode);
    });

    test('schedule rows decode weekday, sections and week bits', () {
      final e = ScheduleEntry.fromJson({
        'teachingClassID': '202620271215122320',
        'courseName': '概率论与数理统计',
        'dayOfWeek': '4',
        'beginSection': '7',
        'endSection': '8',
        'weekName': '2-3周,5-11周(单)',
        'week': '01101010101000000000',
        'teachingPlace': 'N8603',
      });
      expect(e.hasSlot, isTrue);
      expect(e.slotLabel, '周四 第7-8节');
      expect(e.weeks, [2, 3, 5, 7, 9, 11]);
      expect(e.isUnarranged, isFalse);

      final unarranged = ScheduleEntry.fromJson(
          {'courseName': '工程训练（乙）', 'teachingPlace': null});
      expect(unarranged.hasSlot, isFalse);
      expect(unarranged.slotLabel, '');
      expect(unarranged.isUnarranged, isTrue);
    });

    test('selection rows expose canDelete, defaulting to allowed', () {
      expect(
          TeachingClass.fromJson({'teachingClassID': 'A', 'canDelete': '0'})
              .canDelete,
          isFalse);
      expect(
          TeachingClass.fromJson({'teachingClassID': 'A', 'canDelete': '1'})
              .canDelete,
          isTrue);
      expect(
          TeachingClass.fromJson({'teachingClassID': 'A'}).canDelete, isTrue);
    });
  });
}
