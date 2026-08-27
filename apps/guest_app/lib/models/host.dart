class Host {
  final String id;
  final String displayName;
  final String? username;
  final String? bio;
  final String? avatarUrl;
  final bool isLive;
  final String? liveRoomId;

  const Host({
    required this.id,
    required this.displayName,
    this.username,
    this.bio,
    this.avatarUrl,
    required this.isLive,
    this.liveRoomId,
  });

  factory Host.fromMap(Map<String, dynamic> map) {
    return Host(
      id: map['id'] as String,
      displayName: map['display_name'] as String? ?? 'Unknown Host',
      username: map['username'] as String?,
      bio: map['bio'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      isLive: map['is_live'] as bool? ?? false,
      liveRoomId: map['live_room_id'] as String?,
    );
  }
}
