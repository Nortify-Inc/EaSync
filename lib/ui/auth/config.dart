import 'package:flutter_dotenv/flutter_dotenv.dart';

class OAuthConfig {
  OAuthConfig._();

  static const String _googleAndroidClientFallback =
      '15412300673-n6rje7vsp6fjqtg16kupsbgi369iavmg.apps.googleusercontent.com';

  static String _normalizeGoogleTokenUri(String raw) {
    final value = raw.trim().isEmpty
        ? 'https://oauth2.googleapis.com/token'
        : raw.trim();
    if (value.contains('://loauth2.googleapis.com')) {
      return value.replaceFirst(
        '://loauth2.googleapis.com',
        '://oauth2.googleapis.com',
      );
    }
    return value;
  }

  static String get googleClientId => dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  static String get googleIosClientId =>
      dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';
  static String get googleAndroidClientId =>
      dotenv.env['GOOGLE_ANDROID_CLIENT_ID'] ?? _googleAndroidClientFallback;
  static String get googleClientSecret =>
      dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';
  static String get googleTokenUri => _normalizeGoogleTokenUri(
    dotenv.env['GOOGLE_TOKEN_URI'] ?? 'https://oauth2.googleapis.com/token',
  );
  static const googleScopes = [
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/userinfo.profile',
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  static String get microsoftClientId =>
      dotenv.env['MICROSOFT_CLIENT_ID'] ?? '';
  static String get microsoftTenant =>
      dotenv.env['MICROSOFT_TENANT'] ?? 'common';
  static const microsoftScopes = [
    'openid',
    'email',
    'profile',
    'offline_access',
    'User.Read',
  ];

  static String get appleBundleId =>
      dotenv.env['APPLE_BUNDLE_ID'] ?? 'com.easync.nortify';
}
