import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Requests a fresh device GPS reading and asks the trusted Edge Function
/// to determine and persist country/continent. The client never supplies
/// country or continent values.
class HostLocationService {
  HostLocationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> captureAndSave({required bool isUpdate}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on device location to continue.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for host registration.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    );

    final response = await _client.functions.invoke(
      'set-host-location',
      body: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_meters': position.accuracy,
        'is_update': isUpdate,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('The server could not verify this location.');
    }
    if (response.data is! Map) {
      throw StateError('The server returned an invalid location response.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }
}
