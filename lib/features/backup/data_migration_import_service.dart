import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/extensions/company_injection.dart';
import '../../data/services/opening_balance_gl_sync_service.dart';

/// Progress callback for data migration import
typedef MigrationProgressCallback = void Function({
  required String currentSheet,
  required int sheetIndex,
  required int totalSheets,
  required int currentRecord,
  required int totalRecordsInSheet,
  required String statusMessage,
});

/// Individual sheet import result
class SheetImportResult {
  final String sheetName;
  final String tableName;
  int insertedCount = 0;
  int updatedCount = 0;
  int failedCount = 0;
  final List<String> errorMessages = [];

  SheetImportResult({
    required this.sheetName,
    required this.tableName,
  });

  int get totalProcessed => insertedCount + updatedCount + failedCount;
  bool get hasErrors => failedCount > 0 || errorMessages.isNotEmpty;
}

/// Overall migration import summary
class MigrationImportSummary {
  final String fileName;
  final int totalSheetsProcessed;
  final int totalInserted;
  final int totalUpdated;
  final int totalFailed;
  final Map<String, SheetImportResult> sheetResults;
  final List<String> globalErrors;
  final Duration duration;

  MigrationImportSummary({
    required this.fileName,
    required this.totalSheetsProcessed,
    required this.totalInserted,
    required this.totalUpdated,
    required this.totalFailed,
    required this.sheetResults,
    required this.globalErrors,
    required this.duration,
  });

  bool get isSuccess => totalFailed == 0 && globalErrors.isEmpty;
  int get totalRecords => totalInserted + totalUpdated + totalFailed;
}

/// Service to handle reading Excel templates and importing/upserting data into Supabase
class DataMigrationImportService {
  static SupabaseClient get _defaultClient => Supabase.instance.client;

  /// Ordered list of sheet priorities so that parent records (stations, categories)
  /// are imported before dependent records (raw materials).
  static const List<String> _importSheetOrder = [
    'المحطات',
    'فئات مواد التعبئة',
    'العملاء - تصديري',
    'العملاء - محلي',
    'موردين المحاصيل',
    'موردين مواد التعبئة',
    'الموردين المشتركين',
    'موردي المحطات',
    'موردي النقل',
    'موردي التخصيمات',
    'المخلص البحري',
    'المخلص الجوي',
    'شركات الشحن',
    'مواد التعبئة والمستلزمات',
  ];

