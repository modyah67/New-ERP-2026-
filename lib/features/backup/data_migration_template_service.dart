import 'dart:io';
import 'package:excel/excel.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../core/utils/file_helper.dart';

/// Specification for a single column in a migration template.
class MigrationColumnSpec {
  final String columnName; // Exact programmatic column name
  final String arabicLabel; // Arabic description / display name
  final String dataType; // TEXT, NUMERIC, BOOLEAN, etc.
  final bool isRequired;
  final String? allowedValuesHint; // Hints for enum / valid values
  final double columnWidth;

  const MigrationColumnSpec({
    required this.columnName,
    required this.arabicLabel,
    required this.dataType,
    this.isRequired = false,
    this.allowedValuesHint,
    this.columnWidth = 22.0,
  });

  /// Name formatted for Excel header (appends '*' if required)
  String get excelHeaderName => isRequired ? '$columnName*' : columnName;
}

/// Specification for a single table / sheet in the migration templates.
class MigrationTableSpec {
  final String tableId; // Supabase table name
  final String sheetName; // Excel sheet title
  final String fileName; // Dedicated single-file template name
  final String arabicTitle; // Friendly Arabic title
  final String description; // Detailed description of purpose
  final List<MigrationColumnSpec> columns;

  const MigrationTableSpec({
    required this.tableId,
    required this.sheetName,
    required this.fileName,
    required this.arabicTitle,
    required this.description,
    required this.columns,
  });

  /// Programmatic column names matching Supabase schema (without '*')
  List<String> get headerColumnNames => columns.map((c) => c.columnName).toList();

  /// Formatted column names with '*' for required fields
  List<String> get excelHeaderColumnNames => columns.map((c) => c.excelHeaderName).toList();
}

/// Service to generate and export empty, standardized Excel templates for initial data migration.
/// Contains EXCLUSIVELY the 14 master sheets requested:
///  1. العملاء - تصديري (Export Customers)
///  2. العملاء - محلي (Local Customers)
///  3. موردين المحاصيل (Crop Suppliers)
///  4. موردين مواد التعبئة (Packing Materials Suppliers)
///  5. الموردين المشتركين (Shared Suppliers)
///  6. موردي المحطات (Station Suppliers)
///  7. موردي النقل (Transport Suppliers)
///  8. موردي التخصيمات (Deduction Suppliers)
///  9. المخلص البحري (Sea Clearing Agents)
/// 10. المخلص الجوي (Air Clearing Agents)
/// 11. شركات الشحن (Shipping Companies)
/// 12. المحطات (Stations)
/// 13. فئات مواد التعبئة (Packing Material Categories)
/// 14. مواد التعبئة والمستلزمات (Packing Materials & Items)
class DataMigrationTemplateService {
  static const String defaultUnifiedFileName = 'Fruity_Farms_Data_Migration_Templates.xlsx';
  static const String defaultMockDataFileName = 'Fruity_Farms_Test_Data_Migration.xlsx';

