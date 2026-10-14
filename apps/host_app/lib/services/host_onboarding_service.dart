import 'package:supabase_flutter/supabase_flutter.dart';

class HostOnboardingService {
  HostOnboardingService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> saveGpsLocation({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    final response = await _client.functions.invoke(
      'set-host-location',
      body: {
        'mode': 'gps',
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracyMeters,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('The server could not verify your location.');
    }

    if (response.data is! Map) {
      throw StateError('The server returned an invalid response.');
    }

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> saveManualLocation({
    required String countryCode,
    required String country,
    required String continent,
  }) async {
    final response = await _client.functions.invoke(
      'set-host-location',
      body: {
        'mode': 'manual',
        'country_code': countryCode.trim().toUpperCase(),
        'country': country.trim(),
        'continent': continent,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('The server could not save your location.');
    }

    if (response.data is! Map) {
      throw StateError('The server returned an invalid response.');
    }

    return Map<String, dynamic>.from(response.data as Map);
  }
}