  /// Opens file picker to choose an Excel file (.xlsx) and imports its contents.
  static Future<MigrationImportSummary?> pickAndImportFile({
    SupabaseClient? clientOverride,
    MigrationProgressCallback? onProgress,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return null; // User cancelled
      }

      final pickedFile = result.files.single;
      final fileName = pickedFile.name;
      List<int>? bytes = pickedFile.bytes;

      if (bytes == null && pickedFile.path != null) {
        final f = File(pickedFile.path!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('الملف المختار فارغ أو لا يمكن قراءة بياناته.');
      }

      return await importWorkbookBytes(
        bytes: bytes,
        fileName: fileName,
        clientOverride: clientOverride,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('Error picking or importing file: $e');
      rethrow;
    }
  }

  /// Parses bytes of an Excel workbook and imports all recognized sheets into Supabase.
  static Future<MigrationImportSummary> importWorkbookBytes({
    required List<int> bytes,
    required String fileName,
    SupabaseClient? clientOverride,
    MigrationProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final client = clientOverride ?? _defaultClient;
    final excel = Excel.decodeBytes(bytes);

    final Map<String, SheetImportResult> sheetResults = {};
    final List<String> globalErrors = [];

    // Filter available sheets in the workbook matching our migration tables
    final availableSheetNames = excel.tables.keys.where((name) {
      final clean = name.trim();
      return clean != 'Sheet1' &&
          !clean.startsWith('دليل_التعليمات') &&
          !clean.toLowerCase().contains('guide');
    }).toList();

    // Sort sheets according to dependency order
    availableSheetNames.sort((a, b) {
      final idxA = _importSheetOrder.indexWhere((k) => _normalizeSheetName(a) == _normalizeSheetName(k));
      final idxB = _importSheetOrder.indexWhere((k) => _normalizeSheetName(b) == _normalizeSheetName(k));
      final posA = idxA == -1 ? 999 : idxA;
      final posB = idxB == -1 ? 999 : idxB;
      return posA.compareTo(posB);
    });

    final totalSheets = availableSheetNames.length;
    int currentSheetIndex = 0;

    for (final rawSheetName in availableSheetNames) {
      currentSheetIndex++;
      final sheet = excel.tables[rawSheetName];
      if (sheet == null || sheet.rows.isEmpty) continue;

      final normalizedName = _normalizeSheetName(rawSheetName);
      final tableName = _resolveTableName(normalizedName);

      final sheetResult = SheetImportResult(
        sheetName: rawSheetName,
        tableName: tableName,
      );
      sheetResults[rawSheetName] = sheetResult;

      // Header row (normalize by stripping asterisk * so 'code*' matches 'code')
      final headers = sheet.rows[0].map((cell) => _cellToString(cell).replaceAll('*', '').toLowerCase().trim()).toList();

      // Data rows (index 1 onwards)
      final dataRows = sheet.rows.skip(1).toList();
      final totalRecords = dataRows.length;

      for (int i = 0; i < dataRows.length; i++) {
        final row = dataRows[i];
        final rowNumber = i + 2; // Excel 1-based indexing including header

        // Check if row is completely empty
        if (_isRowEmpty(row)) continue;

        // Build key-value map for the row
        final rowMap = <String, Data?>{};
        for (int h = 0; h < headers.length; h++) {
          if (h < row.length) {
            rowMap[headers[h]] = row[h];
          }
        }

        onProgress?.call(
          currentSheet: rawSheetName,
          sheetIndex: currentSheetIndex,
          totalSheets: totalSheets,
          currentRecord: i + 1,
          totalRecordsInSheet: totalRecords,
          statusMessage: 'جاري معالجة السجل ${i + 1} من $totalRecords في [$rawSheetName]...',
        );

        try {
          await _importSingleRow(
            client: client,
            normalizedSheetName: normalizedName,
            rowMap: rowMap,
            rowNumber: rowNumber,
            sheetResult: sheetResult,
          );
        } catch (e) {
          sheetResult.failedCount++;
          final errorMsg = 'الصف $rowNumber: $e';
          sheetResult.errorMessages.add(errorMsg);
          debugPrint('Error importing row in [$rawSheetName]: $errorMsg');
        }
      }
    }

    // Mirror overall opening balances to General Ledger
    try {
      await OpeningBalanceGlSyncService.instance.syncAllEntities();
    } catch (e) {
      debugPrint('Notice: Background GL sync notice: $e');
    }

    stopwatch.stop();

    int totalInserted = 0;
    int totalUpdated = 0;
    int totalFailed = 0;

    for (final res in sheetResults.values) {
      totalInserted += res.insertedCount;
      totalUpdated += res.updatedCount;
      totalFailed += res.failedCount;
    }

    return MigrationImportSummary(
      fileName: fileName,
      totalSheetsProcessed: sheetResults.length,
      totalInserted: totalInserted,
      totalUpdated: totalUpdated,
      totalFailed: totalFailed,
      sheetResults: sheetResults,
      globalErrors: globalErrors,
      duration: stopwatch.elapsed,
    );
  }

  /// Dispatches row import to the corresponding handler based on sheet name
  static Future<void> _importSingleRow({
    required SupabaseClient client,
    required String normalizedSheetName,
    required Map<String, Data?> rowMap,
    required int rowNumber,
    required SheetImportResult sheetResult,
  }) async {
    switch (normalizedSheetName) {
      case 'المحطات':
        await _importStationRow(client, rowMap, sheetResult);
        break;

      case 'فئات مواد التعبئة':
        await _importPackingCategoryRow(client, rowMap, sheetResult);
        break;

      case 'العملاء - تصديري':
        await _importCustomerRow(client, rowMap, sheetResult, isExport: true);
        break;

      case 'العملاء - محلي':
        await _importCustomerRow(client, rowMap, sheetResult, isExport: false);
        break;

      case 'موردين المحاصيل':
        await _importSupplierRow(client, rowMap, sheetResult, supplierType: 'crop');
        break;

      case 'موردين مواد التعبئة':
        await _importSupplierRow(client, rowMap, sheetResult, supplierType: 'packaging');
        break;

      case 'الموردين المشتركين':
        await _importSupplierRow(client, rowMap, sheetResult, supplierType: 'shared');
        break;

      case 'موردي المحطات':
        await _importSupplierRow(client, rowMap, sheetResult, supplierType: 'station');
        break;

      case 'موردي التخصيمات':
        await _importSupplierRow(client, rowMap, sheetResult, supplierType: 'deduction');
        break;

      case 'موردي النقل':
        await _importTransportSupplierRow(client, rowMap, sheetResult);
        break;

      case 'المخلص البحري':
        await _importClearingAgentRow(client, rowMap, sheetResult, brokerType: 'بحري');
        break;

      case 'المخلص الجوي':
        await _importClearingAgentRow(client, rowMap, sheetResult, brokerType: 'جوي');
        break;

      case 'شركات الشحن':
        await _importShippingCompanyRow(client, rowMap, sheetResult);
        break;

      case 'مواد التعبئة والمستلزمات':
        await _importRawMaterialRow(client, rowMap, sheetResult);
        break;

      default:
        sheetResult.failedCount++;
        sheetResult.errorMessages.add('التبويب غير مدعوم للرفع الآلي: $normalizedSheetName');
        break;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Row Handlers
  // ───────────────────────────────────────────────────────────────────────────

  /// 1. المحطات (Stations)
  static Future<void> _importStationRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result,
  ) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final existing = await client.from('stations').select('id').eq('code', code).maybeSingle();
    final data = {
      'code': code,
      'name': name,
      'type': 'sub',
      'is_active': true,
    };

    if (existing != null) {
      await client.from('stations').update(data).eq('id', existing['id']);
      result.updatedCount++;
    } else {
      await client.from('stations').insert(data);
      result.insertedCount++;
    }
  }

  /// 2. فئات مواد التعبئة (Packing Material Categories)
  static Future<void> _importPackingCategoryRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result,
  ) async {
    final name = _cellToString(row['category_name'] ?? row['name']);
    if (name.isEmpty) return;

    final existing = await client.from('raw_material_categories').select('id').eq('name', name).maybeSingle();
    if (existing == null) {
      await client.from('raw_material_categories').insert({'name': name});
      result.insertedCount++;
    } else {
      result.updatedCount++;
    }
  }

  /// 3 & 4. العملاء (تصديري ومحلي)
  static Future<void> _importCustomerRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result, {
    required bool isExport,
  }) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final currency = _cellToString(row['currency']).toUpperCase();
    final phone = _cellToString(row['phone']);
    final email = _cellToString(row['email'] ?? row['gmail']);
    final city = _cellToString(row['city']);
    final country = _cellToString(row['country']);
    final address = _cellToString(row['address']);
    final contactPerson = _cellToString(row['contact_person'] ?? row['contact_person_name']);
    final contactPhone = _cellToString(row['contact_phone'] ?? row['contact_person_phone']);
    final contactEmail = _cellToString(row['contact_email'] ?? row['contact_person_email']);
    final vatNumber = _cellToString(row['vat_number'] ?? row['vat_no']);
    final eoriNumber = _cellToString(row['eori_number'] ?? row['eori_no']);
    final openingBalance = _cellToDouble(row['opening_balance'] ?? row['balance']);
    final rawDir = _cellToString(row['balance_direction']).toUpperCase();
    final balanceDirection = (rawDir.contains('CREDIT') || rawDir.contains('دائن')) ? 'CREDIT' : 'DEBIT';

