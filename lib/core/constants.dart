// lib/core/constants.dart
// ─────────────────────────────────────────────
// All app-wide fixed values live here.
// Change them in ONE place and it updates everywhere.
// ─────────────────────────────────────────────

class AppConstants {
  // App info
  static const String appName = 'FRUITY FARMS';
  static const String appVersion = '1.0.0';
  static String companyName = 'مزارع فروتي';
  static String companyAddress = ' التجمع الخامس - القاهرة الجديدة - مصر';
  static String companyPhone = '01000000000';

  // Database
  static const String databaseName = 'accounting.db';
  static const int databaseVersion =
      16; // adds high-performance WAL & 100M+ scaling indexes (16)

  // Default admin credentials (change after first login)
  static const String defaultUsername = '1';
  static const String defaultPassword = '1111';

  // Invoice settings
  static const String invoiceCurrency = 'ج.م';

  // Date format
  static const String dateFormat = 'yyyy-MM-dd';
  static const String displayDateFormat = 'dd/MM/yyyy';
}

// Transaction types
class TransactionType {
  static const String debit = 'debit'; // مدين
  static const String credit = 'credit'; // دائن
}

// Account types
class AccountType {
  static const String asset = 'asset'; // أصول
  static const String liability = 'liability'; // خصوم
  static const String equity = 'equity'; // حقوق ملكية
  static const String revenue = 'revenue'; // إيرادات
  static const String expense = 'expense'; // مصروفات
}

// Item types
class ItemType {
  static const String raw = 'خام'; // خام
  static const String ready = 'مجهز'; // مجهز
}

// Invoice status
class InvoiceStatus {
  static const String draft = 'draft';
  static const String confirmed = 'confirmed';
  static const String paid = 'paid';
  static const String cancelled = 'cancelled';
}
