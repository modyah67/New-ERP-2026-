// lib/core/security/device_service.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

class DeviceService {
  /// Generates a unique Hardware ID using Windows MachineGuid from Registry.
  /// This is the modern replacement for WMIC-based fingerprinting.
  static Future<String> getHardwareId() async {
    try {
      // 1. Open the Registry Key
      // Path: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography
      const keyPath = r'SOFTWARE\Microsoft\Cryptography';
      final key = Registry.openPath(RegistryHive.localMachine, path: keyPath);
      
      // 2. Read MachineGuid value
      final machineGuid = key.getValueAsString('MachineGuid');
      key.close();

      if (machineGuid == null || machineGuid.isEmpty) {
        throw Exception('MachineGuid not found in registry');
      }

      // 3. Hash the MachineGuid using SHA-256 for privacy and standard length
      final bytes = utf8.encode(machineGuid);
      final hash = sha256.convert(bytes);

      // 4. Return as Uppercase String (First 12 chars for easier handling)
      return hash.toString().toUpperCase().substring(0, 12);
    } catch (e) {
      debugPrint('DeviceService Error: $e');
      return 'FAILED_TO_GENERATE_ID';
    }
  }
}
