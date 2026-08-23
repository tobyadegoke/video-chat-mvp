class Profile {
  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String role;
  final bool isOnline;
  final bool isLive;

  const Profile({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    required this.role,
    required this.isOnline,
    required this.isLive,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      bio: map['bio'] as String?,
      role: map['role'] as String? ?? 'guest',
      isOnline: map['is_online'] as bool? ?? false,
      isLive: map['is_live'] as bool? ?? false,
    );
  }
}