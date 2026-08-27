import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/dao/shareholder_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/account_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_model.dart';
import '../../data/dao/bank_account_dao.dart';
import '../../data/services/inventory_export_service.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/dao/cheque_dao.dart';
import '../../data/dao/purchase_dao.dart';
import '../purchases/purchase_pdf_service.dart';
import '../../data/dao/station_dao.dart';
import '../stations/station_stock_report_service.dart';
import '../../data/dao/transfer_dao.dart';
import '../transfers/transfer_export_service.dart';
import '../../data/dao/warehouse_tracking_dao.dart';
import '../../data/models/warehouse_movement_model.dart';
import '../../data/dao/lot_dao.dart';
import '../lots/lot_export_service.dart';
import '../packing/utils/packing_excel_exporter.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/dao/packing_order_sorting_dao.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/dao/report_dao.dart';
import '../../accounting/reporting/services/report_calculation_service.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/treasury_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/account_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/consolidated_statement_pdf_service.dart';
import '../../core/statement_excel_service.dart';
import '../../core/statement_pdf_service.dart';
import '../../core/utils/file_helper.dart';
import '../shipping_companies/shipping_company_pdf_service.dart';
import '../exports/export_customer_statement_cubit.dart';
import '../exports/export_customer_statement_state.dart';
import '../exports/invoice_pdf_service.dart';
import '../exports/shipment_cost_pdf_service.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/models/shipment_cost_item_model.dart';
import '../proforma/proforma_invoice_dao.dart';
import '../proforma/proforma_invoice_pdf_service.dart';
import '../../data/dao/profit_distribution_dao.dart';
import '../../data/dao/cost_report_dao.dart';
import '../exports/export_customer_statement_pdf_service.dart';
import '../exports/export_customer_statement_excel_service.dart';
import '../suppliers/supplier_account_statement_cubit.dart';
import '../suppliers/supplier_account_statement_state.dart';
import '../clearing_agents/clearing_agent_statement_cubit.dart';
import '../clearing_agents/clearing_agent_statement_state.dart';
import '../shipping_companies/shipping_company_statement_cubit.dart';
import '../shipping_companies/shipping_company_statement_state.dart';
import '../shareholders/shareholder_statement_cubit.dart';
import '../journal_entry/journal_entry_excel_service.dart';

typedef BackupProgressCallback = void Function(
    String category, String taskName, int current, int total);

