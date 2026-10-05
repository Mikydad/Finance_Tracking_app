import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/local/isar_db.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  if (config.hasBackend) {
    await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabasePublishableKey);
  }
  final isar = await openLocalDb();

  runApp(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(config),
        isarProvider.overrideWithValue(isar),
      ],
      child: const FinanceApp(),
    ),
  );
}
