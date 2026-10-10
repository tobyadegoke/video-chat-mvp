import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_app/main.dart';
import 'package:host_app/services/host_presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('shows host availability and timed Away controls',
      (WidgetTester tester) async {
    final presence = _FakeHostPresenceService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HostSignedInScreen(presenceService: presence),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome back, Demo Host'), findsOneWidget);
    expect(find.text('You’re Away'), findsOneWidget);
    expect(find.text('Away time remaining'), findsOneWidget);
    expect(find.text('Renew Away'), findsOneWidget);
    expect(find.text('Away duration'), findsOneWidget);
  });

  testWidgets('renews Away through the presence service',
      (WidgetTester tester) async {
    final presence = _FakeHostPresenceService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HostSignedInScreen(presenceService: presence),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Renew Away'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Renew Away'));
    await tester.pump();

    expect(presence.awayRequests, 1);
    expect(find.text('Away renewed for 15 minutes.'), findsOneWidget);
  });
}

class _FakeHostPresenceService extends HostPresenceService {
  _FakeHostPresenceService()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  int awayRequests = 0;

  @override
  Future<String> requireHostRole() async => 'test-host-id';

  @override
  Future<Map<String, dynamic>?> getCurrentHostProfile() async =>
      {'display_name': 'Demo Host'};

  @override
  Future<Map<String, dynamic>?> getCurrentPresence() async => {
        'host_id': 'test-host-id',
        'status': 'away',
        'away_until': DateTime.now()
            .add(const Duration(minutes: 2))
            .toUtc()
            .toIso8601String(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  @override
  Future<void> sendHeartbeat() async {}

  @override
  Future<Map<String, dynamic>> requestAvailable() async => {
        'host_id': 'test-host-id',
        'status': 'available',
        'away_until': null,
      };

  @override
  Future<Map<String, dynamic>> requestAway({int durationMinutes = 15}) async {
    awayRequests++;
    return {
      'host_id': 'test-host-id',
      'status': 'away',
      'away_until': DateTime.now()
          .add(Duration(minutes: durationMinutes))
          .toUtc()
          .toIso8601String(),
    };
  }
}
