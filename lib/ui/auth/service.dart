import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import 'security.dart';
import 'config.dart';
import 'provider.dart';
import 'tokenStore.dart';
import 'userProfile.dart';

class OAuthService {
  OAuthService._();
  static final OAuthService instance = OAuthService._();

  final _store = OAuthTokenStore.instance;

  static const _kUid = 'account.auth.uid';
  static const _kName = 'account.auth.name';
  static const _kEmail = 'account.auth.email';
  static const _kPhoto = 'account.auth.photo';
  static const _kProvider = 'account.auth.provider';

  // ── Ponto de entrada ──────────────────────────────────────

  Future<OAuthUserProfile> login(OAuthProvider provider) {
    switch (provider) {
      case OAuthProvider.google:
      case OAuthProvider.microsoft:
        return _webOAuthFlow(provider);
      case OAuthProvider.apple:
        return _appleNativeFlow();
    }
  }

  // ── Google + Microsoft ────────────────────────────────────

  Future<OAuthUserProfile> _webOAuthFlow(OAuthProvider provider) async {
    final meta = _metaFor(provider);
    _validateProviderConfig(provider, meta);

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      8888,
      shared: true,
    );
    final redirectUri = Uri.parse('http://localhost:8888');

    final verifier = _makeVerifier();
    final challenge = _makeChallenge(verifier);
    final stateToken = _makeVerifier().substring(0, 24);

