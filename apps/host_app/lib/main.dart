import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/host_auth_screen.dart';
import 'services/host_presence_service.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const HostApp());
}

class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Platform — Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
      ),
      home: const HostAuthGate(),
    );
  }
}

class HostAuthGate extends StatelessWidget {
  const HostAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;

        if (session == null) {
          return const HostAuthScreen();
        }

        return const HostSignedInScreen();
      },
    );
  }
}

/// A small first step toward the host dashboard. It deliberately does not
/// mark a host Available: automatic status transitions belong to trusted
/// backend code, not to the mobile client.
class HostSignedInScreen extends StatefulWidget {
  const HostSignedInScreen({super.key});

  @override
  State<HostSignedInScreen> createState() => _HostSignedInScreenState();
}

class _HostSignedInScreenState extends State<HostSignedInScreen>
    with WidgetsBindingObserver {
  final HostPresenceService _presence = HostPresenceService();

  Timer? _heartbeatTimer;
  String? _status;
  String? _error;
  bool _loading = true;
  bool _requestingAway = false;
  bool _requestingAvailable = false;
  int _awayMinutes = 15;
  bool _isHost = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _presence.requireHostRole();
      final row = await _presence.getCurrentPresence();
      if (!mounted) return;

      setState(() {
        _isHost = true;
        _status = row?['status'] as String?;
        _error = row == null
            ? 'No presence row exists yet. Apply the reviewed database migration before using presence controls.'
            : null;
        _loading = false;
      });

      if (row != null && _appActive) {
        _startHeartbeat();
        await _sendHeartbeat();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        unawaited(_sendHeartbeat());
        unawaited(_refreshPresence());
      },
    );
  }

  Future<void> _sendHeartbeat() async {
    if (!_appActive || !_isHost) return;
    try {
      await _presence.sendHeartbeat();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Heartbeat failed: ${_friendlyError(error)}');
    }
  }

  Future<void> _refreshPresence() async {
    if (!_appActive || !_isHost) return;
    try {
      final row = await _presence.getCurrentPresence();
      if (!mounted || row == null) return;
      setState(() {
        _status = row['status'] as String?;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _isHost) {
      _startHeartbeat();
      unawaited(_sendHeartbeat());
      unawaited(_refreshPresence());
    } else {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
    }
  }

  Future<void> _requestAvailable() async {
    if (_status != 'offline' && _status != 'away') return;

    setState(() {
      _requestingAvailable = true;
      _error = null;
    });

    try {
      final result = await _presence.requestAvailable();
      if (!mounted) return;
      setState(() {
        _status = result['status'] as String? ?? 'available';
        _error = null;
      });
      _startHeartbeat();
      unawaited(_sendHeartbeat());
      _showMessage('You are now Available.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _requestingAvailable = false);
    }
  }

  Future<void> _requestAway() async {
    if (_status != 'available' && _status != 'away') return;

    setState(() {
      _requestingAway = true;
      _error = null;
    });

    try {
      final result =
          await _presence.requestAway(durationMinutes: _awayMinutes);
      if (!mounted) return;
      setState(() {
        _status = result['status'] as String? ?? 'away';
        _error = null;
      });
      _showMessage('Away set for $_awayMinutes minutes.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _requestingAway = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    // Supabase/PostgREST includes the server's validation message. Keep
    // the surfaced message useful without printing credentials or payloads.
    return message.replaceFirst(RegExp(r'^Exception: '), '');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canRequestAway = _status == 'available' || _status == 'away';
    final canRequestAvailable = _status == 'offline' || _status == 'away';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              _heartbeatTimer?.cancel();
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const CircularProgressIndicator()
                : !_isHost
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error ?? 'This account cannot use the host app.'),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () =>
                                Supabase.instance.client.auth.signOut(),
                            child: const Text('Sign out'),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.video_camera_front_rounded,
                            size: 56,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Presence: ${_status ?? 'unknown'}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose Go Available when you are ready to receive calls. '
                            'Busy and Live are set by trusted backend events.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: canRequestAvailable &&
                                    !_requestingAvailable
                                ? _requestAvailable
                                : null,
                            child: _requestingAvailable
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _status == 'available'
                                        ? 'Available'
                                        : canRequestAvailable
                                            ? 'Go Available'
                                            : 'Finish the active session first',
                                  ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            value: _awayMinutes,
                            decoration: const InputDecoration(
                              labelText: 'Away duration',
                              border: OutlineInputBorder(),
                            ),
                            items: const [1, 5, 15, 30, 60]
                                .map(
                                  (minutes) => DropdownMenuItem<int>(
                                    value: minutes,
                                    child: Text('$minutes minute${minutes == 1 ? '' : 's'}'),
                                  ),
                                )
                                .toList(),
                            onChanged: _requestingAway ||
                                    _requestingAvailable
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _awayMinutes = value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: canRequestAway &&
                                    !_requestingAway &&
                                    !_requestingAvailable
                                ? _requestAway
                                : null,
                            child: _requestingAway
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _status == 'away'
                                        ? 'Renew Away'
                                        : 'Set Away',
                                  ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