    final addresses = address.isNotEmpty ? [{'address': address}] : <Map<String, dynamic>>[];

    final customerData = <String, dynamic>{
      'code': code,
      'name': name,
      'company_type': isExport ? 'export' : 'local',
      'currency': currency.isNotEmpty ? currency : (isExport ? 'USD' : 'EGP'),
      'phone': phone,
      'gmail': email,
      'city': city,
      'country': country,
      'contact_person_name': contactPerson,
      'contact_person_phone': contactPhone,
      'contact_person_email': contactEmail,
      'initial_balance': openingBalance,
      'balance': openingBalance,
      'initial_balance_direction': balanceDirection,
      if (isExport && vatNumber.isNotEmpty) 'vat_no': vatNumber,
      if (isExport && eoriNumber.isNotEmpty) 'eori_no': eoriNumber,
      if (addresses.isNotEmpty) 'addresses': addresses,
    };

    final existing = await client.from('customers').select('id').eq('code', code).maybeSingle();
    final dynamic customerId;

    if (existing != null) {
      customerId = existing['id'];
      await client.from('customers').update(customerData).eq('id', customerId);
      result.updatedCount++;
    } else {
      final insertPayload = Map<String, dynamic>.from(customerData).withCompanyId();
      final inserted = await client.from('customers').insert(insertPayload).select('id').single();
      customerId = inserted['id'];
      result.insertedCount++;
    }

