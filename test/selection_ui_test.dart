import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/core/constants.dart';
import 'package:nwafu_bksxk/data/models.dart';
import 'package:nwafu_bksxk/ui/courses_page.dart';
import 'package:nwafu_bksxk/ui/teaching_class_tile.dart';

void main() {
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

    expect(find.text('满员，监控空位'), findsOneWidget);
    expect(find.text('仍要尝试'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('满员，监控空位'));
    expect(monitored, isTrue);
    expect(attempted, isFalse);
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
