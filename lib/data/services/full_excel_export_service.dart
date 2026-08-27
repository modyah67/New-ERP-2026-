import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import '../../features/journal_entry/journal_entry_excel_service.dart';

typedef ExportProgress = void Function(String section, int current, int total);

class FullExcelExportService {
  final _client = Supabase.instance.client;

  // Lookup maps built at export time
  Map<String, String> _supplierNames = {};
  Map<String, String> _supplierCodes = {};
  Map<String, String> _customerNames = {};
  Map<String, String> _customerCodes = {};
  Map<String, String> _stationNames = {};
  Map<String, String> _stationCodes = {};
  Map<String, String> _treasuryNames = {};
  Map<String, String> _bankAccountNames = {};
  Map<String, String> _rawMaterialNames = {};
  Map<String, String> _rawMaterialCodes = {};
  Map<String, String> _accountNames = {};
  Map<String, String> _accountCodes = {};
  Map<String, String> _fruitTypeNames = {};
  Map<String, String> _clearingAgentNames = {};
  Map<String, String> _shippingCompanyNames = {};
  Map<String, String> _userName = {};
  Map<String, String> _shipmentNumbers = {};
  Map<String, String> _purchaseInvoiceNumbers = {};
  Map<String, String> _purchaseInvoiceDates = {};

