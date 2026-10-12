/// The embedded campus VPN (nwafu-connect, an aTrust client for
/// vpn.nwafu.edu.cn). It runs a userspace stack inside the app and exposes a
/// local HTTP proxy; requests to campus hosts go through that proxy while
/// the device is off campus. Web has no native library, so it gets a stub.
library;

import 'vpn_bridge_stub.dart'
    if (dart.library.ffi) 'vpn_bridge_ffi.dart'
    as impl;

/// One reply from the native library.
class VpnReply {
  const VpnReply({
    required this.ok,
    required this.state,
    this.proxy,
    this.error,
    this.needs,
    this.image,
    this.hint,
    this.clientIp,
  });

  factory VpnReply.fromJson(Map<String, dynamic> j) => VpnReply(
    ok: j['ok'] == true,
    state: (j['state'] ?? '').toString(),
    proxy: j['proxy']?.toString(),
    error: j['error']?.toString(),
    needs: j['needs']?.toString(),
    image: j['image']?.toString(),
    hint: j['hint']?.toString(),
    clientIp: j['clientIp']?.toString(),
  );

  final bool ok;

  /// running / awaiting / failed / stopped / starting.
  final String state;

  /// `127.0.0.1:<port>` while running.
  final String? proxy;
  final String? error;

  /// captcha / sms / totp when the gateway wants input.
  final String? needs;

  /// Base64 PNG for a captcha step.
  final String? image;
  final String? hint;
  final String? clientIp;

  bool get running => state == 'running' && proxy != null;
}

/// Login settings passed to the library. The password is the same unified
/// identity password the rest of the app uses.
class VpnConfig {
  const VpnConfig({
    required this.username,
    required this.password,
    required this.clientDataPath,
    this.totpSecret = '',
  });
  final String username;
  final String password;
  final String totpSecret;

  /// Where the library keeps its device id and gateway cookies.
  final String clientDataPath;

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    if (totpSecret.isNotEmpty) 'totpSecret': totpSecret,
    'clientDataPath': clientDataPath,
    'httpBind': '127.0.0.1:0',
  };
}

abstract class VpnBridge {
  /// Whether the native library is present on this platform/build.
  bool get available;

  /// Starts a session; returns when running, failed, or waiting for input.
  Future<VpnReply> start(VpnConfig config);

  /// Answers the pending step (`captcha` takes the coordinate string the
  /// gateway expects, `sms`/`totp` take the code).
  Future<VpnReply> submit(String kind, String value);
  Future<VpnReply> status();
  Future<VpnReply> stop();
}

VpnBridge createVpnBridge() => impl.createVpnBridge();
