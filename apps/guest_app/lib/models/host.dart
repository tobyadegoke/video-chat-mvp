class Host {
  final String id;
  final String displayName;
  final String? username;
  final String? bio;
  final String? avatarUrl;
  final bool isLive;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String? liveRoomId;
  final String? continent;

  const Host({
    required this.id,
    required this.displayName,
    this.username,
    this.bio,
    this.avatarUrl,
    required this.isLive,
    this.isOnline = false,
    this.lastSeenAt,
    this.liveRoomId,
    this.continent,
  });

  factory Host.fromMap(Map<String, dynamic> map) {
    return Host(
      id: map['id'] as String,
      displayName: map['display_name'] as String? ?? 'Unknown Host',
      username: map['username'] as String?,
      bio: map['bio'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      isLive: map['is_live'] as bool? ?? false,
      isOnline: map['is_online'] as bool? ?? false,
      lastSeenAt: map['last_seen_at'] is String
          ? DateTime.tryParse(map['last_seen_at'] as String)?.toLocal()
          : null,
      liveRoomId: map['live_room_id'] as String?,
      continent: map['continent'] as String?,
    );
  }
}
