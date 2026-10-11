import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/host.dart';

/// Online presence is based on a recent host-app heartbeat, not live streaming.
/// A host is online when their last heartbeat was within the last 90 seconds.
class HostService {
  HostService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  static const Duration _presenceTtl = Duration(seconds: 90);

  Future<List<Host>> getLiveHosts() async {
    final hosts = await getAllHosts();
    return hosts.where((host) => host.isLive).toList();
  }

  Future<List<Host>> getAllHosts() async {
    final profileRows = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'host');

    // If presence cannot be read, fail visibly rather than showing every host
    // as offline due to a permissions/schema issue.
    final presenceRows = await _supabase
        .from('host_presence')
        .select('host_id,last_seen_at');

    final presenceByHost = <String, Map<String, dynamic>>{
      for (final row in presenceRows)
        row['host_id'] as String: Map<String, dynamic>.from(row),
    };

    final now = DateTime.now().toUtc();
    return profileRows.map<Host>((rawProfile) {
      final profile = Map<String, dynamic>.from(rawProfile);
      final presence = presenceByHost[profile['id'] as String];
      final lastSeenRaw = presence?['last_seen_at'];
      final lastSeen = lastSeenRaw is String
          ? DateTime.tryParse(lastSeenRaw)?.toUtc()
          : null;
      final online = lastSeen != null &&
          now.difference(lastSeen) >= Duration.zero &&
          now.difference(lastSeen) <= _presenceTtl;

      return Host.fromMap({
        ...profile,
        'is_online': online,
        'last_seen_at': lastSeenRaw,
      });
    }).toList();
  }
}
