import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/file_helper.dart';

/// Single detected discrepancy or validation issue in a record.
class DataAuditItemIssue {
  final String categoryName;
  final String tableName;
  final String recordId;
  final String code;
  final String name;
  final String issueType; // e.g. 'كود خارج النطاق', 'كود مفقود', 'اسم مفقود', 'كود مكرر'
  final String details;

  const DataAuditItemIssue({
    required this.categoryName,
    required this.tableName,
    required this.recordId,
    required this.code,
    required this.name,
    required this.issueType,
    required this.details,
  });
}

/// Audit result for a specific master category or sheet.
class DataAuditCategoryResult {
  final String categoryKey;
  final String categoryName;
  final String tableName;
  final String codeRangeDisplay;
  final int? minCode;
  final int? maxCode;
  final int totalCount;
  final double totalInitialBalance;
  final String currency;
  final List<DataAuditItemIssue> issues;

  const DataAuditCategoryResult({
    required this.categoryKey,
    required this.categoryName,
    required this.tableName,
    required this.codeRangeDisplay,
    this.minCode,
    this.maxCode,
    required this.totalCount,
    required this.totalInitialBalance,
    this.currency = 'EGP',
    required this.issues,
  });

  bool get isPassed => issues.isEmpty;
  int get warningCount => issues.length;
  int get validCount => (totalCount - issues.length).clamp(0, totalCount);
}

/// Comprehensive audit summary report across all ERP categories.
class DataAuditReport {
  final DateTime generatedAt;
  final List<DataAuditCategoryResult> categories;
  final int totalRecords;
  final double totalInitialBalance;
  final int totalPassedCategories;
  final int totalWarningCategories;
  final int totalIssues;

  const DataAuditReport({
    required this.generatedAt,
    required this.categories,
    required this.totalRecords,
    required this.totalInitialBalance,
    required this.totalPassedCategories,
    required this.totalWarningCategories,
    required this.totalIssues,
  });

  bool get isAllPassed => totalWarningCategories == 0;
}

/// Service to execute fast, non-blocking audit queries (COUNT, SUM, Range Verification)
/// across all core master tables in Supabase, and generate formatted Excel / PDF audit reports.
class DataAuditService {
  static final SupabaseClient _client = Supabase.instance.client;
  static final NumberFormat _numFmt = NumberFormat('#,##0.00', 'en_US');

