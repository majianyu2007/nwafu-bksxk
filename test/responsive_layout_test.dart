import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/app/theme.dart';
import 'package:nwafu_bksxk/ui/layout.dart';
import 'package:nwafu_bksxk/ui/widgets.dart';

void main() {
  testWidgets(
      'narrow and large-text controls remain reachable without overflow',
      (tester) async {
    for (final size in [
      const Size(320, 640),
      const Size(375, 812),
      const Size(844, 390),
      const Size(3840, 2160)
    ]) {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.build(brightness: brightness, seed: Colors.indigo),
          home: MediaQuery(
            data: MediaQueryData(
                size: size, textScaler: const TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Column(children: [
              PageHeader(title: '课程监控', actions: [
                FilledButton(onPressed: () {}, child: const Text('开始监控')),
                OutlinedButton(onPressed: () {}, child: const Text('暂停全部')),
              ]),
              NoticeStrip(
                  text: '完整目录已保存，本地搜索不需要重新连接服务器。',
                  icon: Icons.info_outline,
                  action: TextButton(
                      onPressed: () {}, child: const Text('更新完整目录'))),
              AdaptiveGrid(
                  children:
                      List.generate(3, (i) => Card(child: Text('课程详情 $i')))),
            ]))),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size $brightness');
        expect(find.text('开始监控'), findsOneWidget);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  test('app text scaling composes with platform scaling', () {
    const scaler = AppTextScaler(TextScaler.linear(1.5), 1.3);
    expect(scaler.scale(20), 39);
  });
}
