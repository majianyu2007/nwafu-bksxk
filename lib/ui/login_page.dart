/// Login screen: captcha auto-recognition, saved-account chips, remember me.
///
/// The captcha is fetched the moment the screen mounts, recognised by the
/// bundled model, and the login is submitted hands-free when the account and
/// password are already filled in. A wrong captcha refetches and retries a few
/// times before asking the user to type it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/errors.dart';
import '../core/constants.dart';
import '../core/web_env.dart';
import '../data/auth_service.dart';
import '../data/storage.dart';
import 'diagnostics_page.dart';
import 'settings_page.dart';
import 'update_widgets.dart';

/// Visual state of the OCR captcha recognizer.
enum OcrStatus { idle, warming, recognizing, recognized, failed }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.addingAccount = false});

  /// Opened from a signed-in shell to sign in a second account; closes on
  /// success instead of replacing the shell.
  final bool addingAccount;

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

  bool _autoRecognize = true;
  OcrStatus _ocrStatus = OcrStatus.idle;
  int _ocrRetries = 0;
  static const _maxOcrRetries = 4;

  @override
  void initState() {
    super.initState();
    _autoRecognize = ref.read(storageProvider).autoOcr();
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
    final configured = Uri.tryParse(ref.read(storageProvider).origin());
    if (configured?.host != Uri.parse(Env.defaultOrigin).host) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('网页版需要安装配套脚本'),
        content: const Text(
          '浏览器不允许网页直接访问校园网选课接口，需要一个配套脚本转发请求。\n\n'
          '1. 安装 Tampermonkey 或 ScriptCat 扩展\n'
          '2. 安装「西农本科选课 Web 跨域桥接」脚本\n'
          '3. 刷新本页面\n\n'
          '桌面端和手机端不需要此步骤。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
          const FilledButton(
            onPressed: openWebBridgeInstaller,
            child: Text('安装脚本'),
          ),
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
    if (widget.addingAccount) return;
    final storage = ref.read(storageProvider);
    final active = storage.activeAccount();
    if (active != null) _useSavedAccount(active);
  }

  Future<void> _refreshCaptcha({bool autoRecognize = true}) async {
    setState(() {
      _loadingCaptcha = true;
      _challenge = null;
      _captchaCtrl.clear();
      _ocrStatus = _autoRecognize ? OcrStatus.warming : OcrStatus.idle;
    });
    try {
      final challenge = await ref.read(anonymousAuthProvider).fetchCaptcha();
      if (!mounted) return;
      setState(() => _challenge = challenge);
      if (_ocrStatus == OcrStatus.warming) {
        setState(() => _ocrStatus = OcrStatus.recognizing);
      }
      if (autoRecognize && _autoRecognize) {
        final solver = ref.read(captchaSolverProvider);
        final guess = await solver.solve(challenge.imageBytes);
        if (!mounted) return;
        if (guess != null && guess.isNotEmpty) {
          _captchaCtrl.text = guess;
          setState(() => _ocrStatus = OcrStatus.recognized);
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
      setState(() {
        _error = e.hint != null ? '${e.message}：${e.hint}' : e.message;
        _showCampusHint = e.kind == AppErrorKind.campusNetwork ||
            e.kind == AppErrorKind.timeout;
        _ocrStatus = OcrStatus.idle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '验证码加载失败，点击图片重试';
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
    if (ref.read(signedInAccountsProvider).contains(loginName)) {
      setState(() => _error = '该账号已登录');
      return;
    }
    if (!widget.addingAccount &&
        !ref.read(multiAccountProvider) &&
        ref.read(signedInAccountsProvider).isNotEmpty) {
      // Single-account mode: replace the signed-in account.
      for (final id in [...ref.read(signedInAccountsProvider)]) {
        await leaveAccount(ref, id);
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider(loginName).notifier).login(
            loginName: loginName,
            password: password,
            verifyCode: code,
            vtoken: challenge.vtoken,
            remember: _remember,
          );
      ref.read(accountsProvider.notifier).refresh();
      if (!mounted) return;
      enterAccount(ref, loginName);
      if (widget.addingAccount) Navigator.of(context).pop();
    } on LoginException catch (e) {
      if (!mounted) return;
      if (e.code == '3') {
        // Wrong captcha, usually an OCR misread: fetch another and retry
        // hands-free a few times before asking the user to type it.
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
        setState(() => _error = e.message);
        _ocrRetries = 0;
        await _refreshCaptcha(autoRecognize: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is AppError
          ? (e.hint != null ? '${e.message}：${e.hint}' : e.message)
          : '$e');
      await _refreshCaptcha(autoRecognize: false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onCaptchaChanged(String value) {
    if (_ocrStatus != OcrStatus.idle) {
      setState(() => _ocrStatus = OcrStatus.idle);
    }
  }

  Future<void> _useSavedAccount(Account account) async {
    _loginCtrl.text = account.loginName;
    final pw = await ref.read(storageProvider).passwordFor(account.id);
    if (!mounted) return;
    if (pw != null) {
      _pwCtrl.text = pw;
      // A recognised captcha may be waiting for credentials.
      if (_ocrStatus == OcrStatus.recognized && _captchaCtrl.text.isNotEmpty) {
        _submit(fromOcr: true);
      } else {
        _captchaFocus.requestFocus();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(signedInAccountsProvider);
    final accounts = ref
        .watch(accountsProvider)
        .where((a) => !signedIn.contains(a.id))
        .toList();
    final busy = _submitting;

    return Scaffold(
      appBar: widget.addingAccount ? AppBar(title: const Text('添加账号')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.addingAccount) ...[
                    const SizedBox(height: 12),
                    _Brand(scheme: scheme),
                    const SizedBox(height: 28),
                  ],
                  const UpdateNoticeBanner(),
                  if (accounts.isNotEmpty) ...[
                    _SavedAccounts(
                      accounts: accounts,
                      onPick: _useSavedAccount,
                      onRemove: (a) =>
                          ref.read(accountsProvider.notifier).remove(a.id),
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
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? '显示密码' : '隐藏密码',
                        icon: Icon(_obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CaptchaRow(
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
                      const Text('记住账号'),
                      const Spacer(),
                      const Text('自动识别验证码', style: TextStyle(fontSize: 13)),
                      Switch(
                        value: _autoRecognize,
                        onChanged: (v) {
                          setState(() => _autoRecognize = v);
                          ref.read(storageProvider).setAutoOcr(v);
                          if (v) _refreshCaptcha();
                        },
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    _Note(
                      icon: Icons.error_outline,
                      color: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                      child: Text(_error!),
                    ),
                  ],
                  if (_showCampusHint) ...[
                    const SizedBox(height: 8),
                    _Note(
                      icon: Icons.wifi_off,
                      color: scheme.tertiaryContainer,
                      foreground: scheme.onTertiaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('连不上选课服务器',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '选课系统只在校园网内可用，校外请先连接学校 VPN。\n当前地址：${ref.read(storageProvider).origin()}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                ),
                                onPressed: _showServerSettings,
                                child: const Text('更改服务器'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 32),
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const DiagnosticsPage(),
                                  ),
                                ),
                                child: const Text('连接诊断'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(64, 50)),
                    child: busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Text('登录'),
                  ),
                  if (!widget.addingAccount) ...[
                    const SizedBox(height: 8),
                    _SettingsShortcut(onServer: _showServerSettings),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showServerSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选课服务器'),
        content: SizedBox(
          width: 480,
          child: ServerOriginSetting(
            compact: true,
            onSaved: () async {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (!mounted) return;
              setState(() {
                _error = null;
                _showCampusHint = false;
              });
              await _refreshCaptcha();
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.child,
  });
  final IconData icon;
  final Color color;
  final Color foreground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
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
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.school_outlined, color: scheme.onPrimary, size: 36),
        ),
        const SizedBox(height: 14),
        Text('西农本科选课',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _SavedAccounts extends StatelessWidget {
  const _SavedAccounts(
      {required this.accounts, required this.onPick, required this.onRemove});
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

/// Captcha field + image, shared by the login screen and the re-login dialog.
class CaptchaRow extends StatelessWidget {
  const CaptchaRow({
    super.key,
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
        Tooltip(
          message: '点击换一张',
          child: InkWell(
            onTap: loading ? null : onRefresh,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              width: 112,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: loading
                  ? const Center(
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : challenge != null && challenge!.imageBytes.isNotEmpty
                      ? Image.memory(
                          Uint8List.fromList(challenge!.imageBytes),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Center(
                          child: Icon(Icons.refresh,
                              color: scheme.onSurfaceVariant),
                        ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _ocrIndicator(ColorScheme scheme) {
    switch (ocrStatus) {
      case OcrStatus.warming:
      case OcrStatus.recognizing:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case OcrStatus.recognized:
        return const Icon(Icons.auto_awesome, color: Colors.green, size: 20);
      case OcrStatus.failed:
        return Icon(Icons.edit_outlined,
            color: scheme.onSurfaceVariant, size: 20);
      case OcrStatus.idle:
        return null;
    }
  }
}

class _SettingsShortcut extends ConsumerWidget {
  const _SettingsShortcut({required this.onServer});

  final VoidCallback onServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: onServer,
          icon: const Icon(Icons.dns_outlined),
          label: const Text('服务器'),
        ),
        TextButton.icon(
          onPressed: () =>
              ref.read(themeControllerProvider.notifier).cycleMode(),
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
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
          ),
          icon: const Icon(Icons.monitor_heart_outlined),
          label: const Text('连接诊断'),
        ),
      ],
    );
  }
}
