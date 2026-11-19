import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nwafu_bksxk/app/theme.dart';
import 'package:nwafu_bksxk/app/ui_prefs.dart';
import 'package:nwafu_bksxk/ui/layout.dart';
import 'package:nwafu_bksxk/ui/widgets/glass.dart';

void main() {
  group('computeAdaptiveScale', () {
    test('auto tightens on very narrow phones (320x568)', () {
      final s = computeAdaptiveScale(const Size(320, 568), UiScaleMode.auto);
      expect(s.isCompactPhone, isTrue);
      expect(s.factor, lessThan(1.0));
      expect(s.density, VisualDensity.compact);
    });

    test('auto uses compact density on landscape phones (844x390)', () {
      final s = computeAdaptiveScale(const Size(844, 390), UiScaleMode.auto);
      expect(s.isLandscapePhone, isTrue);
      expect(s.density, VisualDensity.compact);
      expect(s.factor, lessThanOrEqualTo(1.0));
    });

    test('auto nudges slightly up on large desktop unless system scale is high', () {
      final normal = computeAdaptiveScale(
        const Size(1920, 1080),
        UiScaleMode.auto,
        systemScale: 1.0,
      );
      expect(normal.factor, greaterThan(1.0));
      final largeText = computeAdaptiveScale(
        const Size(1920, 1080),
        UiScaleMode.auto,
        systemScale: 1.4,
      );
      expect(largeText.factor, 1.0);
    });

    test('explicit presets override auto', () {
      expect(
        computeAdaptiveScale(const Size(390, 844), UiScaleMode.compact).factor,
        lessThan(1.0),
      );
      expect(
        computeAdaptiveScale(const Size(390, 844), UiScaleMode.standard).factor,
        1.0,
      );
      expect(
        computeAdaptiveScale(const Size(390, 844), UiScaleMode.comfortable)
            .factor,
        greaterThan(1.0),
      );
    });
  });

  test('pageGutter scales with width', () {
    expect(pageGutter(320), 12);
    expect(pageGutter(390), 16);
    expect(pageGutter(1280), 24);
  });

  testWidgets('GlassCapsuleNavBar renders cleanly at 320px and 1.6x text scale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(
            brightness: Brightness.light,
            seed: Colors.teal,
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Scaffold(
              bottomNavigationBar: GlassCapsuleNavBar(
                selectedIndex: 0,
                onSelected: (_) {},
                items: const [
                  GlassNavItem(
                    icon: Icon(Icons.calendar_view_week_outlined),
                    selectedIcon: Icon(Icons.calendar_view_week),
                    label: '课表',
                  ),
                  GlassNavItem(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book),
                    label: '课程',
                  ),
                  GlassNavItem(
                    icon: Icon(Icons.radar_outlined),
                    selectedIcon: Icon(Icons.radar),
                    label: '抢课',
                  ),
                  GlassNavItem(
                    icon: Icon(Icons.school_outlined),
                    selectedIcon: Icon(Icons.school),
                    label: '成绩',
                  ),
                  GlassNavItem(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '我的',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Selected tab label is visible; unselected labels hidden at 320px/1.6x.
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('成绩'), findsNothing);
  });
}
