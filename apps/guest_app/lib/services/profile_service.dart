import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Profile?> getCurrentProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return null;
    }

    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return Profile.fromMap(data);
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String bio,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No authenticated user.');
    }

    await _supabase
        .from('profiles')
        .update({
          'display_name': displayName,
          'username': username,
          'bio': bio,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id);
  }
}