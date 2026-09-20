/// Shown by the shell when an account's session was dropped by the server and
/// the silent re-login could not recover it. The saved password is filled in,
/// so usually only the captcha stands between the user and their session, and
/// the recogniser fills that in too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/errors.dart';
import '../data/auth_service.dart';
import 'login_page.dart';

class ReloginDialog extends ConsumerStatefulWidget {
  const ReloginDialog({super.key, required this.accountId});
  final String accountId;

  @override
  ConsumerState<ReloginDialog> createState() => _ReloginDialogState();
}

class _ReloginDialogState extends ConsumerState<ReloginDialog> {
  final _pwCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _captchaFocus = FocusNode();

  CaptchaChallenge? _challenge;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  OcrStatus _ocr = OcrStatus.idle;
  int _ocrRetries = 0;
  String? _error;
  static const _maxOcrRetries = 3;

  SessionController get _controller =>
      ref.read(sessionControllerProvider(widget.accountId).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _captchaCtrl.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final pw = await ref.read(storageProvider).passwordFor(widget.accountId);
    if (!mounted) return;
    if (pw != null && pw.isNotEmpty) _pwCtrl.text = pw;
    await _refreshCaptcha();
  }

  Future<void> _refreshCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _challenge = null;
      _captchaCtrl.clear();
      _ocr = OcrStatus.idle;
    });
    try {
      final challenge = await _controller.fetchCaptcha();
      if (!mounted) return;
      setState(() => _challenge = challenge);
      if (ref.read(storageProvider).autoOcr()) {
        setState(() => _ocr = OcrStatus.recognizing);
        final guess =
            await ref.read(captchaSolverProvider).solve(challenge.imageBytes);
        if (!mounted) return;
        if (guess != null && guess.isNotEmpty) {
          _captchaCtrl.text = guess;
          setState(() => _ocr = OcrStatus.recognized);
          if (_pwCtrl.text.isNotEmpty) {
            await _submit(fromOcr: true);
            return;
          }
        } else {
          setState(() => _ocr = OcrStatus.failed);
        }
      }
      _captchaFocus.requestFocus();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(
          () => _error = e.hint != null ? '${e.message}：${e.hint}' : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '验证码加载失败，点击图片重试');
    } finally {
      if (mounted) setState(() => _loadingCaptcha = false);
    }
  }

  Future<void> _submit({bool fromOcr = false}) async {
    if (_submitting) return;
    final challenge = _challenge;
    if (challenge == null) {
      await _refreshCaptcha();
      return;
    }
    final password = _pwCtrl.text;
    final code = _captchaCtrl.text.trim();
    if (password.isEmpty) {
      if (!fromOcr) setState(() => _error = '请输入密码');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      _captchaFocus.requestFocus();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _controller.relogin(
        password: password,
        verifyCode: code,
        vtoken: challenge.vtoken,
      );
      if (mounted) Navigator.of(context).pop();
    } on LoginException catch (e) {
      if (!mounted) return;
      if (e.code == '3' && fromOcr && _ocrRetries < _maxOcrRetries) {
        _ocrRetries++;
        await _refreshCaptcha();
        return;
      }
      setState(() => _error = e.message);
      await _refreshCaptcha();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is AppError
          ? (e.hint != null ? '${e.message}：${e.hint}' : e.message)
          : '$e');
      await _refreshCaptcha();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _logout() async {
    await leaveAccount(ref, widget.accountId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionControllerProvider(widget.accountId));
    final who = session.displayName;

    return AlertDialog(
      title: const Text('登录已失效'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$who 的会话被服务器结束了，通常是同一账号在别处登录，或长时间无操作。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (session.error != null && session.error!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(session.error!,
                    style: TextStyle(
                        color: scheme.onErrorContainer, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _pwCtrl,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 10),
            CaptchaRow(
              challenge: _challenge,
              loading: _loadingCaptcha,
              controller: _captchaCtrl,
              focusNode: _captchaFocus,
              ocrStatus: _ocr,
              onRefresh: _refreshCaptcha,
              onChanged: (_) {},
              onSubmit: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color: scheme.onErrorContainer, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _logout,
          child: const Text('退出该账号'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('重新登录'),
        ),
      ],
    );
  }
}
