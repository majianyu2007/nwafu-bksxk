// Locks the StudentInfo <- CreditInfo merge: the student/<code>.do profile is
// sparse (often only code/campus), and xkxf.do carries name/college/major/
// grade. mergeFromCredit must fill blanks without overwriting what we have.
import 'package:nwafu_bksxk/data/auth_service.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/data/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  group('StudentInfo.mergeFromCredit', () {
    test('fills name/college/major/grade when profile had blanks', () {
      final profile = StudentInfo.fromJson({
        'code': '20261234',
        'campus': '01',
      });
      expect(profile.name, isEmpty);

      final credit = CreditInfo.fromJson({
        'name': '张三',
        'code': '20261234',
        'collegeName': '农学院',
        'majorName': '农学',
        'grade': '2026',
        'schoolClassName': '农学2601',
        'campus': '01',
        'campusName': '北校区',
      });
      final merged = profile.mergeFromCredit(credit);
      expect(merged.studentCode, '20261234');
      expect(merged.name, '张三');
      expect(merged.collegeName, '农学院');
      expect(merged.majorName, '农学');
      expect(merged.grade, '2026');
      expect(merged.schoolClassName, '农学2601');
      // campus was already set from the profile, keep it.
      expect(merged.campus, '01');
    });

    test('does not overwrite non-empty profile fields', () {
      final profile = StudentInfo.fromJson({
        'code': '20261234',
        'name': '李四',
        'campus': '01',
        'collegeName': '原学院',
      });
      final credit = CreditInfo.fromJson({
        'name': '不应覆盖',
        'collegeName': '不应覆盖',
        'majorName': '新专业',
      });
      final merged = profile.mergeFromCredit(credit);
      expect(merged.name, '李四');
      expect(merged.collegeName, '原学院');
      expect(merged.majorName, '新专业');
    });

    test('mergeFromCredit with empty credit payload leaves StudentInfo intact',
        () {
      final profile = StudentInfo.fromJson({'code': 'S1', 'name': '王五'});
      final merged = profile.mergeFromCredit(CreditInfo.empty);
      expect(merged.name, '王五');
      expect(merged.studentCode, 'S1');
    });
  });

  group('CreditInfo', () {
    test('needCredit is the round\'s selected credit (official label 已选学分)',
        () {
      // Real xkxf.do payload shape: totalCredit is the programme total,
      // getCredit is null before any grades, needCredit is what was selected.
      final c = CreditInfo.fromJson({
        'totalCredit': '155',
        'getCredit': null,
        'needCredit': '25.5',
        'departmentName': '软件工程',
        'majorName': null,
      });
      expect(c.totalCredit, 155);
      expect(c.getCredit, 0);
      expect(c.selectedCredit, 25.5);
      expect(c.majorName, '软件工程');
    });
  });

  group('selectInitialBatch', () {
    ElectiveBatch batch(String code, {required bool open}) =>
        ElectiveBatch(code: code, name: code, batchType: '01', canSelect: open);

    test('picks the first selectable batch rather than the first visible one',
        () {
      final choice = selectInitialBatch([
        batch('closed', open: false),
        batch('open', open: true),
        batch('open-2', open: true),
      ]);
      expect(choice.batch?.code, 'open');
      expect(choice.hasSelectable, isTrue);
    });

    test('keeps first visible batch for browsing and reports none selectable',
        () {
      final choice = selectInitialBatch([
        batch('closed-1', open: false),
        batch('closed-2', open: false),
      ]);
      expect(choice.batch?.code, 'closed-1');
      expect(choice.hasSelectable, isFalse);
    });

    test('empty list yields no batch and no selectable round', () {
      final choice = selectInitialBatch(const []);
      expect(choice.batch, isNull);
      expect(choice.hasSelectable, isFalse);
    });
  });

  group('Storage.autoOcr', () {
    test('defaults to true and persists an explicit choice', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = Storage(prefs);
      expect(storage.autoOcr(), isTrue);
      await storage.setAutoOcr(false);
      expect(storage.autoOcr(), isFalse);
      await storage.setAutoOcr(true);
      expect(storage.autoOcr(), isTrue);
    });
  });
}
