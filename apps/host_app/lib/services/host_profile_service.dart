import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for the signed-in host's public profile.
/// Role and presence fields are deliberately never written here.
class HostProfileService {
  HostProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Please sign in again.');
    return id;
  }

  Future<Map<String, dynamic>> loadProfile() async {
    final id = _userId;
    final profile = await _client
        .from('profiles')
        .select('id,username,display_name,avatar_url,bio,role')
        .eq('id', id)
        .maybeSingle();

    if (profile == null) {
      throw StateError('Your profile could not be found.');
    }
    if (profile['role'] != 'host') {
      throw StateError('This account is not registered as a host.');
    }
    return Map<String, dynamic>.from(profile);
  }

  Future<void> saveProfile({
    required String displayName,
    required String bio,
  }) async {
    final id = _userId;
    final cleanName = displayName.trim();
    final cleanBio = bio.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('Display name cannot be empty.');
    }
    if (cleanName.length > 60) {
      throw ArgumentError('Display name must be 60 characters or fewer.');
    }
    if (cleanBio.length > 500) {
      throw ArgumentError('Bio must be 500 characters or fewer.');
    }

    // Only profile-editable columns are written. Never accept role or presence
    // values from this client-side form.
    await _client.from('profiles').update({
      'display_name': cleanName,
      'bio': cleanBio,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final id = _userId;
    if (bytes.isEmpty) throw ArgumentError('The selected image is empty.');
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose an image smaller than 5 MB.');
    }
    if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
      throw ArgumentError('Choose a JPG, PNG or WebP image.');
    }

    final safeExtension = extension == 'jpeg' ? 'jpg' : extension;
    final path = '$id/avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    await _client.storage.from('host-avatars').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: contentType,
        upsert: false,
      ),
    );

    final url = _client.storage.from('host-avatars').getPublicUrl(path);
    await _client.from('profiles').update({
      'avatar_url': url,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);

    return url;
  }
}
