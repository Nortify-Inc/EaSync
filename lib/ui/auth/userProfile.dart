class OAuthUserProfile {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String provider; // 'Google' | 'Apple' | 'Microsoft'

  const OAuthUserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.provider,
  });
}
