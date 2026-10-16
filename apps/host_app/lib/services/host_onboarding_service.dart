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
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0 ||
        accuracyMeters > 5000) {
      throw StateError(
        'Your GPS reading is not accurate enough. Please try again outdoors.',
      );
    }

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

    final result = Map<String, dynamic>.from(response.data as Map);

    if (result['success'] != true) {
      throw StateError(
        result['error']?.toString() ??
            'Your location could not be verified. Please try again.',
      );
    }

    return result;
  }
}
