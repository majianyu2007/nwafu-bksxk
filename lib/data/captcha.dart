/// Captcha handling built for speed.
///
/// The captcha only gates login and silent re-login — never the per-grab
/// volunteer.do call (which authenticates by the `token` header alone). So the
/// speed goal is: never let a login round-trip wait on a fresh captcha fetch or
/// on human typing when it can be avoided.
///
/// Two mechanisms:
///  - [CaptchaSolver]: pluggable answer source. [ManualCaptchaSolver] waits for
///    a user-entered value; [OcrCaptchaSolver] wraps an optional OCR function so
///    silent re-login can run headlessly. Solvers compose: OCR first, fall back
///    to manual.
///  - [CaptchaPrefetcher]: keeps a small pool of fetched-and-(optionally)-
///    pre-solved challenges warm, so the login screen shows an image instantly
///    and can even pre-fill the answer.
library;

import 'dart:async';

/// Answers a captcha image, or returns null if it cannot.
abstract class CaptchaSolver {
  Future<String?> solve(List<int> imageBytes);
}

/// A no-op solver used before OCR is configured; always returns null so callers
/// fall back to manual entry.
class NoopCaptchaSolver implements CaptchaSolver {
  const NoopCaptchaSolver();
  @override
  Future<String?> solve(List<int> imageBytes) async => null;
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
}

/// Tries solvers in order, returning the first non-null answer.
class ChainCaptchaSolver implements CaptchaSolver {
  ChainCaptchaSolver(this._solvers);
  final List<CaptchaSolver> _solvers;
  @override
  Future<String?> solve(List<int> imageBytes) async {
    for (final s in _solvers) {
      final a = await s.solve(imageBytes);
      if (a != null && a.isNotEmpty) return a;
    }
    return null;
  }
}

/// A challenge plus any pre-computed OCR guess.
class PrefetchedCaptcha {
  PrefetchedCaptcha({
    required this.vtoken,
    required this.imageBytes,
    this.guess,
    required this.fetchedAt,
  });
  final String vtoken;
  final List<int> imageBytes;

  /// OCR's best guess, if a solver was configured — lets the UI pre-fill.
  final String? guess;
  final DateTime fetchedAt;

  /// Challenges older than this are considered stale (server tokens expire).
  bool isStale(DateTime now, Duration ttl) => now.difference(fetchedAt) > ttl;
}

/// Fetches a challenge given nothing; returns token + image bytes.
typedef CaptchaFetcher = Future<PrefetchedCaptcha> Function();

/// Keeps a warm pool of captchas so login never waits on a network round-trip.
///
/// The pool is refilled in the background. Consumers call [take] to get an
/// instantly-available challenge (or await one if the pool is momentarily
/// empty). When an OCR solver is provided, entries arrive pre-solved.
class CaptchaPrefetcher {
  CaptchaPrefetcher({
    required CaptchaFetcher fetcher,
    int poolSize = 2,
    Duration ttl = const Duration(minutes: 2),
  })  : _fetcher = fetcher,
        _poolSize = poolSize,
        _ttl = ttl;

  final CaptchaFetcher _fetcher;
  final int _poolSize;
  final Duration _ttl;

  final List<PrefetchedCaptcha> _pool = [];
  final List<Completer<PrefetchedCaptcha>> _waiters = [];
  bool _refilling = false;
  bool _disposed = false;

  /// Warms the pool. Call on entering the login screen.
  void start() {
    _refill();
  }

  /// Returns a ready challenge immediately when the pool is non-empty, else
  /// awaits the next fetched one. Triggers a background refill.
  Future<PrefetchedCaptcha> take({DateTime? now}) {
    final current = now ?? _clockNow();
    // Drop stale entries.
    _pool.removeWhere((c) => c.isStale(current, _ttl));
    if (_pool.isNotEmpty) {
      final c = _pool.removeAt(0);
      _refill();
      return Future.value(c);
    }
    final completer = Completer<PrefetchedCaptcha>();
    _waiters.add(completer);
    _refill();
    return completer.future;
  }

  Future<void> _refill() async {
    if (_disposed || _refilling) return;
    _refilling = true;
    try {
      while (!_disposed && (_pool.length + _inflightTarget()) < _neededCount()) {
        final c = await _fetcher();
        if (_disposed) return;
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(c);
        } else {
          _pool.add(c);
        }
      }
    } catch (_) {
      // Swallow — a failed prefetch just means the UI fetches on demand.
    } finally {
      _refilling = false;
    }
  }

  int _neededCount() => _poolSize + _waiters.length;
  int _inflightTarget() => 0;

  DateTime _clockNow() => DateTime.now();

  void dispose() {
    _disposed = true;
    for (final w in _waiters) {
      if (!w.isCompleted) w.completeError(StateError('prefetcher disposed'));
    }
    _waiters.clear();
    _pool.clear();
  }
}
