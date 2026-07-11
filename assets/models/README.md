# Captcha OCR model

- `captcha.onnx` — CNN with 4 positional heads, input 1×1×48×128 grayscale
  (normalized to [-1,1]), output logits [1,4,36].
- `captcha_charset.txt` — the 36-char alphabet (digits + uppercase), index order
  matches the model's output classes.

Trained on synthetic captchas (see repo tooling). Replace with a model trained
on real samples for higher accuracy on the school's specific style.
