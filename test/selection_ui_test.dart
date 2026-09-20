import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/ui/courses_page.dart';
import 'package:nwafu_bksxk/ui/teaching_class_tile.dart';

void main() {
  testWidgets('conflicting class with seats is labelled as a conflict, not full',
      (tester) async {
    var attempted = false;
    var monitored = false;
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TC-CONFLICT',
      'courseName': '形势与政策',
      'teacherName': '模拟教师',
      'classCapacity': '138',
      'numberOfSelected': '131',
      'isFull': '0',
      'isConflict': '1',
      'conflictDesc': '与已选课程时间冲突',
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: TeachingClassTile(
            teachingClass: tc,
            kind: CourseKind.fankc,
            onGrab: () => attempted = true,
            onMonitor: () => monitored = true,
            onRefresh: () async {},
          ),
        ),
      ),
    ));

    expect(find.text('已满，监控空位'), findsNothing);
    expect(find.text('有冲突，仍要选'), findsOneWidget);
    expect(find.text('加入监控'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('有冲突，仍要选'));
    expect(attempted, isTrue);
    expect(monitored, isFalse);
  });

  testWidgets('full class makes monitoring the primary action', (tester) async {
    var monitored = false;
    var attempted = false;
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TC-FULL',
      'courseName': '高等数学模拟课',
      'teacherName': '模拟教师',
      'classCapacity': '1',
      'numberOfSelected': '1',
      'isFull': '1',
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: TeachingClassTile(
            teachingClass: tc,
            kind: CourseKind.fankc,
            onGrab: () => attempted = true,
            onMonitor: () => monitored = true,
            onRefresh: () async {},
          ),
        ),
      ),
    ));

    expect(find.text('已满，监控空位'), findsOneWidget);
    expect(find.text('仍要提交'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('已满，监控空位'));
    expect(monitored, isTrue);
    expect(attempted, isFalse);
  });

  testWidgets('a watched class offers 取消监控 and shows the badge', (tester) async {
    var toggled = false;
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TC-W',
      'courseName': '课程',
      'teacherName': '教师',
      'classCapacity': '1',
      'numberOfSelected': '1',
      'isFull': '1',
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: TeachingClassTile(
            teachingClass: tc,
            kind: CourseKind.fankc,
            watched: true,
            onGrab: () {},
            onMonitor: () => toggled = true,
            onRefresh: () async {},
          ),
        ),
      ),
    ));
    expect(find.text('取消监控'), findsOneWidget);
    expect(find.text('监控中'), findsOneWidget);
    expect(find.text('已满，监控空位'), findsNothing);
    await tester.tap(find.text('取消监控'));
    expect(toggled, isTrue);
  });

  testWidgets('an online class shows its platform instead of a room', (tester) async {
    final tc = TeachingClass.fromJson({
      'teachingClassID': 'TC-ZH',
      'courseNumber': 'ZH037',
      'courseName': '食品标准与法规',
      'teacherName': '网络教师',
      'classCapacity': '50',
      'numberOfSelected': '10',
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: TeachingClassTile(
            teachingClass: tc,
            kind: CourseKind.xgxk,
            onGrab: () {},
            onMonitor: () {},
            onRefresh: () async {},
          ),
        ),
      ),
    ));
    expect(find.text('智慧树'), findsOneWidget);
    expect(find.textContaining('网课'), findsOneWidget);
  });

  testWidgets('experiment picker accepts a valid alias after an empty canonical ID', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _PickerHarness()));

    await tester.tap(find.text('打开选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学物理实验（实验班）'));
    await tester.pumpAndSettle();

    expect(find.text('TC-TEST-LAB-01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness();

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  String _selected = '未选择';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () async {
              final value = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (context) => const Scaffold(
                    body: TestClassPicker(list: [
                      {
                        'testTeachingClassID': '',
                        'teachingClassID': 'TC-TEST-LAB-01',
                        'courseName': '大学物理实验（实验班）',
                        'teacherName': '模拟教师',
                      },
                    ]),
                  ),
                ),
              );
              if (value != null) setState(() => _selected = value);
            },
            child: const Text('打开选择'),
          ),
          Text(_selected),
        ],
      ),
    );
  }
}
