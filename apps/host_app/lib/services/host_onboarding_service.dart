import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Owns the complete host GPS verification workflow:
/// permissions, GPS capture, validation, and server verification.
///
/// Country and continent are determined by the trusted Edge Function,
/// never by values supplied by the client.
class HostOnboardingService {
  HostOnboardingService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> captureAndSaveGpsLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Turn on your device location services, then try again.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission is blocked. Open your app settings '
        'and allow location access.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission is required to complete host setup.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    );

    final latitude = position.latitude;
    final longitude = position.longitude;
    final accuracyMeters = position.accuracy;

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
        'Your GPS reading is not accurate enough. '
        'Please try again outdoors.',
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
      throw StateError('The server returned an invalid location response.');
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
