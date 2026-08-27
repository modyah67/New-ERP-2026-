// lib/core/license_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';
import 'security/device_service.dart';

class LicenseService {
  static const String licensePath = r'C:\ProgramData\SystemCache\syscache.bin';
  static const String _passphrase = 'HABIBATEX-ACCOUNTING-SYSTEM-SECURE-KEY-2024';
  
  // Singleton
  static final LicenseService _instance = LicenseService._internal();
  factory LicenseService() => _instance;
  LicenseService._internal();

  bool _isActivated = false;
  bool get isActivated => _isActivated;

  /// Uses the modern DeviceService to get the Hardware ID
  Future<String> getHardwareFingerprint() async {
    return await DeviceService.getHardwareId();
  }

  /// Validates the existing license file on startup
  Future<bool> validateLicense() async {
    final file = File(licensePath);
    if (!file.existsSync()) {
      _isActivated = false;
      return false;
    }

    try {
      // Basic Anti-Debugging check
      if (IsDebuggerPresent() != 0) {
        debugPrint('Debugger detected! Blocking app.');
        return false;
      }

      final encryptedData = await file.readAsBytes();
      final decryptedJson = _decrypt(encryptedData);
      if (decryptedJson == null) return false;

      final data = json.decode(decryptedJson);
      final storedFingerprint = data['fingerprint'];
      final storedSignature = data['signature'];
      final currentFingerprint = await getHardwareFingerprint();

      // Verify integrity signature
      final expectedSignature = _generateSignature(storedFingerprint, data['timestamp']);
      
      if (storedFingerprint == currentFingerprint && storedSignature == expectedSignature) {
        _isActivated = true;
        return true;
      }
    } catch (e) {
      debugPrint('License validation error: $e');
    }

    _isActivated = false;
    return false;
  }

  /// Activates the application with a given key
  Future<bool> activate(String activationKey) async {
    final fingerprint = await getHardwareFingerprint();
    final trimmedKey = activationKey.trim().toUpperCase();

    // Developer Master Key Bypass
    if (trimmedKey == "MASTER-ADMIN-2024") {
      return await _saveLicense(fingerprint);
    }

    final expectedKey = _generateActivationKey(fingerprint);

    if (trimmedKey == expectedKey) {
      return await _saveLicense(fingerprint);
    }
    return false;
  }

  /// Generates the activation key for a given hardware ID
  String _generateActivationKey(String fingerprint) {
    final salt = 'ACTIVATION-SALT-9988';
    return sha256.convert(utf8.encode('$fingerprint$salt')).toString().substring(0, 16).toUpperCase();
  }

  Future<bool> _saveLicense(String fingerprint) async {
    try {
      final timestamp = DateTime.now().toIso8601String();
      final signature = _generateSignature(fingerprint, timestamp);
      
      final licenseData = {
        'fingerprint': fingerprint,
        'timestamp': timestamp,
        'version': '1.0.0',
        'signature': signature,
      };

      final encrypted = _encrypt(json.encode(licenseData));
      
      final file = File(licensePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      await file.writeAsBytes(encrypted);
      
      // Set file to Hidden and System using win32
      _setFileAttributes(licensePath);

      _isActivated = true;
      return true;
    } catch (e) {
      debugPrint('Error saving license: $e');
      return false;
    }
  }

  String _generateSignature(String fingerprint, String timestamp) {
    return sha256.convert(utf8.encode('$fingerprint|$timestamp|INTEGRITY-SIG')).toString();
  }

  // ── Encryption Helpers ───────────────────

  Uint8List _encrypt(String text) {
    final key = encrypt.Key.fromUtf8(_passphrase.substring(0, 32));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    
    final encrypted = encrypter.encrypt(text, iv: iv);
    return Uint8List.fromList(iv.bytes + encrypted.bytes);
  }

  String? _decrypt(Uint8List encryptedBytes) {
    try {
      if (encryptedBytes.length < 16) return null;
      
      final ivBytes = encryptedBytes.sublist(0, 16);
      final contentBytes = encryptedBytes.sublist(16);
      
      final key = encrypt.Key.fromUtf8(_passphrase.substring(0, 32));
      final iv = encrypt.IV(ivBytes);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      
      return encrypter.decrypt(encrypt.Encrypted(contentBytes), iv: iv);
    } catch (e) {
      return null;
    }
  }

  void _setFileAttributes(String path) {
    final lpFileName = path.toNativeUtf16();
    SetFileAttributes(lpFileName, FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM);
    free(lpFileName);
  }
}
