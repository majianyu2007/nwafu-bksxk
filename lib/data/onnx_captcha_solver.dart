/// On-device captcha OCR, migrated from the AutoVerify Chrome extension
/// (author-permitted). AutoVerify bundles a quantized ddddocr-style CRNN whose
/// ArgMax is baked into the graph and whose LSTM is the integer
/// `DynamicQuantizeLSTM` contrib op — which, unlike the float LSTM, computes
/// consistently on flutter_onnxruntime's native runtime (verified: identical
/// non-blank indices to onnxruntime 1.27 in Python). That's what makes an
/// accurate on-device solver possible here.
///
/// Pipeline:
///   - add horizontal whitespace for edge characters, then resize to height 64,
///     preserve aspect ratio, and convert to grayscale,
///   - normalize (gray/255 - 0.5)/0.5  → [-1,1], tensor [1,1,64,W],
///   - model output `output` is [1, seqlen] of int64 class indices,
///   - CTC-collapse (drop consecutive repeats and blank=index 0), map through
///     the 8210-entry charset (index 0 = "").
///
/// Behind [CaptchaSolver]; if the model is missing or inference fails, solve()
/// returns null and the UI falls back to manual entry.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'captcha.dart';

class OnnxCaptchaSolver implements CaptchaSolver {
  OnnxCaptchaSolver({
    this.modelAsset = 'assets/models/autoverify.onnx',
    this.charsetAsset = 'assets/models/autoverify_charset.json',
    this.targetHeight = 64,
    this.expectedLength = 4,
    this.restrictToAlnum = true,
  });

  final String modelAsset;
  final String charsetAsset;
  final int targetHeight;

  /// If >0, reject results whose length differs (the site's captcha is 4 chars).
  final int expectedLength;

  /// Captchas here are alphanumeric; drop any stray CJK class the model emits.
  final bool restrictToAlnum;

  OrtSession? _session;
  String _inputName = 'input1';
  List<String> _charset = const [];
  bool _initFailed = false;
  DateTime? _lastFailureAt;
  bool _disposed = false;
  int _inFlight = 0;
  OrtSession? _pendingClose;
  Completer<void>? _initing;

  bool get unavailable => _initFailed;

  /// Pre-loads the ONNX session + charset so the first real [solve] is fast.
  /// Called from main() at app start to hide cold-start model load behind the
  /// splash / login screen mount.
  @override
  Future<void> warmUp() => _ensureInit();

  Future<void> _ensureInit() async {
    if (_disposed || _session != null) return;
    if (_initFailed) {
      // Allow retrying after a cooldown instead of permanently locking out on
      // a transient asset/WASM fetch failure.
      final failedAt = _lastFailureAt;
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
        return;
      }
      _initFailed = false;
    }
    if (_initing != null) return _initing!.future;
    final c = Completer<void>();
    _initing = c;
    try {
      final csRaw = await rootBundle.loadString(charsetAsset);
      _charset = (jsonDecode(csRaw) as List).map((e) => e.toString()).toList();
      // On web, onnxruntime-web fetches the model by URL. Flutter serves bundled
      // assets under `assets/<declared-path>`, so the URL has a double prefix.
      // On native, createSessionFromAsset extracts the asset to a temp file.
      final session = kIsWeb
          ? await OnnxRuntime().createSession('assets/$modelAsset')
          : await OnnxRuntime().createSessionFromAsset(modelAsset);
      if (_disposed) {
        await session.close();
        return;
      }
      _session = session;
      _inputName =
          session.inputNames.isNotEmpty ? session.inputNames.first : 'input1';
    } catch (_) {
      _initFailed = true;
      _lastFailureAt = DateTime.now();
    } finally {
      c.complete();
      _initing = null;
    }
  }

  @override
  Future<String?> solve(List<int> imageBytes) async {
    if (_disposed || imageBytes.isEmpty) return null;
    await _ensureInit();
    final session = _session;
    if (_disposed || session == null || _charset.isEmpty) return null;

    final pre = _preprocess(imageBytes);
    if (pre == null || _disposed) return null;

    _inFlight++;
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      input =
          await OrtValue.fromList(pre.data, [1, 1, targetHeight, pre.width]);
      if (_disposed) return null;
      outputs = await session.run({_inputName: input});
      if (_disposed || outputs.isEmpty) return null;
      final indices = await outputs.values.first.asFlattenedList();
      return _decode(indices);
    } catch (_) {
      return null;
    } finally {
      if (input != null) {
        try {
          await input.dispose();
        } catch (_) {}
      }
      if (outputs != null) {
        for (final v in outputs.values) {
          try {
            await v.dispose();
          } catch (_) {}
        }
      }
      _inFlight--;
      if (_inFlight == 0 && _pendingClose != null) {
        final s = _pendingClose;
        _pendingClose = null;
        try {
          await s?.close();
        } catch (_) {}
      }
    }
  }

  /// Pad edge characters, resize to height 64, grayscale, normalize to [-1,1].
  _Pre? _preprocess(List<int> bytes) {
    img.Image? im;
    try {
      final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      im = img.decodeImage(raw);
    } catch (_) {
      return null;
    }
    if (im == null || im.height == 0) return null;
    // Rotated glyphs can touch the image boundary. Give the CRNN context on
    // both sides so it does not drop the first/last character before CTC decode.
    final padding = (im.height / 4).round().clamp(1, 500);
    final padded = img.Image(
      width: im.width + padding * 2,
      height: im.height,
      numChannels: 3,
    );
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, im, dstX: padding);
    im = padded;
    final width =
        (im.width * (targetHeight / im.height)).round().clamp(1, 2000);
    final resized = img.copyResize(im, width: width, height: targetHeight);
    final out = Float32List(targetHeight * width);
    var i = 0;
    const scale = 2.0 / 255.0;
    for (final p in resized) {
      final gray = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      out[i++] = gray * scale - 1.0;
    }
    return _Pre(out, width);
  }

  /// The model output is a flat sequence of class indices (ArgMax in-graph).
  /// CTC-collapse: drop consecutive repeats and blank (index 0), map to chars.
  String? _decode(List<dynamic> indices) {
    final buf = StringBuffer();
    var last = 0;
    for (final raw in indices) {
      final idx = (raw as num).toInt();
      if (idx == last) continue;
      last = idx;
      if (idx == 0) continue;
      if (idx < 0 || idx >= _charset.length) continue;
      final ch = _charset[idx];
      if (ch.isEmpty) continue;
      if (restrictToAlnum && !_isAlnum(ch)) continue;
      buf.write(ch);
    }
    final text = buf.toString();
    if (text.isEmpty) return null;
    if (expectedLength > 0 && text.length != expectedLength) return null;
    return text;
  }

  bool _isAlnum(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    _session = null;
    if (session == null) return;
    if (_inFlight > 0) {
      _pendingClose = session;
      return;
    }
    try {
      await session.close();
    } catch (_) {}
  }
}

class _Pre {
  _Pre(this.data, this.width);
  final Float32List data;
  final int width;
}
