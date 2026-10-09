import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/host_auth_screen.dart';
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

        // Temporary signed-in destination.
        // We'll replace this with the actual host dashboard next.
        return const HostSignedInScreen();
      },
    );
  }
}

class HostSignedInScreen extends StatelessWidget {
  const HostSignedInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'You are signed in.\nHost dashboard coming next.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
