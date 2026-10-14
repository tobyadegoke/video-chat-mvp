import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/host_onboarding_service.dart';

class HostOnboardingScreen extends StatefulWidget {
  const HostOnboardingScreen({super.key});

  @override
  State<HostOnboardingScreen> createState() => _HostOnboardingScreenState();
}

class _HostOnboardingScreenState extends State<HostOnboardingScreen> {
  final _service = HostOnboardingService();
  final _countryController = TextEditingController();
  final _countryCodeController = TextEditingController();

  String _continent = 'North America';
  bool _loading = false;
  String? _message;

  static const _continents = [
    'Africa',
    'Antarctica',
    'Asia',
    'Europe',
    'North America',
    'Oceania',
    'South America',
  ];

  Future<void> _useGps() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services or use manual entry.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          'Location permission was denied. You can enter your country manually.',
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

      setState(() {
        _message =
            result['message']?.toString() ??
            'Location saved. Onboarding is complete.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst(
            RegExp(r'^(Exception|Bad state): '),
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveManual() async {
    final country = _countryController.text.trim();
    final code = _countryCodeController.text.trim().toUpperCase();

    if (country.isEmpty || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
      setState(() {
        _message = 'Enter a country and a valid two-letter country code.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final result = await _service.saveManualLocation(
        countryCode: code,
        country: country,
        continent: _continent,
      );

      if (!mounted) return;

      setState(() {
        _message =
            result['message']?.toString() ??
            'Location saved. Onboarding is complete.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error.toString().replaceFirst(
            RegExp(r'^(Exception|Bad state): '),
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _countryController.dispose();
    _countryCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete host setup')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.public_rounded, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    'Confirm your location',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We use your country and continent to finish setting '
                    'up your host account. GPS is preferred; manual entry '
                    'is available if GPS does not work.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : _useGps,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use my current location'),
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Or enter your location manually',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _countryController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      hintText: 'e.g. Canada',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _countryCodeController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'Two-letter country code',
                      hintText: 'e.g. CA',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _continent,
                    decoration: const InputDecoration(labelText: 'Continent'),
                    items: _continents
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _continent = value);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _loading ? null : _saveManual,
                    child: const Text('Save manual location'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 20),
                    Text(_message!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
