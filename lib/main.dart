import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../apps/host_app/lib/main.dart' as host_app;
import '../apps/host_app/lib/supabase_config.dart';

/// Root development entrypoint.
///
/// The actual host UI lives in apps/host_app. Reuse that app instead of
/// maintaining a separate demo that attempts to connect with an empty token.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const host_app.HostApp());
}