  /// Runs the full data audit asynchronously across all 12+ categories.
  static Future<DataAuditReport> runAudit() async {
    // Preload customers once to partition export vs local without redundant queries
    final customers = await _fetchAllCustomers();

    // Execute fast queries concurrently
    final results = await Future.wait([
      _auditExportCustomers(customers),
      _auditLocalCustomers(customers),
      _auditCropSuppliers(),
      _auditPackagingSuppliers(),
      _auditSharedSuppliers(),
      _auditTransportSuppliers(),
      _auditStationSuppliers(),
      _auditDeductionSuppliers(),
      _auditClearingAgents(),
      _auditShippingCompanies(),
      _auditStations(),
      _auditRawMaterials(),
      _auditRawMaterialCategories(),
    ]);

    int totalRecords = 0;
    double totalBalance = 0.0;
    int passedCount = 0;
    int warningCount = 0;
    int totalIssues = 0;

    for (final cat in results) {
      totalRecords += cat.totalCount;
      totalBalance += cat.totalInitialBalance;
      if (cat.isPassed) {
        passedCount++;
      } else {
        warningCount++;
      }
      totalIssues += cat.issues.length;
    }

    return DataAuditReport(
      generatedAt: DateTime.now(),
      categories: results,
      totalRecords: totalRecords,
      totalInitialBalance: totalBalance,
      totalPassedCategories: passedCount,
      totalWarningCategories: warningCount,
      totalIssues: totalIssues,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. Audit Implementations for Each Category
  // ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _fetchAllCustomers() async {
    try {
      final rows = await _client.from('customers').select();
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      try {
        final rows = await _client.from('customers').select('id, code, name, initial_balance, currency');
        return List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        return [];
      }
    }
  }

  static Future<DataAuditCategoryResult> _auditExportCustomers([List<Map<String, dynamic>>? preloaded]) async {
    const catName = 'العملاء - تصديري';
    const tableName = 'customers';
    const minCode = 10000;
    const maxCode = 19999;
    const rangeDisplay = '10000 - 19999';

    try {
      final all = preloaded ?? await _fetchAllCustomers();
      final rows = all.where((r) {
        final compType = (r['company_type'] ?? r['customer_type'])?.toString().toLowerCase().trim();
        if (compType == 'local') return false;
        final rawCode = r['code']?.toString().trim() ?? '';
        final digits = int.tryParse(rawCode.replaceAll(RegExp(r'[^0-9]'), ''));
        if (digits != null && digits >= 20000 && digits <= 29999) return false;
        return true;
      }).toList();

      return _processGenericAudit(
        categoryKey: 'customer_export',
        categoryName: catName,
        tableName: tableName,
        rows: rows,
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
        defaultCurrency: 'USD',
      );
    } catch (e) {
      return _buildErrorResult('customer_export', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditLocalCustomers([List<Map<String, dynamic>>? preloaded]) async {
    const catName = 'العملاء - محلي';
    const tableName = 'customers';
    const minCode = 20000;
    const maxCode = 29999;
    const rangeDisplay = '20000 - 29999';

    try {
      final all = preloaded ?? await _fetchAllCustomers();
      final rows = all.where((r) {
        final compType = (r['company_type'] ?? r['customer_type'])?.toString().toLowerCase().trim();
        if (compType == 'local') return true;
        final rawCode = r['code']?.toString().trim() ?? '';
        final digits = int.tryParse(rawCode.replaceAll(RegExp(r'[^0-9]'), ''));
        if (digits != null && digits >= 20000 && digits <= 29999) return true;
        return false;
      }).toList();

      return _processGenericAudit(
        categoryKey: 'customer_local',
        categoryName: catName,
        tableName: tableName,
        rows: rows,
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
        defaultCurrency: 'EGP',
      );
    } catch (e) {
      return _buildErrorResult('customer_local', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditCropSuppliers() async {
    const catName = 'موردين المحاصيل';
    const tableName = 'suppliers';
    const minCode = 50000;
    const maxCode = 59999;
    const rangeDisplay = '50000 - 59999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .eq('supplier_type', 'crop');

      return _processGenericAudit(
        categoryKey: 'supplier_crop',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_crop', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditPackagingSuppliers() async {
    const catName = 'موردين مواد التعبئة';
    const tableName = 'suppliers';
    const minCode = 70000;
    const maxCode = 74999;
    const rangeDisplay = '70000 - 74999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .or('supplier_type.eq.packaging,supplier_type.eq.sticker');

      return _processGenericAudit(
        categoryKey: 'supplier_packaging',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_packaging', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditSharedSuppliers() async {
    const catName = 'الموردين المشتركين';
    const tableName = 'suppliers';
    const minCode = 75000;
    const maxCode = 79999;
    const rangeDisplay = '75000 - 79999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .eq('supplier_type', 'shared');

      return _processGenericAudit(
        categoryKey: 'supplier_shared',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_shared', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditTransportSuppliers() async {
    const catName = 'موردي النقل ومقاولي الشحن';
    const tableName = 'suppliers';
    const minCode = 60000;
    const maxCode = 69999;
    const rangeDisplay = '60000 - 69999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .eq('supplier_type', 'transport');

      return _processGenericAudit(
        categoryKey: 'supplier_transport',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_transport', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditStationSuppliers() async {
    const catName = 'موردي المحطات';
    const tableName = 'suppliers';
    const minCode = 85000;
    const maxCode = 89999;
    const rangeDisplay = '85000 - 89999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .eq('supplier_type', 'station');

      return _processGenericAudit(
        categoryKey: 'supplier_station',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_station', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditDeductionSuppliers() async {
    const catName = 'الخصومات والتخصيمات';
    const tableName = 'suppliers';
    const minCode = 40000;
    const maxCode = 49999;
    const rangeDisplay = '40000 - 49999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, supplier_type, initial_balance, currency')
          .or('supplier_type.eq.deduction,supplier_type.eq.deductions');

      return _processGenericAudit(
        categoryKey: 'supplier_deduction',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('supplier_deduction', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditClearingAgents() async {
    const catName = 'المخلصين الجمركيين (بحري / جوي)';
    const tableName = 'clearing_agents';
    const minCode = 20000;
    const maxCode = 29999;
    // Clearing agents may also historically be placed under 80000 - 84999
    const rangeDisplay = '20000 - 29999 / 80000 - 84999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, initial_balance, currency');

      final list = List<Map<String, dynamic>>.from(rows);
      final issues = <DataAuditItemIssue>[];
      double totalBalance = 0.0;
      final seenCodes = <String>{};

      for (final r in list) {
        final id = r['id']?.toString() ?? '';
        final code = r['code']?.toString().trim() ?? '';
        final name = r['name']?.toString().trim() ?? '';
        final bal = (r['initial_balance'] as num?)?.toDouble() ?? 0.0;
        totalBalance += bal;

        if (name.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: '(اسم فارغ)',
            issueType: 'اسم مفقود',
            details: 'سجل المخلص مسجل بدون اسم',
          ));
        }

        if (code.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: '(فارغ)',
            name: name,
            issueType: 'كود مفقود',
            details: 'المخلص بدون كود تعريفي',
          ));
        } else {
          final digits = int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), ''));
          final inRange = digits != null &&
              ((digits >= 20000 && digits <= 29999) || (digits >= 80000 && digits <= 84999));
          if (!inRange) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود خارج النطاق',
              details: 'الكود [$code] لا يقع ضمن النطاق المعتمد للمخلصين ($rangeDisplay)',
            ));
          }
          if (!seenCodes.add(code.toLowerCase())) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود مكرر',
              details: 'الكود [$code] مكرر مع مخلص آخر',
            ));
          }
        }
      }

      return DataAuditCategoryResult(
        categoryKey: 'clearing_agents',
        categoryName: catName,
        tableName: tableName,
        codeRangeDisplay: rangeDisplay,
        minCode: minCode,
        maxCode: maxCode,
        totalCount: list.length,
        totalInitialBalance: totalBalance,
        issues: issues,
      );
    } catch (e) {
      return _buildErrorResult('clearing_agents', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditShippingCompanies() async {
    const catName = 'شركات الشحن والخطوط الملاحية';
    const tableName = 'shipping_companies';
    const minCode = 90000;
    const maxCode = 99999;
    const rangeDisplay = '90000 - 99999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, initial_balance, currency');

      return _processGenericAudit(
        categoryKey: 'shipping_companies',
        categoryName: catName,
        tableName: tableName,
        rows: List<Map<String, dynamic>>.from(rows),
        minCode: minCode,
        maxCode: maxCode,
        codeRangeDisplay: rangeDisplay,
      );
    } catch (e) {
      return _buildErrorResult('shipping_companies', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditStations() async {
    const catName = 'محطات التعبئة والمخازن';
    const tableName = 'stations';
    const rangeDisplay = '30000 - 39999 / 80000 - 84999';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name');

      final list = List<Map<String, dynamic>>.from(rows);
      final issues = <DataAuditItemIssue>[];
      final seenCodes = <String>{};

      for (final r in list) {
        final id = r['id']?.toString() ?? '';
        final code = r['code']?.toString().trim() ?? '';
        final name = r['name']?.toString().trim() ?? '';

        if (name.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: '(اسم فارغ)',
            issueType: 'اسم مفقود',
            details: 'المحطة مسجلة بدون اسم',
          ));
        }

        if (code.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: '(فارغ)',
            name: name,
            issueType: 'كود مفقود',
            details: 'المحطة بدون كود تعريفي',
          ));
        } else {
          final digits = int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), ''));
          final inRange = digits != null &&
              ((digits >= 30000 && digits <= 39999) || (digits >= 80000 && digits <= 84999));
          if (!inRange) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود خارج النطاق',
              details: 'الكود [$code] لا يقع ضمن النطاق المعتمد للمحطات ($rangeDisplay)',
            ));
          }
          if (!seenCodes.add(code.toLowerCase())) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود مكرر',
              details: 'الكود [$code] مكرر مع محطة أخرى',
            ));
          }
        }
      }

      return DataAuditCategoryResult(
        categoryKey: 'stations',
        categoryName: catName,
        tableName: tableName,
        codeRangeDisplay: rangeDisplay,
        minCode: 30000,
        maxCode: 39999,
        totalCount: list.length,
        totalInitialBalance: 0.0,
        issues: issues,
      );
    } catch (e) {
      return _buildErrorResult('stations', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditRawMaterials() async {
    const catName = 'مواد التعبئة والمستلزمات';
    const tableName = 'raw_materials';
    const rangeDisplay = 'MAT-XXXX / 70000+';

    try {
      final rows = await _client
          .from(tableName)
          .select('id, code, name, initial_quantity, initial_avg_price');

      final list = List<Map<String, dynamic>>.from(rows);
      final issues = <DataAuditItemIssue>[];
      double totalValuation = 0.0;
      final seenCodes = <String>{};

      for (final r in list) {
        final id = r['id']?.toString() ?? '';
        final code = r['code']?.toString().trim() ?? '';
        final name = r['name']?.toString().trim() ?? '';
        final initQty = (r['initial_quantity'] as num?)?.toDouble() ?? 0.0;
        final initAvg = (r['initial_avg_price'] as num?)?.toDouble() ?? 0.0;
        totalValuation += (initQty * initAvg);

        if (name.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: '(اسم فارغ)',
            issueType: 'اسم مفقود',
            details: 'المادة مسجلة بدون اسم',
          ));
        }

        if (code.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: '(فارغ)',
            name: name,
            issueType: 'كود مفقود',
            details: 'المادة بدون كود تعريفي',
          ));
        } else {
          final isMatPrefix = code.toUpperCase().startsWith('MAT-');
          final digits = int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), ''));
          final inRange = isMatPrefix || (digits != null && digits >= 70000);
          if (!inRange) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود خارج النطاق',
              details: 'الكود [$code] لا يتبع النمط القياسي للمواد (MAT-0001 أو 70000+)',
            ));
          }
          if (!seenCodes.add(code.toLowerCase())) {
            issues.add(DataAuditItemIssue(
              categoryName: catName,
              tableName: tableName,
              recordId: id,
              code: code,
              name: name,
              issueType: 'كود مكرر',
              details: 'كود المادة [$code] مكرر مع صنف آخر',
            ));
          }
        }
      }

      return DataAuditCategoryResult(
        categoryKey: 'raw_materials',
        categoryName: catName,
        tableName: tableName,
        codeRangeDisplay: rangeDisplay,
        totalCount: list.length,
        totalInitialBalance: totalValuation,
        issues: issues,
      );
    } catch (e) {
      return _buildErrorResult('raw_materials', catName, tableName, rangeDisplay, e);
    }
  }

  static Future<DataAuditCategoryResult> _auditRawMaterialCategories() async {
    const catName = 'فئات مواد التعبئة';
    const tableName = 'raw_material_categories';
    const rangeDisplay = 'CAT-XX / كود فريد';

    try {
      final rows = await _client.from(tableName).select('id, name');
      final list = List<Map<String, dynamic>>.from(rows);
      final issues = <DataAuditItemIssue>[];
      final seenNames = <String>{};

      for (final r in list) {
        final id = r['id']?.toString() ?? '';
        final name = r['name']?.toString().trim() ?? '';
        final code = id.length > 8 ? id.substring(0, 8).toUpperCase() : id;

        if (name.isEmpty) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: '(اسم فارغ)',
            issueType: 'اسم مفقود',
            details: 'الفئة مسجلة بدون اسم',
          ));
        } else if (!seenNames.add(name.toLowerCase())) {
          issues.add(DataAuditItemIssue(
            categoryName: catName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: name,
            issueType: 'اسم مكرر',
            details: 'اسم الفئة [$name] مكرر',
          ));
        }
      }

      return DataAuditCategoryResult(
        categoryKey: 'raw_material_categories',
        categoryName: catName,
        tableName: tableName,
        codeRangeDisplay: rangeDisplay,
        totalCount: list.length,
        totalInitialBalance: 0.0,
        issues: issues,
      );
    } catch (e) {
      return _buildErrorResult('raw_material_categories', catName, tableName, rangeDisplay, e);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helper: Generic Audit Processing for Any Code-Ranged Table
  // ─────────────────────────────────────────────────────────────

  static DataAuditCategoryResult _processGenericAudit({
    required String categoryKey,
    required String categoryName,
    required String tableName,
    required List<Map<String, dynamic>> rows,
    required int minCode,
    required int maxCode,
    required String codeRangeDisplay,
    String defaultCurrency = 'EGP',
  }) {
    final issues = <DataAuditItemIssue>[];
    double totalBalance = 0.0;
    final seenCodes = <String>{};

    for (final r in rows) {
      final id = r['id']?.toString() ?? '';
      final code = (r['code']?.toString().trim().isNotEmpty == true
          ? r['code']!.toString().trim()
          : (r['supplier_code']?.toString().trim() ?? ''));
      final name = r['name']?.toString().trim() ?? '';
      final bal = (r['initial_balance'] as num?)?.toDouble() ?? 0.0;
      totalBalance += bal;

      if (name.isEmpty) {
        issues.add(DataAuditItemIssue(
          categoryName: categoryName,
          tableName: tableName,
          recordId: id,
          code: code,
          name: '(اسم فارغ)',
          issueType: 'اسم مفقود',
          details: 'السجل مسجل بدون اسم',
        ));
      }

      if (code.isEmpty) {
        issues.add(DataAuditItemIssue(
          categoryName: categoryName,
          tableName: tableName,
          recordId: id,
          code: '(فارغ)',
          name: name,
          issueType: 'كود مفقود',
          details: 'السجل بدون كود تعريفي',
        ));
      } else {
        final digits = int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), ''));
        if (digits == null || digits < minCode || digits > maxCode) {
          issues.add(DataAuditItemIssue(
            categoryName: categoryName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: name,
            issueType: 'كود خارج النطاق',
            details: 'الكود [$code] خارج النطاق المعتمد ($minCode - $maxCode)',
          ));
        }

        if (!seenCodes.add(code.toLowerCase())) {
          issues.add(DataAuditItemIssue(
            categoryName: categoryName,
            tableName: tableName,
            recordId: id,
            code: code,
            name: name,
            issueType: 'كود مكرر',
            details: 'الكود [$code] مكرر مع سجل آخر في نفس الفئة',
          ));
        }
      }
    }

    return DataAuditCategoryResult(
      categoryKey: categoryKey,
      categoryName: categoryName,
      tableName: tableName,
      codeRangeDisplay: codeRangeDisplay,
      minCode: minCode,
      maxCode: maxCode,
      totalCount: rows.length,
      totalInitialBalance: totalBalance,
      currency: defaultCurrency,
      issues: issues,
    );
  }

  static DataAuditCategoryResult _buildErrorResult(
    String categoryKey,
    String categoryName,
    String tableName,
    String rangeDisplay,
    dynamic error,
  ) {
    return DataAuditCategoryResult(
      categoryKey: categoryKey,
      categoryName: categoryName,
      tableName: tableName,
      codeRangeDisplay: rangeDisplay,
      totalCount: 0,
      totalInitialBalance: 0.0,
      issues: [
        DataAuditItemIssue(
          categoryName: categoryName,
          tableName: tableName,
          recordId: '',
          code: '-',
          name: '-',
          issueType: 'تعذر الاتصال بالجدول',
          details: 'خطأ أثناء استعلام قاعدة البيانات: $error',
        )
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Excel Generation & Export (.xlsx)
  // ─────────────────────────────────────────────────────────────

  /// Builds raw Excel bytes for the comprehensive Data Audit Report.
  static List<int> generateExcelBytes(DataAuditReport report) {
    final excel = Excel.createExcel();

    // ── Sheet 1: ملخص الفحص والمطابقة ──
    const summarySheetName = 'ملخص الفحص والمطابقة';
    final summarySheet = excel[summarySheetName];
    excel.delete('Sheet1');

    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#0F172A'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      bold: true,
      fontFamily: getFontFamily(FontFamily.Calibri),
    );

    final passStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#DCFCE7'),
      fontColorHex: ExcelColor.fromHexString('#166534'),
      bold: true,
    );

    final warnStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#FEF3C7'),
      fontColorHex: ExcelColor.fromHexString('#92400E'),
      bold: true,
    );

    // Title Block
    summarySheet.appendRow([TextCellValue('تقرير التحقق من صحة واكتمال البيانات (Data Audit Report)')]);
    summarySheet.appendRow([TextCellValue('تاريخ وتوقيت الفحص: ${DateFormat('yyyy-MM-dd HH:mm').format(report.generatedAt)}')]);
    summarySheet.appendRow([TextCellValue('')]);

    // Summary KPIs
    summarySheet.appendRow([
      TextCellValue('إجمالي السجلات المفحوصة: ${report.totalRecords}'),
      TextCellValue('إجمالي الأرصدة الافتتاحية: ${_numFmt.format(report.totalInitialBalance)} ج.م'),
      TextCellValue('الفئات السليمة والمطابقة: ${report.totalPassedCategories}'),
      TextCellValue('الفئات التي بها تنبيهات: ${report.totalWarningCategories}'),
      TextCellValue('إجمالي المخالفات المرصودة: ${report.totalIssues}'),
    ]);
    summarySheet.appendRow([TextCellValue('')]);

    // Table Headers
    final tableHeaders = [
      'م',
      'الفئة / التبويب',
      'الجدول في قاعدة البيانات',
      'النطاق المعتمد للأكواد',
      'إجمالي السجلات',
      'السجلات المطابقة',
      'عدد التنبيهات',
      'إجمالي الرصيد الافتتاحي',
      'حالة المطابقة',
    ];
    summarySheet.appendRow(tableHeaders.map((h) => TextCellValue(h)).toList());

    for (int i = 0; i < tableHeaders.length; i++) {
      summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5)).cellStyle = headerStyle;
    }

    // Category Rows
    int rowIdx = 6;
    for (int i = 0; i < report.categories.length; i++) {
      final cat = report.categories[i];
      final statusText = cat.isPassed ? 'سليمة ومطابقة ✓' : 'تنبيه (${cat.warningCount} أخطاء) ⚠';
      summarySheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(cat.categoryName),
        TextCellValue(cat.tableName),
        TextCellValue(cat.codeRangeDisplay),
        IntCellValue(cat.totalCount),
        IntCellValue(cat.validCount),
        IntCellValue(cat.warningCount),
        DoubleCellValue(cat.totalInitialBalance),
        TextCellValue(statusText),
      ]);

      final statusCell = summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIdx));
      statusCell.cellStyle = cat.isPassed ? passStyle : warnStyle;
      rowIdx++;
    }

    // Total Row
    summarySheet.appendRow([TextCellValue('')]);
    summarySheet.appendRow([
      TextCellValue('الإجمالي العام'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(report.totalRecords),
      IntCellValue(report.totalRecords - report.totalIssues),
      IntCellValue(report.totalIssues),
      DoubleCellValue(report.totalInitialBalance),
      TextCellValue(report.isAllPassed ? 'النظام سليم ومطابق بالكامل ✓' : 'يوجد تنبيهات تتطلب المراجعة ⚠'),
    ]);

    // ── Sheet 2: تفاصيل التنبيهات والأخطاء ──
    const issuesSheetName = 'تفاصيل التنبيهات والأخطاء';
    final issuesSheet = excel[issuesSheetName];

    final issueHeaders = [
      'م',
      'الفئة / التبويب',
      'الجدول',
      'كود السجل',
      'اسم السجل / الكيان',
      'نوع التنبيه',
      'التفاصيل وسبب التنبيه',
    ];
    issuesSheet.appendRow(issueHeaders.map((h) => TextCellValue(h)).toList());
    for (int i = 0; i < issueHeaders.length; i++) {
      issuesSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = headerStyle;
    }

    int issueIndex = 1;
    for (final cat in report.categories) {
      for (final iss in cat.issues) {
        issuesSheet.appendRow([
          IntCellValue(issueIndex++),
          TextCellValue(iss.categoryName),
          TextCellValue(iss.tableName),
          TextCellValue(iss.code),
          TextCellValue(iss.name),
          TextCellValue(iss.issueType),
          TextCellValue(iss.details),
        ]);
      }
    }

    if (report.totalIssues == 0) {
      issuesSheet.appendRow([
        TextCellValue('—'),
        TextCellValue('لا توجد أي أخطاء أو تنبيهات'),
        TextCellValue('—'),
        TextCellValue('—'),
        TextCellValue('جميع الأكواد والأرصدة مطابقة للنطاقات المعتمدة بنسبة 100%'),
        TextCellValue('مطابق'),
        TextCellValue('سليم'),
      ]);
    }

    return excel.save()!;
  }

  /// Safely writes bytes to a file. If the file is locked by another process (e.g. open in Microsoft Excel),
  /// it automatically falls back to an incremental numbered suffix like `_(1).xlsx`
  /// to prevent `PathAccessException` (OS Error 32).
  static Future<File> _writeFileSafely(Directory dir, String fileName, List<int> bytes) async {
    final targetPath = p.join(dir.path, fileName);
    final targetFile = File(targetPath);
    try {
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile;
    } on FileSystemException catch (_) {
      // The file is open in Excel, OneDrive syncing, or another program.
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

  /// Exports and saves the Excel report to file, safely handling locked files and web platforms.
  static Future<String> exportExcel(DataAuditReport report) async {
    final bytes = generateExcelBytes(report);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(report.generatedAt);
    final fileName = 'Data_Audit_Report_$timestamp.xlsx';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: fileName);
      return fileName;
    }

    final docDir = await FileHelper.getExportDirectory();
    final targetDir = Directory(p.join(docDir.path, 'Fruity_ERP_Audit_Reports'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final savedFile = await _writeFileSafely(targetDir, fileName, bytes);

    try {
      await OpenFilex.open(savedFile.path);
    } catch (_) {}

    return savedFile.path;
  }

  // ─────────────────────────────────────────────────────────────
  // 3. PDF Generation & Printing
  // ─────────────────────────────────────────────────────────────

  static pw.Font? _cairoRegular;
  static pw.Font? _cairoBold;

  static Future<void> _loadFonts() async {
    if (_cairoRegular != null && _cairoBold != null) return;
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _cairoRegular = pw.Font.ttf(regData);
      _cairoBold = pw.Font.ttf(boldData);
    } catch (_) {
      // Fallback
      _cairoRegular = pw.Font.helvetica();
      _cairoBold = pw.Font.helveticaBold();
    }
  }

  /// Generates a PDF Document with Cairo typography matching the ERP theme in Landscape orientation.
  static Future<pw.Document> buildPdfDocument(
    DataAuditReport report, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    await _loadFonts();
    final doc = pw.Document();

    final theme = pw.ThemeData.withFont(
      base: _cairoRegular!,
      bold: _cairoBold!,
    );

    // Strictly enforce A4 Landscape orientation
    final landscapeFormat = PdfPageFormat.a4.landscape;

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: landscapeFormat,
          orientation: pw.PageOrientation.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
        header: (context) => _buildPdfHeader(report),
        footer: (context) => _buildPdfFooter(context, report),
        build: (context) => [
          _buildPdfKpiRibbon(report),
          pw.SizedBox(height: 12),
          _buildPdfSummaryTable(report),
          if (report.totalIssues > 0) ...[
            pw.SizedBox(height: 16),
            _buildPdfIssuesSection(report),
          ],
        ],
      ),
    );

    return doc;
  }

  static pw.Widget _buildPdfHeader(DataAuditReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'مزارع فروتي (FRUITY FARMS) — نظام الإدارة والـ ERP المتكامل',
                style: pw.TextStyle(
                  fontSize: 13.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
              pw.Text(
                'تقرير التحقق من صحة واكتمال البيانات (Data Audit Report) — تدقيق شامل لقاعدة البيانات',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'تاريخ التقرير: ${DateFormat('yyyy-MM-dd HH:mm').format(report.generatedAt)}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: report.isAllPassed ? PdfColors.green50 : PdfColors.amber50,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(
                    color: report.isAllPassed ? PdfColors.green700 : PdfColors.amber700,
                    width: 0.8,
                  ),
                ),
                child: pw.Text(
                  report.isAllPassed ? 'البيانات سليمة ومطابقة 100%' : 'توجد تنبيهات (${report.totalIssues} مخالفة)',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: report.isAllPassed ? PdfColors.green900 : PdfColors.amber900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfFooter(pw.Context context, DataAuditReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      margin: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'وثيقة تدقيق ومراجعة داخلية محاسبية معتمدة — تم التوليد آلياً من نظام Fruity ERP (اتجاه الصفحة عرضي Landscape)',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfKpiRibbon(DataAuditReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildPdfKpiItem('إجمالي السجلات المفحوصة', '${report.totalRecords} سجل', PdfColors.blue900),
          _buildPdfKpiItem('إجمالي الأرصدة الافتتاحية', '${_numFmt.format(report.totalInitialBalance)} ج.م', PdfColors.teal800),
          _buildPdfKpiItem('الفئات السليمة والمطابقة', '${report.totalPassedCategories} من ${report.categories.length}', PdfColors.green800),
          _buildPdfKpiItem('الفئات التي تتطلب مراجعة', '${report.totalWarningCategories}', report.totalWarningCategories > 0 ? PdfColors.amber900 : PdfColors.grey700),
          _buildPdfKpiItem('إجمالي التنبيهات المرصودة', '${report.totalIssues}', report.totalIssues > 0 ? PdfColors.red800 : PdfColors.green800),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfKpiItem(String title, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 1),
        pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  static pw.Widget _buildPdfSummaryTable(DataAuditReport report) {
    final headers = [
      'م',
      'الفئة / التبويب',
      'الجدول في Supabase',
      'النطاق المعتمد للأكواد',
      'إجمالي السجلات',
      'المطابق',
      'التنبيهات',
      'الرصيد الافتتاحي',
      'حالة المطابقة',
    ];

    final data = <List<String>>[];
    for (int i = 0; i < report.categories.length; i++) {
      final c = report.categories[i];
      data.add([
        '${i + 1}',
        c.categoryName,
        c.tableName,
        c.codeRangeDisplay,
        '${c.totalCount}',
        '${c.validCount}',
        '${c.warningCount}',
        _numFmt.format(c.totalInitialBalance),
        c.isPassed ? 'سليمة ومطابقة' : 'تنبيه (${c.warningCount} أخطاء)',
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      columnWidths: const {
        0: pw.FlexColumnWidth(0.6), // م
        1: pw.FlexColumnWidth(2.8), // الفئة / التبويب
        2: pw.FlexColumnWidth(2.0), // الجدول في Supabase
        3: pw.FlexColumnWidth(2.4), // النطاق المعتمد
        4: pw.FlexColumnWidth(1.2), // إجمالي السجلات
        5: pw.FlexColumnWidth(1.1), // المطابق
        6: pw.FlexColumnWidth(1.1), // التنبيهات
        7: pw.FlexColumnWidth(2.2), // الرصيد الافتتاحي
        8: pw.FlexColumnWidth(1.8), // حالة المطابقة
      },
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColors.blueGrey900,
        borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
      ),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignments: const {
        0: pw.Alignment.center,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.centerLeft,
        8: pw.Alignment.center,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
    );
  }

  static pw.Widget _buildPdfIssuesSection(DataAuditReport report) {
    final issueRows = <List<String>>[];
    int idx = 1;
    for (final cat in report.categories) {
      for (final iss in cat.issues) {
        issueRows.add([
          '${idx++}',
          iss.categoryName,
          iss.tableName,
          iss.code,
          iss.name,
          iss.issueType,
          iss.details,
        ]);
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColors.red50,
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: PdfColors.red700, width: 0.8),
          ),
          child: pw.Text(
            'سجل التنبيهات والمخالفات المرصودة بالتفصيل (${report.totalIssues} مخالفة تتطلب المراجعة):',
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red900,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['م', 'الفئة / التبويب', 'الجدول', 'الكود', 'اسم السجل / الكيان', 'نوع التنبيه', 'تفاصيل المشكلة والسبب'],
          data: issueRows,
          columnWidths: const {
            0: pw.FlexColumnWidth(0.6), // م
            1: pw.FlexColumnWidth(2.2), // الفئة
            2: pw.FlexColumnWidth(1.6), // الجدول
            3: pw.FlexColumnWidth(1.2), // الكود
            4: pw.FlexColumnWidth(2.4), // الاسم
            5: pw.FlexColumnWidth(1.6), // نوع التنبيه
            6: pw.FlexColumnWidth(4.2), // تفاصيل المشكلة
          },
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          cellAlignments: const {
            0: pw.Alignment.center,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.center,
            6: pw.Alignment.centerRight,
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
          rowDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
          ),
        ),
      ],
    );
  }

  /// Triggers standard printing or preview dialog with Landscape orientation locked.
  static Future<void> printOrSharePdf(DataAuditReport report) async {
    final doc = await buildPdfDocument(report, pageFormat: PdfPageFormat.a4.landscape);
    final bytes = await doc.save();

    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'Data_Audit_Report_${DateFormat('yyyyMMdd').format(report.generatedAt)}',
      format: PdfPageFormat.a4.landscape,
    );
  }

  /// Exports and saves the PDF report directly to a file in the user's documents directory.
  static Future<String> savePdfToFile(DataAuditReport report) async {
    final doc = await buildPdfDocument(report, pageFormat: PdfPageFormat.a4.landscape);
    final bytes = await doc.save();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(report.generatedAt);
    final fileName = 'Data_Audit_Report_$timestamp.pdf';

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return fileName;
    }

    final docDir = await FileHelper.getExportDirectory();
    final targetDir = Directory(p.join(docDir.path, 'Fruity_ERP_Audit_Reports'));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final savedFile = await _writeFileSafely(targetDir, fileName, bytes);

    try {
      await OpenFilex.open(savedFile.path);
    } catch (_) {}

    return savedFile.path;
  }
}