  /// Predefined master specifications for the 14 required tables.
  static List<MigrationTableSpec> get allTableSpecs => const [
    // ── 1. العملاء - تصديري (Export Customers) ─────────────────
    MigrationTableSpec(
      tableId: 'customers',
      sheetName: 'العملاء - تصديري',
      fileName: '01_Export_Customers_Template.xlsx',
      arabicTitle: 'العملاء - تصديري',
      description: 'بيانات عملاء التصدير الخارجي والبيانات الجمركية والضريبية والأرصدة',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود العميل',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للعميل (مثال: EXP-001 أو 2001)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم العميل / الشركة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم شركة الاستيراد أو العميل الخارجي',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'USD | EUR | GBP (الافتراضي USD)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف أو الواتساب الدولي مع كود الدولة',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني الرسمي للشركة',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'city',
          arabicLabel: 'المدينة / الميناء',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'مدينة العميل أو ميناء الوصول',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'country',
          arabicLabel: 'الدولة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'دولة الوجهة (مثال: روسيا، هولندا، إنجلترا، الإمارات)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'العنوان التفصيلي للشركة المستوردة',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_person',
          arabicLabel: 'مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'اسم الشخص المسؤول عن المتابعة والطلبيات',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_phone',
          arabicLabel: 'هاتف مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'هاتف التواصل المباشر مع المسؤول',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_email',
          arabicLabel: 'إيميل مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني للمسؤول',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'vat_number',
          arabicLabel: 'الرقم الضريبي (VAT)',
          dataType: 'TEXT',
          allowedValuesHint: 'الرقم الضريبي VAT إن وجد',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'eori_number',
          arabicLabel: 'رقم EORI للتصدير',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم EORI للعملاء الأوروبيين',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'DEBIT (مدين / عليه) | CREDIT (دائن / له)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 2. العملاء - محلي (Local Customers) ───────────────────
    MigrationTableSpec(
      tableId: 'customers',
      sheetName: 'العملاء - محلي',
      fileName: '02_Local_Customers_Template.xlsx',
      arabicTitle: 'العملاء - محلي',
      description: 'بيانات العملاء وتجار السوق المحلي والأرصدة الافتتاحية',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود العميل',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للعميل (مثال: LOC-001 أو 2501)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم العميل / التاجر',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم العميل أو التاجر أو الشركة المحلية',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP (الافتراضي للعملاء المحليين)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني إن وجد',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'city',
          arabicLabel: 'المدينة / المحافظة',
          dataType: 'TEXT',
          allowedValuesHint: 'المحافظة أو المدينة (مثال: القاهرة، الإسكندرية)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'country',
          arabicLabel: 'الدولة',
          dataType: 'TEXT',
          allowedValuesHint: 'مصر',
          columnWidth: 16.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'العنوان التفصيلي / السوق / المحل',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_person',
          arabicLabel: 'مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'اسم مسؤول المشتريات أو الاستلام',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_phone',
          arabicLabel: 'هاتف مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'هاتف مسؤول التواصل',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_email',
          arabicLabel: 'إيميل مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني للمسؤول',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'DEBIT (مدين / عليه) | CREDIT (دائن / له)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 3. موردين المحاصيل (Crop Suppliers) ─────────────────────
    MigrationTableSpec(
      tableId: 'suppliers',
      sheetName: 'موردين المحاصيل',
      fileName: '03_Crop_Suppliers_Template.xlsx',
      arabicTitle: 'موردين المحاصيل الزراعية',
      description: 'بيانات موردي المحاصيل الزراعية والفاكهة والأرصدة الافتتاحية',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المورد',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 50000-59999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المورد / المزرعة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم المزارع أو المورد أو اسم المزرعة',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان / موقع المزرعة',
          dataType: 'TEXT',
          allowedValuesHint: 'المحافظة / المركز / موقع المزرعة',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 4. موردين مواد التعبئة (Packing Materials Suppliers) ───
    MigrationTableSpec(
      tableId: 'suppliers',
      sheetName: 'موردين مواد التعبئة',
      fileName: '04_Packing_Materials_Suppliers_Template.xlsx',
      arabicTitle: 'موردين مواد ومستلزمات التعبئة',
      description: 'بيانات موردي الكراتين، الباليتات، الأطباق، ومستلزمات التعبئة',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المورد',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 70000-74999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم مورد التعبئة / المصنع',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم شركة الكرتون أو مصنع البلاستيك أو المورد',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'مقر المصنع أو الشركة أو المخزن',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 5. الموردين المشتركين (Shared Suppliers) ────────────────
    MigrationTableSpec(
      tableId: 'suppliers',
      sheetName: 'الموردين المشتركين',
      fileName: '05_Shared_Suppliers_Template.xlsx',
      arabicTitle: 'الموردين المشتركين (محاصيل وتعبئة)',
      description: 'بيانات الموردين الذين يتم التوريد منهم محاصيل ومواد تعبئة معاً',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المورد',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 75000-79999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المورد المشترك',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم المورد أو الجهة المشتركة',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'العنوان والمقر',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 6. موردي المحطات (Station Suppliers) ───────────────────
    MigrationTableSpec(
      tableId: 'suppliers',
      sheetName: 'موردي المحطات',
      fileName: '06_Station_Suppliers_Template.xlsx',
      arabicTitle: 'موردي المحطات والخدمات اللوجستية',
      description: 'محطات الفرز والتعبئة ومزودي الخدمات التشغيلية',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود مورد المحطة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 85000-89999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المحطة / المورد',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'الاسم الرسمي للمحطة أو مورد الخدمة',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان / الموقع',
          dataType: 'TEXT',
          allowedValuesHint: 'موقع المحطة وعنوانها',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'services_mapping',
          arabicLabel: 'خدمات المحطة',
          dataType: 'TEXT',
          allowedValuesHint: 'تشغيل | تبريد | حفظ مبرد | تقفيل كرتون | تعتيق صادر | اعادة تدوير | عماله | تبخير | تدوير خام',
          columnWidth: 48.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 7. موردي النقل (Transport Suppliers) ───────────────────
    MigrationTableSpec(
      tableId: 'transport_suppliers',
      sheetName: 'موردي النقل',
      fileName: '07_Transport_Suppliers_Template.xlsx',
      arabicTitle: 'موردي النقل والأسطول',
      description: 'بيانات مقاولي وشركات النقل البري وأرصدة الرحلات',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود مورد النقل',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 60000-69999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المورد / شركة النقل',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم مقاول النقل أو اسم الشركة',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP (الافتراضي لموردي النقل الداخلي)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني إن وجد',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'available_trips_count',
          arabicLabel: 'رصيد الرحلات الافتتاحي',
          dataType: 'NUMERIC',
          allowedValuesHint: 'عدد النقلات أو الرحلات الافتتاحية المدفوعة مسبقاً',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'notes',
          arabicLabel: 'ملاحظات',
          dataType: 'TEXT',
          allowedValuesHint: 'خطوط السير أو أنواع الشاحنات أو ملاحظات',
          columnWidth: 28.0,
        ),
      ],
    ),

    // ── 8. موردي التخصيمات (Deduction Suppliers) ───────────────
    MigrationTableSpec(
      tableId: 'suppliers',
      sheetName: 'موردي التخصيمات',
      fileName: '08_Deduction_Suppliers_Template.xlsx',
      arabicTitle: 'موردي التخصيمات والرسوم الحكومية',
      description: 'الجهات والوحدات المستحقة لرسوم الفحص والتخصيم والشهادات',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود جهة التخصيم',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 40000-49999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم جهة التخصيم',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم الجهة أو المعمل أو وحدة التخصيم',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'مقر الجهة أو المعمل',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'deductions_mapping',
          arabicLabel: 'أنواع التخصيمات',
          dataType: 'TEXT',
          allowedValuesHint: 'رسوم فحص | تخصيم عربي | تخصيم اوروبي | تحليل خاص | تحليل هيئه | سحب عينه عربي | تعديل وجات | دفتر حجر زراعي | دفتر حجر سلامة غذاء',
          columnWidth: 50.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD | EUR (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          isRequired: true,
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'balance_direction',
          arabicLabel: 'طبيعة الرصيد',
          dataType: 'TEXT',
          allowedValuesHint: 'CREDIT (دائن / له) | DEBIT (مدين / عليه)',
          columnWidth: 20.0,
        ),
      ],
    ),

    // ── 9. المخلص البحري (Sea Clearing Agents) ─────────────────
    MigrationTableSpec(
      tableId: 'clearing_agents',
      sheetName: 'المخلص البحري',
      fileName: '09_Sea_Clearing_Agents_Template.xlsx',
      arabicTitle: 'المخلص الجمركي البحري',
      description: 'وكلاء التخليص الجمركي في الموانئ البحرية (الإسكندرية، دمياط، بورسعيد)',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المخلص',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للمخلص الجمركي البحري',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المخلص / مكتب التخليص',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'الاسم الرسمي للمخلص أو مكتب التخليص',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني الرسمي',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'city',
          arabicLabel: 'المدينة / الميناء',
          dataType: 'TEXT',
          allowedValuesHint: 'الميناء البحري (مثال: ميناء الإسكندرية، ميناء دمياط)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'country',
          arabicLabel: 'الدولة',
          dataType: 'TEXT',
          allowedValuesHint: 'مصر',
          columnWidth: 16.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'عنوان المكتب الجمركي',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_person',
          arabicLabel: 'مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'اسم المندوب أو مسؤول المتابعة بالميناء',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
      ],
    ),

    // ── 10. المخلص الجوي (Air Clearing Agents) ──────────────────
    MigrationTableSpec(
      tableId: 'clearing_agents',
      sheetName: 'المخلص الجوي',
      fileName: '10_Air_Clearing_Agents_Template.xlsx',
      arabicTitle: 'المخلص الجمركي الجوي',
      description: 'وكلاء ومكاتب التخليص الجمركي للشحن الجوي ومطار القاهرة',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المخلص',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للمخلص الجمركي الجوي',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المخلص / مكتب التخليص',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'الاسم الرسمي للمخلص أو مكتب التخليص الجوي',
          columnWidth: 28.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني الرسمي',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'city',
          arabicLabel: 'المدينة / المطار',
          dataType: 'TEXT',
          allowedValuesHint: 'المطار (مثال: قرية البضائع - مطار القاهرة)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'country',
          arabicLabel: 'الدولة',
          dataType: 'TEXT',
          allowedValuesHint: 'مصر',
          columnWidth: 16.0,
        ),
        MigrationColumnSpec(
          columnName: 'address',
          arabicLabel: 'العنوان',
          dataType: 'TEXT',
          allowedValuesHint: 'عنوان المكتب بقرية البضائع',
          columnWidth: 24.0,
        ),
        MigrationColumnSpec(
          columnName: 'contact_person',
          arabicLabel: 'مسؤول الاتصال',
          dataType: 'TEXT',
          allowedValuesHint: 'اسم مندوب التخليص الجوي',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
      ],
    ),

    // ── 11. شركات الشحن (Shipping Companies) ───────────────────
    MigrationTableSpec(
      tableId: 'shipping_companies',
      sheetName: 'شركات الشحن',
      fileName: '11_Shipping_Companies_Template.xlsx',
      arabicTitle: 'شركات وخطوط الملاحة والشحن الدولي',
      description: 'بيانات التوكيلات الملاحية وخطوط الشحن البحري والجوي',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود شركة الشحن',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد (نطاق مقترح: 90000-99999)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم شركة / خط الشحن',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم التوكيل الملاحي أو شركة الشحن (مثال: Maersk, MSC, CMA)',
          columnWidth: 30.0,
        ),
        MigrationColumnSpec(
          columnName: 'phone',
          arabicLabel: 'رقم الهاتف',
          dataType: 'TEXT',
          allowedValuesHint: 'رقم الهاتف للتواصل والمتابعة',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'email',
          arabicLabel: 'البريد الإلكتروني',
          dataType: 'TEXT',
          allowedValuesHint: 'البريد الإلكتروني الرسمي لحجز الحاويات (Bookings)',
          columnWidth: 26.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_balance',
          arabicLabel: 'الرصيد الافتتاحي',
          dataType: 'NUMERIC',
          allowedValuesHint: 'قيمة موجبة للرصيد الافتتاحي (0 إن لا يوجد)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'USD | EUR | EGP (الافتراضي USD)',
          columnWidth: 14.0,
        ),
      ],
    ),

