import 'package:flutter_test/flutter_test.dart';
import 'package:nwafu_bksxk/data/vpn/campus_proxy.dart';
import 'package:nwafu_bksxk/data/vpn/campus_route.dart';
import 'package:nwafu_bksxk/data/vpn/vpn_bridge.dart';

void main() {
  test('only campus hosts go through the VPN proxy', () {
    final p = CampusProxy.instance;
    addTearDown(() => p.address = null);
    p.address = null;
    expect(p.route(Uri.parse('https://ehall.nwafu.edu.cn/x')), 'DIRECT');
    p.address = '127.0.0.1:5555';
    expect(
      p.route(Uri.parse('https://ehall.nwafu.edu.cn/x')),
      'PROXY 127.0.0.1:5555',
    );
    expect(
      p.route(Uri.parse('https://bksxk.nwafu.edu.cn/')),
      'PROXY 127.0.0.1:5555',
    );
    expect(p.route(Uri.parse('https://github.com/')), 'DIRECT');
    expect(p.route(Uri.parse('https://evilnwafu.edu.cn/')), 'DIRECT');
  });

  test('direct route needs every campus probe to answer', () async {
    expect(await campusReachableDirectly((_) async => true), isTrue);
    expect(
      await campusReachableDirectly(
        (url) async => !url.contains('ehall'),
      ),
      isFalse,
    );
  });

  test('VPN replies parse the library JSON', () {
    final r = VpnReply.fromJson({
      'ok': true,
      'state': 'running',
      'proxy': '127.0.0.1:61000',
      'needs': null,
      'clientIp': '10.0.0.2',
    });
    expect(r.running, isTrue);
    final c = VpnReply.fromJson({
      'ok': true,
      'state': 'awaiting',
      'needs': 'captcha',
      'image': 'aGk=',
    });
    expect(c.running, isFalse);
    expect(c.needs, 'captcha');
  });

  test('VPN config never sends an empty TOTP secret', () {
    const c = VpnConfig(username: 'u', password: 'p', clientDataPath: '/x');
    expect(c.toJson().containsKey('totpSecret'), isFalse);
    expect(c.toJson()['httpBind'], '127.0.0.1:0');
  });
}
