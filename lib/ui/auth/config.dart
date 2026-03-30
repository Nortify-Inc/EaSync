import 'package:flutter_dotenv/flutter_dotenv.dart';

class OAuthConfig {
  OAuthConfig._();

  static String get googleClientId =>
      dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  static String get googleClientSecret =>
      dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';
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