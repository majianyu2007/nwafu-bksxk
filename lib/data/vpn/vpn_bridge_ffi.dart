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
    final DynamicLibrary lib;
    if (Platform.isIOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libnwafuconnect.dylib');
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open('nwafuconnect.dll');
    } else {
      lib = DynamicLibrary.open('libnwafuconnect.so');
    }
    // Verify the expected symbol exists (important on iOS where
    // DynamicLibrary.process() always succeeds even when unlinked).
    lib.lookup<NativeFunction<_Str0>>('NcStatus');
    return lib;
  } catch (_) {
    return null;
  }
}

String _take(DynamicLibrary lib, Pointer<Utf8> p) {
  if (p == nullptr) {
    return jsonEncode({'ok': false, 'state': 'failed', 'error': '校外访问组件返回空指针'});
  }
  _FreeD? free;
  try {
    free = lib.lookupFunction<_FreeC, _FreeD>('NcFree');
    return p.toDartString();
  } catch (_) {
    return jsonEncode({'ok': false, 'state': 'failed', 'error': '校外访问组件返回异常'});
  } finally {
    free?.call(p);
  }
}

String _call(String name, List<String> args) {
  final lib = _open();
  if (lib == null) {
    return jsonEncode({'ok': false, 'state': 'stopped', 'error': '未找到校外访问组件'});
  }
  final ptrs = <Pointer<Utf8>>[];
  try {
    for (final a in args) {
      ptrs.add(a.toNativeUtf8());
    }
    final Pointer<Utf8> out = switch (ptrs.length) {
      0 => lib.lookupFunction<_Str0, _Str0>(name)(),
      1 => lib.lookupFunction<_Str1, _Str1>(name)(ptrs[0]),
      _ => lib.lookupFunction<_Str2, _Str2>(name)(ptrs[0], ptrs[1]),
    };
    return _take(lib, out);
  } catch (_) {
    return jsonEncode({'ok': false, 'state': 'failed', 'error': '校外访问组件调用异常'});
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
    try {
      final raw = await Isolate.run(() => _call(name, args));
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
