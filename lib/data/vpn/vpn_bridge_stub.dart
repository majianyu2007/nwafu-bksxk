import 'vpn_bridge.dart';

class _UnavailableVpn implements VpnBridge {
  static const _reply = VpnReply(
    ok: false,
    state: 'stopped',
    error: '此平台不支持内置校外访问',
  );
  @override
  bool get available => false;
  @override
  Future<VpnReply> start(VpnConfig config) async => _reply;
  @override
  Future<VpnReply> submit(String kind, String value) async => _reply;
  @override
  Future<VpnReply> status() async => _reply;
  @override
  Future<VpnReply> stop() async => _reply;
}

VpnBridge createVpnBridge() => _UnavailableVpn();
