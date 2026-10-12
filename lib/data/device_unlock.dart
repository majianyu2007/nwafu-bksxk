/// Fingerprint / Face ID / device-PIN confirmation guarding the passkey this
/// app bound to the school account. The private key itself stays in secure
/// storage; this is the user-presence gate before it is used.
library;

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class DeviceUnlock {
  DeviceUnlock([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  /// Whether this device can confirm the user (biometrics or a device
  /// passcode). Web and Linux never can.
  Future<bool> available() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// A short label for the method the device offers, for UI copy.
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return '面容';
      if (types.contains(BiometricType.fingerprint)) return '指纹';
      if (types.isNotEmpty) return '生物识别';
    } catch (_) {}
    return '设备密码';
  }

  /// Asks the user to confirm. False on cancel or failure.
  Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
