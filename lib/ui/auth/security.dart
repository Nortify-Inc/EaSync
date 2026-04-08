import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:otp/otp.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupSecurityState {
  final bool biometricsEnabled;
  final bool authenticatorEnabled;
  final bool authenticatorConfigured;
  final bool authenticatorVerified;
  final String? manualEntryKey;
  final Uri? otpauthUri;

  const StartupSecurityState({
    required this.biometricsEnabled,
    required this.authenticatorEnabled,
    required this.authenticatorConfigured,
    required this.authenticatorVerified,
    this.manualEntryKey,
    this.otpauthUri,
  });

  bool get requiresBiometric => biometricsEnabled;

  bool get requiresAuthenticatorCode =>
      authenticatorEnabled && authenticatorConfigured && authenticatorVerified;

  bool get hasAnyGate => requiresBiometric || requiresAuthenticatorCode;
}

class AuthenticatorSetupData {
  final String secret;
  final String manualEntryKey;
  final Uri otpauthUri;

  const AuthenticatorSetupData({
    required this.secret,
    required this.manualEntryKey,
    required this.otpauthUri,
  });
}

class AppSecurityService {
  const AppSecurityService._();
  static const AppSecurityService instance = AppSecurityService._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kFingerprintEnabled = 'account.security.fingerprint';
  static const _k2faApp = 'account.security.2fa.app';
  static const _k2faVerified = 'account.security.2fa.verified';
  static const _k2faAccountLabel = 'account.security.2fa.account_label';

  static const _kSecure2faSecret = 'account.security.2fa.secret';

  static const _issuer = 'EaSync';
  static const _totpDigits = 6;
  static const _totpInterval = 30;

  Future<StartupSecurityState> readStartupSecurityState() async {
    final prefs = await SharedPreferences.getInstance();
    final secret = await _secure.read(key: _kSecure2faSecret);
    final appEnabled = prefs.getBool(_k2faApp) ?? false;
    final appVerified = prefs.getBool(_k2faVerified) ?? false;
    final accountLabel = _resolveAccountLabel(prefs);

    final configured = (secret ?? '').trim().isNotEmpty;

    return StartupSecurityState(
      biometricsEnabled: prefs.getBool(_kFingerprintEnabled) ?? false,
      authenticatorEnabled: appEnabled,
      authenticatorConfigured: configured,
      authenticatorVerified: appVerified,
      manualEntryKey: configured ? _formatManualKey(secret!) : null,
      otpauthUri: configured
          ? _buildOtpAuthUri(secret: secret!, accountLabel: accountLabel)
          : null,
    );
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFingerprintEnabled, enabled);
  }

  Future<void> setAuthenticatorEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k2faApp, enabled);
  }

  Future<AuthenticatorSetupData> createOrRotateAuthenticator({
    required String accountLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedLabel = accountLabel.trim().isEmpty
        ? 'user@easync.local'
        : accountLabel.trim();
    final secret = _generateBase32Secret(length: 32);

    await _secure.write(key: _kSecure2faSecret, value: secret);
    await prefs.setBool(_k2faApp, true);
    await prefs.setBool(_k2faVerified, false);
    await prefs.setString(_k2faAccountLabel, normalizedLabel);

    return AuthenticatorSetupData(
      secret: secret,
      manualEntryKey: _formatManualKey(secret),
      otpauthUri: _buildOtpAuthUri(
        secret: secret,
        accountLabel: normalizedLabel,
      ),
    );
  }

  Future<bool> verifyAuthenticatorCode(String inputCode) async {
    final normalized = _normalizeCode(inputCode);
    if (!_isValidCode(normalized)) return false;

    final secret = await _secure.read(key: _kSecure2faSecret);
    if (secret == null || secret.trim().isEmpty) return false;

    final now = DateTime.now();
    final candidates = [
      now.subtract(const Duration(seconds: _totpInterval)),
      now,
      now.add(const Duration(seconds: _totpInterval)),
    ];

    for (final dt in candidates) {
      final expected = OTP.generateTOTPCodeString(
        secret,
        dt.millisecondsSinceEpoch,
        interval: _totpInterval,
        length: _totpDigits,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (expected == normalized) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_k2faVerified, true);
        await prefs.setBool(_k2faApp, true);
        return true;
      }
    }

    return false;
  }

  Future<void> disableAuthenticator({bool removeSecret = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k2faApp, false);
    await prefs.setBool(_k2faVerified, false);
    if (removeSecret) {
      await _secure.delete(key: _kSecure2faSecret);
      await prefs.remove(_k2faAccountLabel);
    }
  }

  String _resolveAccountLabel(SharedPreferences prefs) {
    final fromPrefs = (prefs.getString(_k2faAccountLabel) ?? '').trim();
    if (fromPrefs.isNotEmpty) return fromPrefs;

    final authEmail = (prefs.getString('account.auth.email') ?? '').trim();
    if (authEmail.isNotEmpty) return authEmail;

    final authName = (prefs.getString('account.auth.name') ?? '').trim();
    if (authName.isNotEmpty) return authName;

    return 'user@easync.local';
  }

  String _normalizeCode(String code) {
    return code.replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _isValidCode(String code) {
    return code.length == _totpDigits;
  }

  Uri _buildOtpAuthUri({required String secret, required String accountLabel}) {
    final label = Uri.encodeComponent('$_issuer:$accountLabel');
    final issuer = Uri.encodeComponent(_issuer);
    return Uri.parse(
      'otpauth://totp/$label?secret=$secret&issuer=$issuer&algorithm=SHA1&digits=$_totpDigits&period=$_totpInterval',
    );
  }

  String _generateBase32Secret({int length = 32}) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rng = Random.secure();
    final chars = List<String>.generate(
      length,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    );
    return chars.join();
  }

  String _formatManualKey(String raw) {
    final chunks = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      final end = (i + 4 < raw.length) ? i + 4 : raw.length;
      chunks.add(raw.substring(i, end));
    }
    return chunks.join(' ');
  }
}