    // Mirror opening balance to General Ledger (Non-blocking)
    if (openingBalance > 0 && customerId != null) {
      try {
        await OpeningBalanceGlSyncService.instance.syncCustomerOpeningBalance(
          customerId: customerId,
          customerName: name,
          initialBalance: openingBalance,
          currency: customerData['currency'] as String,
          direction: balanceDirection,
          accountId: null,
          customerType: isExport ? 'export' : 'local',
        );
      } catch (e) {
        debugPrint('Warning: Could not sync opening balance to GL for customer $code: $e');
      }
    }
  }

  /// 5, 6, 7, 8, 9. الموردين بكافة فئاتهم (محاصيل، تعبئة، مشترك، محطات، تخصيمات)
  static Future<void> _importSupplierRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result, {
    required String supplierType,
  }) async {
    final code = _cellToString(row['code'] ?? row['supplier_code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final phone = _cellToString(row['phone']);
    final address = _cellToString(row['address']);
    final currency = _cellToString(row['currency']).toUpperCase();
    final openingBalance = _cellToDouble(row['opening_balance'] ?? row['initial_balance']);
    final rawDir = _cellToString(row['balance_direction']).toUpperCase();
    final balanceDirection = (rawDir.contains('DEBIT') || rawDir.contains('مدين')) ? 'DEBIT' : 'CREDIT';

    final servicesMapping = _cellToString(row['services_mapping']);
    final deductionsMapping = _cellToString(row['deductions_mapping']);

    List<String> categories = [];
    if (servicesMapping.isNotEmpty) {
      categories = servicesMapping.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else if (deductionsMapping.isNotEmpty) {
      categories = deductionsMapping.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    final supplierData = <String, dynamic>{
      'code': code,
      'supplier_code': code,
      'name': name,
      'phone': phone,
      'address': address,
      'supplier_type': supplierType,
      'currency': currency.isNotEmpty ? currency : 'EGP',
      'initial_balance': openingBalance,
      'outstanding_balance': openingBalance,
      'initial_balance_direction': balanceDirection,
      if (categories.isNotEmpty) 'categories': categories,
    };

    final existing = await client.from('suppliers').select('id').or('code.eq.$code,supplier_code.eq.$code').maybeSingle();
    final dynamic supplierId;

    if (existing != null) {
      supplierId = existing['id'];
      await client.from('suppliers').update(supplierData).eq('id', supplierId);
      result.updatedCount++;
    } else {
      final insertPayload = Map<String, dynamic>.from(supplierData).withCompanyId();
      final inserted = await client.from('suppliers').insert(insertPayload).select('id').single();
      supplierId = inserted['id'];
      result.insertedCount++;
    }

    // Mirror opening balance to General Ledger (Non-blocking)
    if (openingBalance > 0 && supplierId != null) {
      try {
        await OpeningBalanceGlSyncService.instance.syncSupplierOpeningBalance(
          supplierId: supplierId,
          supplierName: name,
          supplierCode: code,
          supplierType: supplierType,
          initialBalance: openingBalance,
          currency: supplierData['currency'] as String,
          direction: balanceDirection,
          accountId: null,
          isMultiCurrency: false,
        );
      } catch (e) {
        debugPrint('Warning: Could not sync opening balance to GL for supplier $code: $e');
      }
    }
  }

  /// 10. موردي النقل (Transport Suppliers)
  static Future<void> _importTransportSupplierRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result,
  ) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final phone = _cellToString(row['phone']);
    final email = _cellToString(row['email']);
    final openingBalance = _cellToDouble(row['opening_balance'] ?? row['initial_balance']);
    final rawDir = _cellToString(row['balance_direction']).toUpperCase();
    final balanceDirection = (rawDir.contains('DEBIT') || rawDir.contains('مدين')) ? 'DEBIT' : 'CREDIT';
    final tripsCount = _cellToDouble(row['available_trips_count'] ?? row['truck_balance']);
    final notes = _cellToString(row['notes']);

    final transportData = <String, dynamic>{
      'code': code,
      'name': name,
      'phone': phone,
      'email': email,
      'initial_balance': openingBalance,
      'initial_balance_direction': balanceDirection,
      'balance': openingBalance,
      'current_balance': openingBalance,
      'truck_balance': tripsCount,
      'initial_truck_balance': tripsCount,
      if (notes.isNotEmpty) 'notes': notes,
    };

    final existing = await client.from('transport_suppliers').select('id').eq('code', code).maybeSingle();
    final dynamic transportId;

    if (existing != null) {
      transportId = existing['id'];
      await client.from('transport_suppliers').update(transportData).eq('id', transportId);
      result.updatedCount++;
    } else {
      final insertPayload = Map<String, dynamic>.from(transportData).withCompanyId();
      final inserted = await client.from('transport_suppliers').insert(insertPayload).select('id').single();
      transportId = inserted['id'];
      result.insertedCount++;
    }
  }

  /// 11 & 12. مخلصي الجمارك (بحري وجوي)
  static Future<void> _importClearingAgentRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result, {
    required String brokerType,
  }) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final phone = _cellToString(row['phone']);
    final email = _cellToString(row['email'] ?? row['gmail']);
    final city = _cellToString(row['city']);
    final country = _cellToString(row['country']);
    final address = _cellToString(row['address']);
    final contactPerson = _cellToString(row['contact_person'] ?? row['contact_person_name']);
    final openingBalance = _cellToDouble(row['opening_balance'] ?? row['balance']);
    final currency = _cellToString(row['currency']).toUpperCase();

    final addresses = address.isNotEmpty ? [{'address': address}] : <Map<String, dynamic>>[];

    final clearingData = <String, dynamic>{
      'code': code,
      'name': name,
      'phone': phone,
      'gmail': email,
      'city': city,
      'country': country,
      'broker_type': brokerType,
      'contact_person_name': contactPerson,
      'initial_balance': openingBalance,
      'balance': openingBalance,
      'currency': currency.isNotEmpty ? currency : 'EGP',
      if (addresses.isNotEmpty) 'addresses': addresses,
    };

    final existing = await client.from('clearing_agents').select('id').eq('code', code).maybeSingle();
    final dynamic agentId;

    if (existing != null) {
      agentId = existing['id'];
      await client.from('clearing_agents').update(clearingData).eq('id', agentId);
      result.updatedCount++;
    } else {
      final inserted = await client.from('clearing_agents').insert(clearingData).select('id').single();
      agentId = inserted['id'];
      result.insertedCount++;
    }
  }

  /// 13. شركات الشحن (Shipping Companies)
  static Future<void> _importShippingCompanyRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result,
  ) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final phone = _cellToString(row['phone']);
    final email = _cellToString(row['email']);
    final openingBalance = _cellToDouble(row['opening_balance'] ?? row['balance']);
    final currency = _cellToString(row['currency']).toUpperCase();

    final shippingData = <String, dynamic>{
      'code': code,
      'name': name,
      'phone': phone,
      'email': email,
      'initial_balance': openingBalance,
      'balance': openingBalance,
      'currency': currency.isNotEmpty ? currency : 'USD',
    };

    final existing = await client.from('shipping_companies').select('id').eq('code', code).maybeSingle();
    final dynamic shippingId;

    if (existing != null) {
      shippingId = existing['id'];
      await client.from('shipping_companies').update(shippingData).eq('id', shippingId);
      result.updatedCount++;
    } else {
      final inserted = await client.from('shipping_companies').insert(shippingData).select('id').single();
      shippingId = inserted['id'];
      result.insertedCount++;
    }
  }

  /// 14. مواد التعبئة والمستلزمات (Raw Materials & Packing Supplies)
  static Future<void> _importRawMaterialRow(
    SupabaseClient client,
    Map<String, Data?> row,
    SheetImportResult result,
  ) async {
    final code = _cellToString(row['code']);
    final name = _cellToString(row['name']);
    if (code.isEmpty || name.isEmpty) return;

    final currency = _cellToString(row['currency']).toUpperCase();
    final unit = _cellToString(row['unit']);
    final categoryName = _cellToString(row['category'] ?? row['category_name']);
    final openingQty = _cellToDouble(row['opening_quantity'] ?? row['quantity'] ?? row['current_stock']);
    final costPrice = _cellToDouble(row['opening_cost_price'] ?? row['default_purchase_price'] ?? row['cost_price']);

    // Resolve or auto-create category_id if provided
    String? categoryId;
    if (categoryName.isNotEmpty) {
      final cat = await client.from('raw_material_categories').select('id').eq('name', categoryName).maybeSingle();
      if (cat != null) {
        categoryId = cat['id']?.toString();
      } else {
        try {
          final newCat = await client.from('raw_material_categories').insert({'name': categoryName}).select('id').single();
          categoryId = newCat['id']?.toString();
        } catch (_) {}
      }
    }

    final materialData = <String, dynamic>{
      'code': code,
      'name': name,
      'currency': currency.isNotEmpty ? currency : 'EGP',
      'unit': unit.isNotEmpty ? unit : 'piece',
      if (categoryId != null) 'category_id': categoryId,
      'quantity': openingQty,
      'initial_quantity': openingQty,
      'default_purchase_price': costPrice,
      'initial_avg_price': costPrice,
      'minimum_stock': 0.0,
      'is_active': true,
    };

    final existing = await client.from('raw_materials').select('id').eq('code', code).maybeSingle();
    if (existing != null) {
      await client.from('raw_materials').update(materialData).eq('id', existing['id']);
      result.updatedCount++;
    } else {
      // Also check if same name exists
      final byName = await client.from('raw_materials').select('id').eq('name', name).maybeSingle();
      if (byName != null) {
        await client.from('raw_materials').update(materialData).eq('id', byName['id']);
        result.updatedCount++;
      } else {
        await client.from('raw_materials').insert(materialData);
        result.insertedCount++;
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helper Parsing Utilities
  // ───────────────────────────────────────────────────────────────────────────

  static bool _isRowEmpty(List<Data?> row) {
    for (final cell in row) {
      final str = _cellToString(cell);
      if (str.isNotEmpty) return false;
    }
    return true;
  }

  static String _cellToString(Data? cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    if (val is TextCellValue) return val.value.text?.trim() ?? '';
    return val.toString().trim();
  }

  static double _cellToDouble(Data? cell, [double defaultValue = 0.0]) {
    if (cell == null) return defaultValue;
    final val = cell.value;
    if (val == null) return defaultValue;
    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value.toDouble();
    final s = _cellToString(cell).replaceAll(',', '').trim();
    return double.tryParse(s) ?? defaultValue;
  }

  static String _normalizeSheetName(String sheetName) {
    var s = sheetName.trim();
    // Strip leading numbering e.g. "01_" or "1 - "
    s = s.replaceAll(RegExp(r'^\d+[\s\-_.]+'), '');
    return s;
  }

  static String _resolveTableName(String normalizedSheetName) {
    switch (normalizedSheetName) {
      case 'المحطات':
        return 'stations';
      case 'فئات مواد التعبئة':
        return 'raw_material_categories';
      case 'العملاء - تصديري':
      case 'العملاء - محلي':
        return 'customers';
      case 'موردين المحاصيل':
      case 'موردين مواد التعبئة':
      case 'الموردين المشتركين':
      case 'موردي المحطات':
      case 'موردي التخصيمات':
        return 'suppliers';
      case 'موردي النقل':
        return 'transport_suppliers';
      case 'المخلص البحري':
      case 'المخلص الجوي':
        return 'clearing_agents';
      case 'شركات الشحن':
        return 'shipping_companies';
      case 'مواد التعبئة والمستلزمات':
        return 'raw_materials';
      default:
        return 'unknown';
    }
  }
}
