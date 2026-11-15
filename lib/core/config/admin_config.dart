/// إعدادات الاتصال بمشروع Supabase الخاص بلوحة تحكم الأدمن (ERP Admin Control Center)
/// Central Admin Supabase Configuration
class AdminConfig {
  AdminConfig._();

  /// رابط مشروع Supabase الجديد الخاص بالأدمن فقط
  static const String supabaseUrl = String.fromEnvironment(
    'ADMIN_SUPABASE_URL',
    defaultValue: 'https://bwuslqafwlbefntildhx.supabase.co',
  );

  /// المفتاح العمومي (Anon / Publishable Key) الخاص بمشروع الأدمن الجديد
  static const String supabaseAnonKey = String.fromEnvironment(
    'ADMIN_SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_bumvLbOl-vgWynkcWtLsZA_JQLHy79K',
  );

  /// جدول الحسابات الجديد في Supabase
  static const String accountsTable = 'erp_accounts';

  /// جدول الحسابات الاحتياطي / القديم للتوافق الرجعي
  static const String legacyAccountsTable = 'tenants';

  /// جدول إعدادات النظام العامة
  static const String systemSettingsTable = 'system_settings';
}
