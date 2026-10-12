import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/edu_providers.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import '../data/cas_client.dart';
import '../data/ehall_service.dart';
import 'device_passkey.dart';

/// The unified identity login (password, or this device's bound passkey).
class EduLoginPage extends ConsumerStatefulWidget {
  const EduLoginPage({super.key});

  @override
  ConsumerState<EduLoginPage> createState() => _EduLoginPageState();
}

class _EduLoginPageState extends ConsumerState<EduLoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  late final EduSessionController _session;
  bool _deviceKey = false;
  String _unlockLabel = '指纹/面容';
  bool _usedDeviceKey = false;
  bool _remember = false;
  bool _trustDevice = false;
  bool _busy = false;
  bool _finished = false;
  bool _cancelled = false;
  bool _started = false;
  String? _error;
  String? _notice;
  bool _captchaUnsupported = false;
  CasMfaChallenge? _challenge;
  MfaMethod? _method;
  final _sentMethods = <MfaMethod>{};
  Timer? _cooldown;
  int _seconds = 0;
  int _operation = 0;

  @override
  void initState() {
    super.initState();
    _session = ref.read(eduSessionProvider.notifier);
    _username.text = ref.read(eduSessionProvider).account?.username ?? '';
    _username.addListener(_checkDeviceKey);
    _checkDeviceKey();
  }

  Future<void> _checkDeviceKey() async {
    final name = _username.text.trim();
    final has =
        name.isNotEmpty &&
        await _session.hasDeviceKey(name) &&
        await ref.read(deviceUnlockProvider).available();
    final label = has ? await ref.read(deviceUnlockProvider).label() : '';
    if (!mounted || name != _username.text.trim()) return;
    setState(() {
      _deviceKey = has;
      if (label.isNotEmpty) _unlockLabel = label;
    });
  }

  @override
  void dispose() {
    _operation++;
    _cancelLogin();
    _cooldown?.cancel();
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _cancelLogin() {
    if (_finished || _cancelled || !_started) return;
    _cancelled = true;
    _operation++;
    _session.cancelLogin();
  }

  void _showError(Object error) {
    // Never interpolate arbitrary exceptions: parsers may include private JSON.
    _error = error is AppError
        ? [error.message, if (error.hint != null) error.hint!].join('\n')
        : '登录失败，请检查网络后重试。';
    _captchaUnsupported =
        _challenge == null &&
        error is AppError &&
        error.kind == AppErrorKind.captcha;
  }

  Future<void> _submit({bool deviceKey = false}) async {
    if (_busy) return;
    if (deviceKey) {
      if (_username.text.trim().isEmpty) return;
    } else if (!_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final operation = ++_operation;
    _started = true;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _captchaUnsupported = false;
    });
    try {
      final challenge = _challenge;
      if (challenge != null) {
        final method = _method;
        if (method == null) return;
        await _session.completeMfa(
          _username.text.trim(),
          challenge,
          method,
          _code.text.trim(),
          trustDevice: _trustDevice,
          password: _usedDeviceKey ? null : _password.text,
          remember: _remember,
        );
      } else if (deviceKey) {
        _usedDeviceKey = true;
        await _session.loginWithDeviceKey(
          _username.text.trim(),
          () => ref
              .read(deviceUnlockProvider)
              .confirm('验证$_unlockLabel以登录统一身份认证'),
        );
      } else {
        _usedDeviceKey = false;
        await _session.loginWithPassword(
          _username.text.trim(),
          _password.text,
          remember: _remember,
        );
      }
      if (!mounted || operation != _operation) return;
      _finished = true;
      final password = _password.text;
      _password.clear();
      _code.clear();
      if (!_usedDeviceKey && !_deviceKey) {
        await _offerDeviceKey(password);
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } on CasMfaRequired catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() {
        _challenge = e.challenge;
        _method = null;
        for (final method in e.challenge.methods) {
          if (method.supported) {
            _method = method;
            break;
          }
        }
        _code.clear();
        _sentMethods.clear();
      });
    } catch (e) {
      if (!mounted || operation != _operation) return;
      setState(() => _showError(e));
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  /// After a password sign-in, offer fingerprint / Face ID next time.
  Future<void> _offerDeviceKey(String password) async {
    final unlock = ref.read(deviceUnlockProvider);
    if (password.isEmpty || !await unlock.available() || !mounted) return;
    final label = await unlock.label();
    if (!mounted) return;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.fingerprint,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '下次用$label登录？',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                '以后不用输密码，'
                '也不用收短信验证码。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('开启$label登录'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('以后再说'),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes == true && mounted) {
      await bindThisDeviceFlow(context, ref, password: password);
    }
  }

  Future<void> _sendCode() async {
    final method = _method;
    final challenge = _challenge;
    if (_busy || _seconds > 0 || method == null || challenge == null) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final message = await ref
          .read(eduClientProvider)
          .cas
          .sendMfaCode(challenge, method);
      if (!mounted || operation != _operation) return;
      setState(() {
        _notice = message;
        _sentMethods.add(method);
        _seconds = 60;
      });
      _cooldown?.cancel();
      _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _seconds--);
        if (_seconds <= 0) timer.cancel();
      });
    } catch (e) {
      if (mounted && operation == _operation) setState(() => _showError(e));
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _openOfficialLogin() async {
    try {
      final opened = await launchUrl(
        Uri.parse('$kAuthServer/authserver/login'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error = '无法打开浏览器，请手动访问 authserver.nwafu.edu.cn。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法打开浏览器，请手动访问 authserver.nwafu.edu.cn。');
      }
    }
  }

  Future<void> _connectBrowser() async {
    if (_busy) return;
    final operation = ++_operation;
    _started = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.connectBrowserSession();
      if (!mounted || operation != _operation) return;
      _finished = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted && operation == _operation) setState(() => _showError(e));
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _openOfficialEhall() async {
    try {
      if (await launchUrl(
        Uri.parse(EmapApp.exams.indexUrl),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        return;
      }
    } catch (_) {
      // Show an actionable message without exposing arbitrary URL exceptions.
    }
    if (mounted) {
      setState(() => _error = '无法打开学校页面，请在同一浏览器访问 ehall.nwafu.edu.cn 登录。');
    }
  }

  Widget _browserLogin(BuildContext context) {
    final ready = isEduSessionBridgeReady;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _cancelLogin();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('连接教务会话')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    '先在学校网页登录',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '1. 安装或更新桥接脚本后刷新本页。\n'
                    '2. 在同一浏览器打开学校教务页面，完成密码、扫码或安全验证。\n'
                    '3. 回到本页连接当前浏览器会话。',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '网页版不保存密码。'
                    '换了浏览器里的账号，需要重新连接。',
                  ),
                  if (!ready) ...[
                    const SizedBox(height: 16),
                    const Text('需要安装或更新桥接脚本（1.3.0 及以上）。'),
                    const OutlinedButton(
                      onPressed: openWebBridgeInstaller,
                      child: Text('安装或更新桥接脚本'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openOfficialEhall,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('打开学校教务页面'),
                  ),
                  const SizedBox(height: 12),
                  if (_busy)
                    const LinearProgressIndicator(
                      semanticsLabel: '正在连接',
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy || !ready ? null : _connectBrowser,
                    child: Text(_busy ? '正在连接…' : '连接当前浏览器会话'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _browserLogin(context);
    final theme = Theme.of(context);
    final challenge = _challenge;
    final method = _method;
    final canSubmitMfa =
        method != null && (!method.needsSend || _sentMethods.contains(method));
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _cancelLogin();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('统一身份认证')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(
                    challenge == null
                        ? Icons.school_outlined
                        : Icons.verified_user_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    challenge == null ? '登录' : '二次验证',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    challenge == null
                        ? '统一身份认证账号，课表、成绩、选课和校外访问通用。'
                        : '学校要求二次验证。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_busy) ...[
                    const LinearProgressIndicator(semanticsLabel: '正在处理身份认证'),
                    const SizedBox(height: 16),
                  ],
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (challenge == null) ...[
                          TextFormField(
                            controller: _username,
                            enabled: !_busy,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '学号 / 工号',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? '请输入统一身份认证账号'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          if (_deviceKey) ...[
                            FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () => _submit(deviceKey: true),
                              icon: const Icon(Icons.fingerprint),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text('使用$_unlockLabel登录'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('或使用密码'),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          ...[
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: '统一身份认证密码',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (v) =>
                                  v == null || v.isEmpty ? '请输入密码' : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('记住密码'),
                              subtitle: const Text('登录过期时自动重新登录；校外访问也需要它'),
                              value: _remember,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _remember = v!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ],
                        ] else ...[
                          if (challenge.displayName.isNotEmpty) ...[
                            Text(
                              challenge.displayName,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (challenge.methods.isNotEmpty)
                            DropdownButtonFormField<MfaMethod>(
                              initialValue: method,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '验证方式',
                              ),
                              items: [
                                for (final m in challenge.methods)
                                  DropdownMenuItem(
                                    value: m,
                                    enabled: m.supported,
                                    child: Text(
                                      '${m.label}${m.supported ? '' : '（暂不支持）'}',
                                    ),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      _method = value;
                                      _code.clear();
                                      _notice = null;
                                      _error = null;
                                      _sentMethods.clear();
                                    }),
                            ),
                          const SizedBox(height: 16),
                          if (method == null)
                            const Text(
                              '没有可用的验证方式，请在学校认证页面登录。',
                            )
                          else ...[
                            TextFormField(
                              controller: _code,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              decoration: InputDecoration(
                                labelText: method == MfaMethod.totp
                                    ? '安全令牌动态码'
                                    : '验证码',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '请输入验证码'
                                  : null,
                              onFieldSubmitted: (_) {
                                if (canSubmitMfa) _submit();
                              },
                            ),
                            if (method.needsSend)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy || _seconds > 0
                                      ? null
                                      : _sendCode,
                                  child: Text(
                                    _seconds > 0 ? '$_seconds 秒后可重发' : '发送验证码',
                                  ),
                                ),
                              ),
                            if (method == MfaMethod.totp) ...[
                              const SizedBox(height: 8),
                              const Text('输入验证器里的动态码。'),
                            ],
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('信任此设备'),
                              subtitle: const Text(
                                '一年内不再要求二次验证，公用电脑别勾选。',
                              ),
                              value: _trustDevice,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _trustDevice = v!),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ],
                        ],
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_notice!),
                            ),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        if (_captchaUnsupported) ...[
                          const Text(
                            '学校要求滑块验证，请先在官方页面登录一次，再回来重试。',
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_captchaUnsupported ||
                            (challenge != null && method == null))
                          OutlinedButton.icon(
                            onPressed: _openOfficialLogin,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('打开官方认证页面'),
                          ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              _busy || (challenge != null && !canSubmitMfa)
                              ? null
                              : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _busy
                                  ? '正在处理…'
                                  : challenge == null
                                  ? '登录'
                                  : '验证并登录',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _cancelLogin();
                            Navigator.of(context).pop();
                          },
                          child: Text(_busy ? '取消本次登录' : '暂不登录'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
