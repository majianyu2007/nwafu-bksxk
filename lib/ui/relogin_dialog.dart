/// Shown by the shell when the server dropped the session and the silent
/// re-login (captcha OCR, a few attempts) did not recover it.
///
/// The account is fixed to the signed-in one; the saved password is filled in
/// when available, so usually only the captcha stands between the user and
/// their restored session (and OCR fills that too). Success closes the dialog
/// and the session controller restarts the monitor if it had been running.
library;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/errors.dart';
import '../data/auth_service.dart';

class ReloginDialog extends ConsumerStatefulWidget {
  const ReloginDialog({super.key});

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
  bool _ocrBusy = false;
  bool _passwordSaved = false;
  int _ocrRetries = 0;
  String? _error;
  static const _maxOcrRetries = 3;

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
    final account = ref.read(sessionProvider).account;
    if (account != null) {
      final pw = await ref.read(storageProvider).passwordFor(account.id);
      if (!mounted) return;
      if (pw != null && pw.isNotEmpty) {
        _pwCtrl.text = pw;
        _passwordSaved = true;
      }
    }
    await _refreshCaptcha();
  }

  Future<void> _refreshCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _challenge = null;
      _captchaCtrl.clear();
    });
    try {
      final challenge = await ref.read(sessionProvider.notifier).fetchCaptcha();
      if (!mounted) return;
      setState(() => _challenge = challenge);
      final storage = ref.read(storageProvider);
      if (storage.autoOcr()) {
        setState(() => _ocrBusy = true);
        final guess =
            await ref.read(captchaSolverProvider).solve(challenge.imageBytes);
        if (!mounted) return;
        setState(() => _ocrBusy = false);
        if (guess != null && guess.isNotEmpty) {
          _captchaCtrl.text = guess;
          if (_pwCtrl.text.isNotEmpty) {
            await _submit(fromOcr: true);
            return;
          }
        }
      }
      _captchaFocus.requestFocus();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(
          () => _error = e.hint != null ? '${e.message}：${e.hint}' : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '验证码加载失败，请点击刷新');
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
      await ref.read(sessionProvider.notifier).relogin(
            password: password,
            verifyCode: code,
            vtoken: challenge.vtoken,
          );
      if (mounted) Navigator.of(context).pop();
    } on LoginException catch (e) {
      if (!mounted) return;
      if (e.code == '3' && fromOcr && _ocrRetries < _maxOcrRetries) {
        // OCR misread: one more captcha, still hands-free, bounded so a
        // persistently unreadable captcha lands with the user.
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
    await ref.read(sessionProvider.notifier).logout();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(sessionProvider);
    final attempts = ref.watch(silentReloginAttemptsProvider);
    final who = session.account?.displayName ?? session.student?.name ?? '';
    final code =
        session.account?.loginName ?? session.student?.studentCode ?? '';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_reset, color: scheme.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('登录已失效，请重新登录')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              attempts == 0
                  ? '学校服务器已结束当前会话（例如在别处登录了同一账号）。'
                  : attempts < 0
                      ? '学校服务器已结束当前会话（例如在别处登录了同一账号），后台自动重登被账号错误终止。'
                      : '学校服务器已结束当前会话（例如在别处登录了同一账号），后台自动重登 $attempts 次仍未成功。',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        [who, code].where((s) => s.isNotEmpty).join(' · '))),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pwCtrl,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: _passwordSaved ? '已填入保存的密码' : null,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _captchaCtrl,
                    focusNode: _captchaFocus,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(6),
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '验证码',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      suffixIcon: _ocrBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: '点击刷新验证码',
                  child: InkWell(
                    onTap: _loadingCaptcha ? null : _refreshCaptcha,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 52,
                      width: 120,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _loadingCaptcha
                          ? const Center(
                              child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : (_challenge != null &&
                                  _challenge!.imageBytes.isNotEmpty)
                              ? Image.memory(
                                  Uint8List.fromList(_challenge!.imageBytes),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Center(
                                  child: Icon(Icons.refresh,
                                      color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ],
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
          child: const Text('退出登录'),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login, size: 18),
          label: const Text('重新登录'),
        ),
      ],
    );
  }
}