    // ── 12. المحطات (Stations) ──────────────────────────────────
    MigrationTableSpec(
      tableId: 'stations',
      sheetName: 'المحطات',
      fileName: '12_Stations_Template.xlsx',
      arabicTitle: 'المحطات ومواقع الفرز والتعبئة',
      description: 'تعريف محطات التعبئة والمواقع التشغيلية التابعة للنظام',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المحطة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للمحطة (مثال: ST-01 أو 85001)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المحطة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'الاسم الرسمي لمحطة الفرز والتعبئة',
          columnWidth: 28.0,
        ),
      ],
    ),

    // ── 13. فئات مواد التعبئة (Packing Material Categories) ───────
    MigrationTableSpec(
      tableId: 'raw_material_categories',
      sheetName: 'فئات مواد التعبئة',
      fileName: '13_Packing_Material_Categories_Template.xlsx',
      arabicTitle: 'فئات وتصنيفات مواد التعبئة',
      description: 'تعريف فئات مواد ومستلزمات التعبئة (كراتين، أطباق، زوايا، باليتات)',
      columns: [
        MigrationColumnSpec(
          columnName: 'category_name',
          arabicLabel: 'اسم الفئة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم الفئة (مثال: كراتين، أطباق، زوايا، طبالي، مواد تعبئة)',
          columnWidth: 32.0,
        ),
      ],
    ),

    // ── 14. مواد التعبئة والمستلزمات (Packing Materials & Items) ──
    MigrationTableSpec(
      tableId: 'raw_materials',
      sheetName: 'مواد التعبئة والمستلزمات',
      fileName: '14_Packing_Materials_Items_Template.xlsx',
      arabicTitle: 'مواد التعبئة والمستلزمات',
      description: 'تعريف خامات ومواد التعبئة والأرصدة الافتتاحية والمحطة المرتبطة',
      columns: [
        MigrationColumnSpec(
          columnName: 'code',
          arabicLabel: 'كود المادة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'كود فريد للمادة (مثال: MAT-001 أو BOX-05)',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'name',
          arabicLabel: 'اسم المادة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'الاسم التفصيلي للمادة (مثال: كرتونة تليسكوبيك 5 كجم)',
          columnWidth: 30.0,
        ),
        MigrationColumnSpec(
          columnName: 'currency',
          arabicLabel: 'العملة',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'EGP | USD (الافتراضي EGP)',
          columnWidth: 14.0,
        ),
        MigrationColumnSpec(
          columnName: 'unit',
          arabicLabel: 'وحدة القياس',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'قطعة | رول | كرتونة | باليتة | كجم',
          columnWidth: 18.0,
        ),
        MigrationColumnSpec(
          columnName: 'category',
          arabicLabel: 'الفئة التابعة لها',
          dataType: 'TEXT',
          isRequired: true,
          allowedValuesHint: 'اسم فئة المادة (يطابق أسماء تبويب فئات مواد التعبئة)',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_quantity',
          arabicLabel: 'الكمية الابتدائية',
          dataType: 'NUMERIC',
          allowedValuesHint: 'الرصيد الفعلي أول المدة (0 إن لا يوجد)',
          columnWidth: 20.0,
        ),
        MigrationColumnSpec(
          columnName: 'opening_cost_price',
          arabicLabel: 'سعر الوحدة الابتدائي',
          dataType: 'NUMERIC',
          allowedValuesHint: 'سعر تكلفة شراء الوحدة الافتتاحي',
          columnWidth: 22.0,
        ),
        MigrationColumnSpec(
          columnName: 'station_id',
          arabicLabel: 'المحطة المرتبطة',
          dataType: 'TEXT',
          allowedValuesHint: 'كود المحطة المرتبطة بالمادة (station code)',
          columnWidth: 20.0,
        ),
      ],
    ),
  ];

  // ── Excel Header & Palette Styling ────────────────────────
  static const String _requiredHeaderBg = '#991B1B'; // Deep Crimson Red (Tailwind red-800) for Mandatory Columns (*)
  static const String _requiredHeaderFg = '#FFFFFF'; // Crisp Pure White
  static const String _optionalHeaderBg = '#1E293B'; // Deep Slate Navy (Tailwind slate-800) for Optional Columns
  static const String _optionalHeaderFg = '#F8FAFC'; // Off-white / Slate 50
  static const String _guideHeaderBg = '#1E3A8A'; // Blue 900
  static const String _subHeaderBg = '#334155'; // Slate 700

  /// Generates the raw bytes of the unified multi-sheet workbook containing all 14 templates.
  /// Follows the strict requirement:
  /// - Data sheets contain ONLY the programmatic column headers (Row 0).
  /// - NO sample/dummy rows in the data sheets.
  /// - Includes an initial "Guide / تعليمات" sheet explaining the schemas and validation rules.
  static List<int> generateUnifiedWorkbookBytes() {
    final excel = Excel.createExcel();

    // 1. Build Guide / Instructions Sheet
    _buildGuideSheet(excel);
    excel.delete('Sheet1'); // Remove default empty sheet after creating guide sheet

    // 2. Build each individual data template sheet
    for (final spec in allTableSpecs) {
      _buildDataTemplateSheet(excel, spec);
    }

    return excel.save()!;
  }

  /// Generates the raw bytes of a test Excel file containing realistic, consistent mock data
  /// across all 14 sheets to test the Supabase import process and verify foreign key integrity.
  /// [rowCountPerSheet] controls the number of rows generated for each sheet (default: 100).
  static List<int> generateMockDataWorkbookBytes({int rowCountPerSheet = 100}) {
    final excel = Excel.createExcel();

    // 1. Build Guide / Instructions Sheet
    _buildGuideSheet(excel);
    excel.delete('Sheet1'); // Remove default empty sheet after creating guide sheet

    // 2. Build each individual sheet with headers (Row 0) + Realistic Mock Rows (Row 1, 2...)
    for (final spec in allTableSpecs) {
      _buildDataTemplateSheet(excel, spec);
      final sheet = excel[spec.sheetName];
      final mockRows = _getMockRowsForSheet(spec.sheetName, rowCount: rowCountPerSheet);
      for (final rowValues in mockRows) {
        final cells = rowValues.map((val) {
          if (val is int) return IntCellValue(val);
          if (val is double) return DoubleCellValue(val);
          if (val is bool) return BoolCellValue(val);
          return TextCellValue(val.toString());
        }).toList();
        sheet.appendRow(cells);
      }
    }

    return excel.save()!;
  }

  /// Export and save the test mock data Excel workbook directly to the user's Documents folder.
  /// If the target file is currently open in Excel or another program, it automatically saves to a numbered copy.
  /// Automatically opens the generated file if [openAfterSave] is true.
  static Future<String> exportMockDataWorkbook({
    int rowCountPerSheet = 100,
    String? customDirectory,
    bool openAfterSave = true,
  }) async {
    final bytes = generateMockDataWorkbookBytes(rowCountPerSheet: rowCountPerSheet);
    final Directory baseDir;
    if (customDirectory != null && customDirectory.isNotEmpty) {
      baseDir = Directory(customDirectory);
    } else {
      final docDir = await FileHelper.getExportDirectory();
      baseDir = Directory(p.join(docDir.path, 'Fruity_ERP_Migration_Templates'));
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final savedFile = await _writeFileSafely(baseDir, defaultMockDataFileName, bytes);

    if (openAfterSave && await savedFile.exists()) {
      try {
        await OpenFilex.open(savedFile.path);
      } catch (_) {}
    }

    return savedFile.path;
  }

  /// Generates the raw bytes for a single table's dedicated template workbook.
  static List<int> generateSingleTemplateBytes(MigrationTableSpec spec) {
    final excel = Excel.createExcel();

    // Build the data template sheet
    _buildDataTemplateSheet(excel, spec);
    excel.delete('Sheet1'); // Delete default Sheet1 after creating the data sheet

    return excel.save()!;
  }

  /// Export and save the unified multi-sheet workbook directly to the user's Documents folder.
  /// If the target file is currently open in Excel or another program, it automatically saves to a numbered copy.
  /// Automatically opens the generated file if [openAfterSave] is true.
  static Future<String> exportUnifiedWorkbook({
    String? customDirectory,
    bool openAfterSave = true,
  }) async {
    final bytes = generateUnifiedWorkbookBytes();
    final Directory baseDir;
    if (customDirectory != null && customDirectory.isNotEmpty) {
      baseDir = Directory(customDirectory);
    } else {
      final docDir = await FileHelper.getExportDirectory();
      baseDir = Directory(p.join(docDir.path, 'Fruity_ERP_Migration_Templates'));
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final savedFile = await _writeFileSafely(baseDir, defaultUnifiedFileName, bytes);

    if (openAfterSave && await savedFile.exists()) {
      try {
        await OpenFilex.open(savedFile.path);
      } catch (_) {}
    }

    return savedFile.path;
  }

  /// Export all tables as separate, individual Excel template files inside a dedicated folder.
  /// If any file is locked/open, it automatically saves to a numbered copy without crashing.
  /// Returns the path to the directory containing all generated files.
  static Future<String> exportIndividualTemplates({
    String? customDirectory,
    bool openFolderAfterSave = true,
  }) async {
    final Directory targetDir;
    if (customDirectory != null && customDirectory.isNotEmpty) {
      targetDir = Directory(customDirectory);
    } else {
      final docDir = await FileHelper.getExportDirectory();
      targetDir = Directory(p.join(docDir.path, 'Fruity_ERP_Migration_Templates', 'Individual_Files'));
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final spec in allTableSpecs) {
      final bytes = generateSingleTemplateBytes(spec);
      await _writeFileSafely(targetDir, spec.fileName, bytes);
    }

    if (openFolderAfterSave && await targetDir.exists()) {
      try {
        await OpenFilex.open(targetDir.path);
      } catch (_) {}
    }

    return targetDir.path;
  }

  /// Safely writes bytes to a file. If the file is locked by another process (e.g. open in Microsoft Excel),
  /// it automatically falls back to an incremental numbered suffix like `_v2.xlsx` or `_(1).xlsx`
  /// to prevent `PathAccessException` (OS Error 32).
  static Future<File> _writeFileSafely(Directory dir, String fileName, List<int> bytes) async {
    final targetPath = p.join(dir.path, fileName);
    final targetFile = File(targetPath);
    try {
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile;
    } on FileSystemException catch (_) {
      // The file is open in Excel or another program.
      final ext = p.extension(fileName);
      final base = p.basenameWithoutExtension(fileName);
      for (int i = 1; i <= 50; i++) {
        final fallbackPath = p.join(dir.path, '${base}_($i)$ext');
        final fallbackFile = File(fallbackPath);
        try {
          await fallbackFile.writeAsBytes(bytes, flush: true);
          return fallbackFile;
        } on FileSystemException catch (_) {
          continue;
        }
      }
      final fallbackPath = p.join(dir.path, '${base}_${DateTime.now().millisecondsSinceEpoch}$ext');
      final fallbackFile = File(fallbackPath);
      await fallbackFile.writeAsBytes(bytes, flush: true);
      return fallbackFile;
    }
  }

  // ── Helper: Build Data Sheet (Row 0 Headers Only) ──────────
  static void _buildDataTemplateSheet(Excel excel, MigrationTableSpec spec) {
    final sheet = excel[spec.sheetName];

    // Append Row 0 (Strict programmatic headers with * appended for required fields)
    final headerRowCells = spec.columns.map((c) => TextCellValue(c.excelHeaderName)).toList();
    sheet.appendRow(headerRowCells);

    // Format Header Cells:
    // - Required: Vibrant Crimson Red background (_requiredHeaderBg) with bold white text
    // - Optional: Deep Slate Navy background (_optionalHeaderBg) with bold light slate text
    for (int colIndex = 0; colIndex < spec.columns.length; colIndex++) {
      final colSpec = spec.columns[colIndex];
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: 0));
      final bgHex = colSpec.isRequired ? _requiredHeaderBg : _optionalHeaderBg;
      final fgHex = colSpec.isRequired ? _requiredHeaderFg : _optionalHeaderFg;

      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 12,
        fontColorHex: ExcelColor.fromHexString(fgHex),
        backgroundColorHex: ExcelColor.fromHexString(bgHex),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // Auto-set column width
      sheet.setColumnWidth(colIndex, colSpec.columnWidth);
    }

    // STRICT REQUIREMENT: No dummy or sample data rows added.
    // Row 0 is the ONLY row in this sheet.
  }

  // ── Helper: Build Instructions / Guide Sheet ───────────────
  static void _buildGuideSheet(Excel excel) {
    final sheet = excel['دليل_التعليمات (Guide)'];

    int r = 0;

    // Title Row
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r),
    );
    final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
    titleCell.value = TextCellValue('نظام مزارع فروتي ERP - قوالب ترحيل وإدخال البيانات الافتتاحية');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString(_guideHeaderBg),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    r++;

    // Subtitle Row
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r),
    );
    final subCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
    subCell.value = TextCellValue('دليل الحقول وقواعد إدخال البيانات المعتمدة لقاعدة بيانات Supabase');
    subCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 12,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString(_subHeaderBg),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    r += 2;

    // Rules Summary
    final rules = [
      '★ تنبيه هام وميثاق الألوان في صف العناوين (Headers):',
      '  🔴 الخلايا باللون الأحمر الداكن وعلامة النجمة (*) [مثل code*, name*, currency*, opening_balance*]: حقول إجبارية إلزامية لا يمكن تركها فارغة لنجاح الربط المحاسبي.',
      '  🔵 الخلايا باللون الكحلي الداكن [مثل phone, email, address, notes]: حقول اختيارية تكميلية يفضل ملؤها متى توافرت.',
      '1. الحفاظ على صف العناوين: لا تقم بتعديل أو حذف الصف الأول (صف أسماء الأعمدة البرمجية) في أي تبويب لضمان الرفع الآلي المباشر.',
      '2. بدء الإدخال من الصف الثاني: يتم تسجيل بيانات السجلات ابتداءً من الصف رقم 2 مباشرة.',
      '3. عدم تكرار الأكواد (code): الأكواد التعريفية يجب أن تكون أرقاماً فريدة غير مكررة وفق النطاقات المعتمدة (العملاء 12000+، المحاصيل 50000+، النقل 60000+، التعبئة 70000+، المشتركون 75000+، المحطات 80000+، موردي المحطات 85000+، التخصيمات 40000+، الشحن 90000+، المخلصين 20000+ / 25000+).',
      '4. طبيعة الرصيد (balance_direction): تسجل بدقة كـ CREDIT (له / دائن) أو DEBIT (عليه / مدين).',
      '5. العملات المدعومة (currency): تسجل كـ EGP أو USD أو EUR أو GBP.',
      '6. وحدات قياس مواد التعبئة (unit): تسجل كـ قطعة | رول | كرتونة | باليتة | كجم.',
    ];

    for (final rule in rules) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r),
      );
      final c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r));
      c.value = TextCellValue(rule);
      final isAlert = rule.contains('تنبيه هام') || rule.contains('الخلايا باللون الأحمر');
      c.cellStyle = CellStyle(
        bold: isAlert,
        fontSize: isAlert ? 12 : 11,
        fontColorHex: ExcelColor.fromHexString(isAlert ? '#991B1B' : '#1E293B'),
        horizontalAlign: HorizontalAlign.Right,
      );
      r++;
    }

    r += 2;

    // Table of Sheets Summary
    final guideHeaders = [
      'اسم التبويب (Sheet)',
      'الجدول في Supabase',
      'الحقول الإجبارية (*)',
      'عدد الأعمدة',
      'الوصف والغرض المحاسبي',
    ];
    sheet.appendRow(guideHeaders.map((e) => TextCellValue(e)).toList());
    for (int col = 0; col < guideHeaders.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r));
      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString(_guideHeaderBg),
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    r++;

    for (final spec in allTableSpecs) {
      final requiredColsStr = spec.columns
          .where((c) => c.isRequired)
          .map((c) => '${c.columnName}* (${c.arabicLabel})')
          .join(' ، ');

      sheet.appendRow([
        TextCellValue(spec.sheetName),
        TextCellValue(spec.tableId),
        TextCellValue(requiredColsStr),
        IntCellValue(spec.columns.length),
        TextCellValue(spec.description),
      ]);
      r++;
    }

    // Set Column Widths for Guide
    sheet.setColumnWidth(0, 26.0);
    sheet.setColumnWidth(1, 20.0);
    sheet.setColumnWidth(2, 45.0);
    sheet.setColumnWidth(3, 14.0);
    sheet.setColumnWidth(4, 55.0);
  }

  // ── Helper: Realistic Large Scale Mock Data Rows For All 14 Sheets ─────
  static const List<String> _firstNames = [
    'أحمد', 'محمد', 'محمود', 'علي', 'إبراهيم', 'مصطفى', 'ياسر', 'كريم', 'خالد', 'سامح',
    'حسام', 'طارق', 'عمر', 'عمرو', 'أيمن', 'وليد', 'إسلام', 'حسن', 'حسين', 'سيد',
  ];
  static const List<String> _lastNames = [
    'السيد', 'الشبراوي', 'إبراهيم', 'حسن', 'عبد الرحمن', 'الشناوي', 'البنا', 'عثمان',
    'كمال', 'المهدي', 'الديب', 'العدوي', 'الصاوي', 'الجندي', 'الفار', 'راضي', 'نصار', 'علام', 'غانم', 'منصور',
  ];

  static const List<String> _baseCategories = [
    'مواد تعبئة وكراتين',
    'أطباق فوم وبلاستيك',
    'طبالي وزوايا خشبية',
    'بلاستيك استريتش وشبك',
    'زوايا كرتون مقوى',
    'ورق لف وثمار',
    'أشرطة لاصقة وسولار',
    'فواصل وتليسكوبيك كرتون',
    'صناديق بلاستيك حقلية',
    'أكياس تفريغ هواء وممتصات رطوبة',
    'أغطية باليتات وشلت حرارية',
    'ملصقات وباركودات تصدير',
  ];

  static List<List<dynamic>> _getMockRowsForSheet(String sheetName, {int rowCount = 100}) {
    final count = rowCount.clamp(1, 1000);
    switch (sheetName) {
      case 'العملاء - تصديري':
        return _generateExportCustomers(count);

      case 'العملاء - محلي':
        return _generateLocalCustomers(count);

      case 'موردين المحاصيل':
        return _generateCropSuppliers(count);

      case 'موردين مواد التعبئة':
        return _generatePackingSuppliers(count);

      case 'الموردين المشتركين':
        return _generateSharedSuppliers(count);

      case 'موردي المحطات':
        return _generateStationSuppliers(count);

      case 'موردي النقل':
        return _generateTransportSuppliers(count);

      case 'موردي التخصيمات':
        return _generateDeductionSuppliers(count);

      case 'المخلص البحري':
        return _generateSeaClearingAgents(count);

      case 'المخلص الجوي':
        return _generateAirClearingAgents(count);

      case 'شركات الشحن':
        return _generateShippingCompanies(count);

      case 'المحطات':
        return _generateStations(count);

      case 'فئات مواد التعبئة':
        return _generatePackingCategories(count);

      case 'مواد التعبئة والمستلزمات':
        return _generatePackingMaterials(count);

      default:
        return [];
    }
  }

  static List<List<dynamic>> _generateExportCustomers(int count) {
    const locations = [
      ('روسيا', 'موسكو'),
      ('هولندا', 'روتردام'),
      ('المملكة المتحدة', 'لندن'),
      ('ألمانيا', 'برلين'),
      ('الإمارات', 'دبي'),
      ('السعودية', 'الرياض'),
      ('إيطاليا', 'روما'),
      ('فرنسا', 'مارسيليا'),
      ('بولندا', 'وارسو'),
      ('إسبانيا', 'فالنسيا'),
      ('اليونان', 'أثينا'),
      ('الكويت', 'الكويت'),
      ('قطر', 'الدوحة'),
      ('سلطنة عمان', 'مسقط'),
    ];
    const companyNames = [
      'شركة جرين فروت العالمية للاستيراد',
      'أوراسيا فريش لوجستيكس',
      'الدلتا جلوبال للتجارة الزراعية',
      'يوروب فريش إكسبورت للفاكهة',
      'الفرسان للتوزيع والشحن الدولي',
      'الأمل فودز للتوريدات العامة',
      'النيل يوروب للاستيراد والتصدير',
      'أطلس فروت للتوزيع والتسويق',
      'البحر الأبيض فريش إكسبورت',
      'طيبة تريدينج إنترناشيونال',
      'جولدن هارفست للتوزيع الزراعي',
      'رويال فريش العالمية للتوريد',
    ];
    const currencies = ['USD', 'EUR', 'GBP'];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (12001 + i).toString();
      final baseName = companyNames[i % companyNames.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final currency = currencies[i % currencies.length];
      final loc = locations[i % locations.length];
      final country = loc.$1;
      final city = loc.$2;
      final phone = '+${(i % 2 == 0 ? "7911" : "3120")}${((i * 3571) % 8999999 + 1000000)}';
      final email = 'import_${i + 1}@greenfruit-intl.ru';
      final address = '${(i * 7 % 80) + 12} شارع الميناء التجاري، $city';
      final contactPerson = '${_firstNames[i % _firstNames.length]} ${_lastNames[(i * 3) % _lastNames.length]}';
      final contactPhone = '+${(i % 2 == 0 ? "7911" : "3120")}${((i * 4819) % 8999999 + 1000000)}';
      final contactEmail = 'alexey_${i + 1}@greenfruit-intl.ru';
      final vat = 'RU77${(10000000 + i * 47).toString()}';
      final eori = 'GB${(123456700000 + i * 29).toString()}';
      final balance = ((i * 1234.50 + 2500.0) % 95000 + 1000.0).roundToDouble();
      final dir = (i % 4 == 0) ? 'CREDIT' : 'DEBIT';

      rows.add([
        code,
        name,
        currency,
        phone,
        email,
        city,
        country,
        address,
        contactPerson,
        contactPhone,
        contactEmail,
        vat,
        eori,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateLocalCustomers(int count) {
    const localNames = [
      'مؤسسة العبور لتجارة الفاكهة',
      'شركة الفردوس للتوريدات الغذائية',
      'محلات النيل للفواكه والخضار',
      'سوبرماركت المدينة للتوريد',
      'وكالة الصفا لتجارة الحاصلات',
      'شركة النصر للمواد الغذائية',
      'أسواق البركة المركزية للفاكهة',
      'مؤسسة الإخلاص لتجارة الجملة',
      'شركة الهداية للتوزيع الغذائي',
      'مجمع أسواق الفتح للحاصلات',
      'شركة الرضوان لتجارة الفاكهة',
      'سوق الحرمين للجملة والتوزيع',
    ];
    const cities = ['القاهرة', 'الجيزة', 'الإسكندرية', 'المنصورة', 'طنطا', 'الإسماعيلية', 'أسيوط', 'الزقازيق', 'دمنهور', 'سوهاج'];
    const markets = ['سوق العبور للجملة', 'سوق 6 أكتوبر المركزي', 'سوق العامرية للخضار والفاكهة', 'سوق الحضرة بالإسكندرية', 'سوق المنصورة التجاري'];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (12501 + i).toString();
      final baseName = localNames[i % localNames.length];
      final name = (i < 2) ? baseName : '$baseName (${i + 1})';
      const currency = 'EGP';
      final city = cities[i % cities.length];
      const country = 'مصر';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(10000000 + (i * 3791) % 89999999).toString()}';
      final email = 'client_loc_${i + 1}@gmail.com';
      final address = '${markets[i % markets.length]} - عنبر ${(i % 12) + 1} - محل ${(i % 50) + 1}';
      final contactPerson = '${_firstNames[(i + 4) % _firstNames.length]} ${_lastNames[(i * 2 + 1) % _lastNames.length]}';
      final contactPhone = '01${[0, 1, 2, 5][(i + 1) % 4]}${(20000000 + (i * 4123) % 79999999).toString()}';
      final contactEmail = 'contact_${i + 1}@ferdos-trade.com';
      final balance = ((i * 750.0 + 3500.0) % 85000 + 500.0).roundToDouble();
      final dir = (i % 3 == 0) ? 'CREDIT' : 'DEBIT';

      rows.add([
        code,
        name,
        currency,
        phone,
        email,
        city,
        country,
        address,
        contactPerson,
        contactPhone,
        contactEmail,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateCropSuppliers(int count) {
    const names = [
      'مزرعة السلام - وادي النطرون',
      'الحاج فوزي الشبراوي (مزارع مانجو)',
      'مزارع الواحة الخضراء',
      'مزارع طيبة الزراعية الحديثة',
      'بساتين وادي النطرون النموذجية',
      'مزارع النوبارية للتنمية والإنتاج',
      'مزارع الصالحية الجديدة للفاكهة',
      'مزارع الخطاطبة للبساتين والخضار',
      'مزرعة الهدى والنور للحاصلات',
      'مزارع الفجر الجديد للحمضيات',
      'مزارع الجيزة النموذجية للتمور',
      'مزارع سيناء للتنمية الزراعية',
    ];
    const regions = [
      'البحيرة - وادي النطرون ك 110',
      'الإسماعيلية - القنطرة غرب',
      'طريق مصر إسكندرية الصحراوي ك 76',
      'النوبارية - مدخل التحدي',
      'المنوفية - الخطاطبة',
      'الشرقية - الصالحية الجديدة',
      'الجيزة - الواحات البحرية',
      'الفيوم - طامية',
      'بني سويف - سمسطا',
      'المنيا - مغاغة',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (50001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(30000000 + (i * 5183) % 69999999).toString()}';
      final address = regions[i % regions.length];
      final currency = (i % 6 == 0) ? 'USD' : 'EGP';
      final balance = ((i * 2450.0 + 15000.0) % 250000 + 2000.0).roundToDouble();
      final dir = (i % 5 == 0) ? 'DEBIT' : 'CREDIT';

      rows.add([
        code,
        name,
        phone,
        address,
        currency,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generatePackingSuppliers(int count) {
    const names = [
      'الشركة المصرية لصناعة الكرتون (إيجيبت باك)',
      'مصنع الأهرام للأطباق الفوم والبلاستيك',
      'الشركة الدولية لحلول التغليف والتعبئة',
      'رويال باك لمستلزمات التصدير والتعبئة',
      'مصنع النيل للطباعة والكرتون المضلع',
      'دلتا باك لحلول التعبئة والتغليف',
      'الوطنية لصناعة الزوايا والكرتون المقوى',
      'الأمل للمنتجات البلاستيكية ومواد التغليف',
      'الشرق لمستلزمات محطات الفاكهة',
      'أكتوبر للمطبوعات وتجهيز الكراتين',
    ];
    const zones = [
      'مدينة العاشر من رمضان - المنطقة الصناعية B3',
      'مدينة السادات - المنطقة الصناعية الرابعة',
      'مدينة 6 أكتوبر - المنطقة الصناعية الثالثة',
      'برج العرب الجديدة - المنطقة الثانية',
      'العبور الصناعية - الامتداد الشمالي',
      'العاشر من رمضان - المنطقة الصناعية A1',
      'مدينة بدر - المنطقة الصناعية المركزية',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (70001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(40000000 + (i * 6271) % 59999999).toString()}';
      final address = zones[i % zones.length];
      const currency = 'EGP';
      final balance = ((i * 3200.0 + 20000.0) % 280000 + 5000.0).roundToDouble();
      final dir = (i % 6 == 0) ? 'DEBIT' : 'CREDIT';

      rows.add([
        code,
        name,
        phone,
        address,
        currency,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateSharedSuppliers(int count) {
    const names = [
      'الواحة للخدمات والتنمية الزراعية والتعبئة',
      'شركة الدلتا للتوريدات والمحاصيل المتكاملة',
      'مجموعة الشروق الزراعية الصناعية',
      'الفهد للتوريد الزراعي وحلول التعبئة',
      'الأوائل للتنمية الزراعية والتوريد المتكامل',
      'الصفوة للمحاصيل ومستلزمات التعبئة والتغليف',
    ];
    const regions = [
      'طريق مصر إسكندرية الصحراوي ك 72',
      'النوبارية - مدخل التحدي',
      'الإسماعيلية - طريق فايد',
      'وادي النطرون - طريق الدبلوماسيين',
      'المنوفية - مدينة السادات',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (75001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(50000000 + (i * 7393) % 49999999).toString()}';
      final address = regions[i % regions.length];
      final currency = (i % 5 == 0) ? 'USD' : 'EGP';
      final balance = ((i * 4100.0 + 25000.0) % 300000 + 8000.0).roundToDouble();
      final dir = (i % 5 == 0) ? 'DEBIT' : 'CREDIT';

      rows.add([
        code,
        name,
        phone,
        address,
        currency,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateStationSuppliers(int count) {
    const names = [
      'محطة الأمل للفرز والتعبئة الميكانيكية',
      'محطة الخبراء للتبريد والتصدير الزراعي',
      'محطة النوبارية الحديثة للخدمات اللوجستية',
      'محطة الصالحية الاستثمارية للفرز والتبريد',
      'محطة القمة لتجهيز وفحص الصادرات',
      'محطة الصحراوي المتطورة للتعبئة والحفظ',
    ];
    const services = [
      'تشغيل | تبريد | حفظ مبرد | تقفيل كرتون | تعتيق صادر',
      'تبريد | حفظ مبرد | تبخير | تدوير خام',
      'تشغيل | عماله | تبريد | اعادة تدوير',
      'تشغيل | تبريد | حفظ مبرد | تقفيل كرتون | عماله',
      'تبريد | تبخير | تعتيق صادر | تدوير خام',
    ];
    const zones = [
      'الصحراوي ك 64 - النوبارية',
      'الصالحية الجديدة - المنطقة الاستثمارية',
      'طريق السويس - مجمع الخدمات',
      'وادي النطرون ك 105',
      'طريق الإسماعيلية الصحراوي ك 84',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (85001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(60000000 + (i * 8419) % 39999999).toString()}';
      final address = zones[i % zones.length];
      final service = services[i % services.length];
      const currency = 'EGP';
      final balance = ((i * 3800.0 + 30000.0) % 220000 + 6000.0).roundToDouble();
      const dir = 'CREDIT';

      rows.add([
        code,
        name,
        phone,
        address,
        service,
        currency,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateTransportSuppliers(int count) {
    const names = [
      'شركة الفرسان للنقل البري والمبرد',
      'مقاولات الحرمين لنقل المحاصيل (نقل ثقيل)',
      'أسطول الدلتا للنقل المبرد والشحن',
      'النيل لوجستيكس لنقل الحاصلات الزراعية',
      'البركة للشحن البري والسيارات المبردة',
      'الوفاء لخدمات النقل السريع والترلات',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (60001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(70000000 + (i * 9127) % 29999999).toString()}';
      final email = 'trans_${i + 1}@transport-group.com';
      final balance = ((i * 2100.0 + 12000.0) % 180000 + 3000.0).roundToDouble();
      final dir = (i % 4 == 0) ? 'DEBIT' : 'CREDIT';
      final trips = (i % 15) + 3;
      const notes = 'أسطول شاحنات مبردة سعة 24 طن مع أجهزة تتبع GPS';

      rows.add([
        code,
        name,
        'EGP',
        phone,
        email,
        balance,
        dir,
        trips,
        notes,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateDeductionSuppliers(int count) {
    const names = [
      'مكتب الحجر الزراعي وسلامة الغذاء - الميناء',
      'معامل التحليل المعتمدة ومراقبة الصادرات',
      'وحدة الفحص النوعي والشهادات الدولية',
      'مكتب الرقابة على الصادرات والواردات',
      'مركز الجودة والسلامة الغذائية الزراعية',
    ];
    const mappings = [
      'رسوم فحص | دفتر حجر زراعي | دفتر حجر سلامة غذاء',
      'تحليل خاص | تحليل هيئه | سحب عينه عربي',
      'رسوم وزن وقبانة | شهادة منشأ | فحص بيئي',
      'فحص إشعاعي | معاينة جمركية | تحليل متبقيات مبيدات',
    ];
    const locations = [
      'مبنى الخدمات الجمركية - باب 22 ميناء الإسكندرية',
      'مجمع المعامل المركزية - الدقي، الجيزة',
      'مكتب الحجر الزراعي - ميناء دمياط',
      'مبنى الخدمات الاستثمارية - ميناء السويس',
      'قرية البضائع - مطار القاهرة الدولي',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (40001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '02${(20000000 + (i * 3421) % 7999999).toString()}';
      final address = locations[i % locations.length];
      final mapping = mappings[i % mappings.length];
      const currency = 'EGP';
      final balance = ((i * 1150.0 + 8000.0) % 90000 + 1500.0).roundToDouble();
      const dir = 'CREDIT';

      rows.add([
        code,
        name,
        phone,
        address,
        mapping,
        currency,
        balance,
        dir,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateSeaClearingAgents(int count) {
    const names = [
      'مكتب البدر للتخليص الجمركي البحري',
      'توكيل الدلتا للتخليص وميناء دمياط',
      'مكتب البحر المتوسط للخدمات الجمركية',
      'المنار للتخليص الجمركي البحري والموانئ',
      'النورس لخدمات الشحن والتخليص البحري',
    ];
    const ports = ['ميناء الإسكندرية', 'ميناء دمياط', 'ميناء بورسعيد', 'ميناء السخنة', 'ميناء الدخيلة'];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (20001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(80000000 + (i * 4721) % 19999999).toString()}';
      final email = 'sea_clear_${i + 1}@customs.com';
      final city = ports[i % ports.length];
      const country = 'مصر';
      final address = 'مجمع الخدمات الجمركية - باب ${(i % 25) + 1} - $city';
      final contactPerson = '${_firstNames[(i + 6) % _firstNames.length]} ${_lastNames[(i * 3 + 2) % _lastNames.length]}';
      final balance = ((i * 1400.0 + 6000.0) % 80000 + 1000.0).roundToDouble();
      const currency = 'EGP';

      rows.add([
        code,
        name,
        phone,
        email,
        city,
        country,
        address,
        contactPerson,
        balance,
        currency,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateAirClearingAgents(int count) {
    const names = [
      'مكتب النيل للتخليص والشحن الجوي',
      'أير إكسبريس للخدمات الجمركية السريعة',
      'طيبة للشحن الجوي وقرية البضائع',
      'الأجنحة السريعة للخدمات الجمركية',
      'سكاي كارغو للتخليص والشحن السريع',
    ];
    const airports = ['مطار القاهرة الدولي', 'مطار سفنكس الدولي', 'مطار برج العرب الدولي', 'مطار شرم الشيخ الدولي'];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (25001 + i).toString();
      final baseName = names[i % names.length];
      final name = (i < 2) ? baseName : '$baseName #${i + 1}';
      final phone = '01${[0, 1, 2, 5][i % 4]}${(90000000 + (i * 5831) % 9999999).toString()}';
      final email = 'air_cargo_${i + 1}@customs-air.com';
      final city = airports[i % airports.length];
      const country = 'مصر';
      final address = 'قرية البضائع - مكتب رقم ${(i % 150) + 1} - $city';
      final contactPerson = '${_firstNames[(i + 8) % _firstNames.length]} ${_lastNames[(i * 2 + 3) % _lastNames.length]}';
      final balance = ((i * 1250.0 + 5000.0) % 70000 + 1000.0).roundToDouble();
      const currency = 'EGP';

      rows.add([
        code,
        name,
        phone,
        email,
        city,
        country,
        address,
        contactPerson,
        balance,
        currency,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateShippingCompanies(int count) {
    const lines = [
      'خط ميرسك الملاحي (Maersk Line Egypt)',
      'شركة إم إس سي للشحن البحري (MSC Mediterranean)',
      'خط هاباج لويد الملاحي (Hapag-Lloyd)',
      'خط كوسكو الملاحي (COSCO)',
      'خط سي إم إيه الملاحي (CMA CGM)',
      'خط وان للملاحة البحرية (ONE Line)',
      'خط إيفرجرين الملاحي (Evergreen)',
      'خط يانغ مينغ للشحن (Yang Ming)',
      'شركة الفارس للخدمات الملاحية',
      'الشرق الأوسط للتوكيلات الملاحية',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (90001 + i).toString();
      final baseName = lines[i % lines.length];
      final name = (i < 2) ? baseName : '$baseName (#${i + 1})';
      final phone = '02${(30000000 + (i * 6917) % 6999999).toString()}';
      final email = 'booking_${i + 1}@shipping-line.com';
      final balance = ((i * 2800.0 + 10000.0) % 150000 + 2000.0).roundToDouble();
      final currency = (i % 3 == 0) ? 'USD' : ((i % 3 == 1) ? 'EUR' : 'EGP');

      rows.add([
        code,
        name,
        phone,
        email,
        balance,
        currency,
      ]);
    }
    return rows;
  }

  static List<List<dynamic>> _generateStations(int count) {
    const names = [
      'محطة الأمل المركزية للتعبئة',
      'محطة النوبارية الحديثة للفرز',
      'محطة الصالحية الاستثمارية للتجهيز',
      'محطة وادي النطرون النموذجية للتصدير',
      'محطة طريق مصر إسكندرية المتقدمة',
      'محطة القنطرة غرب لفرز وتعبئة المانجو',
      'محطة السادات الكبرى للحاصلات',
      'محطة العامرية للتبريد والتصدير',
      'محطة الخطاطبة للتعبئة الحديثة',
      'محطة الإسماعيلية لتجهيز الموالح',
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (80001 + i).toString();
      final name = (i == 0)
          ? 'محطة الأمل المركزية للتعبئة'
          : (i == 1)
              ? 'محطة النوبارية الحديثة للفرز'
              : '${names[i % names.length]} (${i + 1})';
      rows.add([code, name]);
    }
    return rows;
  }

  static List<List<dynamic>> _generatePackingCategories(int count) {
    final catCount = count.clamp(3, _baseCategories.length);
    final rows = <List<dynamic>>[];
    for (int i = 0; i < catCount; i++) {
      rows.add([_baseCategories[i]]);
    }
    return rows;
  }

  static List<List<dynamic>> _generatePackingMaterials(int count) {
    const items = [
      ('كرتونة تليسكوبيك مانجو 5 كجم فاخر', 'كرتونة', 'مواد تعبئة وكراتين', 24.50),
      ('باليتة خشبية معالجة حرارياً 100x120', 'باليتة', 'طبالي وزوايا خشبية', 220.0),
      ('طبق فوم أبيض مقاس 22 للثمار الحساسة', 'قطعة', 'أطباق فوم وبلاستيك', 1.75),
      ('كرتونة أوبن توب برتقال 15 كجم تصدير', 'كرتونة', 'مواد تعبئة وكراتين', 32.0),
      ('كرتونة روف توب عنب 4.5 كجم مخرومة', 'كرتونة', 'مواد تعبئة وكراتين', 28.5),
      ('زاوية كرتون مقوى سمك 4 مم طول 2 متر', 'قطعة', 'زوايا كرتون مقوى', 18.0),
      ('رول بلاستيك استريتش 23 ميكرون يدوي', 'رول', 'بلاستيك استريتش وشبك', 185.0),
      ('شبك تغليف حمضيات برتقالي 5 كجم', 'متر', 'بلاستيك استريتش وشبك', 3.25),
      ('ورق لف ثمار معالج مضاد للعفن والندوة', 'كيلوجرام', 'ورق لف وثمار', 48.0),
      ('شريط لاصق عريض شفاف 500 متر ماكينة', 'بكرة', 'أشرطة لاصقة وسولار', 65.0),
      ('فواصل كرتون عازلة للثمار داخل الصندوق', 'قطعة', 'فواصل وتليسكوبيك كرتون', 4.5),
      ('كيس تفريغ هواء وممتص غاز الإيثيلين', 'كيس', 'أكياس تفريغ هواء وممتصات رطوبة', 12.0),
    ];

    final rows = <List<dynamic>>[];
    for (int i = 0; i < count; i++) {
      final code = (i == 0)
          ? 'MAT-BOX-01'
          : (i == 1)
              ? 'MAT-PLT-01'
              : (i == 2)
                  ? 'MAT-TRAY-01'
                  : 'MAT-${(i + 1).toString().padLeft(4, '0')}';
      final item = items[i % items.length];
      final name = (i < 3) ? item.$1 : '${item.$1} (#${i + 1})';
      const currency = 'EGP';
      final unit = item.$2;
      final category = item.$3;
      final quantity = ((i * 450) % 55000 + 500).toDouble();
      final costPrice = item.$4;
      final stationId = (80001 + (i % count.clamp(1, 100))).toString();

      rows.add([
        code,
        name,
        currency,
        unit,
        category,
        quantity,
        costPrice,
        stationId,
      ]);
    }
    return rows;
  }
}
