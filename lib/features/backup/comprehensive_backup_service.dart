import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../suppliers/supplier_account_statement_cubit.dart';
import '../exports/export_customer_statement_cubit.dart';
import '../shareholders/shareholder_statement_cubit.dart';
import '../clearing_agents/clearing_agent_statement_cubit.dart';
import '../shipping_companies/shipping_company_statement_cubit.dart';
import '../../core/statement_excel_service.dart';
import '../../core/statement_pdf_service.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/services/full_excel_export_service.dart';
import '../suppliers/supplier_account_statement_state.dart';
import '../exports/export_customer_statement_state.dart';
import '../shareholders/shareholder_statement_state.dart';
import '../clearing_agents/clearing_agent_statement_state.dart';
import '../shipping_companies/shipping_company_statement_state.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

typedef BackupProgressCallback = void Function(String taskName, int current, int total);

class ComprehensiveBackupService {
  Future<void> startBackup({required BackupProgressCallback onProgress}) async {
    try {
      final docDir = await FileHelper.getExportDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final rootDir = Directory('${docDir.path}/ERP_Backup_$timestamp');
      await rootDir.create(recursive: true);

      final suppliersDir = Directory('${rootDir.path}/الموردين');
      final customersDir = Directory('${rootDir.path}/العملاء');
      final accountsDir = Directory('${rootDir.path}/الحسابات');
      final inventoryDir = Directory('${rootDir.path}/المخازن والعمليات');

      await suppliersDir.create();
      await customersDir.create();
      await accountsDir.create();
      await inventoryDir.create();

      int totalSteps = 6;
      int currentStep = 0;

      // 1. Export Supplier Statements
      onProgress('جاري تحضير الموردين...', currentStep, totalSteps);
      await _exportSuppliers(suppliersDir.path, (name, c, t) {
        onProgress('مورد: $name', currentStep, totalSteps);
      });
      currentStep++;

      // 2. Export Customer Statements
      onProgress('جاري تحضير العملاء...', currentStep, totalSteps);
      await _exportCustomers(customersDir.path, (name, c, t) {
        onProgress('عميل: $name', currentStep, totalSteps);
      });
      currentStep++;

      // 3. Export Shareholders
      onProgress('جاري تحضير الشركاء...', currentStep, totalSteps);
      await _exportShareholders(accountsDir.path);
      currentStep++;

      // 4. Export Clearing Agents
      onProgress('جاري تحضير المخلصين...', currentStep, totalSteps);
      await _exportClearingAgents(accountsDir.path);
      currentStep++;

      // 5. Export Shipping Companies
      onProgress('جاري تحضير شركات الشحن...', currentStep, totalSteps);
      await _exportShippingCompanies(accountsDir.path);
      currentStep++;

      // 6. Full Database Backup
      onProgress('جاري استخراج قاعدة البيانات كاملة...', currentStep, totalSteps);
      final fullExportService = FullExcelExportService();
      await fullExportService.exportAll(
        customDirectory: rootDir.path,
      );
      currentStep++;

      onProgress('اكتمل النسخ الاحتياطي بنجاح', currentStep, totalSteps);

    } catch (e) {
      throw Exception('فشل النسخ الاحتياطي: $e');
    }
  }

  Future<void> _exportSuppliers(String dirPath, void Function(String, int, int) onProgress) async {
    final cubit = SupplierAccountStatementCubit();
    await cubit.init();
    final state = cubit.state;
    if (state is! SupplierAccountStatementLoaded) return;

    final suppliers = state.suppliers;
    for (int i = 0; i < suppliers.length; i++) {
      final s = suppliers[i];
      onProgress(s.name, i + 1, suppliers.length);
      await cubit.selectSupplier(s);
      
      final st = cubit.state;
      if (st is SupplierAccountStatementLoaded && st.statementRows.isNotEmpty) {
        await StatementExcelService.saveToFile(
          title: 'كشف حساب مورد',
          vendorName: s.name,
          vendorCode: s.supplierCode,
          currency: 'EGP',
          rows: st.statementRows,
          totalDebit: st.totalDebit,
          totalCredit: st.totalCredit,
          finalBalance: st.finalBalance,
          statementNumber: 1,
          locale: 'ar',
          customDirectory: dirPath,
        );
        await StatementPdfService.saveToFile(
          title: 'كشف حساب مورد',
          vendorName: s.name,
          vendorCode: s.supplierCode,
          currency: 'EGP',
          rows: st.statementRows,
          totalDebit: st.totalDebit,
          totalCredit: st.totalCredit,
          finalBalance: st.finalBalance,
          statementNumber: 1,
          locale: 'ar',
          customDirectory: dirPath,
        );
      }
    }
    await cubit.close();
  }

