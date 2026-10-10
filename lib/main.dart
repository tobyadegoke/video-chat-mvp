import 'package:flutter/widgets.dart';
import 'package:host_app/main.dart' as host_app;
import 'package:host_app/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Root development entrypoint.
///
/// The host UI lives in apps/host_app. Reuse that app instead of maintaining
/// a separate demo that attempts to connect with an empty LiveKit token.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const host_app.HostApp());
}
