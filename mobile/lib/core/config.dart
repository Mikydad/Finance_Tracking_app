/// Build-time configuration, passed with --dart-define:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://PROJECT.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=KEY
/// ```
class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.supabasePublishableKey});

  factory AppConfig.fromEnvironment() => const AppConfig(
        supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
        supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get hasBackend => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