  Future<void> _exportCustomers(String dirPath, void Function(String, int, int) onProgress) async {
    final cubit = ExportCustomerStatementCubit();
    await cubit.init();
    final state = cubit.state;
    if (state is! ExportCustomerStatementLoaded) return;

    final customers = state.customers;
    for (int i = 0; i < customers.length; i++) {
      final c = customers[i];
      onProgress(c.name, i + 1, customers.length);
      await cubit.selectCustomer(c);
      
      final st = cubit.state;
      if (st is ExportCustomerStatementLoaded && st.statementRows.isNotEmpty) {
        await StatementExcelService.saveToFile(
          title: 'كشف حساب عميل',
          vendorName: c.name,
          vendorCode: c.code,
          currency: 'USD',
          rows: st.statementRows,
          totalDebit: st.totalDebit,
          totalCredit: st.totalCredit,
          finalBalance: st.finalBalance,
          statementNumber: 1,
          locale: 'ar',
          customDirectory: dirPath,
        );
      }
    }
    await cubit.close();
  }

  Future<void> _exportShareholders(String dirPath) async {
    final cubit = ShareholderStatementCubit();
    await cubit.init();
    final state = cubit.state;
    const currencies = ['EGP', 'USD', 'EUR', 'GBP'];

    final list = state.shareholders;
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      await cubit.selectShareholder(item);
      for (final cur in currencies) {
        cubit.setCurrency(cur);
        await cubit.loadStatement();
        final st = cubit.state;
        if (st.rows.isNotEmpty) {
          await StatementExcelService.saveToFile(
            title: 'كشف حساب شريك',
            vendorName: item.name,
            vendorCode: item.code,
            currency: cur,
            rows: st.rows,
            totalDebit: st.totalDebit,
            totalCredit: st.totalCredit,
            finalBalance: st.finalBalance,
            statementNumber: 1,
            locale: 'ar',
            customDirectory: dirPath,
          );
        }
      }
    }
    await cubit.close();
  }

  Future<void> _exportClearingAgents(String dirPath) async {
    final cubit = ClearingAgentStatementCubit();
    await cubit.init();
    final state = cubit.state;
    if (state is! ClearingAgentStatementLoaded) return;

    final list = state.agents;
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      await cubit.selectAgent(item);
      final st = cubit.state;
      if (st is ClearingAgentStatementLoaded && st.statementRows.isNotEmpty) {
        await StatementExcelService.saveToFile(
          title: 'كشف حساب مخلص',
          vendorName: item.name,
          vendorCode: item.code,
          currency: 'EGP',
          rows: st.statementRows,
          totalDebit: st.totalDebit,
          totalCredit: st.totalCredit,
          finalBalance: st.finalBalance,
          statementNumber: 1,
          locale: 'ar',
          customDirectory: dirPath,
        );
      }
    }
    await cubit.close();
  }

  Future<void> _exportShippingCompanies(String dirPath) async {
    final cubit = ShippingCompanyStatementCubit();
    await cubit.init();
    final state = cubit.state;
    if (state is! ShippingCompanyStatementLoaded) return;

    final list = state.companies;
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      await cubit.selectCompany(item);
      final st = cubit.state;
      if (st is ShippingCompanyStatementLoaded && st.statementRows.isNotEmpty) {
        await StatementExcelService.saveToFile(
          title: 'كشف حساب شركة شحن',
          vendorName: item.name,
          vendorCode: item.code,
          currency: 'USD',
          rows: st.statementRows,
          totalDebit: st.totalDebit,
          totalCredit: st.totalCredit,
          finalBalance: st.finalBalance,
          statementNumber: 1,
          locale: 'ar',
          customDirectory: dirPath,
        );
      }
    }
    await cubit.close();
  }
}
