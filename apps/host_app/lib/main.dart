import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/host_auth_screen.dart';
import 'screens/host_chats_screen.dart';

import 'services/host_presence_service.dart';
import 'services/host_chat_service.dart';

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
  const HostSignedInScreen({super.key, this.presenceService});

  @visibleForTesting
  final HostPresenceService? presenceService;

  @override
  State<HostSignedInScreen> createState() => _HostSignedInScreenState();
}

class _HostSignedInScreenState extends State<HostSignedInScreen>
    with WidgetsBindingObserver {
  late final HostPresenceService _presence =
      widget.presenceService ?? HostPresenceService();

  final HostChatService _chatService = HostChatService();

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

  int _selectedDestination = 0;

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

      Map<String, dynamic>? row;

      String? presenceError;

      try {
        row = await _presence.getCurrentPresence();
      } catch (error) {
        presenceError =
            'Could not load availability. The reviewed presence migration may not be applied yet. ${_friendlyError(error)}';
      }

      if (!mounted) return;

      setState(() {
        _isHost = true;

        _displayName = profile?['display_name'] as String?;

        _status = row?['status'] as String?;

        _awayUntil = _parseAwayUntil(row?['away_until']);

        _expiryRefreshRequested = false;

        _lastRefreshed = DateTime.now();

        _error =
            presenceError ??
            (row == null
                ? 'Your presence record is missing. The reviewed database migration must be applied before availability controls can work.'
                : null);

        _loading = false;
      });

      unawaited(_chatService.startInboxRealtime());
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

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_sendHeartbeat());

      unawaited(_refreshPresence());
    });
  }

  Future<void> _sendHeartbeat() async {
    if (!_appActive || !_isHost) return;

    try {
      await _presence.sendHeartbeat();
    } catch (error) {
      if (!mounted) return;

      setState(
        () => _error = 'Presence heartbeat failed: ${_friendlyError(error)}',
      );
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

        _expiryRefreshRequested =
            nextStatus == 'away' &&
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

    setState(() {
      _refreshing = true;

      _expiryRefreshRequested = false;
    });

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

    if (_expiryRefreshRequested && !DateTime.now().isBefore(_awayUntil!)) {
      _countdownTimer?.cancel();

      _countdownTimer = null;

      return;
    }

    if (_countdownTimer != null) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_appActive) return;

      if (!_expiryRefreshRequested &&
          _awayUntil != null &&
          !DateTime.now().isBefore(_awayUntil!)) {
        _expiryRefreshRequested = true;

        _countdownTimer?.cancel();

        _countdownTimer = null;

        setState(() {});

        unawaited(_refreshPresence());

        return;
      }

      setState(() {});
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
      final result = await _presence.requestAway(durationMinutes: _awayMinutes);

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
        _status == 'away'
            ? 'Away renewed for $_awayMinutes minutes.'
            : 'Away enabled.',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _requestingAway = false);
    }
  }

  String _friendlyError(Object error) {
    return error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state): '),

      '',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
    unawaited(_chatService.stopInboxRealtime());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                      onPressed: () => Supabase.instance.client.auth.signOut(),

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
                color: _accent.withValues(alpha: 0.16),

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

      body: _selectedDestination == 0
          ? SafeArea(
              top: false,

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),

                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),

                    children: [
                      Text(
                        'Welcome back, ${(_displayName?.trim().isNotEmpty ?? false) ? _displayName!.trim() : 'Creator'}',

                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
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

                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
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

                      const SizedBox(height: 18),

                      _buildCreatorProgressCard(),
                    ],
                  ),
                ),
              ),
            )
          : _buildDestinationPage(_selectedDestination),

      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: HostChatService.unreadTotal,
        builder: (context, unreadCount, _) {
          const destinationMap = [0, 2, 3, 5, 1];
          final selectedIndex = switch (_selectedDestination) {
            0 => 0,
            2 => 1,
            3 => 2,
            5 => 3,
            1 => 4,
            _ => 0,
          };

          return NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedDestination = destinationMap[index]);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: _chatNavigationIcon(unreadCount),
                selectedIcon: _chatNavigationIcon(unreadCount, selected: true),
                label: 'Chats',
              ),
              const NavigationDestination(
                icon: Icon(Icons.videocam_outlined),
                selectedIcon: Icon(Icons.videocam),
                label: 'Go Live',
              ),
              const NavigationDestination(
                icon: Icon(Icons.star_outline),
                selectedIcon: Icon(Icons.star),
                label: 'Star Hosts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chatNavigationIcon(int unreadCount, {bool selected = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline),
        if (unreadCount > 0)
          Positioned(
            right: -9,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: const BoxDecoration(
                color: Color(0xFFFF6577),
                shape: BoxShape.circle,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDestinationPage(int index) {
    if (index == 2) return const HostChatsScreen();

    const titles = [
      'Home',
      'Profile',
      'Chats',
      'Go Live',
      'Friends',
      'Star Hosts',
    ];

    const subtitles = [
      '',

      'Manage your public creator profile.',

      'Your conversations will appear here.',

      'Prepare your camera, microphone and broadcast details.',

      'Find and manage your creator relationships.',

      'Explore weekly and monthly creator rankings.',
    ];

    const icons = [
      Icons.home_rounded,

      Icons.person_rounded,

      Icons.chat_bubble_rounded,

      Icons.videocam_rounded,

      Icons.people_rounded,

      Icons.star_rounded,
    ];

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),

          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 36),

            children: [
              Row(
                children: [
                  Icon(icons[index], color: _accent, size: 30),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      titles[index],

                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                subtitles[index],

                style: const TextStyle(color: Color(0xFF9299A8), height: 1.45),
              ),

              const SizedBox(height: 22),

              if (index == 3)
                _buildFeatureCard(
                  icon: Icons.live_tv_rounded,

                  title: 'Broadcast setup',

                  description: 'Camera preview, microphone checks, title and cover settings will be connected in the LiveKit broadcast step.',

                  actionLabel: 'Broadcast setup is not connected yet',
                )
              else if (index == 5)
                _buildStarHostsCard()
              else if (index == 1)
                _buildFeatureCard(
                  icon: Icons.edit_outlined,

                  title: 'Creator profile',

                  description: 'Your editable profile, photo, bio and follower statistics will be connected to Supabase.',

                  actionLabel: 'Profile editing is not connected yet',
                )
              else if (index == 2)
                _buildFeatureCard(
                  icon: Icons.mark_chat_unread_outlined,

                  title: 'Your messages',

                  description: 'This screen will reuse the existing messaging services when the Host app integration is added.',

                  actionLabel: 'Messaging integration is pending',
                )
              else
                _buildFeatureCard(
                  icon: Icons.people_outline,

                  title: 'Friends and followers',

                  description: 'Search, follow status, availability and profile actions will be wired to the shared relationship model.',

                  actionLabel: 'Relationship integration is pending',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,

    required String title,

    required String description,

    required String actionLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFF2B3240)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, color: _accent, size: 28),

          const SizedBox(height: 14),

          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 8),

          Text(
            description,
            style: const TextStyle(color: Color(0xFF9299A8), height: 1.5),
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),

            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),

              borderRadius: BorderRadius.circular(12),
            ),

            child: Text(
              actionLabel,
              style: const TextStyle(
                color: _accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarHostsCard() {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFF2B3240)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Row(
            children: [
              Icon(Icons.star_rounded, color: Color(0xFFFFD166), size: 28),

              SizedBox(width: 10),

              Text(
                'Star Hosts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ],
          ),

          const SizedBox(height: 8),

          const Text(
            'Celebrate the creators making the biggest impact.',
            style: TextStyle(color: Color(0xFF9299A8)),
          ),

          const SizedBox(height: 18),

          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'weekly',
                label: Text('Weekly'),
                icon: Icon(Icons.calendar_view_week),
              ),

              ButtonSegment(
                value: 'monthly',
                label: Text('Monthly'),
                icon: Icon(Icons.calendar_month),
              ),
            ],

            selected: const {'weekly'},

            onSelectionChanged: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ranking data integration is the next step.'),
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),

              child: Column(
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    color: Color(0xFFFFD166),
                    size: 42,
                  ),

                  SizedBox(height: 10),

                  Text(
                    'Rankings are coming next',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),

                  SizedBox(height: 6),

                  Text(
                    'We will show verified scores once ranking metrics are connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9299A8)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorProgressCard() {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: const Color(0xFF2B3240)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Creator Progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),

              Icon(
                Icons.insights_rounded,
                color: _accent.withValues(alpha: 0.9),
              ),
            ],
          ),

          const SizedBox(height: 18),

          const Row(
            children: [
              Expanded(
                child: _ProgressMetric(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Gifts received',
                ),
              ),

              SizedBox(width: 14),

              Expanded(
                child: _ProgressMetric(
                  icon: Icons.groups_rounded,
                  label: 'Engagement',
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Row(
            children: [
              Expanded(
                child: Text(
                  'Next level',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),

              Text(
                'Coming later',
                style: TextStyle(color: Color(0xFF9299A8), fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(20)),

            child: LinearProgressIndicator(
              value: 0,

              minHeight: 7,

              backgroundColor: const Color(0xFF2B3240),

              valueColor: AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Progress thresholds will be defined when the level system is designed.',
            style: TextStyle(color: Color(0xFF9299A8), fontSize: 11),
          ),
        ],
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
            color: _accent.withValues(alpha: 0.07),

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
                  color: statusColor.withValues(alpha: 0.13),

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
                color: const Color(0xFFFFC66D).withValues(alpha: 0.09),

                borderRadius: BorderRadius.circular(15),

                border: Border.all(
                  color: const Color(0xFFFFC66D).withValues(alpha: 0.2),
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
            onPressed:
                canRequestAvailable && !_requestingAvailable && !_requestingAway
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
              Icon(
                Icons.pause_circle_outline_rounded,

                size: 18,

                color: _accent,
              ),

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
            initialValue: _awayMinutes,

            isExpanded: true,

            decoration: const InputDecoration(
              labelText: 'Away duration',

              prefixIcon: Icon(Icons.timer_outlined),
            ),

            items: const [1, 5, 15, 30, 60]
                .map(
                  (minutes) => DropdownMenuItem<int>(
                    value: minutes,

                    child: Text('$minutes minute${minutes == 1 ? '' : 's'}'),
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
            onPressed:
                canRequestAway && !_requestingAway && !_requestingAvailable
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

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF9299A8), fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          '—',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Awaiting data integration',
          style: TextStyle(color: Color(0xFF9299A8), fontSize: 10),
        ),
      ],
    );
  }
}
