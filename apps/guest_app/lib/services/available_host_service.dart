import 'package:supabase_flutter/supabase_flutter.dart';

class AvailableHost {
  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? bio;

  const AvailableHost({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.bio,
  });

  factory AvailableHost.fromMap(Map<String, dynamic> map) {
    return AvailableHost(
      id: map['id'] as String,
      displayName: (map['display_name'] as String?) ?? 'Host',
      username: (map['username'] as String?) ?? '',
      avatarUrl: map['avatar_url'] as String?,
      bio: map['bio'] as String?,
    );
  }
}

class AvailableHostService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<AvailableHost>> getAvailableHosts() async {
    final response = await _client
        .from('host_presence')
        .select('''
          host_id,
          profiles (
            id,
            display_name,
            username,
            avatar_url,
            bio
          )
          ''')
        .eq('status', 'available');

    return (response as List)
        .map((item) {
          final map = item as Map<String, dynamic>;

          final profile = map['profiles'];

          if (profile == null) {
            return null;
          }

          return AvailableHost.fromMap(profile as Map<String, dynamic>);
        })
        .whereType<AvailableHost>()
        .toList();
  }
}
