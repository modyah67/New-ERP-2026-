/// Supabase project configuration options for "Fruity Farms" ERP.
/// Target project: rakdzuvlauphupkywoik
class SupabaseOptions {
  SupabaseOptions._();

  /// The Supabase URL for the project.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rakdzuvlauphupkywoik.supabase.co',
  );

  /// The Supabase Anon / Public API Key.
  /// Replace 'YOUR_SUPABASE_ANON_KEY' with your anon key from:
  /// Supabase Dashboard -> Project Settings -> API -> anon (public)
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJha2R6dXZsYXVwaHVwa3l3b2lrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkyMjYyNTksImV4cCI6MjEwNDgwMjI1OX0.gK5YRX3oCy8VHLeFcfcw9I1jfZY3gE75tflyyP_owZk',
  );
}
