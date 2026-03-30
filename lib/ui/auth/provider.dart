enum OAuthProvider { google, apple, microsoft }

class OAuthProviderMeta {
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri userInfoEndpoint;
  final String clientId;
  final String clientSecret;
  final List<String> scopes;

  const OAuthProviderMeta({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.userInfoEndpoint,
    required this.clientId,
    this.clientSecret = '',
    required this.scopes,
  });
}