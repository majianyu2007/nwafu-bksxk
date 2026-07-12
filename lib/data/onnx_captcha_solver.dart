/// On-device captcha OCR, migrated from the AutoVerify Chrome extension
/// (author-permitted). AutoVerify bundles a quantized ddddocr-style CRNN whose
/// ArgMax is baked into the graph and whose LSTM is the integer
/// `DynamicQuantizeLSTM` contrib op — which, unlike the float LSTM, computes
/// consistently on flutter_onnxruntime's native runtime (verified: identical
/// non-blank indices to onnxruntime 1.27 in Python). That's what makes an
/// accurate on-device solver possible here.
///
/// Pipeline (matches AutoVerify's model.js exactly):
///   - resize to height 64, width = round(w * 64/h), grayscale,
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
  Completer<void>? _initing;

  bool get unavailable => _initFailed;

  Future<void> _ensureInit() async {
    if (_session != null || _initFailed) return;
    if (_initing != null) return _initing!.future;
    final c = Completer<void>();
    _initing = c;
    try {
      final csRaw = await rootBundle.loadString(charsetAsset);
      _charset = (jsonDecode(csRaw) as List).map((e) => e.toString()).toList();
      final session = await OnnxRuntime().createSessionFromAsset(modelAsset);
      _session = session;
      _inputName = session.inputNames.isNotEmpty ? session.inputNames.first : 'input1';
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

    final pre = _preprocess(imageBytes);
    if (pre == null) return null;

    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      input = await OrtValue.fromList(pre.data, [1, 1, targetHeight, pre.width]);
      outputs = await session.run({_inputName: input});
      final indices = await outputs.values.first.asFlattenedList();
      return _decode(indices);
    } catch (_) {
      return null;
    } finally {
      await input?.dispose();
      if (outputs != null) {
        for (final v in outputs.values) {
          await v.dispose();
        }
      }
    }
  }

  /// Resize to height 64 keeping aspect ratio, grayscale, normalize to [-1,1].
  _Pre? _preprocess(List<int> bytes) {
    img.Image? im;
    try {
      im = img.decodeImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
    if (im == null || im.height == 0) return null;
    final width = (im.width * (targetHeight / im.height)).round().clamp(1, 2000);
    final resized = img.copyResize(im, width: width, height: targetHeight);
    final out = Float32List(targetHeight * width);
    var i = 0;
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < width; x++) {
        final p = resized.getPixel(x, y);
        final gray = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        out[i++] = (gray / 255.0 - 0.5) / 0.5;
      }
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
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
  }
}

class _Pre {
  _Pre(this.data, this.width);
  final Float32List data;
  final int width;
}
