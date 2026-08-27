import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/host.dart';

class HostService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Host>> getLiveHosts() async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'host')
        .eq('is_live', true);

    return data.map((host) => Host.fromMap(host)).toList();
  }

  Future<List<Host>> getAllHosts() async {
    final data = await _supabase.from('profiles').select().eq('role', 'host');

    return data.map((host) => Host.fromMap(host)).toList();
  }
}
