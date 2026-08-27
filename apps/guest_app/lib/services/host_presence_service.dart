import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/host_presence.dart';

class HostPresenceService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<HostPresence?> getPresence(String hostId) async {
    final response = await _client
        .from('host_presence')
        .select()
        .eq('host_id', hostId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return HostPresence.fromMap(response);
  }

  Future<void> setStatus(String hostId, HostStatus status) async {
    await _client.from('host_presence').upsert({
      'host_id': hostId,
      'status': status.value,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'host_id');
  }

  Future<void> updateHeartbeat(String hostId) async {
    await _client
        .from('host_presence')
        .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('host_id', hostId);
  }

  Future<List<HostPresence>> getAvailableHosts() async {
    final response = await _client
        .from('host_presence')
        .select()
        .eq('status', 'available');

    return (response as List)
        .map((item) => HostPresence.fromMap(item as Map<String, dynamic>))
        .toList();
  }
}
