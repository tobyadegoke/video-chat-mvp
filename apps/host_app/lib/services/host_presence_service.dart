import 'package:supabase_flutter/supabase_flutter.dart';

/// Client operations for the signed-in host's presence row.
///
/// Available and Away are explicit, host-authenticated requests. Busy and Live
/// transitions remain restricted to trusted backend event handlers. This client
/// also sends a heartbeat while the host app is active.
class HostPresenceService {
  HostPresenceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  Future<String> requireHostRole() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw StateError('Please sign in again.');
    }

    final profile = await _client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    if (profile == null || profile['role'] != 'host') {
      throw StateError('This account is not registered as a host.');
    }

    return userId;
  }

  Future<Map<String, dynamic>?> getCurrentPresence() async {
    final userId = await requireHostRole();
    return _client
        .from('host_presence')
        .select('host_id,status,last_seen_at,updated_at')
        .eq('host_id', userId)
        .maybeSingle();
  }

  /// Refreshes the host's heartbeat without changing their status.
  Future<void> sendHeartbeat() async {
    final userId = await requireHostRole();
    await _client
        .from('host_presence')
        .update({'last_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('host_id', userId);
  }

  /// Requests Available through the authenticated, host-only database RPC.
  /// The database rejects requests that would override Busy or Live.
  Future<Map<String, dynamic>> requestAvailable() async {
    final result = await _client.rpc('request_host_available');

    if (result is! Map) {
      throw StateError('The server returned an invalid Available response.');
    }

    return Map<String, dynamic>.from(result);
  }

  /// Away is the only other status a host may explicitly request.
  /// The database enforces the 1–60 minute range and eligibility rules.
  Future<Map<String, dynamic>> requestAway({int durationMinutes = 15}) async {
    final result = await _client.rpc(
      'request_host_away',
      params: {'p_duration_minutes': durationMinutes},
    );

    if (result is! Map) {
      throw StateError('The server returned an invalid Away response.');
    }

    return Map<String, dynamic>.from(result);
  }
}
