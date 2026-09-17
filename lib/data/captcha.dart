/// Captcha handling built for speed.
///
/// The captcha only gates login and silent re-login — never the per-grab
/// volunteer.do call (which authenticates by the `token` header alone). So the
/// speed goal is: never let a login round-trip wait on a fresh captcha fetch or
/// on human typing when it can be avoided.
///
/// [CaptchaSolver] is the pluggable answer source: the on-device ONNX model
/// (onnx_captcha_solver.dart), a user-configured HTTP OCR API
/// (http_ocr_solver.dart), or [OcrCaptchaSolver] wrapping any callback (used
/// by tests). A null answer means "fall back to manual entry".
library;

/// Answers a captcha image, or returns null if it cannot.
abstract class CaptchaSolver {
  Future<String?> solve(List<int> imageBytes);

  /// Pre-load any model/session so the first real solve is fast. Default
  /// no-op; the ONNX solver overrides to load the model into memory ahead of
  /// the login screen mount.
  Future<void> warmUp() async {}
}

/// Wraps a user-supplied OCR callback. The callback can call a bundled model, a
/// local isolate, or a remote service — the app stays agnostic. Returns null on
/// low confidence so we don't submit a guess that burns the vtoken.
class OcrCaptchaSolver implements CaptchaSolver {
  OcrCaptchaSolver(this._ocr, {this.expectedLength = 4});

  /// Returns recognised text (already trimmed/normalised) or null.
  final Future<String?> Function(List<int> imageBytes) _ocr;

  /// If set (>0), answers whose length differs are rejected as low-confidence.
  final int expectedLength;

  @override
  Future<String?> solve(List<int> imageBytes) async {
    final raw = await _ocr(imageBytes);
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    if (expectedLength > 0 && cleaned.length != expectedLength) return null;
    return cleaned;
  }
  @override
  Future<void> warmUp() async {}
}
