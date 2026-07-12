/// Web implementation: enable the same on-device ONNX captcha OCR as native.
///
/// flutter_onnxruntime supports web (onnxruntime-web / WASM), so the web build
/// can auto-recognize captchas just like the desktop/mobile client — provided
/// `web/index.html` loads onnxruntime-web (window.ort) and its wasm. If ort is
/// not present, the solver degrades to null and the UI falls back to manual.
library;

import 'captcha.dart';
import 'onnx_captcha_solver.dart';

CaptchaSolver makePlatformCaptchaSolver() => OnnxCaptchaSolver();

void disposePlatformCaptchaSolver(CaptchaSolver solver) {
  if (solver is OnnxCaptchaSolver) solver.dispose();
}
