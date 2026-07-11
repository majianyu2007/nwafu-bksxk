/// Native (io) implementation: the ONNX-backed captcha OCR solver.
library;

import 'captcha.dart';
import 'onnx_captcha_solver.dart';

CaptchaSolver makePlatformCaptchaSolver() => OnnxCaptchaSolver();

void disposePlatformCaptchaSolver(CaptchaSolver solver) {
  if (solver is OnnxCaptchaSolver) solver.dispose();
}
