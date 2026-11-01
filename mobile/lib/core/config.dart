/// Build-time configuration. The app talks to the project's hosted Supabase
/// by default, so `flutter run` and Xcode's Run button need no flags. Both
/// values are public (the publishable key is meant to ship inside the app;
/// row-level security protects the data). Override them for another project:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=KEY
/// ```
///
/// Passing both as empty strings runs the app local-only, with no sign-in.
class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabasePublishableKey});

  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL', defaultValue: defaultSupabaseUrl),
    supabasePublishableKey: String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: defaultSupabasePublishableKey,
    ),
  );

  static const defaultSupabaseUrl = 'https://hpswkgmcxhrrbsnlbbdl.supabase.co';
  static const defaultSupabasePublishableKey = 'sb_publishable_orm-wb-7pBR4Z-c38Z6UYQ_TJ-ltRha';

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get hasBackend => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
