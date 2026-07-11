/// Web/stub implementation: no ONNX (dart:ffi unavailable on web). Manual entry.
library;

import 'captcha.dart';

CaptchaSolver makePlatformCaptchaSolver() => const NoopCaptchaSolver();

void disposePlatformCaptchaSolver(CaptchaSolver solver) {}
