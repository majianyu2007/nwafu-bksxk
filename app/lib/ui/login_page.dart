/// Login screen: fast captcha entry, saved-account quick switch, remember me.
///
/// Speed touches: the captcha image is fetched as soon as the screen mounts (and
/// again immediately after any failure), the captcha field autofocuses, and
/// entering the expected number of characters submits automatically so the user
/// never taps a button during a rush.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import '../data/auth_service.dart';
import '../data/storage.dart';
import 'diagnostics_page.dart';

/// Visual state of the OCR captcha recognizer.
enum OcrStatus { idle, recognizing, recognized, failed }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _loginCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _captchaFocus = FocusNode();

  CaptchaChallenge? _challenge;
  bool _loadingCaptcha = false;
  bool _submitting = false;
  bool _remember = true;
  bool _obscure = true;
  bool _showCampusHint = false;
  String? _error;

  /// Whether to auto-recognize captchas via OCR. User can turn it off to type.
  bool _autoRecognize = true;
  OcrStatus _ocrStatus = OcrStatus.idle;
  int _ocrRetries = 0;
  static const _maxOcrRetries = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillActiveAccount();
      _maybePromptWebBridge();
      _refreshCaptcha();
    });
  }

  /// On the web build, if the companion CORS bridge userscript isn't installed,
  /// direct requests to the school server will be blocked. Prompt the user to
  /// install it. Native builds skip this entirely.
  void _maybePromptWebBridge() {
    if (!isWebRuntime || isWebBridgeReady) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('网页版需要安装配套脚本'),
        content: const Text(
          '由于浏览器跨域限制，网页版需要一个配套的浏览器脚本才能访问校园网选课接口。\n\n'
          '请：\n'
          '1. 安装篡改猴 (Tampermonkey) 或脚本猫 (ScriptCat) 扩展；\n'
          '2. 安装「西农本科选课 · Web 跨域桥接」脚本；\n'
          '3. 刷新本页面。\n\n'
          '桌面端 / 手机端 App 无需此步骤。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('我知道了')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _pwCtrl.dispose();
    _captchaCtrl.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  void _prefillActiveAccount() {
    final storage = ref.read(storageProvider);
    final active = storage.activeAccount();
    if (active != null) {
      _loginCtrl.text = active.loginName;
    }
  }

  Future<void> _refreshCaptcha({bool autoRecognize = true}) async {
    setState(() {
      _loadingCaptcha = true;
      _challenge = null;
      _captchaCtrl.clear();
      _ocrStatus = _autoRecognize ? OcrStatus.recognizing : OcrStatus.idle;
    });
    try {
      final challenge = await ref.read(sessionProvider.notifier).fetchCaptcha();
      if (!mounted) return;
      setState(() => _challenge = challenge);

      // Auto-recognize the captcha so the user never types during a rush.
      if (autoRecognize && _autoRecognize) {
        final solver = ref.read(captchaSolverProvider);
        final guess = await solver.solve(challenge.imageBytes);
        if (!mounted) return;
        if (guess != null && guess.isNotEmpty) {
          _captchaCtrl.text = guess;
          setState(() => _ocrStatus = OcrStatus.recognized);
          // Auto-submit if we also have credentials — full hands-free login.
          if (_loginCtrl.text.trim().isNotEmpty && _pwCtrl.text.isNotEmpty) {
            _submit(fromOcr: true);
          }
        } else {
          setState(() => _ocrStatus = OcrStatus.failed);
          _captchaFocus.requestFocus();
        }
      } else {
        _captchaFocus.requestFocus();
      }
    } on AppError catch (e) {
      if (!mounted) return;
      // A captcha fetch failing is the first signal of an unreachable backend —
      // surface the campus-network hint prominently.
      setState(() {
        _error = e.hint != null ? '${e.message}：${e.hint}' : e.message;
        _showCampusHint = e.kind == AppErrorKind.campusNetwork || e.kind == AppErrorKind.timeout;
        _ocrStatus = OcrStatus.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '验证码加载失败，请点击刷新';
        _ocrStatus = OcrStatus.idle;
      });
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
    final loginName = _loginCtrl.text.trim();
    final password = _pwCtrl.text;
    final code = _captchaCtrl.text.trim();
    if (loginName.isEmpty || password.isEmpty) {
      if (!fromOcr) setState(() => _error = '请输入学号和密码');
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
      await ref.read(sessionProvider.notifier).login(
            loginName: loginName,
            password: password,
            verifyCode: code,
            vtoken: challenge.vtoken,
            remember: _remember,
          );
      ref.read(accountsProvider.notifier).refresh();
      // Navigation happens reactively via main.dart's home switch.
    } on LoginException catch (e) {
      if (!mounted) return;
      if (e.code == '3') {
        // Wrong captcha (often OCR misread). Auto-refresh + re-recognize + retry
        // — the user shouldn't have to intervene during a rush. Bounded so a
        // persistently-failing OCR doesn't loop forever.
        _ocrRetries++;
        if (_ocrRetries <= _maxOcrRetries) {
          setState(() => _error = null);
          await _refreshCaptcha();
          return;
        }
        setState(() => _error = '验证码多次识别失败，请手动输入');
        _ocrRetries = 0;
        await _refreshCaptcha(autoRecognize: false);
      } else {
        // Wrong credentials or other — stop and show it; refresh the captcha.
        setState(() => _error = e.message);
        _ocrRetries = 0;
        await _refreshCaptcha(autoRecognize: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      await _refreshCaptcha(autoRecognize: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onCaptchaChanged(String value) {
    // Manual typing no longer auto-submits — the user presses 登录 (or OCR does
    // it automatically). This avoids firing a login on every keystroke.
    if (_ocrStatus != OcrStatus.idle) {
      setState(() => _ocrStatus = OcrStatus.idle);
    }
  }

  Future<void> _useSavedAccount(Account account) async {
    _loginCtrl.text = account.loginName;
    final pw = await ref.read(storageProvider).passwordFor(account.id);
    if (pw != null) {
      _pwCtrl.text = pw;
      _captchaFocus.requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider);
    final phase = ref.watch(sessionProvider.select((s) => s.phase));
    final busy = _submitting || phase == AuthPhase.loggingIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _Brand(scheme: scheme),
                  const SizedBox(height: 28),
                  if (accounts.isNotEmpty) ...[
                    _SavedAccounts(
                      accounts: accounts,
                      onPick: _useSavedAccount,
                      onRemove: (a) => ref.read(accountsProvider.notifier).remove(a.id),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _loginCtrl,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CaptchaRow(
                    challenge: _challenge,
                    loading: _loadingCaptcha,
                    controller: _captchaCtrl,
                    focusNode: _captchaFocus,
                    ocrStatus: _ocrStatus,
                    onRefresh: () => _refreshCaptcha(),
                    onChanged: _onCaptchaChanged,
                    onSubmit: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? true),
                      ),
                      const Text('记住此账号'),
                      const Spacer(),
                      const Text('自动识别', style: TextStyle(fontSize: 13)),
                      Switch(
                        value: _autoRecognize,
                        onChanged: (v) {
                          setState(() => _autoRecognize = v);
                          if (v) _refreshCaptcha();
                        },
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_showCampusHint) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.wifi_off, color: scheme.onTertiaryContainer, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('连不上选课服务器？',
                                    style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text('本系统仅在校园网内可用。请连接校园网，或用 VPN 接入校园网后重试。',
                                    style: TextStyle(color: scheme.onTertiaryContainer, fontSize: 13)),
                                TextButton(
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
                                  ),
                                  child: const Text('打开连接诊断'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(
                            height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 8),
                  const _SettingsShortcut(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.bolt, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 16),
        Text('西农本科选课', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('选课 · 抢课，快人一步', style: TextStyle(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SavedAccounts extends StatelessWidget {
  const _SavedAccounts({required this.accounts, required this.onPick, required this.onRemove});
  final List<Account> accounts;
  final void Function(Account) onPick;
  final void Function(Account) onRemove;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in accounts)
            InputChip(
              avatar: const Icon(Icons.account_circle, size: 18),
              label: Text(a.displayName),
              onPressed: () => onPick(a),
              onDeleted: () => onRemove(a),
            ),
        ],
      ),
    );
  }
}

class _CaptchaRow extends StatelessWidget {
  const _CaptchaRow({
    required this.challenge,
    required this.loading,
    required this.controller,
    required this.focusNode,
    required this.ocrStatus,
    required this.onRefresh,
    required this.onChanged,
    required this.onSubmit,
  });

  final CaptchaChallenge? challenge;
  final bool loading;
  final TextEditingController controller;
  final FocusNode focusNode;
  final OcrStatus ocrStatus;
  final VoidCallback onRefresh;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(6),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
            decoration: InputDecoration(
              labelText: '验证码',
              prefixIcon: const Icon(Icons.pin_outlined),
              suffixIcon: _ocrIndicator(scheme),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmit,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onRefresh,
          child: Container(
            height: 52,
            width: 120,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: loading
                ? const Center(
                    child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : challenge != null && challenge!.imageBytes.isNotEmpty
                    ? Image.memory(
                        Uint8List.fromList(challenge!.imageBytes),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Icon(Icons.refresh, color: scheme.onSurfaceVariant),
                      ),
          ),
        ),
      ],
    );
  }

  Widget? _ocrIndicator(ColorScheme scheme) {
    switch (ocrStatus) {
      case OcrStatus.recognizing:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case OcrStatus.recognized:
        return const Icon(Icons.auto_awesome, color: Colors.green, size: 20);
      case OcrStatus.failed:
        return Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant, size: 20);
      case OcrStatus.idle:
        return null;
    }
  }
}

class _SettingsShortcut extends ConsumerWidget {
  const _SettingsShortcut();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: () => ref.read(themeControllerProvider.notifier).cycleMode(),
          icon: Icon(switch (theme.mode) {
            ThemeMode.light => Icons.light_mode_outlined,
            ThemeMode.dark => Icons.dark_mode_outlined,
            ThemeMode.system => Icons.brightness_auto_outlined,
          }),
          label: Text(switch (theme.mode) {
            ThemeMode.light => '浅色',
            ThemeMode.dark => '深色',
            ThemeMode.system => '跟随系统',
          }),
        ),
      ],
    );
  }
}
