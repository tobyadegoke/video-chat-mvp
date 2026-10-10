import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/host_auth_screen.dart';
import 'services/host_presence_service.dart';
import 'supabase_config.dart';

const _pageBackground = Color(0xFF090B10);
const _surface = Color(0xFF141821);
const _surfaceRaised = Color(0xFF1B202B);
const _accent = Color(0xFF9B8AFB);
const _mint = Color(0xFF61D9B4);

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
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Video Platform — Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _pageBackground,
        colorScheme: colorScheme.copyWith(
          primary: _accent,
          secondary: _mint,
          surface: _surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _pageBackground,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceRaised,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2B3240)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _accent, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF100D20),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: Color(0xFF394151)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
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

/// Host availability controls only request the supported host RPCs.
/// Busy/Live transitions remain the responsibility of trusted backend events.
class HostSignedInScreen extends StatefulWidget {
  const HostSignedInScreen({super.key});

  @override
  State<HostSignedInScreen> createState() => _HostSignedInScreenState();
}

class _HostSignedInScreenState extends State<HostSignedInScreen>
    with WidgetsBindingObserver {
  final HostPresenceService _presence = HostPresenceService();

  Timer? _heartbeatTimer;
  Timer? _countdownTimer;
  String? _status;
  String? _error;
  String? _displayName;
  DateTime? _awayUntil;
  DateTime? _lastRefreshed;
  bool _loading = true;
  bool _refreshing = false;
  bool _requestingAway = false;
  bool _requestingAvailable = false;
  bool _expiryRefreshRequested = false;
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
      final profile = await _presence.getCurrentHostProfile();
      final row = await _presence.getCurrentPresence();
      if (!mounted) return;

      setState(() {
        _isHost = true;
        _displayName = profile?['display_name'] as String?;
        _status = row?['status'] as String?;
        _awayUntil = _parseAwayUntil(row?['away_until']);
        _expiryRefreshRequested = _status == 'away' &&
            _awayUntil != null &&
            !DateTime.now().isBefore(_awayUntil!);
        _lastRefreshed = DateTime.now();
        _error = row == null
            ? 'Your presence record is missing. The reviewed database migration must be applied before availability controls can work.'
            : null;
        _loading = false;
      });
      _syncCountdownTimer();

      if (row != null && _appActive) {
        _startHeartbeat();
        unawaited(_sendHeartbeat());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isHost = false;
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _retryInitialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _initialize();
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
      setState(() => _error = 'Presence heartbeat failed: ${_friendlyError(error)}');
    }
  }

  Future<void> _refreshPresence() async {
    if (!_appActive || !_isHost) return;

    try {
      final row = await _presence.getCurrentPresence();
      if (!mounted) return;

      final nextStatus = row?['status'] as String?;
      final nextAwayUntil = _parseAwayUntil(row?['away_until']);
      setState(() {
        _status = nextStatus;
        _awayUntil = nextAwayUntil;
        _lastRefreshed = DateTime.now();
        _expiryRefreshRequested = nextStatus == 'away' &&
            nextAwayUntil != null &&
            !DateTime.now().isBefore(nextAwayUntil);
        _error = row == null
            ? 'Your presence record is missing. Apply the reviewed database migration before using availability controls.'
            : null;
      });
      _syncCountdownTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _refreshPresence();
    if (mounted) setState(() => _refreshing = false);
  }

  DateTime? _parseAwayUntil(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  void _syncCountdownTimer() {
    if (_status != 'away' || _awayUntil == null) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _expiryRefreshRequested = false;
      return;
    }

    if (_countdownTimer != null) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_appActive) return;
      setState(() {});
      if (!_expiryRefreshRequested &&
          _awayUntil != null &&
          !DateTime.now().isBefore(_awayUntil!)) {
        _expiryRefreshRequested = true;
        unawaited(_refreshPresence());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && _isHost) {
      _startHeartbeat();
      unawaited(_sendHeartbeat());
      unawaited(_refreshPresence());
      _syncCountdownTimer();
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
        _awayUntil = _parseAwayUntil(result['away_until']);
        _lastRefreshed = DateTime.now();
        _error = null;
      });
      _syncCountdownTimer();
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
        _awayUntil = _parseAwayUntil(result['away_until']);
        _lastRefreshed = DateTime.now();
        _expiryRefreshRequested = false;
        _error = null;
      });
      _syncCountdownTimer();
      _showMessage(
        _status == 'away' ? 'Away renewed for $_awayMinutes minutes.' : 'Away enabled.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _requestingAway = false);
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _statusColor(BuildContext context) {
    switch (_status) {
      case 'available':
        return _mint;
      case 'away':
        return const Color(0xFFFFC66D);
      case 'busy':
        return const Color(0xFFFF986D);
      case 'live':
        return const Color(0xFFFF6577);
      case 'offline':
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _statusIcon() {
    switch (_status) {
      case 'available':
        return Icons.check_circle_rounded;
      case 'away':
        return Icons.schedule_rounded;
      case 'busy':
        return Icons.phone_in_talk_rounded;
      case 'live':
        return Icons.sensors_rounded;
      case 'offline':
      default:
        return Icons.cloud_off_rounded;
    }
  }

  String get _statusTitle {
    switch (_status) {
      case 'available':
        return 'Available for calls';
      case 'away':
        return 'You’re Away';
      case 'busy':
        return 'In a call';
      case 'live':
        return 'Live now';
      case 'offline':
        return 'You’re Offline';
      default:
        return 'Status unavailable';
    }
  }

  String get _statusDescription {
    switch (_status) {
      case 'available':
        return 'You can be discovered and receive incoming calls.';
      case 'away':
        return 'New calls are paused while your Away timer is running.';
      case 'busy':
        return 'Your availability is managed by the active call.';
      case 'live':
        return 'Your availability is managed by the live session.';
      case 'offline':
        return 'Go Available when you’re ready to receive calls.';
      default:
        return 'Refresh to check your current availability.';
    }
  }

  String get _awayCountdown {
    final until = _awayUntil;
    if (until == null) return 'Expiry is being checked';
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      return 'Refreshing your status…';
    }
    final totalSeconds = remaining.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return 'Back in ${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return 'Back in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _lastUpdatedLabel {
    final value = _lastRefreshed;
    if (value == null) return 'Not synced yet';
    final time = TimeOfDay.fromDateTime(value);
    return 'Synced at ${time.format(context)}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isHost) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 44),
                    const SizedBox(height: 18),
                    Text(
                      _error ?? 'This account cannot use the host app.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _retryInitialize,
                      child: const Text('Try again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          Supabase.instance.client.auth.signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final canRequestAway = _status == 'available' || _status == 'away';
    final canRequestAvailable = _status == 'offline' || _status == 'away';
    final statusColor = _statusColor(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.video_camera_front_rounded,
                color: _accent,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CREATOR STUDIO',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Host dashboard',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9299A8),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _refreshing ? null : _manualRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              _heartbeatTimer?.cancel();
              _countdownTimer?.cancel();
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
              children: [
                Text(
                  'Welcome back, ${(_displayName?.trim().isNotEmpty ?? false) ? _displayName!.trim() : 'Creator'}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Your space. Your schedule. You’re in control.',
                  style: TextStyle(
                    color: Color(0xFF9299A8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatusCard(statusColor),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _buildErrorCard(),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Availability',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text(
                      _lastUpdatedLabel,
                      style: const TextStyle(
                        color: Color(0xFF858D9D),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose when you’re ready to receive calls. Active calls and live sessions control their own status.',
                  style: TextStyle(
                    color: Color(0xFF9299A8),
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                _buildAvailabilityControls(
                  canRequestAvailable: canRequestAvailable,
                  canRequestAway: canRequestAway,
                ),
                const SizedBox(height: 22),
                _buildInfoCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22253A), Color(0xFF151922), Color(0xFF12151C)],
        ),
        border: Border.all(color: const Color(0xFF34384D)),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.07),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(_statusIcon(), color: statusColor, size: 27),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT STATUS',
                      style: TextStyle(
                        color: Color(0xFF9CA3B2),
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusDescription,
                      style: const TextStyle(
                        color: Color(0xFFB0B6C3),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_status == 'away') ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC66D).withOpacity(0.09),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: const Color(0xFFFFC66D).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_bottom_rounded,
                    size: 19,
                    color: Color(0xFFFFC66D),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Away time remaining',
                      style: TextStyle(
                        color: Color(0xFFFFD79B),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    _awayCountdown,
                    style: const TextStyle(
                      color: Color(0xFFFFD79B),
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvailabilityControls({
    required bool canRequestAvailable,
    required bool canRequestAway,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF252B37)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: canRequestAvailable &&
                    !_requestingAvailable &&
                    !_requestingAway
                ? _requestAvailable
                : null,
            child: _requestingAvailable
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 19),
                      const SizedBox(width: 9),
                      Text(
                        _status == 'available'
                            ? 'You’re Available'
                            : _status == 'busy' || _status == 'live'
                                ? 'Active session in progress'
                                : 'Go Available',
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded, size: 18, color: _accent),
              SizedBox(width: 8),
              Text(
                'Take a break',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Away expires automatically. You can renew it whenever you need.',
            style: TextStyle(
              color: Color(0xFF9299A8),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<int>(
            value: _awayMinutes,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Away duration',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: const [1, 5, 15, 30, 60]
                .map(
                  (minutes) => DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(
                      '$minutes minute${minutes == 1 ? '' : 's'}',
                    ),
                  ),
                )
                .toList(),
            onChanged: _requestingAway || _requestingAvailable
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _awayMinutes = value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: canRequestAway &&
                    !_requestingAway &&
                    !_requestingAvailable
                ? _requestAway
                : null,
            child: _requestingAway
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bedtime_outlined, size: 18),
                      const SizedBox(width: 9),
                      Text(_status == 'away' ? 'Renew Away' : 'Set Away'),
                    ],
                  ),
          ),
          if (_status == 'busy' || _status == 'live') ...[
            const SizedBox(height: 12),
            const Text(
              'Availability controls are paused while your active session is in progress.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9299A8),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF351C26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6D3447)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFFF91A5),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFFC0CB),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Retry',
            onPressed: _refreshing ? null : _manualRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF252B37)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: _mint, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your status stays in sync',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 5),
                Text(
                  'Availability is checked against the server. The countdown is only a display; the backend decides when Away expires.',
                  style: TextStyle(
                    color: Color(0xFF9299A8),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
