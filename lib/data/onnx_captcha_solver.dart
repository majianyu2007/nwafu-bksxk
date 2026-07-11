/// On-device captcha OCR using a bundled ONNX model.
///
/// The model (`assets/models/captcha.onnx`) is a small CNN with 4 positional
/// classification heads, trained on synthetic 4-char alphanumeric captchas that
/// mimic the common noisy style. It takes a 1×1×48×128 grayscale tensor
/// (normalized to [-1,1]) and emits logits shaped [1, 4, 36] over the charset
/// (digits + uppercase). We argmax each position and gate on mean confidence.
///
/// Accuracy on the school's exact captcha style can only be confirmed on the
/// campus network, so this is wired as a best-effort default: on low confidence
/// the caller refreshes the captcha and tries again, and manual entry always
/// remains available. The whole thing is behind [CaptchaSolver] so a better
/// model (or a remote solver) can replace it without touching the app.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'captcha.dart';

class OnnxCaptchaSolver implements CaptchaSolver {
  OnnxCaptchaSolver({
    this.modelAsset = 'assets/models/captcha.onnx',
    this.charsetAsset = 'assets/models/captcha_charset.txt',
    this.inputWidth = 128,
    this.inputHeight = 48,
    this.numChars = 4,
    this.minConfidence = 0.5,
    this.caseInsensitive = true,
  });

  final String modelAsset;
  final String charsetAsset;
  final int inputWidth;
  final int inputHeight;
  final int numChars;

  /// Reject predictions whose mean per-char probability is below this, so we
  /// don't waste a vtoken on a low-confidence guess.
  final double minConfidence;

  /// The charset is uppercase; if the server's captcha is case-insensitive we
  /// keep the model's uppercase output. (Kept as a flag for future tuning.)
  final bool caseInsensitive;

  OrtSession? _session;
  String _charset = '';
  bool _initFailed = false;
  Completer<void>? _initing;

  /// True once we've tried to load the model and it wasn't there / failed. Lets
  /// the UI know OCR is unavailable so it can stay in manual mode.
  bool get unavailable => _initFailed;

  /// Lazily loads the ONNX runtime + model + charset. Safe to call repeatedly.
  Future<void> _ensureInit() async {
    if (_session != null || _initFailed) return;
    if (_initing != null) return _initing!.future;
    final c = Completer<void>();
    _initing = c;
    try {
      OrtEnv.instance.init();
      _charset = (await rootBundle.loadString(charsetAsset)).trim();
      final raw = await rootBundle.load(modelAsset);
      final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
      final opts = OrtSessionOptions();
      _session = OrtSession.fromBuffer(bytes, opts);
    } catch (_) {
      _initFailed = true;
    } finally {
      c.complete();
      _initing = null;
    }
  }

  @override
  Future<String?> solve(List<int> imageBytes) async {
    await _ensureInit();
    final session = _session;
    if (session == null || _charset.isEmpty) return null;

    final input = _preprocess(imageBytes);
    if (input == null) return null;

    OrtValueTensor? tensor;
    OrtRunOptions? runOptions;
    try {
      tensor = OrtValueTensor.createTensorWithDataList(
        input,
        [1, 1, inputHeight, inputWidth],
      );
      runOptions = OrtRunOptions();
      final outputs = session.run(runOptions, {'image': tensor});
      final logits = outputs.first?.value; // [1, numChars, charsetLen]
      for (final o in outputs) {
        o?.release();
      }
      if (logits is! List) return null;
      return _decode(logits);
    } catch (_) {
      return null;
    } finally {
      tensor?.release();
      runOptions?.release();
    }
  }

  /// Decodes the captcha bytes, resizes to the model input, grayscales, and
  /// normalizes to [-1,1]. Returns a flat Float32List of length H*W.
  Float32List? _preprocess(List<int> bytes) {
    img.Image? im;
    try {
      im = img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
    if (im == null) return null;
    final resized = img.copyResize(im, width: inputWidth, height: inputHeight);
    final out = Float32List(inputHeight * inputWidth);
    var i = 0;
    for (var y = 0; y < inputHeight; y++) {
      for (var x = 0; x < inputWidth; x++) {
        final p = resized.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
        out[i++] = (lum - 0.5) / 0.5;
      }
    }
    return out;
  }

  /// Argmax each of the [numChars] positional heads; gate on mean confidence.
  /// [logits3d] is [1][numChars][charsetLen].
  String? _decode(List<dynamic> logits3d) {
    final rows = logits3d[0];
    if (rows is! List || rows.isEmpty) return null;

    final chars = <String>[];
    var confSum = 0.0;
    for (final rowDyn in rows) {
      final row = (rowDyn as List).cast<double>();
      var maxIdx = 0;
      var maxVal = row[0];
      for (var k = 1; k < row.length; k++) {
        if (row[k] > maxVal) {
          maxVal = row[k];
          maxIdx = k;
        }
      }
      if (maxIdx < 0 || maxIdx >= _charset.length) return null;
      chars.add(_charset[maxIdx]);
      confSum += _softmax(row, maxIdx);
    }
    final text = chars.join();
    final meanConf = confSum / chars.length;
    if (meanConf < minConfidence) return null;
    return text;
  }

  double _softmax(List<double> logits, int idx) {
    var maxLogit = logits[0];
    for (final l in logits) {
      if (l > maxLogit) maxLogit = l;
    }
    var sum = 0.0;
    for (final l in logits) {
      sum += math.exp(l - maxLogit);
    }
    return math.exp(logits[idx] - maxLogit) / (sum == 0 ? 1 : sum);
  }

  void dispose() {
    _session?.release();
    _session = null;
  }
}