    final authUrl = meta.authorizationEndpoint.replace(
      queryParameters: {
        'client_id': meta.clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'scope': meta.scopes.join(' '),
        'state': stateToken,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        if (provider == OAuthProvider.google) ...{
          'access_type': 'offline',
          'prompt': 'consent',
        },
      },
    );

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw OAuthException(
        'Não foi possível abrir o browser para autenticação.',
      );
    }

    HttpRequest? oauthReq;
    try {
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final qp = req.uri.queryParameters;
        final isOAuthCallback =
            qp.containsKey('code') ||
            qp.containsKey('error') ||
            qp.containsKey('state');

        if (isOAuthCallback) {
          oauthReq = req;
          break;
        }

        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><html><body>OK</body></html>')
          ..close().ignore();
      }
    } on TimeoutException {
      await server.close(force: true);
      throw OAuthException('Login expirou (5 min). Tente novamente.');
    } catch (e) {
      await server.close(force: true);
      rethrow;
    }

    if (oauthReq == null) {
      await server.close(force: true);
      throw OAuthException('Login não concluído: callback OAuth não recebido.');
    }

    oauthReq.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_callbackHtml)
      ..close().ignore();
    await server.close();

    if (oauthReq.uri.queryParameters['state'] != stateToken) {
      throw OAuthException('Resposta inválida do provedor (state mismatch).');
    }

    final code = oauthReq.uri.queryParameters['code'];
    if (code == null) {
      final desc =
          oauthReq.uri.queryParameters['error_description'] ??
          oauthReq.uri.queryParameters['error'] ??
          'cancelado';
      throw OAuthException('Login não concluído: $desc');
    }

    final tokens = await _exchangeCode(
      meta: meta,
      code: code,
      redirectUri: redirectUri,
      codeVerifier: verifier,
    );

    await _store.save(
      accessToken: tokens['access_token']!,
      refreshToken: tokens['refresh_token'],
      expiresInSeconds: int.tryParse(tokens['expires_in'] ?? '3600') ?? 3600,
      provider: provider.name,
    );

    final profile = await _fetchUserInfo(meta, tokens['access_token']!);
    await _persistProfile(profile);
    return profile;
  }

  // ── Apple ─────────────────────────────────────────────────

  Future<OAuthUserProfile> _appleNativeFlow() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isMacOS)) {
      throw OAuthException(
        'Apple Sign In está disponível apenas em iOS e macOS.\n'
        'Use Google ou Microsoft para entrar nesta plataforma.',
      );
    }

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final prefs = await SharedPreferences.getInstance();
    final parts = [
      credential.givenName ?? '',
      credential.familyName ?? '',
    ].where((s) => s.isNotEmpty).toList();
    final freshName = parts.join(' ').trim();
    final displayName = freshName.isNotEmpty
        ? freshName
        : (prefs.getString(_kName) ?? 'Usuário Apple');

    final email = credential.email?.isNotEmpty == true
        ? credential.email!
        : (prefs.getString(_kEmail) ?? '');

    await _store.save(
      accessToken: credential.identityToken ?? '',
      refreshToken: credential.authorizationCode,
      expiresInSeconds: 3600,
      provider: OAuthProvider.apple.name,
    );

    final profile = OAuthUserProfile(
      id: credential.userIdentifier ?? '',
      name: displayName,
      email: email,
      avatarUrl: null,
      provider: 'Apple',
    );

    await _persistProfile(profile);
    return profile;
  }

  // ── Troca code → tokens ───────────────────────────────────

  Future<Map<String, String?>> _exchangeCode({
    required OAuthProviderMeta meta,
    required String code,
    required Uri redirectUri,
    required String codeVerifier,
  }) async {
    final response = await http
        .post(
          meta.tokenEndpoint,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {
            'grant_type': 'authorization_code',
            'code': code,
            'redirect_uri': redirectUri.toString(),
            'client_id': meta.clientId,
            'code_verifier': codeVerifier,
            if (meta.clientSecret.isNotEmpty)
              'client_secret': meta.clientSecret,
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw OAuthException(
        'Falha na troca de token [${response.statusCode}]:\n${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data.map((k, v) => MapEntry(k, v?.toString()));
  }

  // ── Refresh ───────────────────────────────────────────────

  Future<String?> getValidAccessToken() async {
    final token = await _store.readAccessToken();
    if (token == null) return null;
    if (await _store.isExpired()) return _refreshAccessToken();
    return token;
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = await _store.readRefreshToken();
    final providerName = await _store.readProvider();
    if (refreshToken == null || providerName == null) return null;
    if (providerName == OAuthProvider.apple.name) return null;

    final provider = OAuthProvider.values.firstWhere(
      (p) => p.name == providerName,
      orElse: () => OAuthProvider.google,
    );
    final meta = _metaFor(provider);

    try {
      final response = await http
          .post(
            meta.tokenEndpoint,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'client_id': meta.clientId,
              if (meta.clientSecret.isNotEmpty)
                'client_secret': meta.clientSecret,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newToken = data['access_token']?.toString();
      if (newToken == null) return null;

      await _store.save(
        accessToken: newToken,
        refreshToken: data['refresh_token']?.toString() ?? refreshToken,
        expiresInSeconds:
            int.tryParse(data['expires_in']?.toString() ?? '') ?? 3600,
        provider: providerName,
      );
      return newToken;
    } catch (_) {
      return null;
    }
  }

  // ── Busca perfil ──────────────────────────────────────────

  Future<OAuthUserProfile> _fetchUserInfo(
    OAuthProviderMeta meta,
    String accessToken,
  ) async {
    final response = await http
        .get(
          meta.userInfoEndpoint,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw OAuthException(
        'Falha ao buscar perfil [${response.statusCode}]:\n${response.body}',
      );
    }

    final d = jsonDecode(response.body) as Map<String, dynamic>;
    final id = (d['sub'] ?? d['oid'] ?? '').toString();
    final name = (d['name'] ?? d['displayName'] ?? '').toString();
    final email =
        (d['email'] ??
                d['userPrincipalName'] ??
                d['preferred_username'] ??
                d['upn'] ??
                d['mail'] ??
                '')
            .toString();
    final photo = d['picture']?.toString();

    final host = meta.userInfoEndpoint.host;
    final label = host.contains('google')
        ? 'Google'
        : host.contains('microsoft') || host.contains('graph')
        ? 'Microsoft'
        : 'OAuth';

    final resolvedName = name.isNotEmpty
        ? name
        : (email.isNotEmpty
              ? email.split('@').first
              : (id.isNotEmpty ? 'user_$id' : 'Authenticated account'));

    return OAuthUserProfile(
      id: id,
      name: resolvedName,
      email: email,
      avatarUrl: photo,
      provider: label,
    );
  }

  // ── Persistência ──────────────────────────────────────────

  Future<void> _persistProfile(OAuthUserProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_kUid, p.id),
      prefs.setString(_kName, p.name),
      prefs.setString(_kEmail, p.email),
      prefs.setString(_kPhoto, p.avatarUrl ?? ''),
      prefs.setString(_kProvider, p.provider),
    ]);
    await AppSecurityService.instance.markSessionValidated(false);
  }

  Future<OAuthUserProfile?> getSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final id = (prefs.getString(_kUid) ?? '').trim();
    final name = (prefs.getString(_kName) ?? '').trim();
    final email = prefs.getString(_kEmail) ?? '';
    final provider = (prefs.getString(_kProvider) ?? '').trim();

    final hasAuthIdentity =
        id.isNotEmpty || name.isNotEmpty || email.trim().isNotEmpty;
    if (!hasAuthIdentity) return null;

    return OAuthUserProfile(
      id: id,
      name: name,
      email: email,
      avatarUrl: prefs.getString(_kPhoto),
      provider: provider,
    );
  }

  Future<bool> get isLoggedIn async => (await getSavedProfile()) != null;

  Future<void> logout() async {
    await _store.clear();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_kUid),
      prefs.remove(_kName),
      prefs.remove(_kEmail),
      prefs.remove(_kPhoto),
      prefs.remove(_kProvider),
    ]);
    await AppSecurityService.instance.clearSessionValidation();
  }

  // ── Config por provedor ───────────────────────────────────

  OAuthProviderMeta _metaFor(OAuthProvider provider) {
    switch (provider) {
      case OAuthProvider.google:
        return OAuthProviderMeta(
          authorizationEndpoint: Uri.parse(
            'https://accounts.google.com/o/oauth2/v2/auth',
          ),
          tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
          userInfoEndpoint: Uri.parse(
            'https://www.googleapis.com/oauth2/v3/userinfo',
          ),
          clientId: OAuthConfig.googleClientId,
          clientSecret: OAuthConfig.googleClientSecret,
          scopes: OAuthConfig.googleScopes,
        );
      case OAuthProvider.microsoft:
        final t = OAuthConfig.microsoftTenant;
        return OAuthProviderMeta(
          authorizationEndpoint: Uri.parse(
            'https://login.microsoftonline.com/$t/oauth2/v2.0/authorize',
          ),
          tokenEndpoint: Uri.parse(
            'https://login.microsoftonline.com/$t/oauth2/v2.0/token',
          ),
          userInfoEndpoint: Uri.parse('https://graph.microsoft.com/v1.0/me'),
          clientId: OAuthConfig.microsoftClientId,
          scopes: OAuthConfig.microsoftScopes,
        );
      case OAuthProvider.apple:
        throw OAuthException('Apple usa _appleNativeFlow(), não _metaFor().');
    }
  }

  void _validateProviderConfig(OAuthProvider provider, OAuthProviderMeta meta) {
    if (meta.clientId.trim().isNotEmpty) return;

    switch (provider) {
      case OAuthProvider.google:
        throw OAuthException(
          'Configuração OAuth inválida: GOOGLE_CLIENT_ID não definido no arquivo .env.',
        );
      case OAuthProvider.microsoft:
        throw OAuthException(
          'Configuração OAuth inválida: MICROSOFT_CLIENT_ID não definido no arquivo .env.',
        );
      case OAuthProvider.apple:
        throw OAuthException('Configuração inválida para Apple Sign In.');
    }
  }

  // ── PKCE ─────────────────────────────────────────────────

  String _makeVerifier() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _makeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ── HTML de callback ──────────────────────────────────────

  static const _callbackHtml = '''
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">

  <!-- Favicon base64 (sempre funciona) -->
  <link rel="icon" type="image/png" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAQCAYAAABAfUpZAAAAKUlEQVR4nO3BMQEAAADCoPVPbQ0PoAAAAAAAAAAAAAAAAAAAAAAA4G4GAAE9l0yXAAAAAElFTkSuQmCC">

  <title>Nortify</title>

  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
      background:#0f0f0f;color:#f0f0f0;
      min-height:100vh;display:flex;flex-direction:column;
      align-items:center;justify-content:center;gap:14px;
    }
    p{font-size:13px;color:#aaa;text-align:center}
  </style>
</head>
<body>
  <p>Done. You can close this window and get back to EaSync.</p>

  <script>
    try {
      if (window.opener) {
        window.opener.postMessage(
          { type: "oauth_success", url: window.location.href },
          "*"
        );
        window.close();
      } else {
        setTimeout(() => window.close(), 800);
      }
    } catch (e) {
      setTimeout(() => window.close(), 1000);
    }
  </script>
</body>
</html>
''';
}

class OAuthException implements Exception {
  final String message;
  const OAuthException(this.message);

  @override
  String toString() => message;
}
