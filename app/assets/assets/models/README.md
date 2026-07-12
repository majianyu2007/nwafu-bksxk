# Captcha OCR model

- `autoverify.onnx` — a quantized ddddocr-style CRNN captcha recognizer, migrated
  from the AutoVerify Chrome extension (used with the author's permission). Input
  `input1` is `[1,1,64,W]` float32, grayscale, normalized `(gray/255-0.5)/0.5`
  (→ [-1,1]); output `output` is `[1,seqlen]` int64 class indices (ArgMax is baked
  into the graph). The quantized `DynamicQuantizeLSTM` op computes consistently on
  flutter_onnxruntime's native runtime (verified identical non-blank indices to
  onnxruntime 1.27 in Python).
- `autoverify_charset.json` — the 8210-entry charset (index 0 = "" = CTC blank).

Decode: drop consecutive-duplicate indices and blank(0), map through the charset,
keep alphanumerics. See lib/data/onnx_captcha_solver.dart.
