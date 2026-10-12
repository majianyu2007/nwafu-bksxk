import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'vpn_bridge.dart';

typedef _Str0 = Pointer<Utf8> Function();
typedef _Str1 = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _Str2 = Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);

/// Opens the library by its platform name. Native calls block (login can
/// take seconds), so each runs on a short-lived isolate.
DynamicLibrary? _open() {
  try {
    if (Platform.isIOS) return DynamicLibrary.process();
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libnwafuconnect.dylib');
    }
    if (Platform.isWindows) return DynamicLibrary.open('nwafuconnect.dll');
    return DynamicLibrary.open('libnwafuconnect.so');
  } catch (_) {
    return null;
  }
}

String _take(DynamicLibrary lib, Pointer<Utf8> p) {
  final free = lib.lookupFunction<_FreeC, _FreeD>('NcFree');
  try {
    return p.toDartString();
  } finally {
    free(p);
  }
}

String _call(String name, List<String> args) {
  final lib = _open();
  if (lib == null) {
    return jsonEncode({'ok': false, 'state': 'stopped', 'error': '未找到校外访问组件'});
  }
  final ptrs = [for (final a in args) a.toNativeUtf8()];
  try {
    final Pointer<Utf8> out = switch (ptrs.length) {
      0 => lib.lookupFunction<_Str0, _Str0>(name)(),
      1 => lib.lookupFunction<_Str1, _Str1>(name)(ptrs[0]),
      _ => lib.lookupFunction<_Str2, _Str2>(name)(ptrs[0], ptrs[1]),
    };
    return _take(lib, out);
  } finally {
    for (final p in ptrs) {
      malloc.free(p);
    }
  }
}

class _FfiVpn implements VpnBridge {
  late final bool _available = _open() != null;

  @override
  bool get available => _available;

  Future<VpnReply> _run(String name, [List<String> args = const []]) async {
    if (!available) {
      return const VpnReply(ok: false, state: 'stopped', error: '未找到校外访问组件');
    }
    final raw = await Isolate.run(() => _call(name, args));
    try {
      return VpnReply.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VpnReply(ok: false, state: 'failed', error: '校外访问组件返回异常');
    }
  }

  @override
  Future<VpnReply> start(VpnConfig config) =>
      _run('NcStart', [jsonEncode(config.toJson())]);
  @override
  Future<VpnReply> submit(String kind, String value) =>
      _run('NcSubmit', [kind, value]);
  @override
  Future<VpnReply> status() => _run('NcStatus');
  @override
  Future<VpnReply> stop() => _run('NcStop');
}

VpnBridge createVpnBridge() => _FfiVpn();
