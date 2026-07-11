# Captcha OCR model training

The bundled captcha recognizer (`assets/models/captcha.onnx`) is a small CNN with
4 positional classification heads over a 36-char alphabet (digits + uppercase).
It takes a `1×1×48×128` grayscale tensor (normalized to `[-1,1]`) and outputs
logits shaped `[1, 4, 36]`.

## Why synthetic training

The NWAFU course system is **campus-network-only**, so real captcha samples can't
be collected off-network. These scripts generate synthetic 4-char captchas that
mimic the common noisy style (rotated glyphs, background dots, interference lines,
blur) using system fonts, and train the model on them. The in-app auto-refresh +
retry loop compensates for imperfect accuracy, and the solver is pluggable — swap
in a model trained on real samples for higher accuracy.

## Reproduce

Requires Python with `torch`, `onnx`, `pillow`, `numpy` (CPU is fine):

```bash
python3 -m venv venv && ./venv/bin/pip install torch onnx pillow numpy

# 1. Generate a fixed dataset (once; caches to /tmp/captcha_data.npz)
./venv/bin/python generate_dataset.py 40000

# 2. Train (writes /tmp/captcha.onnx + /tmp/captcha_charset.txt)
EPOCHS=18 ./venv/bin/python train.py

# 3. Copy the outputs into the app
cp /tmp/captcha.onnx ../../assets/models/captcha.onnx
cp /tmp/captcha_charset.txt ../../assets/models/captcha_charset.txt
```

## IMPORTANT: ONNX IR version

The `onnxruntime` Dart package (1.4.x) supports **ONNX IR version ≤ 9**. PyTorch's
exporter defaults to opset 18 → IR 10, which fails to load at runtime with
`Unsupported model IR version: 10`. `train.py` downgrades the exported model to
IR 9 after export:

```python
import onnx
m = onnx.load('/tmp/captcha.onnx'); m.ir_version = 9; onnx.save(m, '/tmp/captcha.onnx')
```

Keep this when re-exporting, or the app will fall back to manual captcha entry.

## Model contract (must match `lib/data/onnx_captcha_solver.dart`)

- input name `image`, shape `[batch,1,48,128]`, float32, normalized `(lum/255-0.5)/0.5`
- output name `logits`, shape `[batch,4,36]`
- `captcha_charset.txt` = the 36 chars in class-index order (`0-9A-Z`)
