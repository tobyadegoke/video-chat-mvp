import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/host_onboarding_service.dart';

class HostOnboardingScreen extends StatefulWidget {
  const HostOnboardingScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<HostOnboardingScreen> createState() => _HostOnboardingScreenState();
}

class _HostOnboardingScreenState extends State<HostOnboardingScreen> {
  final _service = HostOnboardingService();

  bool _loading = false;
  String? _error;

  Future<void> _verifyLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
          'Location permission is blocked. Open your app settings and allow location access.',
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

      final result = await _service.saveGpsLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );

      if (!mounted) return;

      if (result['success'] != true) {
        throw StateError(
          'The server could not verify your location. Please try again.',
        );
      }

      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString().replaceFirst(
          RegExp(r'^(Exception|Bad state):\s*'),
          '',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host setup · Location')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.location_on_outlined, size: 60),
                  const SizedBox(height: 20),
                  Text(
                    'Verify your location',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We use your device location to determine your country '
                    'and continent. Location verification is required before '
                    'you can access the host dashboard.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your exact GPS coordinates are used for verification; '
                    'the app saves your country and continent, not the raw '
                    'coordinates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _loading ? null : _verifyLocation,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      _loading
                          ? 'Verifying location…'
                          : 'Verify my current location',
                    ),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_error!.contains('settings')) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loading ? null : _openSettings,
                        child: const Text('Open app settings'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'If verification fails, setup remains incomplete. '
                    'Check your location settings and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
