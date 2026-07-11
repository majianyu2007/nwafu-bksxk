/// Factory for the platform captcha solver, conditionally imported so the
/// native-only ONNX runtime (dart:ffi) never reaches the web build.
///
/// On native platforms this returns the ONNX-backed solver; on web it returns a
/// no-op solver (web can't run dart:ffi, and the web build uses manual captcha
/// entry anyway).
library;

import 'captcha_solver_factory_stub.dart'
    if (dart.library.io) 'captcha_solver_factory_io.dart';

import 'captcha.dart';

/// Creates the best captcha solver for the current platform.
CaptchaSolver createCaptchaSolver() => makePlatformCaptchaSolver();

/// Disposes a solver if it holds native resources (no-op for the web solver).
void disposeCaptchaSolver(CaptchaSolver solver) => disposePlatformCaptchaSolver(solver);