class CategorizedBackupService {
  Future<void> startBackup({required BackupProgressCallback onProgress}) async {
    try {
      final docDir = await FileHelper.getExportDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final rootDir = Directory('${docDir.path}/ERPP_Backup_$timestamp');
      await rootDir.create(recursive: true);

      await _exportDataSection(rootDir.path, onProgress);

      await _exportStatementsSection(rootDir.path, onProgress);

      await _exportTreasurySection(rootDir.path, onProgress);

      await _exportBankAccountsSection(rootDir.path, onProgress);

      await _exportChequesSection(rootDir.path, onProgress);

      await _exportTrialBalanceSection(rootDir.path, onProgress);

      await _exportJournalEntriesSection(rootDir.path, onProgress);

      await _exportGeneralLedgerSection(rootDir.path, onProgress);

      await _exportBalanceSheetSection(rootDir.path, onProgress);

      await _exportIncomeStatementSection(rootDir.path, onProgress);

      await _exportCashFlowSection(rootDir.path, onProgress);

      await _exportWarehouseSection(rootDir.path, onProgress);

      await _exportInvoicesAndProfitsSection(rootDir.path, onProgress);

      onProgress('اكتمل', 'اكتمل النسخ الاحتياطي بنجاح!', 1, 1);
    } catch (e) {
      throw Exception('فشل النسخ الاحتياطي: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // البيانات - العملاء، الموردون، المخلصين، شركات الشحن، المساهمين
  // ═══════════════════════════════════════════════════
  Future<void> _exportDataSection(String rootDir, BackupProgressCallback onProgress) async {
    final dir = Directory(p.join(rootDir, 'البيانات'));
    await dir.create(recursive: true);
    int step = 0, total = 5;

    onProgress('البيانات', 'جاري تصدير العملاء...', ++step, total);
    await _exportCustomers(dir.path);

    onProgress('البيانات', 'جاري تصدير الموردين...', ++step, total);
    await _exportSuppliers(dir.path);

    onProgress('البيانات', 'جاري تصدير المخلصين...', ++step, total);
    await _exportClearingAgents(dir.path);

    onProgress('البيانات', 'جاري تصدير شركات الشحن...', ++step, total);
    await _exportShippingCompanies(dir.path);

    onProgress('البيانات', 'جاري تصدير المساهمين...', ++step, total);
    await _exportShareholders(dir.path);
  }

  // ═══════════════════════════════════════════════════
  // العملاء
  // ═══════════════════════════════════════════════════
  Future<void> _exportCustomers(String dirPath) async {
    try {
      final dao = CustomerDao();
      final List<CustomerModel> all = [];
      int offset = 0;
      while (true) {
        final batch = await dao.getAll(limit: 500, offset: offset);
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      if (all.isEmpty) return;

      // PDF - ConsolidatedStatementPdfService (same as page button)
      try {
        final rows = all.map((c) => {
          'code': c.code,
          'name': c.name,
          'currency': c.currency,
          'balance': c.balance.toStringAsFixed(2),
        }).toList();
        final totalBalance = all.fold<double>(0, (s, c) => s + c.balance);
        final path = await ConsolidatedStatementPdfService.saveToFile(
          title: 'كشف حساب مجمع - العملاء',
          rows: rows,
          totalBalance: totalBalance,
        );
        if (path.isNotEmpty) {
          final src = File(path);
          if (await src.exists()) await src.copy(p.join(dirPath, 'العملاء.pdf'));
        }
      } catch (_) {}

      // Excel
      try {
        final bytes = _buildCustomersExcel(all);
        if (bytes != null) await File(p.join(dirPath, 'العملاء.xlsx')).writeAsBytes(bytes, flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  List<int>? _buildCustomersExcel(List<CustomerModel> list) {
    try {
      final excel = Excel.createExcel();
      final s = excel['العملاء'];
      s.appendRow([TextCellValue('الكود'), TextCellValue('الاسم'), TextCellValue('الهاتف'),
        TextCellValue('المدينة'), TextCellValue('الدولة'), TextCellValue('البريد الإلكتروني'),
        TextCellValue('الرقم الضريبي'), TextCellValue('رقم EORI'),
        TextCellValue('شخص الاتصال'), TextCellValue('هاتف الاتصال'), TextCellValue('بريد الاتصال'),
        TextCellValue('العملة'), TextCellValue('الرصيد'), TextCellValue('الرصيد المبدئي'),
        TextCellValue('الاتجاه'), TextCellValue('التاريخ')]);
      for (final c in list) {
        s.appendRow([
          TextCellValue(c.code), TextCellValue(c.name), TextCellValue(c.phone),
          TextCellValue(c.city), TextCellValue(c.country), TextCellValue(c.gmail),
          TextCellValue(c.vatNumber), TextCellValue(c.eoriNo),
          TextCellValue(c.contactPersonName), TextCellValue(c.contactPersonPhone), TextCellValue(c.contactPersonEmail),
          TextCellValue(c.currency), DoubleCellValue(c.balance), DoubleCellValue(c.initialBalance),
          TextCellValue(c.initialBalanceDirection), TextCellValue(c.createdAt),
        ]);
      }
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      return excel.encode();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════
  // الموردون
  // ═══════════════════════════════════════════════════
  Future<void> _exportSuppliers(String dirPath) async {
    try {
      final dao = SupplierDao();
      final List<SupplierModel> all = [];
      int offset = 0;
      while (true) {
        final batch = await dao.getAll(limit: 500, offset: offset);
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      if (all.isEmpty) return;

      // PDF - ConsolidatedStatementPdfService (same as page button)
      try {
        final rows = all.map((s) => {
          'code': s.supplierCode,
          'name': s.name,
          'currency': s.currency,
          'balance': s.outstandingBalance.toStringAsFixed(2),
        }).toList();
        final totalBalance = all.fold<double>(0, (s, sp) => s + sp.outstandingBalance);
        final path = await ConsolidatedStatementPdfService.saveToFile(
          title: 'كشف حساب مجمع - الموردون',
          rows: rows,
          totalBalance: totalBalance,
        );
        if (path.isNotEmpty) {
          final src = File(path);
          if (await src.exists()) await src.copy(p.join(dirPath, 'الموردون.pdf'));
        }
      } catch (_) {}

      // Excel
      try {
        final bytes = _buildSuppliersExcel(all);
        if (bytes != null) await File(p.join(dirPath, 'الموردون.xlsx')).writeAsBytes(bytes, flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  List<int>? _buildSuppliersExcel(List<SupplierModel> list) {
    try {
      final excel = Excel.createExcel();
      final s = excel['الموردون'];
      s.appendRow([TextCellValue('الكود'), TextCellValue('الاسم'), TextCellValue('الهاتف'),
        TextCellValue('العنوان'), TextCellValue('العملة'), TextCellValue('الرصيد الحالي'),
        TextCellValue('الرصيد المبدئي'), TextCellValue('الاتجاه'), TextCellValue('التاريخ')]);
      for (final s2 in list) {
        s.appendRow([
          TextCellValue(s2.supplierCode), TextCellValue(s2.name), TextCellValue(s2.phone),
          TextCellValue(s2.address), TextCellValue(s2.currency), DoubleCellValue(s2.outstandingBalance),
          DoubleCellValue(s2.initialBalance), TextCellValue(s2.initialBalanceDirection), TextCellValue(s2.createdAt),
        ]);
      }
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      return excel.encode();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════
  // المخلصين
  // ═══════════════════════════════════════════════════
  Future<void> _exportClearingAgents(String dirPath) async {
    try {
      final dao = ClearingAgentDao();
      final List<ClearingAgentModel> all = [];
      int offset = 0;
      while (true) {
        final batch = await dao.getAll(limit: 500, offset: offset);
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      if (all.isEmpty) return;

      // PDF - ConsolidatedStatementPdfService (same as page button)
      try {
        final rows = all.map((a) => {
          'code': a.code,
          'name': a.name,
          'currency': a.currency,
          'balance': a.balance.toStringAsFixed(2),
        }).toList();
        final totalBalance = all.fold<double>(0, (s, a) => s + a.balance);
        final path = await ConsolidatedStatementPdfService.saveToFile(
          title: 'كشف حساب مجمع - المخلصين',
          rows: rows,
          totalBalance: totalBalance,
        );
        if (path.isNotEmpty) {
          final src = File(path);
          if (await src.exists()) await src.copy(p.join(dirPath, 'المخلصين.pdf'));
        }
      } catch (_) {}

      // Excel
      try {
        final bytes = _buildClearingAgentsExcel(all);
        if (bytes != null) await File(p.join(dirPath, 'المخلصين.xlsx')).writeAsBytes(bytes, flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  List<int>? _buildClearingAgentsExcel(List<ClearingAgentModel> list) {
    try {
      final excel = Excel.createExcel();
      final s = excel['المخلصين'];
      s.appendRow([TextCellValue('الكود'), TextCellValue('الاسم'), TextCellValue('الهاتف'),
        TextCellValue('المدينة'), TextCellValue('الدولة'), TextCellValue('البريد الإلكتروني'),
        TextCellValue('النوع'), TextCellValue('شخص الاتصال'), TextCellValue('هاتف الاتصال'), TextCellValue('بريد الاتصال'),
        TextCellValue('العملة'), TextCellValue('الرصيد'), TextCellValue('الرصيد المبدئي'),
        TextCellValue('الاتجاه'), TextCellValue('التاريخ')]);
      for (final a in list) {
        s.appendRow([
          TextCellValue(a.code), TextCellValue(a.name), TextCellValue(a.phone),
          TextCellValue(a.city), TextCellValue(a.country), TextCellValue(a.gmail),
          TextCellValue(a.brokerType),
          TextCellValue(a.contactPersonName), TextCellValue(a.contactPersonPhone), TextCellValue(a.contactPersonEmail),
          TextCellValue(a.currency), DoubleCellValue(a.balance), DoubleCellValue(a.initialBalance),
          TextCellValue(a.initialBalanceDirection), TextCellValue(a.createdAt),
        ]);
      }
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      return excel.encode();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════
  // شركات الشحن
  // ═══════════════════════════════════════════════════
  Future<void> _exportShippingCompanies(String dirPath) async {
    try {
      final dao = ShippingCompanyDao();
      final List<ShippingCompanyModel> all = [];
      int offset = 0;
      while (true) {
        final batch = await dao.getAll(limit: 500, offset: offset);
        all.addAll(batch);
        if (batch.length < 500) break;
        offset += 500;
      }
      if (all.isEmpty) return;

      // PDF - ShippingCompanyPdfService (same as page button)
      try {
        final path = await ShippingCompanyPdfService.saveToFile(all);
        if (path.isNotEmpty) {
          final src = File(path);
          if (await src.exists()) await src.copy(p.join(dirPath, 'شركات الشحن.pdf'));
        }
      } catch (_) {}

      // Excel
      try {
        final bytes = _buildShippingCompaniesExcel(all);
        if (bytes != null) await File(p.join(dirPath, 'شركات الشحن.xlsx')).writeAsBytes(bytes, flush: true);
      } catch (_) {}
    } catch (_) {}
  }

  List<int>? _buildShippingCompaniesExcel(List<ShippingCompanyModel> list) {
    try {
      final excel = Excel.createExcel();
      final s = excel['شركات الشحن'];
      s.appendRow([TextCellValue('الكود'), TextCellValue('اسم الشركة'), TextCellValue('الهاتف'),
        TextCellValue('البريد الإلكتروني'), TextCellValue('العملة'), TextCellValue('الرصيد'),
        TextCellValue('الرصيد المبدئي'), TextCellValue('الاتجاه'), TextCellValue('التاريخ')]);
      for (final c in list) {
        s.appendRow([
          TextCellValue(c.code), TextCellValue(c.name), TextCellValue(c.phone),
          TextCellValue(c.email), TextCellValue(c.currency), DoubleCellValue(c.balance),
          DoubleCellValue(c.initialBalance), TextCellValue(c.initialBalanceDirection), TextCellValue(c.createdAt),
        ]);
      }
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      return excel.encode();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════
  // المساهمين
  // ═══════════════════════════════════════════════════
  Future<void> _exportShareholders(String dirPath) async {
    try {
      final dao = ShareholderDao();
      final list = await dao.getAll(limit: 2000, offset: 0);
      if (list.isEmpty) return;
      final bytes = _buildShareholdersExcel(list);
      if (bytes != null) await File(p.join(dirPath, 'المساهمين.xlsx')).writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  List<int>? _buildShareholdersExcel(List<ShareholderModel> list) {
    try {
      final excel = Excel.createExcel();
      final s = excel['المساهمين'];
      s.appendRow([TextCellValue('الكود'), TextCellValue('اسم المساهم'), TextCellValue('رصيد EGP'),
        TextCellValue('رصيد USD'), TextCellValue('رصيد EUR'), TextCellValue('رصيد GBP'),
        TextCellValue('إيداعات EGP'), TextCellValue('إيداعات USD'), TextCellValue('سحوبات EGP'), TextCellValue('سحوبات USD'), TextCellValue('التاريخ')]);
      for (final h in list) {
        s.appendRow([TextCellValue(h.code), TextCellValue(h.name), DoubleCellValue(h.currentBalanceEgp),
          DoubleCellValue(h.currentBalanceUsd), DoubleCellValue(h.currentBalanceEur), DoubleCellValue(h.currentBalanceGbp),
          DoubleCellValue(h.totalDepositsEgp), DoubleCellValue(h.totalDepositsUsd),
          DoubleCellValue(h.totalWithdrawalsEgp), DoubleCellValue(h.totalWithdrawalsUsd), TextCellValue(h.createdAt)]);
      }
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      return excel.encode();
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════
  // كشوفات الحساب
  // ═══════════════════════════════════════════════════
  Future<void> _exportStatementsSection(String rootDir, BackupProgressCallback onProgress) async {
    final base = p.join(rootDir, 'كشوفات الحساب');
    int step = 0, total = 5;

    onProgress('كشوفات الحساب', 'كشف حساب العملاء', ++step, total);
    await _exportCustomerStatements(p.join(base, 'كشف حساب العملاء'));

    onProgress('كشوفات الحساب', 'كشف حساب الموردين', ++step, total);
    await _exportSupplierStatements(p.join(base, 'كشف حساب الموردين'));

    onProgress('كشوفات الحساب', 'كشف حساب المخلصين', ++step, total);
    await _exportClearingAgentStatements(p.join(base, 'كشف حساب المخلصين'));

    onProgress('كشوفات الحساب', 'كشف حساب شركات الشحن', ++step, total);
    await _exportShippingCompanyStatements(p.join(base, 'كشف حساب شركات الشحن'));

    onProgress('كشوفات الحساب', 'كشف حساب المساهمين', ++step, total);
    await _exportShareholderStatements(p.join(base, 'كشف حساب المساهمين'));
  }

  Future<void> _exportCustomerStatements(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
    final cubit = ExportCustomerStatementCubit();
    try {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (cubit.state is ExportCustomerStatementLoaded) break;
      }
      final state = cubit.state;
      if (state is! ExportCustomerStatementLoaded) return;
      for (final c in state.customers) {
        await cubit.selectCustomer(c);
        for (int j = 0; j < 20; j++) {
          await Future.delayed(const Duration(milliseconds: 100));
          final st = cubit.state;
          if (st is ExportCustomerStatementLoaded && st.statementRows.isNotEmpty) break;
        }
        final st = cubit.state;
        if (st is ExportCustomerStatementLoaded && st.statementRows.isNotEmpty) {
          try {
            final path = await ExportCustomerStatementPdfService.saveToFile(
              customer: c, rows: st.statementRows, totalDebit: st.totalDebit,
              totalCredit: st.totalCredit, finalBalance: st.finalBalance, statementNumber: 1);
            if (path.isNotEmpty) {
              final src = File(path);
              if (await src.exists()) await src.copy(p.join(dirPath, '${c.name}.pdf'));
            }
          } catch (_) {}
          try {
            final path = await ExportCustomerStatementExcelService.saveToFile(
              customer: c, rows: st.statementRows, totalDebit: st.totalDebit,
              totalCredit: st.totalCredit, finalBalance: st.finalBalance, statementNumber: 1);
            if (path.isNotEmpty) {
              final src = File(path);
              if (await src.exists()) await src.copy(p.join(dirPath, '${c.name}.xlsx'));
            }
          } catch (_) {}
        }
      }
    } finally { await cubit.close(); }
  }

  Future<void> _exportSupplierStatements(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
    final cubit = SupplierAccountStatementCubit();
    try {
      await cubit.init();
      await Future.delayed(const Duration(milliseconds: 200));
      final state = cubit.state;
      if (state is! SupplierAccountStatementLoaded) return;
      for (final s in state.suppliers) {
        await cubit.selectSupplier(s);
        await Future.delayed(const Duration(milliseconds: 100));
        final st = cubit.state;
        if (st is SupplierAccountStatementLoaded && st.statementRows.isNotEmpty) {
          // Arabic
          await StatementExcelService.saveToFile(title: 'كشف حساب مورد', vendorName: s.name,
            vendorCode: s.supplierCode, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'كشف حساب مورد', vendorName: s.name,
            vendorCode: s.supplierCode, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          // English
          await StatementExcelService.saveToFile(title: 'Account Statement - Supplier', vendorName: s.name,
            vendorCode: s.supplierCode, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'Account Statement - Supplier', vendorName: s.name,
            vendorCode: s.supplierCode, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
        }
      }
    } finally { await cubit.close(); }
  }

  Future<void> _exportClearingAgentStatements(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
    final cubit = ClearingAgentStatementCubit();
    try {
      await cubit.init();
      await Future.delayed(const Duration(milliseconds: 200));
      final state = cubit.state;
      if (state is! ClearingAgentStatementLoaded) return;
      for (final a in state.agents) {
        await cubit.selectAgent(a);
        await Future.delayed(const Duration(milliseconds: 100));
        final st = cubit.state;
        if (st is ClearingAgentStatementLoaded && st.statementRows.isNotEmpty) {
          // Arabic
          await StatementExcelService.saveToFile(title: 'كشف حساب مخلص', vendorName: a.name,
            vendorCode: a.code, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'كشف حساب مخلص', vendorName: a.name,
            vendorCode: a.code, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          // English
          await StatementExcelService.saveToFile(title: 'Account Statement - Clearing Agent', vendorName: a.name,
            vendorCode: a.code, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'Account Statement - Clearing Agent', vendorName: a.name,
            vendorCode: a.code, currency: 'EGP', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
        }
      }
    } finally { await cubit.close(); }
  }

  Future<void> _exportShippingCompanyStatements(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
    final cubit = ShippingCompanyStatementCubit();
    try {
      await cubit.init();
      await Future.delayed(const Duration(milliseconds: 200));
      final state = cubit.state;
      if (state is! ShippingCompanyStatementLoaded) return;
      for (final c in state.companies) {
        await cubit.selectCompany(c);
        await Future.delayed(const Duration(milliseconds: 100));
        final st = cubit.state;
        if (st is ShippingCompanyStatementLoaded && st.statementRows.isNotEmpty) {
          // Arabic
          await StatementExcelService.saveToFile(title: 'كشف حساب شركة شحن', vendorName: c.name,
            vendorCode: c.code, currency: 'USD', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'كشف حساب شركة شحن', vendorName: c.name,
            vendorCode: c.code, currency: 'USD', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'ar', customDirectory: dirPath);
          // English
          await StatementExcelService.saveToFile(title: 'Account Statement - Shipping Company', vendorName: c.name,
            vendorCode: c.code, currency: 'USD', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
          await StatementPdfService.saveToFile(title: 'Account Statement - Shipping Company', vendorName: c.name,
            vendorCode: c.code, currency: 'USD', rows: st.statementRows,
            totalDebit: st.totalDebit, totalCredit: st.totalCredit, finalBalance: st.finalBalance,
            statementNumber: 1, locale: 'en', customDirectory: dirPath);
        }
      }
    } finally { await cubit.close(); }
  }

  Future<void> _exportShareholderStatements(String dirPath) async {
    await Directory(dirPath).create(recursive: true);
    final cubit = ShareholderStatementCubit();
    const currencies = ['EGP', 'USD', 'EUR', 'GBP'];
    try {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (cubit.state.shareholders.isNotEmpty) break;
      }
      for (final s in cubit.state.shareholders) {
        await cubit.selectShareholder(s);
        final excel = Excel.createExcel();

        for (final cur in currencies) {
          cubit.setCurrency(cur);
          await cubit.loadStatement();
          final st = cubit.state;

          final sheet = excel[cur];
          sheet.appendRow([
            TextCellValue('رقم المرجع'),
            TextCellValue('التاريخ'),
            TextCellValue('النوع'),
            TextCellValue('البيان'),
            TextCellValue('مدين'),
            TextCellValue('دائن'),
            TextCellValue('الرصيد'),
          ]);
          for (final r in st.rows) {
            sheet.appendRow([
              TextCellValue(r.transactionNumber),
              TextCellValue(r.date),
              TextCellValue(r.type),
              TextCellValue(r.description),
              DoubleCellValue(r.debit),
              DoubleCellValue(r.credit),
              DoubleCellValue(r.balance),
            ]);
          }
          sheet.appendRow([TextCellValue('')]);
          sheet.appendRow([TextCellValue('إجمالي المدين'), DoubleCellValue(st.totalDebit)]);
          sheet.appendRow([TextCellValue('إجمالي الدائن'), DoubleCellValue(st.totalCredit)]);
          sheet.appendRow([TextCellValue('الرصيد النهائي'), DoubleCellValue(st.finalBalance)]);
        }

        if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
        final bytes = excel.encode();
        if (bytes != null) {
          await File(p.join(dirPath, '${s.name}.xlsx')).writeAsBytes(bytes, flush: true);
        }
      }
    } finally {
      await cubit.close();
    }
  }



  // ═══════════════════════════════════════════════════
  // الحسابات - الخزينة الرئيسية + العهد الفرعية
  // ═══════════════════════════════════════════════════
  Future<void> _exportTreasurySection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('الحسابات', 'جاري تصدير أرصدة الخزائن...', 0, 1);
    try {
      final dao = TreasuryDao();
      final treasuries = await dao.getAll();
      if (treasuries.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الحسابات', 'الخزينة'));
      await dir.create(recursive: true);

      // Sheet 1: أرصدة الخزائن
      await _exportTreasuryBalancesExcel(dir.path, treasuries);

      // Sheet 2+: حركات كل خزنة
      int step = 0;
      final total = treasuries.length;
      for (final t in treasuries) {
        onProgress('الحسابات', 'جاري تصدير حركات ${t.name}...', ++step, total);
        await _exportTreasuryTransactionsExcel(dir.path, dao, t);
      }
    } catch (_) {}
    onProgress('الحسابات', 'اكتمل', 1, 1);
  }

  Future<void> _exportTreasuryBalancesExcel(String rootDir, List<TreasuryModel> treasuries) async {
    try {
      final excel = Excel.createExcel();
      final s = excel['أرصدة الخزائن'];
      excel.delete('Sheet1');
      s.appendRow([
        TextCellValue('الخزينة'), TextCellValue('النوع'), TextCellValue('الموظف'),
        TextCellValue('العملة'), TextCellValue('الرصيد'),
      ]);
      for (final t in treasuries) {
        final typeLabel = t.type == 'main' ? ' رئيسية' : 'فرعية';
        for (final b in t.balances) {
          if (b.balance != 0) {
            s.appendRow([
              TextCellValue(t.name), TextCellValue(typeLabel),
              TextCellValue(t.userName ?? ''),
              TextCellValue(b.currency), DoubleCellValue(b.balance),
            ]);
          }
        }
        if (t.balances.isEmpty) {
          s.appendRow([
            TextCellValue(t.name), TextCellValue(typeLabel),
            TextCellValue(t.userName ?? ''),
            TextCellValue('—'), DoubleCellValue(0),
          ]);
        }
      }
      // Totals per currency
      final currencyTotals = <String, double>{};
      for (final t in treasuries) {
        for (final b in t.balances) {
          currencyTotals[b.currency] = (currencyTotals[b.currency] ?? 0) + b.balance;
        }
      }
      if (currencyTotals.isNotEmpty) {
        s.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
        for (final entry in currencyTotals.entries) {
          s.appendRow([
            TextCellValue('الإجمالي'), TextCellValue(''), TextCellValue(''),
            TextCellValue(entry.key), DoubleCellValue(entry.value),
          ]);
        }
      }
      await File(p.join(rootDir, 'أرصدة الخزائن.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
  }

  Future<void> _exportTreasuryTransactionsExcel(String rootDir, TreasuryDao dao, TreasuryModel treasury) async {
    try {
      final transactions = await dao.getTransactionsForExport(treasuryId: int.tryParse(treasury.id ?? '') ?? 0);
      if (transactions.isEmpty) return;
      final excel = Excel.createExcel();
      final sheetName = 'حركات ${treasury.name}';
      final s = excel[sheetName];
      excel.delete('Sheet1');
      s.appendRow([
        TextCellValue('التاريخ'), TextCellValue('نوع الحركة'), TextCellValue('المبلغ'),
        TextCellValue('العملة'), TextCellValue('الوصف'),
        TextCellValue('المنشئ'), TextCellValue('الجهة'), TextCellValue('رقم القيد'),
      ]);
      for (final tx in transactions) {
        final date = tx['created_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? '';
        final type = tx['transaction_type']?.toString() ?? tx['type']?.toString() ?? '';
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = tx['currency']?.toString() ?? '';
        final description = tx['description']?.toString() ?? '';
        final creator = tx['created_by_user']?['full_name']?.toString() ?? '';
        final entryNumber = tx['journal_entry_id']?.toString() ?? '';

        // Build counterparty from nested join objects
        final parts = <String>[];
        final customerName = tx['customers']?['name']?.toString() ?? '';
        final supplierName = tx['suppliers']?['name']?.toString() ?? '';
        final agentName = tx['clearing_agents']?['name']?.toString() ?? '';
        final shippingName = tx['shipping_companies']?['name']?.toString() ?? '';
        final shareholderName = tx['shareholders']?['name']?.toString() ?? '';
        final relatedName = tx['related']?['name']?.toString() ?? '';
        if (customerName.isNotEmpty) parts.add('عميل: $customerName');
        if (supplierName.isNotEmpty) parts.add('مورد: $supplierName');
        if (agentName.isNotEmpty) parts.add('مخلص: $agentName');
        if (shippingName.isNotEmpty) parts.add('شحن: $shippingName');
        if (shareholderName.isNotEmpty) parts.add('مساهم: $shareholderName');
        if (relatedName.isNotEmpty) parts.add('خزنة: $relatedName');

        s.appendRow([
          TextCellValue(date), TextCellValue(type), DoubleCellValue(amount),
          TextCellValue(currency), TextCellValue(description), TextCellValue(creator),
          TextCellValue(parts.join(' | ')), TextCellValue(entryNumber),
        ]);
      }
      await File(p.join(rootDir, 'حركات ${treasury.name}.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  // الحسابات البنكية - شيت لكل حساب بالرصيد والحركات
  // ═══════════════════════════════════════════════════
  Future<void> _exportBankAccountsSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('الحسابات', 'جاري تصدير الحسابات البنكية...', 0, 1);
    try {
      final dao = BankAccountDao();
      final accounts = await dao.getAll();
      if (accounts.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الحسابات', 'الحسابات البنكية'));
      await dir.create(recursive: true);

      int step = 0;
      final total = accounts.length;
      for (final account in accounts) {
        onProgress('الحسابات', 'جاري تصدير ${account.name}...', ++step, total);
        await _exportBankAccountExcel(dir.path, dao, account);
      }
    } catch (_) {}
    onProgress('الحسابات', 'اكتمل', 1, 1);
  }

  Future<void> _exportBankAccountExcel(String rootDir, BankAccountDao dao, account) async {
    try {
      final transactions = await dao.getTransactions(account.id, limit: 100000);
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final s = excel[account.name];
      s.appendRow([
        TextCellValue('الرصيد الحالي'), DoubleCellValue(account.balance),
        TextCellValue(account.currency),
      ]);
      s.appendRow([TextCellValue('')]);
      s.appendRow([
        TextCellValue('التاريخ'), TextCellValue('نوع الحركة'), TextCellValue('المبلغ'),
        TextCellValue('العملة'), TextCellValue('الوصف'), TextCellValue('المنشئ'),
        TextCellValue('الطرف المعني'), TextCellValue('رقم القيد'),
      ]);
      for (final tx in transactions) {
        final date = tx.createdAt.toIso8601String().substring(0, 16).replaceAll('T', ' ');
        final typeLabel = tx.type == 'deposit' || tx.type == 'currency_exchange_in'
            ? 'إيداع' : 'سحب';
        s.appendRow([
          TextCellValue(date), TextCellValue(typeLabel),
          DoubleCellValue(tx.amount), TextCellValue(account.currency),
          TextCellValue(tx.description ?? ''),
          TextCellValue(tx.createdByName ?? ''),
          TextCellValue(tx.relatedPartyName ?? ''),
          TextCellValue(tx.journalEntryId?.toString() ?? ''),
        ]);
      }
      final fileName = '${account.name}.xlsx';
      await File(p.join(rootDir, fileName)).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  // الشيكات - شيت مجمع لجميع الشيكات مع تلوين الحالة
  // ═══════════════════════════════════════════════════
  Future<void> _exportChequesSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('الشيكات', 'جاري تصدير الشيكات...', 0, 1);
    try {
      final dao = ChequeDao();
      final cheques = await dao.getAll(limit: 100000);
      if (cheques.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الشيكات'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final s = excel['الشيكات'];
      s.appendRow([
        TextCellValue('رقم الشيك'), TextCellValue('النوع'), TextCellValue('الحالة'),
        TextCellValue('المبلغ'), TextCellValue('العملة'), TextCellValue('الطرف المعني'),
        TextCellValue('تاريخ التحرير'), TextCellValue('تاريخ الاستحقاق'),
        TextCellValue('الملاحظات'),
      ]);

      for (var i = 0; i < cheques.length; i++) {
        final c = cheques[i];
        final statusLabel = c.status == 'cleared' ? 'تم الصرف'
            : c.status == 'cancelled' ? 'ملغي'
            : 'معلق';
        s.appendRow([
          TextCellValue(c.chequeNumber),
          TextCellValue(c.isOutgoing ? 'صادر' : 'وارد'),
          TextCellValue(statusLabel),
          DoubleCellValue(c.amount),
          TextCellValue(c.currency),
          TextCellValue(c.counterpartyDisplay),
          TextCellValue(c.issueDate),
          TextCellValue(c.dueDate),
          TextCellValue(c.notes ?? ''),
        ]);

        // Color the status cell
        final statusCell = s.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1));
        String colorHex;
        if (c.status == 'cleared') {
          colorHex = '#FF4CAF50'; // green
        } else if (c.status == 'cancelled') {
          colorHex = '#FFF44336'; // red
        } else {
          colorHex = '#FFFFEB3B'; // yellow for pending
        }
        statusCell.cellStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(colorHex),
          fontColorHex: c.status == 'cancelled'
              ? ExcelColor.fromHexString('#FFFFFFFF')
              : ExcelColor.fromHexString('#FF000000'),
          bold: true,
        );
      }

      await File(p.join(dir.path, 'الشيكات.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('الشيكات', 'اكتمل', 1, 1);
  }

  // ═══════════════════════════════════════════════════
  // الميزان التجريبي - شيت موحد بالعملة الأساسية (EGP)
  // ═══════════════════════════════════════════════════
  Future<void> _exportTrialBalanceSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('الميزان التجريبي', 'جاري تصدير الميزان التجريبي...', 0, 1);
    try {
      final reportDao = ReportDao();
      final calcService = ReportCalculationService(reportDao);
      final dir = Directory(p.join(rootDir, 'الميزان التجريبي'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      final report = await calcService.calculateTrialBalance(
        asOfDate: DateTime.now(),
        currency: null, // Unified base currency (EGP)
      );

      excel.rename('Sheet1', 'الميزان التجريبي');
      final s = excel['الميزان التجريبي'];

      // Summary metrics at top
      int debitCount = 0;
      int creditCount = 0;
      for (final row in report.rows) {
        if (row.isDebitBalance) {
          debitCount++;
        } else {
          creditCount++;
        }
      }

      s.appendRow([
        TextCellValue('الميزانية التجريبية / Trial Balance'),
      ]);
      s.appendRow([
        TextCellValue('بتاريخ: ${report.asOfDate.toString().substring(0, 10)} | العملة: مجمع موحد (EGP)'),
      ]);
      s.appendRow([TextCellValue('')]);

      // Summary cards
      s.appendRow([
        TextCellValue('إجمالي الحسابات'), TextCellValue('${report.rows.length}'),
        TextCellValue('حسابات مدين'), TextCellValue('$debitCount'),
        TextCellValue('حسابات دائنة'), TextCellValue('$creditCount'),
      ]);
      s.appendRow([
        TextCellValue('إجمالي المدين'), TextCellValue(report.totalDebit.toStringAsFixed(2)),
        TextCellValue('إجمالي الدائن'), TextCellValue(report.totalCredit.toStringAsFixed(2)),
        TextCellValue('الفرق'), TextCellValue(report.difference.abs().toStringAsFixed(2)),
      ]);
      s.appendRow([
        TextCellValue('الحالة'), TextCellValue(report.isBalanced ? 'متوازن' : 'غير متوازن'),
      ]);
      s.appendRow([TextCellValue('')]);

      // Table headers
      s.appendRow([
        TextCellValue('الحساب'), TextCellValue('اسم الحساب'),
        TextCellValue('مدين'), TextCellValue('دائن'),
        TextCellValue('الرصيد'), TextCellValue('النوع'),
      ]);

      // Data rows
      for (final row in report.rows) {
        final net = row.debit - row.credit;
        s.appendRow([
          TextCellValue(row.accountCode),
          TextCellValue(row.accountNameAr),
          DoubleCellValue(row.debit),
          DoubleCellValue(row.credit),
          DoubleCellValue(net.abs()),
          TextCellValue(net >= 0 ? 'مدين' : 'دائن'),
        ]);
      }

      // Totals row
      s.appendRow([
        TextCellValue(''), TextCellValue('الإجمالي'),
        DoubleCellValue(report.totalDebit), DoubleCellValue(report.totalCredit),
        TextCellValue(''), TextCellValue(''),
      ]);

      await File(p.join(dir.path, 'الميزان التجريبي.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('الميزان التجريبي', 'اكتمل', 1, 1);
  }

  // ═══════════════════════════════════════════════════
  // دفتر الاستاذ - شيت مجمع بـ 4 عملات (EGP, USD, EUR, GBP)
  // ═══════════════════════════════════════════════════
  Future<void> _exportGeneralLedgerSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('دفتر الاستاذ', 'جاري تصدير دفتر الاستاذ...', 0, 1);
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('v_journal_entry_lines')
          .select('*')
          .order('transaction_date', ascending: true)
          .order('id', ascending: true);

      if (data.isEmpty) return;

      // Fetch account info
      final accountIds = <String>{};
      for (final row in (data as List)) {
        final m = row as Map<String, dynamic>;
        if (m['account_id'] != null) accountIds.add(m['account_id'].toString());
      }
      final Map<String, Map<String, dynamic>> accountsMap = {};
      if (accountIds.isNotEmpty) {
        try {
          final accData = await client
              .from('accounts')
              .select('id, name, account_name, account_code')
              .inFilter('id', accountIds.toList());
          for (final a in (accData as List)) {
            final m = Map<String, dynamic>.from(a as Map);
            accountsMap[m['id'].toString()] = m;
          }
        } catch (_) {}
      }

      // Build all rows
      final allRows = <Map<String, dynamic>>[];
      for (final row in (data as List)) {
        final flat = Map<String, dynamic>.from(row as Map);
        final accId = flat['account_id']?.toString();
        final account = accId != null ? accountsMap[accId] : null;
        final acCode = flat['account_code']?.toString();
        final acName = flat['account_name']?.toString();
        allRows.add({
          'currency': (flat['currency']?.toString() ?? 'EGP').toUpperCase(),
          'date': flat['transaction_date']?.toString() ?? '',
          'entry_number': flat['entry_number']?.toString() ?? '',
          'account_code': (acCode != null && acCode.isNotEmpty) ? acCode : (account?['account_code']?.toString() ?? ''),
          'account_name': (acName != null && acName.isNotEmpty) ? acName : (account?['account_name']?.toString() ?? account?['name']?.toString() ?? ''),
          'description': flat['description']?.toString() ?? '',
          'debit': (flat['debit'] as num?)?.toDouble() ?? 0.0,
          'credit': (flat['credit'] as num?)?.toDouble() ?? 0.0,
        });
      }

      final dir = Directory(p.join(rootDir, 'دفتر الاستاذ'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      const currencies = ['EGP', 'USD', 'EUR', 'GBP'];

      for (final cur in currencies) {
        final rows = allRows.where((r) => r['currency'] == cur).toList();
        final s = excel[cur];

        // Compute running balance
        double runningBalance = 0;
        double totalDebit = 0;
        double totalCredit = 0;
        for (final r in rows) {
          final debit = r['debit'] as double;
          final credit = r['credit'] as double;
          totalDebit += debit;
          totalCredit += credit;
          runningBalance += debit - credit;
          r['balance'] = runningBalance;
        }

        // Title
        s.appendRow([TextCellValue('دفتر الأستاذ العام / General Ledger - $cur')]);
        s.appendRow([TextCellValue('بتاريخ: ${DateTime.now().toString().substring(0, 10)} | العملة: $cur')]);
        s.appendRow([TextCellValue('')]);

        // Summary metrics
        s.appendRow([
          TextCellValue('العمليات'), TextCellValue('${rows.length}'),
          TextCellValue('إجمالي المدين'), TextCellValue(totalDebit.toStringAsFixed(2)),
          TextCellValue('إجمالي الدائن'), TextCellValue(totalCredit.toStringAsFixed(2)),
        ]);
        s.appendRow([
          TextCellValue('الرصيد الختامي'), TextCellValue(runningBalance.toStringAsFixed(2)),
        ]);
        s.appendRow([TextCellValue('')]);

        // Table headers
        s.appendRow([
          TextCellValue('التاريخ'), TextCellValue('رقم القيد'), TextCellValue('الحساب'),
          TextCellValue('البيان'), TextCellValue('مدين'), TextCellValue('دائن'),
          TextCellValue('الرصيد'),
        ]);

        // Data rows
        for (final r in rows) {
          final date = r['date']?.toString() ?? '';
          final dateOnly = date.length >= 10 ? date.substring(0, 10) : date;
          s.appendRow([
            TextCellValue(dateOnly),
            TextCellValue(r['entry_number']?.toString() ?? ''),
            TextCellValue(r['account_code']?.toString() ?? ''),
            TextCellValue(r['description']?.toString() ?? ''),
            DoubleCellValue(r['debit'] as double),
            DoubleCellValue(r['credit'] as double),
            DoubleCellValue((r['balance'] ?? 0.0) as double),
          ]);
        }

        // Totals row
        s.appendRow([
          TextCellValue(''), TextCellValue(''), TextCellValue(''),
          TextCellValue('الإجمالي'),
          DoubleCellValue(totalDebit), DoubleCellValue(totalCredit),
          TextCellValue(''),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      await File(p.join(dir.path, 'دفتر الاستاذ.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('دفتر الاستاذ', 'اكتمل', 1, 1);
  }

  // ═══════════════════════════════════════════════════
  // دفتر قيود اليومية - شيت إكسيل موحد لجميع القيود اليومية (16 عموداً)
  // ═══════════════════════════════════════════════════
  Future<void> _exportJournalEntriesSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('قيود اليومية', 'جاري تصدير دفتر قيود اليومية...', 0, 1);
    try {
      final entries = await JournalEntryExcelService.fetchAllEntries();
      final rows = JournalEntryExcelService.generateJournalRows(entries);
      if (rows.isNotEmpty) {
        final dir = Directory(p.join(rootDir, 'دفتر قيود اليومية'));
        await dir.create(recursive: true);

        final excel = Excel.createExcel();
        final sheet = excel['دفتر قيود اليومية'];
        if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

        final headers = rows.first.map((e) => e.toString()).toList();
        for (var c = 0; c < headers.length; c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
          cell.value = TextCellValue(headers[c]);
          cell.cellStyle = CellStyle(
            bold: true,
            backgroundColorHex: ExcelColor.fromHexString('#FF1A237E'),
            fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
          );
        }

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

        for (var c = 0; c < headers.length; c++) {
          var maxLen = 10.0;
          for (var r = 0; r < rows.length && r < 200; r++) {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
            final val = cell.value;
            if (val != null) {
              final len = val.toString().length;
              if (len > maxLen) maxLen = len.toDouble();
            }
          }
          sheet.setColumnWidth(c, (maxLen + 4).toDouble());
        }

        final fileBytes = excel.save();
        if (fileBytes != null) {
          await File(p.join(dir.path, 'دفتر قيود اليومية.xlsx')).writeAsBytes(fileBytes, flush: true);
        }
      }
    } catch (_) {}
    onProgress('قيود اليومية', 'اكتمل', 1, 1);
  }

  // ═══════════════════════════════════════════════════
  // الميزانية العامة - شيت موحد بالعملة الأساسية (EGP)
  // ═══════════════════════════════════════════════════
  Future<void> _exportBalanceSheetSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('الميزانية العامة', 'جاري تصدير الميزانية العامة...', 0, 1);
    try {
      final reportDao = ReportDao();
      final calcService = ReportCalculationService(reportDao);
      final dir = Directory(p.join(rootDir, 'الميزانية العامة'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      final report = await calcService.calculateBalanceSheet(
        asOfDate: DateTime.now(),
        currency: null, // Unified base currency (EGP)
      );

      excel.rename('Sheet1', 'الميزانية العامة');
      final s = excel['الميزانية العامة'];

      // Title
      s.appendRow([TextCellValue('الميزانية العامة / Balance Sheet')]);
      s.appendRow([TextCellValue('بتاريخ: ${report.asOfDate.toString().substring(0, 10)} | العملة: مجمع موحد (EGP)')]);
      s.appendRow([TextCellValue('')]);

      // Summary metrics
      s.appendRow([
        TextCellValue('إجمالي الأصول'), TextCellValue(report.totalAssets.toStringAsFixed(2)),
        TextCellValue('إجمالي الخصوم'), TextCellValue(report.liabilities.total.toStringAsFixed(2)),
      ]);
      s.appendRow([
        TextCellValue('إجمالي حقوق الملكية'), TextCellValue(report.equity.total.toStringAsFixed(2)),
        TextCellValue('إجمالي الخصوم وحقوق الملكية'), TextCellValue(report.totalLiabilitiesAndEquity.toStringAsFixed(2)),
      ]);
      s.appendRow([
        TextCellValue('الفرق'), TextCellValue(report.difference.abs().toStringAsFixed(2)),
        TextCellValue('الحالة'), TextCellValue(report.isBalanced ? 'متوازن' : 'غير متوازن'),
      ]);
      s.appendRow([TextCellValue('')]);

      // Sections
      int row = 4;
      row = _writeBalanceSheetSection(s, row, report.assets, 'الأصول');
      row += 1;
      row = _writeBalanceSheetSection(s, row, report.liabilities, 'الخصوم');
      row += 1;
      row = _writeBalanceSheetSection(s, row, report.equity, 'حقوق الملكية');
      row += 1;

      // Grand totals
      s.appendRow([TextCellValue('')]);
      s.appendRow([
        TextCellValue(''), TextCellValue('إجمالي الأصول'),
        DoubleCellValue(report.totalAssets),
      ]);
      s.appendRow([
        TextCellValue(''), TextCellValue('إجمالي الخصوم وحقوق الملكية'),
        DoubleCellValue(report.totalLiabilitiesAndEquity),
      ]);

      await File(p.join(dir.path, 'الميزانية العامة.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('الميزانية العامة', 'اكتمل', 1, 1);
  }

  int _writeBalanceSheetSection(Sheet s, int startRow, section, String title) {
    // Section title
    s.appendRow([TextCellValue(title)]);
    startRow += 2;

    // Column headers
    s.appendRow([
      TextCellValue('الحساب'), TextCellValue('اسم الحساب'), TextCellValue('المبلغ'),
    ]);
    startRow += 1;

    // Data rows
    for (final line in section.lines) {
      s.appendRow([
        TextCellValue(line.accountCode),
        TextCellValue(line.accountNameAr),
        DoubleCellValue(line.amount),
      ]);
      startRow += 1;
    }

    // Section total
    s.appendRow([
      TextCellValue(''), TextCellValue('الإجمالي'),
      DoubleCellValue(section.total),
    ]);

    return startRow + 1;
  }

  // ═══════════════════════════════════════════════════
  // قائمة الدخل - شيت مجمع بـ 4 عملات (EGP, USD, EUR, GBP)
  // ═══════════════════════════════════════════════════
  Future<void> _exportIncomeStatementSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('قائمة الدخل', 'جاري تصدير قائمة الدخل...', 0, 1);
    try {
      final reportDao = ReportDao();
      final calcService = ReportCalculationService(reportDao);
      final dir = Directory(p.join(rootDir, 'قائمة الدخل'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      final currencies = [null, 'EGP', 'USD', 'EUR', 'GBP'];

      for (final cur in currencies) {
        final report = await calcService.calculateIncomeStatement(
          fromDate: DateTime(DateTime.now().year, 1, 1),
          toDate: DateTime.now(),
          currency: cur,
        );

        final sheetName = cur ?? 'المجمع';
        final s = excel[sheetName];

        // Title
        s.appendRow([TextCellValue('قائمة الدخل / Income Statement - $sheetName')]);
        s.appendRow([
          TextCellValue('من: ${report.fromDate.toString().substring(0, 10)} إلى: ${report.toDate.toString().substring(0, 10)} | العملة: ${cur ?? 'الكل (مجمع)'}'),
        ]);
        s.appendRow([TextCellValue('')]);

        // Summary metrics
        s.appendRow([
          TextCellValue('إجمالي الإيرادات'), DoubleCellValue(report.revenue.total),
          TextCellValue('تكلفة البضاعة المباعة'), DoubleCellValue(report.costOfGoodsSold.total),
        ]);
        s.appendRow([
          TextCellValue('إجمالي الربح'), DoubleCellValue(report.grossProfit),
          TextCellValue('المصروفات التشغيلية'), DoubleCellValue(report.operatingExpenses.total),
        ]);
        s.appendRow([
          TextCellValue('صافي الدخل'), DoubleCellValue(report.netIncome),
          TextCellValue('هامش الربح'),
          TextCellValue(report.revenue.total > 0
              ? '${((report.grossProfit / report.revenue.total) * 100).toStringAsFixed(1)}%'
              : '0%'),
        ]);
        s.appendRow([TextCellValue('')]);

        // Revenue section
        int row = 4;
        row = _writeIncomeSection(s, row, report.revenue, 'الإيرادات');
        row += 1;

        // COGS section
        row = _writeIncomeSection(s, row, report.costOfGoodsSold, 'تكلفة البضاعة المباعة');
        row += 1;

        // Gross profit
        s.appendRow([TextCellValue(''), TextCellValue('إجمالي الربح'), DoubleCellValue(report.grossProfit)]);
        row += 2;

        // Operating expenses section
        row = _writeIncomeSection(s, row, report.operatingExpenses, 'المصروفات التشغيلية');
        row += 1;

        // Net income
        s.appendRow([TextCellValue(''), TextCellValue('صافي الدخل'), DoubleCellValue(report.netIncome)]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      await File(p.join(dir.path, 'قائمة الدخل.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('قائمة الدخل', 'اكتمل', 1, 1);
  }

  int _writeIncomeSection(Sheet s, int startRow, section, String title) {
    // Section title
    s.appendRow([TextCellValue(title)]);
    startRow += 2;

    // Column headers
    s.appendRow([
      TextCellValue('الحساب'), TextCellValue('اسم الحساب'), TextCellValue('المبلغ'),
    ]);
    startRow += 1;

    // Data rows
    for (final line in section.lines) {
      s.appendRow([
        TextCellValue(line.accountCode),
        TextCellValue(line.accountNameAr),
        DoubleCellValue(line.amount),
      ]);
      startRow += 1;
    }

    // Section total
    s.appendRow([
      TextCellValue(''), TextCellValue('الإجمالي'),
      DoubleCellValue(section.total),
    ]);

    return startRow + 1;
  }

  // ═══════════════════════════════════════════════════
  // قائمة التدفقات النقدية - شيت مجمع بـ 4 عملات (EGP, USD, EUR, GBP)
  // ═══════════════════════════════════════════════════
  Future<void> _exportCashFlowSection(String rootDir, BackupProgressCallback onProgress) async {
    onProgress('التدفقات النقدية', 'جاري تصدير التدفقات النقدية...', 0, 1);
    try {
      final reportDao = ReportDao();
      final calcService = ReportCalculationService(reportDao);
      final dir = Directory(p.join(rootDir, 'التدفقات النقدية'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      const currencies = ['EGP', 'USD', 'EUR', 'GBP'];

      for (final cur in currencies) {
        final report = await calcService.calculateCashFlowStatement(
          fromDate: DateTime(DateTime.now().year, 1, 1),
          toDate: DateTime.now(),
          currency: cur,
        );

        final s = excel[cur];

        // Title
        s.appendRow([TextCellValue('قائمة التدفقات النقدية / Cash Flow Statement - $cur')]);
        s.appendRow([
          TextCellValue('من: ${report.fromDate.toString().substring(0, 10)} إلى: ${report.toDate.toString().substring(0, 10)} | العملة: $cur'),
        ]);
        s.appendRow([TextCellValue('')]);

        // Summary metrics
        s.appendRow([
          TextCellValue('التدفقات التشغيلية'), DoubleCellValue(report.netCashFromOperating),
          TextCellValue('التدفقات الاستثمارية'), DoubleCellValue(report.netCashFromInvesting),
        ]);
        s.appendRow([
          TextCellValue('التدفقات التمويلية'), DoubleCellValue(report.netCashFromFinancing),
          TextCellValue('صافي التغير في النقد'), DoubleCellValue(report.netChangeInCash),
        ]);
        s.appendRow([TextCellValue('')]);

        // Operating activities section
        int row = 4;
        row = _writeCashFlowSection(s, row, report.operating, 'الأنشطة التشغيلية', report.netCashFromOperating);
        row += 1;

        // Investing activities section
        row = _writeCashFlowSection(s, row, report.investing, 'الأنشطة الاستثمارية', report.netCashFromInvesting);
        row += 1;

        // Financing activities section
        row = _writeCashFlowSection(s, row, report.financing, 'الأنشطة التمويلية', report.netCashFromFinancing);
        row += 1;

        // Net change in cash
        s.appendRow([TextCellValue('')]);
        s.appendRow([
          TextCellValue(''), TextCellValue('صافي التغير في النقد'),
          DoubleCellValue(report.netChangeInCash),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
      await File(p.join(dir.path, 'التدفقات النقدية.xlsx')).writeAsBytes(excel.encode()!, flush: true);
    } catch (_) {}
    onProgress('التدفقات النقدية', 'اكتمل', 1, 1);
  }

  int _writeCashFlowSection(Sheet s, int startRow, section, String title, double sectionTotal) {
    // Section title
    s.appendRow([TextCellValue(title)]);
    startRow += 2;

    // Column headers
    s.appendRow([
      TextCellValue('البيان'), TextCellValue('المبلغ'),
    ]);
    startRow += 1;

    // Data rows
    for (final line in section.lines) {
      s.appendRow([
        TextCellValue(line.descriptionAr),
        DoubleCellValue(line.amount),
      ]);
      startRow += 1;
    }

    // Section total
    s.appendRow([
      TextCellValue('صافي التدفقات من $title'),
      DoubleCellValue(sectionTotal),
    ]);

    return startRow + 1;
  }

  // ═══════════════════════════════════════════════════
  // المخازن - مواد التعبئة + أصناف الفاكهة + المشتريات + المحطات + التحويلات + متابعة المخازن
  // ═══════════════════════════════════════════════════
  Future<void> _exportWarehouseSection(String rootDir, BackupProgressCallback onProgress) async {
    final dir = Directory(p.join(rootDir, 'المخازن'));
    await dir.create(recursive: true);

    onProgress('المخازن', 'جاري تصدير المواد الخام...', 0, 9);
    await _exportRawMaterialsExcel(dir.path);

    onProgress('المخازن', 'جاري تصدير أصناف الفاكهة...', 1, 9);
    await _exportFruitTypesExcel(dir.path);

    onProgress('المخازن', 'جاري تصدير المشتريات...', 2, 9);
    await _exportPurchasesFolder(dir.path);

    onProgress('المخازن', 'جاري تصدير المحطات...', 3, 9);
    await _exportStationsFolder(dir.path);

    onProgress('المخازن', 'جاري تصدير التحويلات...', 4, 9);
    await _exportTransfersExcel(dir.path);

    onProgress('المخازن', 'جاري تصدير متابعة المخازن...', 5, 9);
    await _exportWarehouseTrackingFolder(dir.path);

    onProgress('المخازن', 'جاري تصدير فواتير شراء المحاصيل...', 6, 9);
    await _exportCropPurchasesFolder(dir.path);

    onProgress('المخازن', 'جاري تصدير أوامر التعبئة...', 7, 9);
    await _exportPackingOrdersFolder(dir.path);

    onProgress('المخازن', 'جاري تصدير تقارير الفرز...', 8, 9);
    await _exportSortingFolder(dir.path);

    onProgress('المخازن', 'اكتمل', 9, 9);
  }

  Future<void> _exportPurchasesFolder(String rootDir) async {
    try {
      final dao = PurchaseDao();
      final allPurchases = await dao.getAll(limit: 100000);
      if (allPurchases.isEmpty) return;

      final purchasesDir = Directory(p.join(rootDir, 'المشتريات'));
      await purchasesDir.create(recursive: true);

      for (final purchase in allPurchases) {
        if (purchase.id == null) continue;
        final intId = int.tryParse(purchase.id!);
        if (intId == null) continue;

        final fullPurchase = await dao.getById(intId);
        if (fullPurchase == null || fullPurchase.items.isEmpty) continue;

        final bytes = await PurchasePdfService.generatePdfBytes(fullPurchase);
        final number = purchase.purchaseNumber.toString().padLeft(6, '0');
        final file = File(p.join(purchasesDir.path, 'فاتورة مشتريات $number.pdf'));
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  Future<void> _exportStationsFolder(String rootDir) async {
    try {
      final stationDao = StationDao();
      final stations = await stationDao.getAll(limit: 10000);
      if (stations.isEmpty) return;

      final stationsDir = Directory(p.join(rootDir, 'المحطات'));
      await stationsDir.create(recursive: true);

      for (final station in stations) {
        if (station.id == null) continue;
        final intId = int.tryParse(station.id!);
        if (intId == null) continue;

        final bytes = await StationStockReportService.buildExcelBytes(
          stationId: intId,
          stationName: station.name,
          stationCode: station.code,
        );
        if (bytes == null) continue;

        final file = File(p.join(stationsDir.path, '${station.name}.xlsx'));
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  Future<void> _exportTransfersExcel(String rootDir) async {
    try {
      final transferDao = TransferDao();
      final stationDao = StationDao();
      final transfers = await transferDao.getAll(limit: 100000);
      if (transfers.isEmpty) return;

      final stationIds = <int>{};
      for (final t in transfers) {
        stationIds.add(t.fromStationId);
        stationIds.add(t.toStationId);
      }

      final stationNames = <int, String>{};
      for (final id in stationIds) {
        final station = await stationDao.getById(id.toString());
        stationNames[id] = station?.name ?? 'محطة #$id';
      }

      final bytes = await TransferExportService.buildExcelBytes(
        transfers: transfers,
        stationNames: stationNames,
      );
      if (bytes == null) return;

      await File(p.join(rootDir, 'التحويلات.xlsx')).writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<void> _exportWarehouseTrackingFolder(String rootDir) async {
    try {
      final stationDao = StationDao();
      final trackingDao = WarehouseTrackingDao();
      final stations = await stationDao.getAll(limit: 10000);
      if (stations.isEmpty) return;

      final trackingDir = Directory(p.join(rootDir, 'متابعة المخازن'));
      await trackingDir.create(recursive: true);

      for (final station in stations) {
        if (station.id == null) continue;

        final movements = await trackingDao.getMovementsForStation(station.id!);
        if (movements.isEmpty) continue;

        final grouped = <String, List<WarehouseMovementModel>>{};
        for (final m in movements) {
          final key = m.productName ?? 'غير محدد';
          grouped.putIfAbsent(key, () => []).add(m);
        }

        final excel = Excel.createExcel();
        excel.delete('Sheet1');
        final sheet = excel['حركات المخزن'];

        sheet.appendRow([
          TextCellValue('الصنف'),
          TextCellValue('التاريخ'),
          TextCellValue('النوع'),
          TextCellValue('الرقم المرجعي'),
          TextCellValue('الكمية'),
          TextCellValue('المورد'),
          TextCellValue('التفاصيل'),
        ]);

        for (final entry in grouped.entries) {
          final productName = entry.key;
          final items = entry.value;
          final totalQty = items.fold<double>(0, (s, m) => s + (m.quantity ?? 0));

          for (final m in items) {
            sheet.appendRow([
              TextCellValue(productName),
              TextCellValue(m.date != null ? AppUtils.formatDate(m.date!) : '-'),
              TextCellValue(m.type.label),
              TextCellValue(m.referenceNumber),
              TextCellValue(
                  m.quantity != null ? '${AppUtils.formatNumber(m.quantity!)} ${m.type == MovementType.materialTransfer ? "قطعة" : "كجم"}' : '-'),
              TextCellValue(m.supplierName ?? '-'),
              TextCellValue(m.details ?? '-'),
            ]);
          }

          sheet.appendRow([
            TextCellValue(''),
            TextCellValue(''),
            TextCellValue(''),
            TextCellValue('إجمالي $productName'),
            TextCellValue('${AppUtils.formatNumber(totalQty)} كجم'),
            TextCellValue(''),
            TextCellValue(''),
          ]);

          sheet.appendRow([TextCellValue('')]);
        }

        for (int i = 0; i < 7; i++) {
          sheet.setColumnWidth(i, 20);
        }

        final fileBytes = excel.save();
        if (fileBytes == null) continue;

        final file = File(p.join(trackingDir.path, '${station.name}.xlsx'));
        await file.writeAsBytes(fileBytes, flush: true);
      }
    } catch (_) {}
  }

  Future<void> _exportCropPurchasesFolder(String rootDir) async {
    try {
      final dao = LotDao();
      final lots = await dao.getAll();
      if (lots.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'فواتير شراء المحاصيل'));
      await dir.create(recursive: true);

      // Per-lot PDF + Excel
      for (final lot in lots) {
        if (lot.id == null) continue;

        // Fetch full lot with grading results
        final fullLot = await dao.getById(lot.id!);
        final lotToExport = fullLot ?? lot;

        try {
          final pdfBytes = await LotExportService.generatePdfBytes(lotToExport);
          final pdfFile = File(p.join(dir.path, 'فاتورة محصول ${lot.lotNumber}.pdf'));
          await pdfFile.writeAsBytes(pdfBytes, flush: true);
        } catch (_) {}

        try {
          final excelBytes = await LotExportService.generateExcelBytes(lotToExport);
          if (excelBytes != null) {
            final excelFile = File(p.join(dir.path, 'فاتورة محصول ${lot.lotNumber}.xlsx'));
            await excelFile.writeAsBytes(excelBytes, flush: true);
          }
        } catch (_) {}
      }

      // Bulk combined Excel
      try {
        final allBytes = await LotExportService.generateAllExcelBytes(lots: lots);
        if (allBytes != null) {
          final allFile = File(p.join(dir.path, 'جميع فواتير المحاصيل.xlsx'));
          await allFile.writeAsBytes(allBytes, flush: true);
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _exportPackingOrdersFolder(String rootDir) async {
    try {
      final dao = PackingOrderDao();
      final orders = await dao.getAll();
      if (orders.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'أوامر التعبئة'));
      await dir.create(recursive: true);

      for (final order in orders) {
        if (order.id == null) continue;

        try {
          final data = await PackingExcelExporter.prepareOrderData(order);
          if (data == null) continue;

          final excelBytes = await PackingExcelExporter.generateExcelBytes(
            order: order,
            data: data,
          );
          if (excelBytes != null) {
            final file = File(p.join(dir.path, 'أمر تعبئة ${order.orderNumber}.xlsx'));
            await file.writeAsBytes(excelBytes, flush: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _exportSortingFolder(String rootDir) async {
    try {
      final dao = PackingOrderSortingDao();
      final items = await dao.getAll();
      if (items.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الفرز'));
      await dir.create(recursive: true);

      final excel = Excel.createExcel();
      final sheet = excel['تقارير الفرز'];

      final headerStyle = CellStyle(
        fontSize: 11,
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#1A5276'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = ['التاريخ', 'المنتج', 'رقم اللوت', 'الوزن الأصلي', 'المتبقي', 'الوزن المباع', 'اجمالي المبيعات', 'الخزنة', 'الحالة'];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (var i = 0; i < items.length; i++) {
        final s = items[i];
        final sold = s.weightKg - s.remainingWeightKg;
        final row = i + 1;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            TextCellValue(s.createdAt != null ? DateFormat('yyyy-MM-dd').format(s.createdAt!) : '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
            TextCellValue(s.productName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
            TextCellValue(s.lotNumber ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
            DoubleCellValue(s.weightKg);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
            DoubleCellValue(s.remainingWeightKg);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
            DoubleCellValue(sold);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value =
            DoubleCellValue(s.totalSaleAmount);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value =
            TextCellValue(s.treasuryNames ?? '—');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value =
            TextCellValue(s.isSoldOut ? 'تم البيع بالكامل' : (sold > 0 ? 'مباع جزئياً' : 'متاح'));
      }

      final summary = <String, Map<String, dynamic>>{};
      for (final s in items) {
        final sold = s.weightKg - s.remainingWeightKg;
        if (sold <= 0) continue;
        if (!summary.containsKey(s.productName)) {
          summary[s.productName] = {
            'totalWeight': 0.0,
            'soldWeight': 0.0,
            'totalSale': 0.0,
            'count': 0,
          };
        }
        final entry = summary[s.productName]!;
        entry['totalWeight'] = (entry['totalWeight'] as double) + s.weightKg;
        entry['soldWeight'] = (entry['soldWeight'] as double) + sold;
        entry['totalSale'] = (entry['totalSale'] as double) + s.totalSaleAmount;
        entry['count'] = (entry['count'] as int) + 1;
      }

      if (summary.isNotEmpty) {
        final startRow = items.length + 3;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
            TextCellValue('ملخص المبيعات');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).cellStyle =
            CellStyle(bold: true, fontSize: 12);

        final sumHeaders = ['المنتج', 'العدد', 'الوزن المباع (كجم)', 'اجمالي المبيعات (ج.م)'];
        for (var i = 0; i < sumHeaders.length; i++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: startRow + 1));
          cell.value = TextCellValue(sumHeaders[i]);
          cell.cellStyle = headerStyle;
        }

        var r = startRow + 2;
        for (final entry in summary.entries) {
          final v = entry.value;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
              TextCellValue(entry.key);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value =
              IntCellValue(v['count'] as int);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value =
              DoubleCellValue(v['soldWeight'] as double);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value =
              DoubleCellValue(v['totalSale'] as double);
          r++;
        }
      }

      final bytes = excel.save();
      if (bytes != null) {
        final file = File(p.join(dir.path, 'تقرير الفرز.xlsx'));
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  Future<void> _exportRawMaterialsExcel(String rootDir) async {
    try {
      final dao = RawMaterialDao();
      final allItems = await dao.getAll();
      if (allItems.isEmpty) return;

      final items = <Map<String, dynamic>>[];
      for (final e in allItems) {
        items.add({
          'name': e.name,
          'code': e.code,
          'unit': e.unit,
          'currency': e.currency,
          'categoryName': e.categoryName ?? 'بدون فئة',
          'quantity': e.quantity,
          'totalValue': e.quantity * e.defaultPurchasePrice,
        });
      }

      final bytes = InventoryExportService.buildExcelBytes(
        title: 'المواد الخام',
        items: items,
      );
      if (bytes != null) {
        await File(p.join(rootDir, 'المواد الخام.xlsx')).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  Future<void> _exportFruitTypesExcel(String rootDir) async {
    try {
      final dao = FruitTypeDao();
      final results = await Future.wait([
        dao.getAllWithPrices(),
        dao.getWarehouseDistribution(),
        dao.getStockByFruitTypeId(),
      ]);
      final allItems = results[0] as List<FruitTypeModel>;
      final warehouseDistribution = results[1] as Map<String, List<Map<String, dynamic>>>;
      final stockByTypeId = results[2] as Map<int, double>;
      if (allItems.isEmpty) return;

      for (final item in allItems) {
        final idInt = int.tryParse(item.id ?? '');
        if (idInt == null) continue;
        final directStock = stockByTypeId[idInt];
        if (directStock != null && directStock > 0) {
          item.totalStockQuantity = directStock;
        }
      }

      double totalQuantityForItem(FruitTypeModel item) {
        final dist = warehouseDistribution[item.name] ?? [];
        final distQty = dist.fold<double>(0, (sum, d) => sum + (d['quantity'] as double? ?? 0));
        if (distQty > 0) return distQty;
        if (item.totalStockQuantity != null && item.totalStockQuantity! > 0) {
          return item.totalStockQuantity!;
        }
        if (item.totalQuantity != null && item.totalQuantity! > 0) {
          return item.totalQuantity!;
        }
        return 0;
      }

      final items = <Map<String, dynamic>>[];
      for (final e in allItems) {
        final isCarton = (e.purchaseMode ?? e.latestPurchaseMode) == 'carton';
        final mode = e.purchaseMode ?? e.latestPurchaseMode ?? 'weight';
        final qty = totalQuantityForItem(e);
        final price =
            (e.averagePurchasePrice ?? e.latestPurchasePrice ?? 0.0).toDouble();
        final value = e.totalStockValue != null && e.totalStockValue! > 0
            ? e.totalStockValue!
            : qty * price;
        items.add({
          'name': e.name,
          'code': e.code,
          'categoryName': mode == 'carton' ? 'بالكراتين' : 'بالوزن',
          'unit': isCarton ? 'كرتونة' : 'كجم',
          'currency': e.currency,
          'quantity': qty,
          'totalValue': value,
        });
      }

      final bytes = InventoryExportService.buildExcelBytes(
        title: 'أصناف الفاكهة',
        items: items,
      );
      if (bytes != null) {
        await File(p.join(rootDir, 'أصناف الفاكهة.xlsx')).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  // الفواتير و الارباح
  // ═══════════════════════════════════════════════════
  Future<void> _exportInvoicesAndProfitsSection(String rootDir, BackupProgressCallback onProgress) async {
    final dir = Directory(p.join(rootDir, 'الفواتير و الارباح'));
    await dir.create(recursive: true);
    int step = 0, total = 5;

    onProgress('الفواتير و الارباح', 'جاري تصدير الشحنات التصديرية...', ++step, total);
    await _exportShipmentsFolder(dir.path);

    onProgress('الفواتير و الارباح', 'جاري تصدير الفواتير المبدئية...', ++step, total);
    await _exportProformaInvoicesFolder(dir.path);

    onProgress('الفواتير و الارباح', 'جاري تصدير تقارير الربحية...', ++step, total);
    await _exportProfitabilityFolder(dir.path);

    onProgress('الفواتير و الارباح', 'جاري تصدير توزيع الأرباح...', ++step, total);
    await _exportProfitDistributionFolder(dir.path);

    onProgress('الفواتير و الارباح', 'جاري تصدير تقارير التكاليف...', ++step, total);
    await _exportCostReportsFolder(dir.path);
  }

  Future<void> _exportShipmentsFolder(String rootDir) async {
    try {
      final dao = ExportShipmentDao();
      final shipments = await dao.getAll(limit: 10000);
      if (shipments.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الشحنات التصديرية'));
      await dir.create(recursive: true);

      for (final shipment in shipments) {
        try {
          final rawItems = await ExportShipmentItemDao().getByShipmentId(shipment.id!);
          final items = rawItems.map((r) => {
            'product_name': (r['invoice_product_name']?.toString().isNotEmpty == true)
                ? r['invoice_product_name']
                : r['product_name'],
            'qty': r['quantity'],
            'exportPricePerCarton': r['export_price_per_carton'] ?? r['price'],
            'netWt': r['net_weight'],
            'grossWt': r['gross_weight'],
            'amount': r['amount'],
          }).toList();

          CustomerModel? customer;
          if (shipment.customerId != null && shipment.customerId!.isNotEmpty) {
            try { customer = await CustomerDao().getById(shipment.customerId!); } catch (_) {}
          }
          ClearingAgentModel? clearingAgent;
          if (shipment.clearingAgentId != null && shipment.clearingAgentId!.isNotEmpty) {
            try {
              final data = await Supabase.instance.client
                  .from('clearing_agents')
                  .select()
                  .eq('id', shipment.clearingAgentId!)
                  .maybeSingle();
              if (data != null) clearingAgent = ClearingAgentModel.fromMap(data);
            } catch (_) {}
          }

          final doc = await InvoicePdfService.generate(
            shipment,
            itemsData: items,
            customer: customer,
            clearingAgent: clearingAgent,
          );
          final bytes = await doc.save();
          final no = (shipment.shipmentNo ?? 'unknown').replaceAll('/', '-');
          final file = File(p.join(dir.path, 'شحنة $no.pdf'));
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _exportProformaInvoicesFolder(String rootDir) async {
    try {
      final dao = ProformaInvoiceDao();
      final invoices = await dao.getAll(limit: 10000);
      if (invoices.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'الفواتير المبدئية'));
      await dir.create(recursive: true);

      for (final invoice in invoices) {
        try {
          final items = await dao.getItems(invoice.id);

          CustomerModel? customer;
          if (invoice.customerId != null && invoice.customerId!.isNotEmpty) {
            try {
              final custData = await Supabase.instance.client
                  .from('customers')
                  .select()
                  .eq('id', invoice.customerId!)
                  .maybeSingle();
              if (custData != null) customer = CustomerModel.fromMap(custData);
            } catch (_) {}
          }
          ClearingAgentModel? clearingAgent;
          if (invoice.clearingAgentId != null && invoice.clearingAgentId!.isNotEmpty) {
            try {
              final agentData = await Supabase.instance.client
                  .from('clearing_agents')
                  .select()
                  .eq('id', invoice.clearingAgentId!)
                  .maybeSingle();
              if (agentData != null) clearingAgent = ClearingAgentModel.fromMap(agentData);
            } catch (_) {}
          }

          final doc = await ProformaInvoicePdfService.generate(
            invoice,
            items: items,
            customer: customer,
            clearingAgent: clearingAgent,
          );
          final bytes = await doc.save();
          final no = invoice.invoiceNo.replaceAll('/', '-');
          final file = File(p.join(dir.path, 'فاتورة مبدئية $no.pdf'));
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _exportProfitabilityFolder(String rootDir) async {
    try {
      final dir = Directory(p.join(rootDir, 'الربحية'));
      await dir.create(recursive: true);

      final dao = ExportShipmentDao();
      final shipments = await dao.getAll(limit: 10000, excludeStatus: 'cancelled');
      if (shipments.isEmpty) return;

      final costItemDao = ShipmentCostItemDao();
      final packingDao = PackingOrderDao();
      final client = Supabase.instance.client;

      for (final shipment in shipments) {
        try {
          final shipmentId = int.parse(shipment.id!);

          final results = await Future.wait<dynamic>([
            costItemDao.getForShipment(shipmentId),
            packingDao.getByShipmentIdViaItems(shipmentId),
            ExportShipmentItemDao().getByShipmentId(shipment.id!),
            client.rpc('list_cost_report_categories', params: {'p_scope': 'shipment'}).then((v) => v as List),
          ]);

          var items = results[0] as List<ShipmentCostItemModel>;
          final packingOrders = results[1] as List<PackingOrderModel>;
          final shipmentItems = results[2] as List<Map<String, dynamic>>;
          final cats = (results[3] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .where((c) => c['name'] != 'مصاريف إدارية')
              .toList();

          double liveRevenue = 0.0;
          for (final item in shipmentItems) {
            final qty = int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
            final ep = double.tryParse(
                    item['export_price_per_carton']?.toString() ?? '0') ??
                0;
            liveRevenue += qty * ep;
          }

          double avgPackingCost = 0.0;
          if (packingOrders.isNotEmpty) {
            double totalPoCost = 0.0;
            int totalPoCartons = 0;
            for (final po in packingOrders) {
              totalPoCost += po.packingCostPerCarton * po.cartonCount;
              totalPoCartons += po.cartonCount;
            }
            avgPackingCost = totalPoCartons > 0 ? totalPoCost / totalPoCartons : packingOrders.first.packingCostPerCarton;
          }

          int? cartonCostCatId;
          try {
            final cat = cats.firstWhere(
                (c) => c['name'] == 'تكلفة الكراتين' || c['name'] == 'تكلفة كراتين',
                orElse: () => <String, dynamic>{});
            if (cat.isNotEmpty) cartonCostCatId = cat['id'];
          } catch (_) {}

          items.removeWhere((i) => i.description == 'تكلفة كراتين الشحنة' || i.description.contains('أمر تعبئة رقم'));

          if (shipment.cartonsCount > 0 && avgPackingCost > 0) {
            String poDesc = 'تكلفة الكراتين';
            if (packingOrders.isNotEmpty) {
              poDesc = packingOrders.map((po) => '${po.productName ?? 'محصول'} - أمر تعبئة رقم: ${po.orderNumber}').join(' ، ');
            }
            items.add(ShipmentCostItemModel(
              shipmentId: shipmentId,
              reportCategoryId: cartonCostCatId,
              reportCategoryName: 'تكلفة الكراتين',
              category: 'packing',
              description: poDesc,
              quantity: shipment.cartonsCount.toDouble(),
              unitPrice: avgPackingCost,
              totalPrice: avgPackingCost * shipment.cartonsCount,
              isReadOnly: true,
            ));
          }

          final rate = shipment.exchangeRate > 0 ? shipment.exchangeRate : 1.0;
          final currency = shipment.currency ?? shipment.currencyCode ?? 'EGP';
          final cartonCount = shipment.cartonsCount;
          final discountEgp = shipment.discountAmount * rate;
          final allocatedAdmin = shipment.allocatedAdminExpenses;
          final allocatedTaxes = shipment.allocatedTaxes;

          final totalRevenueForeign = liveRevenue > 0 ? liveRevenue : shipment.totalRevenueForeign;
          final totalRevenueEgp = totalRevenueForeign * rate;
          final totalCostEgp = items.fold(0.0, (s, i) => s + i.totalPrice) + discountEgp + allocatedAdmin + allocatedTaxes;
          final netProfitEgp = totalRevenueEgp - discountEgp - totalCostEgp;
          final revAfterDiscount = totalRevenueEgp - discountEgp;
          final margin = revAfterDiscount > 0 ? (netProfitEgp / revAfterDiscount * 100) : 0.0;

          final revPerCartonForeign = cartonCount == 0 ? 0.0 : (totalRevenueForeign / cartonCount);
          final revPerCartonEgp = cartonCount == 0 ? 0.0 : (totalRevenueEgp / cartonCount);
          final costPerCartonEgp = cartonCount == 0 ? 0.0 : (totalCostEgp / cartonCount);
          final costPerCartonForeign = cartonCount == 0 ? 0.0 : (costPerCartonEgp / rate);
          final grossPerCartonForeign = revPerCartonForeign - costPerCartonForeign;
          final grossPerCartonEgp = revPerCartonEgp - costPerCartonEgp;

          final doc = await ShipmentCostPdfService.generatePdf(
            s: shipment,
            items: items,
            revForeign: totalRevenueForeign,
            revEgp: totalRevenueEgp,
            totalCostEgp: totalCostEgp,
            netProfitEgp: netProfitEgp,
            margin: margin,
            revPerCartonForeign: revPerCartonForeign,
            costPerCartonForeign: costPerCartonForeign,
            grossPerCartonForeign: grossPerCartonForeign,
            revPerCartonEgp: revPerCartonEgp,
            costPerCartonEgp: costPerCartonEgp,
            grossPerCartonEgp: grossPerCartonEgp,
            currency: currency,
            discount: discountEgp,
          );
          final bytes = await doc.save();
          final no = (shipment.shipmentNo ?? 'unknown').replaceAll('/', '-');
          final file = File(p.join(dir.path, 'ربحية شحنة $no.pdf'));
          await file.writeAsBytes(bytes, flush: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _exportProfitDistributionFolder(String rootDir) async {
    try {
      final dir = Directory(p.join(rootDir, 'توزيع الأرباح'));
      await dir.create(recursive: true);

      final dao = ProfitDistributionDao();
      final shareholderDao = ShareholderDao();
      final shipmentDao = ExportShipmentDao();

      final results = await Future.wait([
        shipmentDao.getAll(limit: 10000, excludeStatus: 'cancelled'),
        shareholderDao.getAll(limit: 200),
        dao.getSettings(),
      ]);

      final shipments = results[0] as List;
      final shareholders = results[1] as List;
      final settings = results[2] as Map<String, dynamic>?;

      if (shipments.isEmpty || settings == null) return;

      ShareholderModel? person1, person2, person3;
      final p1Id = settings['person1_id']?.toString();
      final p2Id = settings['person2_id']?.toString();
      final p3Id = settings['person3_id']?.toString();

      if (p1Id != null) {
        person1 = shareholders.where((s) => s.id == p1Id).firstOrNull;
      }
      if (p2Id != null) {
        person2 = shareholders.where((s) => s.id == p2Id).firstOrNull;
      }
      if (p3Id != null) {
        person3 = shareholders.where((s) => s.id == p3Id).firstOrNull;
      }

      final Map<String, List<double>> percentages = {};
      final pctRaw = settings['percentages'];
      if (pctRaw != null) {
        Map<String, dynamic> pctData = {};
        if (pctRaw is String) {
          pctData = jsonDecode(pctRaw) as Map<String, dynamic>;
        } else if (pctRaw is Map) {
          pctData = Map<String, dynamic>.from(pctRaw);
        }
        for (final entry in pctData.entries) {
          final vals = (entry.value as List).map((e) => (e as num).toDouble()).toList();
          while (vals.length < 4) vals.add(0.0);
          percentages[entry.key] = vals;
        }
      }

      final Map<String, Map<String, dynamic>> currencyConversions = {};
      final convRaw = settings['currency_conversions'];
      if (convRaw != null && convRaw is Map) {
        for (final entry in convRaw.entries) {
          if (entry.value is Map) {
            final shipmentConvs = <String, dynamic>{};
            for (final innerEntry in (entry.value as Map).entries) {
              shipmentConvs[innerEntry.key.toString()] = innerEntry.value;
            }
            currencyConversions[entry.key.toString()] = shipmentConvs;
          }
        }
      }

      for (final s in shipments) {
        final sid = s.id ?? '';
        if (!percentages.containsKey(sid)) {
          percentages[sid] = [33.33, 33.33, 33.34, 0.0];
        }
      }

      String convertedLabel(String sid, int personIndex, double share) {
        final shipmentConvs = currencyConversions[sid];
        final conv = shipmentConvs?[personIndex.toString()];
        final cur = conv?['currency']?.toString();
        final rate = (conv?['rate'] as num?)?.toDouble() ?? 0;
        if (cur != null && rate > 0 && share > 0) {
          final converted = CurrencyConversionService.instance.fromBase(share, cur, rate);
          return '$cur ${converted.toStringAsFixed(2)}';
        }
        return 'EGP ${share.toStringAsFixed(2)}';
      }

      final excel = Excel.createExcel();
      final sheet = excel['توزيع الأرباح'];
      excel.setDefaultSheet(sheet.sheetName);

      sheet.appendRow([
        TextCellValue('رقم الشحنة'),
        TextCellValue('التاريخ'),
        TextCellValue('صافي الربح (EGP)'),
        TextCellValue('${person1?.name ?? ''} %'),
        TextCellValue(person1?.name ?? ''),
        TextCellValue('${person2?.name ?? ''} %'),
        TextCellValue(person2?.name ?? ''),
        TextCellValue('${person3?.name ?? ''} %'),
        TextCellValue(person3?.name ?? ''),
        TextCellValue('الشخص 4 %'),
        TextCellValue('الشخص 4'),
      ]);

      for (final s in shipments) {
        final profit = s.netProfitEgp;
        final sid = s.id ?? '';
        final p = percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
        final sum3 = p[0] + p[1] + p[2];
        final autoPct4 = (100.0 - sum3) < 0 ? 0.0 : 100.0 - sum3;

        final share0 = profit * p[0] / 100.0;
        final share1 = profit * p[1] / 100.0;
        final share2 = profit * p[2] / 100.0;
        final share3 = profit * autoPct4 / 100.0;

        sheet.appendRow([
          TextCellValue(AppUtils.cleanShipmentNo(s.shipmentNo, s.id)),
          TextCellValue(s.shipmentDate != null ? '${s.shipmentDate!.day}/${s.shipmentDate!.month}/${s.shipmentDate!.year}' : '—'),
          DoubleCellValue(profit),
          DoubleCellValue(p[0]),
          TextCellValue(convertedLabel(sid, 0, share0)),
          DoubleCellValue(p[1]),
          TextCellValue(convertedLabel(sid, 1, share1)),
          DoubleCellValue(p[2]),
          TextCellValue(convertedLabel(sid, 2, share2)),
          DoubleCellValue(autoPct4),
          TextCellValue(convertedLabel(sid, 3, share3)),
        ]);
      }

      double totalProfit = 0;
      double totalP0 = 0, totalP1 = 0, totalP2 = 0, totalP3 = 0;
      for (final s in shipments) {
        final profit = s.netProfitEgp;
        final sid = s.id ?? '';
        final p = percentages[sid] ?? [0.0, 0.0, 0.0, 0.0];
        final sum3 = p[0] + p[1] + p[2];
        final autoPct4 = (100.0 - sum3) < 0 ? 0.0 : 100.0 - sum3;

        totalProfit += profit;
        totalP0 += profit * p[0] / 100.0;
        totalP1 += profit * p[1] / 100.0;
        totalP2 += profit * p[2] / 100.0;
        totalP3 += profit * autoPct4 / 100.0;
      }

      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('الإجمالي'),
        TextCellValue(''),
        DoubleCellValue(totalProfit),
        TextCellValue(''),
        TextCellValue('EGP ${totalP0.toStringAsFixed(2)}'),
        TextCellValue(''),
        TextCellValue('EGP ${totalP1.toStringAsFixed(2)}'),
        TextCellValue(''),
        TextCellValue('EGP ${totalP2.toStringAsFixed(2)}'),
        TextCellValue(''),
        TextCellValue('EGP ${totalP3.toStringAsFixed(2)}'),
      ]);

      for (int i = 0; i < 11; i++) {
        sheet.setColumnWidth(i, 22);
      }

      final bytes = excel.save();
      if (bytes != null) {
        final now = DateTime.now();
        final fileName = 'profit_distribution_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.xlsx';
        await File(p.join(dir.path, fileName)).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  String _costReportMajorCategory(Map<String, dynamic> row) {
    final name = (row['item_name'] as String? ?? '').toLowerCase();
    final cat = (row['category'] as String? ?? '').trim();
    final catLower = cat.toLowerCase();

    if (name.contains('محصول') || catLower == 'crop' || catLower == 'manual_crop') return 'المحاصيل';
    if (catLower == 'packing' || catLower == 'manual_packing' || catLower == 'packaging' || catLower == 'packing_material' || name.contains('تعبئة') || name.contains('ورق') || name.contains('كراتين')) return 'مواد التعبئة';
    if (name.contains('شحن') || catLower == 'shipping') return 'الشحن';
    if (name.contains('تخليص') || catLower == 'clearance') return 'التخليص';
    if (catLower == 'general') return 'أخرى';
    if (cat.isEmpty) return 'أخرى';
    return cat;
  }

  String _costReportCurrencyName(String? code) {
    if (code == null) return 'EGP';
    switch (code.toUpperCase()) {
      case 'USD': return 'USD';
      case 'EUR': return 'EURO';
      case 'GBP': return 'GBP';
      case 'EGP': return 'EGP';
      default: return code;
    }
  }

  Future<void> _exportCostReportsFolder(String rootDir) async {
    try {
      final dao = CostReportDao();
      final allDetails = await dao.getDetails();
      if (allDetails.isEmpty) return;

      final dir = Directory(p.join(rootDir, 'تقارير التكاليف'));
      await dir.create(recursive: true);

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final row in allDetails) {
        final major = _costReportMajorCategory(row);
        grouped.putIfAbsent(major, () => []).add(row);
      }

      for (final entry in grouped.entries) {
        final catName = entry.key;
        final rows = entry.value;
        if (rows.isEmpty) continue;

        final excel = Excel.createExcel();
        final sheet = excel['تفاصيل التكاليف'];
        excel.setDefaultSheet(sheet.sheetName);

        sheet.appendRow([
          TextCellValue('التاريخ'),
          TextCellValue('رقم الشحنة'),
          TextCellValue('العميل'),
          TextCellValue('البيان'),
          TextCellValue('الكمية'),
          TextCellValue('سعر الوحدة'),
          TextCellValue('سعر الصرف'),
          TextCellValue('الإجمالي بالعملة'),
          TextCellValue('الإجمالي بالمصري'),
        ]);

        double totalQty = 0;
        double totalAmount = 0;

        for (final r in rows) {
          final date = r['shipment_date']?.toString() ?? '';
          final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
          final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
          final amount = (r['amount'] as num?)?.toDouble() ?? 0;
          final exchangeRate = (r['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          final actualExRate = exchangeRate == 0 ? 1.0 : exchangeRate;
          final totalInCurrency = (r['total_in_currency'] as num?)?.toDouble() ?? amount;
          final unitPriceForeign = qty > 0 ? totalInCurrency / qty : 0.0;
          final currency = _costReportCurrencyName(r['currency']?.toString());

          totalQty += qty;
          totalAmount += amount;

          sheet.appendRow([
            TextCellValue(dateStr),
            TextCellValue('\u200E${r['shipment_no']?.toString() ?? ''}'),
            TextCellValue(r['customer_name']?.toString() ?? ''),
            TextCellValue(r['item_name']?.toString() ?? ''),
            DoubleCellValue(qty),
            TextCellValue('$currency ${unitPriceForeign.toStringAsFixed(2)}'),
            DoubleCellValue(actualExRate),
            TextCellValue('$currency ${totalInCurrency.toStringAsFixed(2)}'),
            DoubleCellValue(amount),
          ]);
        }

        sheet.appendRow([
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('الإجمالي'),
          DoubleCellValue(totalQty),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          DoubleCellValue(totalAmount),
        ]);

        final bytes = excel.save();
        if (bytes != null) {
          await File(p.join(dir.path, '$catName.xlsx')).writeAsBytes(bytes, flush: true);
        }
      }
    } catch (_) {}
  }
}
