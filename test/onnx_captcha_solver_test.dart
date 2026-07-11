// The ONNX captcha solver's decode path needs a real model + native runtime, so
// it's exercised by the on-device integration check, not here. What we CAN lock
// down without the runtime is graceful degradation: a solver pointed at a missing
// model must return null (so the UI falls back to manual entry) rather than throw.
import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/onnx_captcha_solver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing model asset -> solve returns null, marks unavailable', () async {
    final solver = OnnxCaptchaSolver(
      modelAsset: 'assets/models/does_not_exist.onnx',
      charsetAsset: 'assets/models/does_not_exist.txt',
    );
    // Feed arbitrary bytes; with no model this must degrade to null, not throw.
    final result = await solver.solve(List<int>.filled(64, 0));
    expect(result, isNull);
    expect(solver.unavailable, isTrue);
  });

  test('undecodable image bytes -> null', () async {
    // Even if a model were present, non-image bytes must not crash the solver.
    final solver = OnnxCaptchaSolver(
      modelAsset: 'assets/models/does_not_exist.onnx',
    );
    final result = await solver.solve([1, 2, 3]);
    expect(result, isNull);
  });
}