  Future<void> _loadLookups() async {
    try {
      final suppliers = await _client.from('suppliers').select('id, name, supplier_code');
      for (final s in suppliers) {
        final id = s['id']?.toString() ?? '';
        _supplierNames[id] = s['name']?.toString() ?? '';
        _supplierCodes[id] = s['supplier_code']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final customers = await _client.from('customers').select('id, name, code');
      for (final c in customers) {
        final id = c['id']?.toString() ?? '';
        _customerNames[id] = c['name']?.toString() ?? '';
        _customerCodes[id] = c['code']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final stations = await _client.from('stations').select('id, name, code');
      for (final s in stations) {
        final id = s['id']?.toString() ?? '';
        _stationNames[id] = s['name']?.toString() ?? '';
        _stationCodes[id] = s['code']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final treasuries = await _client.from('treasuries').select('id, name');
      for (final t in treasuries) {
        _treasuryNames[t['id']?.toString() ?? ''] = t['name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final banks = await _client.from('bank_accounts').select('id, name');
      for (final b in banks) {
        _bankAccountNames[b['id']?.toString() ?? ''] = b['name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final materials = await _client.from('raw_materials').select('id, name, code');
      for (final m in materials) {
        final id = m['id']?.toString() ?? '';
        _rawMaterialNames[id] = m['name']?.toString() ?? '';
        _rawMaterialCodes[id] = m['code']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final accounts = await _client.from('accounts').select('id, account_name, account_code');
      for (final a in accounts) {
        final id = a['id']?.toString() ?? '';
        _accountNames[id] = a['account_name']?.toString() ?? '';
        _accountCodes[id] = a['account_code']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final fruits = await _client.from('fruit_types').select('id, name, code');
      for (final f in fruits) {
        final id = f['id']?.toString() ?? '';
        _fruitTypeNames[id] = f['name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final agents = await _client.from('clearing_agents').select('id, name');
      for (final a in agents) {
        _clearingAgentNames[a['id']?.toString() ?? ''] = a['name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final companies = await _client.from('shipping_companies').select('id, name');
      for (final c in companies) {
        _shippingCompanyNames[c['id']?.toString() ?? ''] = c['name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final users = await _client.from('users').select('id, full_name');
      for (final u in users) {
        _userName[u['id']?.toString() ?? ''] = u['full_name']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final shipments = await _client.from('export_shipments').select('id, shipment_no');
      for (final s in shipments) {
        _shipmentNumbers[s['id']?.toString() ?? ''] = s['shipment_no']?.toString() ?? '';
      }
    } catch (_) {}

    try {
      final purchases = await _client.from('purchase_invoices').select('id, invoice_number, invoice_date');
      for (final p in purchases) {
        final id = p['id']?.toString() ?? '';
        _purchaseInvoiceNumbers[id] = p['invoice_number']?.toString() ?? '';
        _purchaseInvoiceDates[id] = p['invoice_date']?.toString() ?? '';
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  // Main export
  // ═══════════════════════════════════════════════════

    Future<String> exportAll({ExportProgress? onProgress, String? customDirectory}) async {
    onProgress?.call('جاري تحميل البيانات...', 0, 45);
    await _loadLookups();

    final selectedDir = customDirectory ?? await FilePicker.getDirectoryPath();
    if (selectedDir == null) throw Exception('لم يتم اختيار مجلد لحفظ النسخة');

    final total = 37;
    var idx = 0;

    // ── البيانات ──
    onProgress?.call('العملاء', ++idx, total);
    await _safe('البيانات', 'العملاء', selectedDir, (excel) => _writeCustomers(excel));

    onProgress?.call('الموردين', ++idx, total);
    await _safe('البيانات', 'الموردين', selectedDir, (excel) => _writeSuppliers(excel));

    onProgress?.call('وكلاء التخليص', ++idx, total);
    await _safe('البيانات', 'وكلاء التخليص', selectedDir, (excel) => _writeClearingAgents(excel));

    onProgress?.call('شركات الشحن', ++idx, total);
    await _safe('البيانات', 'شركات الشحن', selectedDir, (excel) => _writeShippingCompanies(excel));

    // ── المخازن ──
    onProgress?.call('المحطات', ++idx, total);
    await _safe('المخازن', 'المحطات', selectedDir, (excel) => _writeSimple(excel, 'المحطات', 'stations',
        ['code', 'name', 'type', 'is_active'], ['الكود', 'الاسم', 'النوع', 'الحالة']));

    onProgress?.call('المواد الخام', ++idx, total);
    await _safe('المخازن', 'المواد الخام', selectedDir, (excel) => _writeSimple(excel, 'المواد الخام', 'raw_materials',
        ['code', 'name', 'unit', 'cost_price', 'is_active'], ['الكود', 'الاسم', 'الوحدة', 'سعر الشراء', 'الحالة']));

    onProgress?.call('أنواع الفاكهة', ++idx, total);
    await _safe('المخازن', 'أنواع الفاكهة', selectedDir, (excel) => _writeSimple(excel, 'أنواع الفاكهة', 'fruit_types',
        ['code', 'name', 'is_active'], ['الكود', 'الاسم', 'الحالة']));

    onProgress?.call('المنتجات النهائية', ++idx, total);
    await _safe('المخازن', 'المنتجات النهائية', selectedDir, (excel) => _writeSimple(excel, 'المنتجات النهائية', 'finished_products',
        ['code', 'name', 'barcode', 'category', 'sale_price', 'unit', 'is_active'],
        ['الكود', 'الاسم', 'الباركود', 'التصنيف', 'سعر البيع', 'الوحدة', 'الحالة']));

    onProgress?.call('وصفات التعبئة', ++idx, total);
    await _safe('المخازن', 'وصفات التعبئة', selectedDir, (excel) => _writeSimple(excel, 'وصفات التعبئة', 'packing_recipes',
        ['name', 'description', 'grade', 'quantity_per_carton', 'unit', 'is_active'],
        ['الاسم', 'الوصف', 'المستوى', 'الكمية/كرتونة', 'الوحدة', 'الحالة']));

    onProgress?.call('فواتير الشراء', ++idx, total);
    await _safe('المخازن', 'فواتير الشراء', selectedDir, (excel) => _writePurchaseInvoices(excel));

    onProgress?.call('بنود فواتير الشراء', ++idx, total);
    await _safe('المخازن', 'بنود فواتير الشراء', selectedDir, (excel) => _writePurchaseItems(excel));

    onProgress?.call('المحاصيل', ++idx, total);
    await _safe('المخازن', 'المحاصيل', selectedDir, (excel) => _writeLots(excel));

    onProgress?.call('أوامر التعبئة', ++idx, total);
    await _safe('المخازن', 'أوامر التعبئة', selectedDir, (excel) => _writePackingOrders(excel));

    onProgress?.call('النقل الداخلي', ++idx, total);
    await _safe('المخازن', 'النقل الداخلي', selectedDir, (excel) => _writeTransfers(excel));

    onProgress?.call('حركات المخزون', ++idx, total);
    await _safe('المخازن', 'حركات المخزون', selectedDir, (excel) => _writeStockMovements(excel));
    
    onProgress?.call('المنتجات في المحطة', ++idx, total);
    await _safe('المخازن', 'المنتجات في المحطة', selectedDir, (excel) => _writeStationProducts(excel));

    onProgress?.call('دفعات المحطة', ++idx, total);
    await _safe('المخازن', 'دفعات المحطة', selectedDir, (excel) => _writeStationBatches(excel));
    
    onProgress?.call('متابعة المخازن', ++idx, total);
    await _safe('المخازن', 'متابعة المخازن', selectedDir, (excel) => _writeWarehouseTracking(excel));

    // ── الفواتير و الارباح ──
    onProgress?.call('فواتير البيع', ++idx, total);
    await _safe('الفواتير و الارباح', 'فواتير البيع', selectedDir, (excel) => _writeInvoices(excel));

    onProgress?.call('فواتير التصدير', ++idx, total);
    await _safe('الفواتير و الارباح', 'فواتير التصدير', selectedDir, (excel) => _writeExportInvoices(excel));

    onProgress?.call('شحنات التصدير', ++idx, total);
    await _safe('الفواتير و الارباح', 'شحنات التصدير', selectedDir, (excel) => _writeExportShipments(excel));

    onProgress?.call('بنود تكلفة الشحن', ++idx, total);
    await _safe('الفواتير و الارباح', 'بنود تكلفة الشحن', selectedDir, (excel) => _writeShipmentCostItems(excel));

    onProgress?.call('ربحية الشحنات', ++idx, total);
    await _safe('الفواتير و الارباح', 'ربحية الشحنات', selectedDir, (excel) => _writeSimple(excel, 'ربحية الشحنات', 'shipment_profitability_snapshots',
        ['shipment_no', 'revenue_foreign', 'revenue_local', 'fruit_cost', 'packing_cost', 'logistics_cost', 'total_cost', 'gross_profit', 'net_profit', 'gross_margin', 'net_margin', 'cartons', 'net_weight', 'pallets', 'created_at'],
        ['رقم الشحنة', 'الإيراد (أجنبي)', 'الإيراد (محلي)', 'تكلفة الفاكهة', 'تكلفة التعبئة', 'تكلفة اللوجستيات', 'التكلفة الإجمالية', 'الربح الإجمالي', 'صافي الربح', 'هامش الإجمالي', 'هامش الصافي', 'الكراتين', 'الصافي (كجم)', 'الباليتات', 'التاريخ']));
        
    onProgress?.call('توزيع الأرباح', ++idx, total);
    await _safe('الفواتير و الارباح', 'توزيع الأرباح', selectedDir, (excel) => _writeProfitDistribution(excel));
    
    onProgress?.call('فئات المصروفات', ++idx, total);
    await _safe('الفواتير و الارباح', 'فئات المصروفات', selectedDir, (excel) => _writeSimple(excel, 'فئات المصروفات', 'expense_categories',
        ['name', 'is_active'], ['الاسم', 'الحالة']));
        
    onProgress?.call('تقارير التكاليف', ++idx, total);
    await _safe('الفواتير و الارباح', 'تقارير التكاليف', selectedDir, (excel) => _writeCostReport(excel));

    // ── الحسابات ──
    onProgress?.call('الخزائن', ++idx, total);
    await _safe('الحسابات', 'الخزائن', selectedDir, (excel) => _writeSimple(excel, 'الخزائن', 'treasuries',
        ['name', 'type', 'notes', 'created_at'], ['الاسم', 'النوع', 'ملاحظات', 'التاريخ']));

    onProgress?.call('أرصدة الخزائن', ++idx, total);
    await _safe('الحسابات', 'أرصدة الخزائن', selectedDir, (excel) => _writeTreasuryBalances(excel));

    onProgress?.call('حركات الخزينة', ++idx, total);
    await _safe('الحسابات', 'حركات الخزينة', selectedDir, (excel) => _writeTreasuryTransactions(excel));

    onProgress?.call('الحسابات البنكية', ++idx, total);
    await _safe('الحسابات', 'الحسابات البنكية', selectedDir, (excel) => _writeSimple(excel, 'الحسابات البنكية', 'bank_accounts',
        ['name', 'account_number', 'currency', 'created_at'], ['الاسم', 'رقم الحساب', 'العملة', 'التاريخ']));

    onProgress?.call('حركات البنك', ++idx, total);
    await _safe('الحسابات', 'حركات البنك', selectedDir, (excel) => _writeBankTransactions(excel));

    onProgress?.call('الشيكات', ++idx, total);
    await _safe('الحسابات', 'الشيكات', selectedDir, (excel) => _writeCheques(excel));

    onProgress?.call('سندات القبض', ++idx, total);
    await _safe('الحسابات', 'سندات القبض', selectedDir, (excel) => _writeCashReceipts(excel));

    onProgress?.call('سندات الصرف', ++idx, total);
    await _safe('الحسابات', 'سندات الصرف', selectedDir, (excel) => _writeCashPayments(excel));

    onProgress?.call('القيود اليومية', ++idx, total);
    await _safe('الحسابات', 'القيود اليومية', selectedDir, (excel) => _writeLedgerEntries(excel));

    onProgress?.call('الحسابات', ++idx, total);
    await _safe('الحسابات', 'الحسابات', selectedDir, (excel) => _writeSimple(excel, 'الحسابات', 'accounts',
        ['account_code', 'account_name', 'account_type', 'balance', 'is_active'],
        ['كود الحساب', 'اسم الحساب', 'النوع', 'الرصيد', 'الحالة']));

    onProgress?.call('المشتريات المحصولية', ++idx, total);
    await _safe('الحسابات', 'المشتريات المحصولية', selectedDir, (excel) => _writeCropPurchases(excel));

    // ── إدارة المستخدمين ──
    onProgress?.call('مستخدمين النظام', ++idx, total);
    await _safe('إدارة المستخدمين', 'مستخدمين النظام', selectedDir, (excel) => _writeUserRoles(excel));

    return selectedDir;
  }


Future<void> _safe(
      String folderName,
      String fileName,
      String customDirectory,
      Future<void> Function(Excel excel) fn) async {
    try {
      final excel = Excel.createExcel();
      
      await fn(excel);
      
      // Cleanup empty default sheets
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final folderPath = p.join(customDirectory, folderName);
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final filePath = p.join(folderPath, '$fileName.xlsx');
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes, flush: true);
      }
    } catch (e) {
      final folderPath = p.join(customDirectory, folderName);
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final filePath = p.join(folderPath, '$fileName - خطأ.txt');
      final file = File(filePath);
      await file.writeAsString('Error exporting $fileName: $e');
    }
  }


Future<void> _writeSimple(Excel excel, String sheetName, String table, List<String> columns, List<String> headers) async {
    final data = await _fetchAll(table);
    final sheet = excel[sheetName];
    _writeHeader(sheet, headers);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      for (var c = 0; c < columns.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = _toCellValue(row[columns[c]]);
      }
    }
    _autoWidth(sheet, headers.length, data.length + 1);
  }

  void _writeHeader(Sheet sheet, List<String> headers) {
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
      );
    }
  }

  // ═══════════════════════════════════════════════════
  // Custom writers with ID resolution
  // ═══════════════════════════════════════════════════

  // ── العملاء ──
  Future<void> _writeCustomers(Excel excel) async {
    final data = await _fetchAll('customers');
    final sheet = excel['العملاء'];
    final h = ['الكود', 'الاسم', 'العنوان', 'الهاتف', 'الرصيد الحالي', 'الرصيد المبدئي'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final addr = row['addresses'];
      String addrStr = '';
      if (addr is List && addr.isNotEmpty) {
        addrStr = addr[0]['address_line_1']?.toString() ?? '';
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(addrStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['phone']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['balance']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['initial_balance']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── الموردين ──
  Future<void> _writeSuppliers(Excel excel) async {
    final data = await _fetchAll('suppliers');
    final sheet = excel['الموردين'];
    final h = ['الكود', 'الاسم', 'العنوان', 'الهاتف', 'الرصيد الحالي', 'الرصيد المبدئي'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['supplier_code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['address']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['phone']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['outstanding_balance']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['initial_balance']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── وكلاء التخليص ──
  Future<void> _writeClearingAgents(Excel excel) async {
    final data = await _fetchAll('clearing_agents');
    final sheet = excel['وكلاء التخليص'];
    final h = ['الكود', 'الاسم', 'النوع', 'الهاتف', 'الرصيد', 'الرصيد المبدئي'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['broker_type']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['phone']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['balance']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['initial_balance']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── شركات الشحن ──
  Future<void> _writeShippingCompanies(Excel excel) async {
    final data = await _fetchAll('shipping_companies');
    final sheet = excel['شركات الشحن'];
    final h = ['الكود', 'الاسم', 'الهاتف', 'البريد الإلكتروني', 'الرصيد', 'الرصيد المبدئي'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['phone']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['email']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['balance']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['initial_balance']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── فواتير الشراء (with supplier name + code) ──
  Future<void> _writePurchaseInvoices(Excel excel) async {
    final data = await _fetchAll('purchase_invoices');
    final sheet = excel['فواتير الشراء'];
    final h = ['رقم الفاتورة', 'التاريخ', 'المورد', 'كود المورد', 'الإجمالي', 'المدفوع', 'الخصم', 'الحالة', 'ملاحظات'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final sid = row['supplier_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['invoice_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['invoice_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_supplierNames[sid] ?? sid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(_supplierCodes[sid] ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['total_amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['paid_amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['discount_amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── بنود فواتير الشراء (with material name + code + invoice number + date) ──
  Future<void> _writePurchaseItems(Excel excel) async {
    final data = await _fetchAll('purchase_invoice_items');
    final sheet = excel['بنود فواتير الشراء'];
    final h = ['رقم الفاتورة', 'تاريخ الفاتورة', 'المنتج', 'كود المنتج', 'الكمية', 'سعر الوحدة', 'الإجمالي', 'المحطة'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final pid = row['purchase_invoice_id']?.toString() ?? '';
      final mid = row['raw_material_id']?.toString() ?? '';
      final stid = row['station_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_purchaseInvoiceNumbers[pid] ?? pid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_purchaseInvoiceDates[pid] ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_rawMaterialNames[mid] ?? mid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(_rawMaterialCodes[mid] ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['unit_price']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['total_price']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(_stationNames[stid] ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── المحاصيل (with supplier name) ──
  Future<void> _writeLots(Excel excel) async {
    final data = await _fetchAll('lot_receipts');
    final sheet = excel['المحاصيل'];
    final h = ['رقم اللوت', 'المورد', 'نوع الفاكهة', 'تاريخ الاستلام', 'الوزن الإجمالي (كجم)', 'الوزن الصافي (كجم)', 'النفايات (كجم)', 'نسبة النفايات', 'الحالة'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final sid = row['supplier_id']?.toString() ?? '';
      final fid = row['fruit_type_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['lot_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_supplierNames[sid] ?? sid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_fruitTypeNames[fid] ?? fid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['receipt_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['gross_weight_kg']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['net_weight_kg']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['waste_weight_kg']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = _toCellValue(row['waste_percentage']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── أوامر التعبئة ──
  Future<void> _writePackingOrders(Excel excel) async {
    final data = await _fetchAll('packing_orders');
    final sheet = excel['أوامر التعبئة'];
    final h = ['رقم الطلب', 'المنتج', 'المستوى', 'عدد الكراتين', 'الصافي/كرتونة', 'الصافي (كجم)', 'الإجمالي (كجم)', 'الحالة', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['order_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['product_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['grade']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['carton_count']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['net_weight_per_carton']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['total_net_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['total_gross_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── النقل الداخلي (with station names) ──
  Future<void> _writeTransfers(Excel excel) async {
    final data = await _fetchAll('stock_transfers');
    final sheet = excel['النقل الداخلي'];
    final h = ['من', 'إلى', 'المنتج', 'الكود', 'الكمية', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final fromId = row['from_station_id']?.toString() ?? '';
      final toId = row['to_station_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_stationNames[fromId] ?? fromId);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_stationNames[toId] ?? toId);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['product_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['product_code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── حركات المخزون ──
  Future<void> _writeStockMovements(Excel excel) async {
    final data = await _fetchAll('stock_movements');
    final sheet = excel['حركات المخزون'];
    final h = ['نوع الحركة', 'المنتج', 'الكمية', 'سعر الوحدة', 'الإجمالي', 'البيان', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['movement_type']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['product_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['unit_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['total_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['description']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── فواتير البيع (with customer name) ──
  Future<void> _writeInvoices(Excel excel) async {
    final data = await _fetchAll('invoices');
    final sheet = excel['فواتير البيع'];
    final h = ['رقم الفاتورة', 'التاريخ', 'العميل', 'الإجمالي', 'المدفوع', 'المتبقي', 'الحالة', 'ملاحظات'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final cid = row['customer_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['invoice_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['invoice_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_customerNames[cid] ?? cid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['total_amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['paid_amount']);
      final total = _toDouble(row['total_amount']);
      final paid = _toDouble(row['paid_amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = DoubleCellValue(total - paid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── فواتير التصدير (with customer name) ──
  Future<void> _writeExportInvoices(Excel excel) async {
    final data = await _fetchAll('export_invoices');
    final sheet = excel['فواتير التصدير'];
    final h = ['رقم الفاتورة', 'التاريخ', 'العميل', 'طريقة النقل', 'عدد الكراتين', 'عدد الباليتات', 'الصافي (كجم)', 'الإجمالي (كجم)', 'العملة', 'سعر الكرتونة', 'الإجمالي (ج.م)', 'صافي الربح (ج.م)'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final cid = row['customer_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['invoice_no']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_customerNames[cid] ?? cid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['transport_mode']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['total_cartons']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['total_pallets']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['total_net_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = _toCellValue(row['total_gross_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(row['currency_code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r + 1)).value = _toCellValue(row['export_price_per_carton']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r + 1)).value = _toCellValue(row['total_amount_egp']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r + 1)).value = _toCellValue(row['net_profit_egp']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── شحنات التصدير (with customer name) ──
  Future<void> _writeExportShipments(Excel excel) async {
    final data = await _fetchAll('export_shipments');
    final sheet = excel['شحنات التصدير'];
    final h = ['رقم الشحنة', 'العميل', 'الوجهة', 'رقم الحاوية', 'رقم BL', 'السفينة', 'طريقة النقل', 'عدد الكراتين', 'الصافي (كجم)', 'الإجمالي (كجم)', 'الشحن', 'التكلفة الإجمالية', 'الإيراد (ج.م)', 'صافي الربح (ج.م)', 'الحالة', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final cid = row['customer_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['shipment_no']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_customerNames[cid] ?? cid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['destination_country']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['container_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(row['bl_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['vessel_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['transport_mode']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = _toCellValue(row['carton_count']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = _toCellValue(row['net_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r + 1)).value = _toCellValue(row['gross_weight']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: r + 1)).value = _toCellValue(row['freight_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: r + 1)).value = _toCellValue(row['total_landed_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: r + 1)).value = _toCellValue(row['total_revenue_egp']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: r + 1)).value = _toCellValue(row['net_profit_egp']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: r + 1)).value = TextCellValue(row['shipment_date']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── بنود تكلفة الشحن (with shipment number) ──
  Future<void> _writeShipmentCostItems(Excel excel) async {
    final data = await _fetchAll('shipment_cost_items');
    final sheet = excel['بنود تكلفة الشحن'];
    final h = ['رقم الشحنة', 'البند', 'الوصف', 'الكمية', 'سعر الوحدة', 'الإجمالي', 'المورد'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final sid = row['shipment_id']?.toString() ?? '';
      final vid = row['vendor_id']?.toString() ?? '';
      final vtype = row['vendor_type']?.toString() ?? '';
      String vendorName = '';
      if (vtype == 'clearing_agent') {
        vendorName = _clearingAgentNames[vid] ?? vid;
      } else if (vtype == 'shipping_company') {
        vendorName = _shippingCompanyNames[vid] ?? vid;
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_shipmentNumbers[sid] ?? sid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['category']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['description']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['unit_price']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['total_price']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(vendorName);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── أرصدة الخزائن (with treasury name) ──
  Future<void> _writeTreasuryBalances(Excel excel) async {
    final data = await _fetchAll('treasury_balances');
    final sheet = excel['أرصدة الخزائن'];
    final h = ['الخزينة', 'العملة', 'الرصيد'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final tid = row['treasury_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_treasuryNames[tid] ?? tid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['currency']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = _toCellValue(row['balance']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── حركات الخزينة (with treasury name) ──
  Future<void> _writeTreasuryTransactions(Excel excel) async {
    final data = await _fetchAll('treasury_transactions');
    final sheet = excel['حركات الخزينة'];
    final h = ['الخزينة', 'نوع الحركة', 'العملة', 'المبلغ', 'الرصيد قبل', 'الرصيد بعد', 'البيان', 'الملاحظات', 'منشئ', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final tid = row['treasury_id']?.toString() ?? '';
      final uid = row['created_by']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_treasuryNames[tid] ?? tid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['transaction_type']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['currency']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['balance_before']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['balance_after']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['description']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(_userName[uid] ?? uid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── حركات البنك (with account name) ──
  Future<void> _writeBankTransactions(Excel excel) async {
    final data = await _fetchAll('bank_account_transactions');
    final sheet = excel['حركات البنك'];
    final h = ['الحساب', 'نوع الحركة', 'المبلغ', 'الرصيد قبل', 'الرصيد بعد', 'البيان', 'الملاحظات', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final bid = row['bank_account_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_bankAccountNames[bid] ?? bid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['transaction_type']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['balance_before']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['balance_after']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['description']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── الشيكات (with counterparty name) ──
  Future<void> _writeCheques(Excel excel) async {
    final data = await _fetchAll('cheques');
    final sheet = excel['الشيكات'];
    final h = ['رقم الشيك', 'النوع', 'المستلم / المُرسِل', 'المبلغ', 'العملة', 'تاريخ الاستحقاق', 'الحالة', 'ملاحظات', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final counterpartyId = row['counterparty_id']?.toString() ?? '';
      final counterpartyType = row['counterparty_type']?.toString() ?? '';
      String counterpartyName = row['counterparty_name']?.toString() ?? '';
      if (counterpartyName.isEmpty) {
        if (counterpartyType == 'supplier') {
          counterpartyName = _supplierNames[counterpartyId] ?? counterpartyId;
        } else if (counterpartyType == 'customer') {
          counterpartyName = _customerNames[counterpartyId] ?? counterpartyId;
        }
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['cheque_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['type']?.toString() == 'sent' ? 'صرف' : 'قبض');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(counterpartyName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(row['currency']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['due_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['status']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── سندات القبض (with customer name) ──
  Future<void> _writeCashReceipts(Excel excel) async {
    final data = await _fetchAll('cash_receipts');
    final sheet = excel['سندات القبض'];
    final h = ['رقم السند', 'التاريخ', 'العميل', 'المبلغ', 'ملاحظات', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final cid = row['customer_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['receipt_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['receipt_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_customerNames[cid] ?? cid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── سندات الصرف (with supplier name) ──
  Future<void> _writeCashPayments(Excel excel) async {
    final data = await _fetchAll('cash_payments');
    final sheet = excel['سندات الصرف'];
    final h = ['رقم السند', 'التاريخ', 'المورد', 'المبلغ', 'ملاحظات', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final sid = row['supplier_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['payment_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['payment_date']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_supplierNames[sid] ?? sid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(row['notes']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── القيود اليومية (16-column layout matching Journal Entry page exactly) ──
  Future<void> _writeLedgerEntries(Excel excel) async {
    final entries = await JournalEntryExcelService.fetchAllEntries();
    final rows = JournalEntryExcelService.generateJournalRows(entries);
    final sheet = excel['القيود اليومية'];
    if (rows.isEmpty) return;

    final headers = rows.first.map((e) => e.toString()).toList();
    _writeHeader(sheet, headers);

    for (var r = 1; r < rows.length; r++) {
      final rowData = rows[r];
      for (var c = 0; c < rowData.length; c++) {
        final val = rowData[c];
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        if (val is num) {
          cell.value = DoubleCellValue(val.toDouble());
        } else if (val is bool) {
          cell.value = TextCellValue(val ? 'نعم' : 'لا');
        } else {
          cell.value = TextCellValue(val?.toString() ?? '');
        }
      }
    }
    _autoWidth(sheet, headers.length, rows.length);
  }

  // ── المشتريات المحصولية (with supplier + fruit type names) ──
  Future<void> _writeCropPurchases(Excel excel) async {
    final data = await _fetchAll('crop_purchases');
    final sheet = excel['المشتريات المحصولية'];
    final h = ['رقم الإيصال', 'المورد', 'نوع الفاكهة', 'الكمية', 'سعر الكجم', 'التكلفة الإجمالية', 'التكلفة الصافية', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final sid = row['supplier_id']?.toString() ?? '';
      final fid = row['fruit_type_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row['receipt_number']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(_supplierNames[sid] ?? sid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_fruitTypeNames[fid] ?? fid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['purchase_price_per_kg']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['total_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = _toCellValue(row['net_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['purchase_date']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── المنتجات في المحطة (with station name) ──
  Future<void> _writeStationProducts(Excel excel) async {
    final data = await _fetchAll('station_products');
    final sheet = excel['المنتجات في المحطة'];
    final h = ['المحطة', 'المنتج', 'الكود', 'الكمية'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final stid = row['station_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_stationNames[stid] ?? stid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['product_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['product_code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── دفعات المحطة (with station name) ──
  Future<void> _writeStationBatches(Excel excel) async {
    final data = await _fetchAll('station_product_batches');
    final sheet = excel['دفعات المحطة'];
    final h = ['المحطة', 'المنتج', 'الكود', 'الكمية', 'المتبقي', 'سعر الوحدة', 'المورد', 'التاريخ'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final stid = row['station_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_stationNames[stid] ?? stid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['product_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['product_code']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = _toCellValue(row['quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['remaining_quantity']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = _toCellValue(row['unit_cost']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row['supplier_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r + 1)).value = TextCellValue(row['created_at']?.toString() ?? '');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── مستخدمين النظام ──
  Future<void> _writeUserRoles(Excel excel) async {
    final data = await _fetchAll('user_roles');
    final sheet = excel['مستخدمين النظام'];
    final h = ['المستخدم', 'الصفحات المسموحة', 'الحالة'];
    _writeHeader(sheet, h);
    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final uid = row['user_id']?.toString() ?? '';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(_userName[uid] ?? uid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['allowed_pages']?.toString() ?? '');
      final isActive = row['is_active'];
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(isActive == true ? 'نشط' : 'غير نشط');
    }
    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ── توزيع الأرباح ──
  Future<void> _writeProfitDistribution(Excel excel) async {
    final shipments = await _fetchAll('export_shipments');
    final snapshots = await _fetchAll('shipment_profitability_snapshots');

    // Build profitability lookup by shipment_id
    final Map<String, Map<String, dynamic>> profitByShipment = {};
    for (final snap in snapshots) {
      final sid = snap['shipment_id']?.toString() ?? '';
      profitByShipment[sid] = snap;
    }

    // Load settings (person names + percentages)
    String person1 = 'الشخص 1', person2 = 'الشخص 2', person3 = 'الشخص 3';
    Map<String, List<double>> percentages = {};
    try {
      final settings = await _client.from('profit_distribution_settings').select().limit(1);
      if (settings.isNotEmpty) {
        final s = settings[0];
        person1 = s['person1_name']?.toString() ?? person1;
        person2 = s['person2_name']?.toString() ?? person2;
        person3 = s['person3_name']?.toString() ?? person3;
        final pctRaw = s['percentages'];
        if (pctRaw != null) {
          try {
            final map = _parseJsonMap(pctRaw);
            for (final entry in map.entries) {
              percentages[entry.key] = (entry.value as List).map((e) => (e as num).toDouble()).toList();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    final sheet = excel['توزيع الأرباح'];
    final h = ['رقم الشحنة', 'التاريخ', 'صافي الربح', '$person1 %', '$person1 (ج.م)', '$person2 %', '$person2 (ج.م)', '$person3 %', '$person3 (ج.م)'];
    _writeHeader(sheet, h);

    var r = 1;
    double totalProfit = 0;
    double totalP1 = 0, totalP2 = 0, totalP3 = 0;

    for (final ship in shipments) {
      final sid = ship['id']?.toString() ?? '';
      final shipNo = ship['shipment_no']?.toString() ?? '';
      final shipDate = ship['shipment_date']?.toString() ?? '';
      final snap = profitByShipment[sid];
      final netProfit = _toDouble(snap?['net_profit'] ?? 0);
      final p = percentages[sid] ?? [0.0, 0.0, 0.0];

      final p1Share = netProfit * p[0] / 100.0;
      final p2Share = netProfit * p[1] / 100.0;
      final p3Share = netProfit * p[2] / 100.0;

      totalProfit += netProfit;
      totalP1 += p1Share;
      totalP2 += p2Share;
      totalP3 += p3Share;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(shipNo);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(shipDate);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = DoubleCellValue(netProfit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = DoubleCellValue(p[0]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = DoubleCellValue(p1Share);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(p[1]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = DoubleCellValue(p2Share);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: r)).value = DoubleCellValue(p[2]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = DoubleCellValue(p3Share);
      r++;
    }

    // Total row
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue('الإجمالي');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = DoubleCellValue(totalProfit);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = DoubleCellValue(totalP1);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = DoubleCellValue(totalP2);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: r)).value = DoubleCellValue(totalP3);

    _autoWidth(sheet, h.length, r + 1);
  }

  Map<String, dynamic> _parseJsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {};
  }

  Future<void> _writeStatementSheet(Excel excel, String sheetName, String label, List<Map<String, dynamic>> entities, String idField) async {
    if (entities.isEmpty) return;

    final sheet = excel[sheetName];
    final h = [label, 'رقم الفاتورة', 'التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'];
    _writeHeader(sheet, h);

    // Batch-load all invoices/purchases and transactions ONCE
    List<Map<String, dynamic>> allInvoices = [];
    List<Map<String, dynamic>> allPurchases = [];
    List<Map<String, dynamic>> allTransactions = [];

    try {
      if (idField == 'customer_id') {
        allInvoices = await _fetchAll('invoices');
        allTransactions = await _fetchAll('transactions');
      } else if (idField == 'supplier_id') {
        allPurchases = await _fetchAll('purchase_invoices');
        allTransactions = await _fetchAll('transactions');
      }
    } catch (_) {}

    var r = 1;
    for (final entity in entities) {
      final entityId = entity['id']?.toString() ?? '';
      final entityName = entity['name']?.toString() ?? '';
      final initialBalance = _toDouble(entity['initial_balance'] ?? 0);

      // Filter in-memory instead of querying per entity
      List<Map<String, dynamic>> invoices = [];
      List<Map<String, dynamic>> purchases = [];
      List<Map<String, dynamic>> transactions = [];

      if (idField == 'customer_id') {
        invoices = allInvoices.where((inv) => inv['customer_id']?.toString() == entityId).toList();
        transactions = allTransactions.where((tx) => tx['customer_id']?.toString() == entityId).toList();
      } else if (idField == 'supplier_id') {
        purchases = allPurchases.where((pur) => pur['supplier_id']?.toString() == entityId).toList();
        transactions = allTransactions.where((tx) => tx['supplier_id']?.toString() == entityId && tx['purchase_id'] == null).toList();
      }

      final rows = <Map<String, dynamic>>[];

      // Opening balance
      rows.add({
        'number': '—', 'date': '', 'description': 'رصيد سابق',
        'debit': initialBalance < 0 ? initialBalance.abs() : 0.0,
        'credit': initialBalance > 0 ? initialBalance : 0.0,
      });

      // Invoices
      for (final inv in invoices) {
        rows.add({
          'number': inv['invoice_number']?.toString() ?? '',
          'date': inv['invoice_date']?.toString() ?? '',
          'description': 'فاتورة بيع',
          'debit': _toDouble(inv['total_amount'] ?? 0) - _toDouble(inv['paid_amount'] ?? 0),
          'credit': 0.0,
        });
      }

      // Purchases
      for (final pur in purchases) {
        rows.add({
          'number': pur['invoice_number']?.toString() ?? '',
          'date': pur['invoice_date']?.toString() ?? '',
          'description': 'فاتورة شراء',
          'debit': _toDouble(pur['total_amount'] ?? 0) - _toDouble(pur['paid_amount'] ?? 0),
          'credit': 0.0,
        });
      }

      // Transactions
      for (final tx in transactions) {
        final isDebit = tx['debit'] != null && _toDouble(tx['debit']) > 0;
        rows.add({
          'number': tx['transaction_number']?.toString() ?? '',
          'date': tx['transaction_date']?.toString() ?? '',
          'description': tx['description']?.toString() ?? '',
          'debit': isDebit ? _toDouble(tx['debit']) : 0.0,
          'credit': !isDebit ? _toDouble(tx['credit']) : 0.0,
        });
      }

      rows.sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));

      var balance = initialBalance;
      for (final row in rows) {
        balance += (row['debit'] as double) - (row['credit'] as double);
        row['balance'] = balance;
      }

      for (final row in rows) {
        if (r > _maxRows) break;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(entityName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(row['number'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(row['date'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(row['description'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = DoubleCellValue(row['debit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(row['credit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = DoubleCellValue(row['balance'] as double);
        r++;
      }
    }

    _autoWidth(sheet, h.length, r);
  }

  Future<void> _writeCustomerStatements(Excel excel) async {
    final customers = await _fetchAll('customers');
    await _writeStatementSheet(excel, 'كشف حساب العملاء', 'العميل', customers, 'customer_id');
  }

  Future<void> _writeSupplierStatements(Excel excel) async {
    final suppliers = await _fetchAll('suppliers');
    await _writeStatementSheet(excel, 'كشف حساب الموردين', 'المورد', suppliers, 'supplier_id');
  }

  Future<void> _writeClearingAgentStatements(Excel excel) async {
    final agents = await _fetchAll('clearing_agents');
    if (agents.isEmpty) return;

    final sheet = excel['كشف حساب المخلصين'];
    final h = ['المخلص', 'رقم البند', 'التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'];
    _writeHeader(sheet, h);

    // Batch-load once
    final allCostItems = await _fetchAll('shipment_cost_items');
    final allTransactions = await _fetchAll('transactions');

    var r = 1;
    for (final agent in agents) {
      if (r > _maxRows) break;
      final agentId = agent['id']?.toString() ?? '';
      final agentName = agent['name']?.toString() ?? '';
      final initialBalance = _toDouble(agent['initial_balance'] ?? 0);

      final costItems = allCostItems.where((ci) => ci['vendor_id']?.toString() == agentId).toList();
      final txs = allTransactions.where((tx) => tx['supplier_id']?.toString() == agentId).toList();

      final rows = <Map<String, dynamic>>[];
      rows.add({'number': '—', 'date': '', 'description': 'رصيد سابق', 'debit': initialBalance < 0 ? initialBalance.abs() : 0.0, 'credit': initialBalance > 0 ? initialBalance : 0.0});

      for (final item in costItems) {
        rows.add({
          'number': 'شحنة #${item['shipment_id']}',
          'date': item['created_at']?.toString() ?? '',
          'description': item['description']?.toString() ?? item['category']?.toString() ?? '',
          'debit': _toDouble(item['total_price'] ?? 0),
          'credit': 0.0,
        });
      }

      for (final tx in txs) {
        final isDebit = tx['debit'] != null && _toDouble(tx['debit']) > 0;
        rows.add({
          'number': tx['transaction_number']?.toString() ?? '',
          'date': tx['transaction_date']?.toString() ?? '',
          'description': tx['description']?.toString() ?? '',
          'debit': isDebit ? _toDouble(tx['debit']) : 0.0,
          'credit': !isDebit ? _toDouble(tx['credit']) : 0.0,
        });
      }

      rows.sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
      var balance = initialBalance;
      for (final row in rows) {
        balance += (row['debit'] as double) - (row['credit'] as double);
        row['balance'] = balance;
      }

      for (final row in rows) {
        if (r > _maxRows) break;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(agentName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(row['number'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(row['date'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(row['description'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = DoubleCellValue(row['debit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(row['credit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = DoubleCellValue(row['balance'] as double);
        r++;
      }
    }

    _autoWidth(sheet, h.length, r);
  }

  Future<void> _writeShippingCompanyStatements(Excel excel) async {
    final companies = await _fetchAll('shipping_companies');
    if (companies.isEmpty) return;

    final sheet = excel['كشف حساب شركات الشحن'];
    final h = ['شركة الشحن', 'رقم البند', 'التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'];
    _writeHeader(sheet, h);

    // Batch-load once
    final allCostItems = await _fetchAll('shipment_cost_items');
    final allTransactions = await _fetchAll('transactions');

    var r = 1;
    for (final company in companies) {
      if (r > _maxRows) break;
      final companyId = company['id']?.toString() ?? '';
      final companyName = company['name']?.toString() ?? '';
      final initialBalance = _toDouble(company['initial_balance'] ?? 0);

      final costItems = allCostItems.where((ci) => ci['vendor_id']?.toString() == companyId).toList();
      final txs = allTransactions.where((tx) => tx['supplier_id']?.toString() == companyId || tx['customer_id']?.toString() == companyId).toList();

      final rows = <Map<String, dynamic>>[];
      rows.add({'number': '—', 'date': '', 'description': 'رصيد سابق', 'debit': initialBalance < 0 ? initialBalance.abs() : 0.0, 'credit': initialBalance > 0 ? initialBalance : 0.0});

      for (final item in costItems) {
        rows.add({
          'number': 'شحنة #${item['shipment_id']}',
          'date': item['created_at']?.toString() ?? '',
          'description': item['description']?.toString() ?? item['category']?.toString() ?? '',
          'debit': _toDouble(item['total_price'] ?? 0),
          'credit': 0.0,
        });
      }

      for (final tx in txs) {
        final isDebit = tx['debit'] != null && _toDouble(tx['debit']) > 0;
        rows.add({
          'number': tx['transaction_number']?.toString() ?? '',
          'date': tx['transaction_date']?.toString() ?? '',
          'description': tx['description']?.toString() ?? '',
          'debit': isDebit ? _toDouble(tx['debit']) : 0.0,
          'credit': !isDebit ? _toDouble(tx['credit']) : 0.0,
        });
      }

      rows.sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
      var balance = initialBalance;
      for (final row in rows) {
        balance += (row['debit'] as double) - (row['credit'] as double);
        row['balance'] = balance;
      }

      for (final row in rows) {
        if (r > _maxRows) break;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(companyName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(row['number'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(row['date'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value = TextCellValue(row['description'].toString());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value = DoubleCellValue(row['debit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r)).value = DoubleCellValue(row['credit'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value = DoubleCellValue(row['balance'] as double);
        r++;
      }
    }

    _autoWidth(sheet, h.length, r);
  }

  // ═══════════════════════════════════════════════════
  // تقارير التكاليف
  // ═══════════════════════════════════════════════════

  Future<void> _writeCostReport(Excel excel) async {
    List<Map<String, dynamic>> data = [];
    try {
      final result = await _client.from('vw_cost_details_live').select();
      data = (result as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      // View might not exist, try alternative
      return;
    }

    final sheet = excel['تقارير التكاليف'];
    final h = ['التاريخ', 'رقم الشحنة', 'العميل', 'بند التكلفة', 'المبلغ', 'البيان'];
    _writeHeader(sheet, h);

    // Sort by date descending
    data.sort((a, b) {
      final da = a['shipment_date']?.toString() ?? '';
      final db = b['shipment_date']?.toString() ?? '';
      return db.compareTo(da);
    });

    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final date = (row['shipment_date']?.toString() ?? '').substring(0, (row['shipment_date']?.toString() ?? '').length >= 10 ? 10 : (row['shipment_date']?.toString() ?? '').length);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(date);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row['shipment_no']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(row['customer_name']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(row['item_name']?.toString() ?? row['category']?.toString() ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = _toCellValue(row['amount']);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row['description']?.toString() ?? '');
    }

    _autoWidth(sheet, h.length, data.length + 1);
  }

  // ═══════════════════════════════════════════════════
  // متابعة المخازن
  // ═══════════════════════════════════════════════════

  Future<void> _writeWarehouseTracking(Excel excel) async {
    final stations = await _fetchAll('stations');
    if (stations.isEmpty) return;

    final sheet = excel['متابعة المخازن'];
    final h = ['اسم المحطة', 'الكود', 'النوع', 'الحالة', 'مشتريات', 'محاصيل', 'تعبئة', 'تحويلات', 'مواد تعبئة', 'إجمالي الحركات', 'عدد الأصناف', 'الوزن (كجم)'];
    _writeHeader(sheet, h);

    // Pre-fetch all data for counts
    final batches = await _fetchAll('station_product_batches');
    final lots = await _fetchAll('lot_receipts');
    final packingOrders = await _fetchAll('packing_orders');
    final transfers = await _fetchAll('stock_transfers');
    final movements = await _fetchAll('stock_movements');
    final stationProducts = await _fetchAll('station_products');

    for (var i = 0; i < stations.length; i++) {
      final station = stations[i];
      final stId = station['id']?.toString() ?? '';
      final stName = station['name']?.toString() ?? '';
      final stCode = station['code']?.toString() ?? '';
      final stType = station['type']?.toString() ?? '';
      final isActive = station['is_active'] == true;

      // Count purchases (distinct purchase_invoice_id from batches)
      final stationBatches = batches.where((b) => b['station_id']?.toString() == stId && b['source_type']?.toString() == 'purchase');
      final purchaseIds = stationBatches.map((b) => b['purchase_invoice_id']).toSet();

      // Count lots
      final lotCount = lots.where((l) => l['station_id']?.toString() == stId).length;

      // Count packing orders
      final packingCount = packingOrders.where((p) => p['station_id']?.toString() == stId).length;

      // Count transfers (from or to this station)
      final transferCount = transfers.where((t) => t['from_station_id']?.toString() == stId || t['to_station_id']?.toString() == stId).length;

      // Count material movements (stock_movements where description mentions station)
      final materialCount = movements.where((m) => m['description']?.toString().contains(stName) == true && (m['movement_type']?.toString() == 'transfer' || m['movement_type']?.toString() == 'return')).length;

      final totalMovements = purchaseIds.length + lotCount + packingCount + transferCount + materialCount;

      // Station products
      final products = stationProducts.where((p) => p['station_id']?.toString() == stId && _toDouble(p['quantity']) > 0);
      final productCount = products.length;
      final totalWeight = products.fold(0.0, (sum, p) => sum + _toDouble(p['quantity']));

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(stName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(stCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue(stType);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = TextCellValue(isActive ? 'نشط' : 'غير نشط');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1)).value = DoubleCellValue(purchaseIds.length.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1)).value = DoubleCellValue(lotCount.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1)).value = DoubleCellValue(packingCount.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: i + 1)).value = DoubleCellValue(transferCount.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: i + 1)).value = DoubleCellValue(materialCount.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: i + 1)).value = DoubleCellValue(totalMovements.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: i + 1)).value = DoubleCellValue(productCount.toDouble());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: i + 1)).value = DoubleCellValue(totalWeight);
    }

    _autoWidth(sheet, h.length, stations.length + 1);
  }

  // ═══════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════

  static const int _maxRows = 50000;
  static const int _pageSize = 1000;

  Future<List<Map<String, dynamic>>> _fetchAll(String table) async {
    final allRows = <Map<String, dynamic>>[];
    var offset = 0;
    while (allRows.length < _maxRows) {
      try {
        final data = await _client
            .from(table)
            .select()
            .range(offset, offset + _pageSize - 1);
        final rows = (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
        allRows.addAll(rows);
        if (rows.length < _pageSize) break;
        offset += _pageSize;
      } catch (_) {
        break;
      }
    }
    return allRows;
  }

  Future<List<Map<String, dynamic>>> _fetchAllFiltered(String table, String column, String value) async {
    final allRows = <Map<String, dynamic>>[];
    var offset = 0;
    while (allRows.length < _maxRows) {
      try {
        final data = await _client
            .from(table)
            .select()
            .eq(column, value)
            .range(offset, offset + _pageSize - 1);
        final rows = (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
        allRows.addAll(rows);
        if (rows.length < _pageSize) break;
        offset += _pageSize;
      } catch (_) {
        break;
      }
    }
    return allRows;
  }

  void _autoWidth(Sheet sheet, int colCount, int rowCount) {
    for (var c = 0; c < colCount; c++) {
      var maxLen = 10.0;
      for (var r = 0; r < rowCount && r < 200; r++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final val = cell.value;
        if (val != null) {
          final len = val.toString().length;
          if (len > maxLen) maxLen = len.toDouble();
        }
      }
      sheet.setColumnWidth(c, (maxLen + 4).toDouble());
    }
  }

  CellValue? _toCellValue(dynamic val) {
    if (val == null) return null;
    if (val is num) return DoubleCellValue(val.toDouble());
    if (val is bool) return TextCellValue(val ? 'نعم' : 'لا');
    return TextCellValue(val.toString());
  }

  double _toDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0;
    return 0;
  }
}

