import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OAuthTokenStore {
  const OAuthTokenStore._();
  static const OAuthTokenStore instance = OAuthTokenStore._();

  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccess = 'oauth.access_token';
  static const _kRefresh = 'oauth.refresh_token';
  static const _kExpiry = 'oauth.token_expiry';
  static const _kProvider = 'oauth.provider';

  Future<void> save({
    required String accessToken,
    String? refreshToken,
    required int expiresInSeconds,
    required String provider,
  }) async {
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresInSeconds))
        .toIso8601String();

    await Future.wait([
      _s.write(key: _kAccess, value: accessToken),
      _s.write(key: _kExpiry, value: expiry),
      _s.write(key: _kProvider, value: provider),
      if (refreshToken != null) _s.write(key: _kRefresh, value: refreshToken),
    ]);
  }

  Future<String?> readAccessToken() => _s.read(key: _kAccess);
  Future<String?> readRefreshToken() => _s.read(key: _kRefresh);
  Future<String?> readProvider() => _s.read(key: _kProvider);

  Future<bool> isExpired() async {
    final raw = await _s.read(key: _kExpiry);
    if (raw == null) return false;
    final expiry = DateTime.tryParse(raw);
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry.subtract(const Duration(seconds: 60)));
  }

  Future<void> clear() => Future.wait([
    _s.delete(key: _kAccess),
    _s.delete(key: _kRefresh),
    _s.delete(key: _kExpiry),
    _s.delete(key: _kProvider),
  ]);
}
