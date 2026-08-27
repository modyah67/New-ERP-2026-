import 'package:supabase_flutter/supabase_flutter.dart';
import 'injection.dart';
// Fiscal Year
import '../accounting/fiscal_year/dao/fiscal_year_dao.dart';
import '../accounting/fiscal_year/services/fiscal_year_service.dart';
import '../accounting/fiscal_year/services/fiscal_year_closing_engine.dart';
import '../accounting/fiscal_year/services/closing_validation_service.dart';
import '../accounting/fiscal_year/services/closing_audit_service.dart';
import '../accounting/fiscal_year/services/closing_report_service.dart';
import '../accounting/fiscal_year/services/health_check_service.dart';
import '../accounting/fiscal_year/services/consistency_scanner.dart';
import '../accounting/fiscal_year/services/progress_service.dart';
import '../accounting/fiscal_year/services/notification_service.dart';
import '../accounting/fiscal_year/services/dry_run_service.dart';
import '../accounting/fiscal_year/services/readiness_report_service.dart';
import '../accounting/fiscal_year/services/diagnostics_service.dart';
import '../accounting/fiscal_year/services/production_validator.dart';
import '../accounting/fiscal_year/cubit/fiscal_year_cubit.dart';

// Repositories
import '../data/repositories/auth_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/purchase_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/repositories/export_repository.dart';
import '../data/repositories/supplier_repository.dart';
import '../data/repositories/dashboard_repository.dart';

// Auth
import '../features/auth/auth_cubit.dart';

// Customers
import '../features/customers/customer_cubit.dart';

// Suppliers
import '../features/suppliers/supplier_cubit.dart';

// Invoices
import '../features/invoices/invoice_cubit.dart';

// Purchases
import '../features/purchases/purchase_cubit.dart';

// Accounts
import '../features/accounting/account_cubit.dart';
import '../features/accounting/cashbox_cubit.dart';
import '../features/accounting/accounting_cubit.dart';
import '../features/accounting/cash_receipt_cubit.dart';
import '../features/accounting/cash_payment_cubit.dart';

// Statements
import '../features/statements/statement_cubit.dart';
import '../features/statements/supplier_statement_cubit.dart';
import '../features/statements/brief_statement_cubit.dart';

// Reports
import '../features/reports/report_cubit.dart';

// Settings
import '../features/settings/settings_cubit.dart';

// Clearing Agents
import '../features/clearing_agents/clearing_agent_cubit.dart';

// Shipping Companies
import '../features/shipping_companies/shipping_company_cubit.dart';

// Stations
import '../features/stations/station_cubit.dart';

// Transfers
import '../features/transfers/transfer_cubit.dart';

// Journal Entry
import '../features/journal_entry/journal_entry_cubit.dart';

// User Management
import '../features/user_management/user_management_cubit.dart';

// Cheques
import '../features/cheques/cheque_cubit.dart';

// Export Customer Statement
import '../features/exports/export_customer_statement_cubit.dart';

// Dashboard
import '../data/dao/dashboard_dao.dart';
import '../features/dashboard/dashboard_cubit.dart';

// Reporting Foundation
import '../accounting/reporting/dao/report_dao.dart';
import '../accounting/reporting/services/report_calculation_service.dart';
import '../accounting/reporting/services/report_filter_service.dart';
import '../accounting/reporting/services/report_validation_service.dart';

// Trial Balance
import '../features/trial_balance/trial_balance_cubit.dart';
import '../features/balance_sheet/balance_sheet_cubit.dart';
import '../features/income_statement/income_statement_cubit.dart';
import '../features/cash_flow/cash_flow_cubit.dart';

// General Ledger
import '../features/general_ledger/general_ledger_cubit.dart';

void registerDependencies() {
  if (!sl.isRegistered<SupabaseClient>()) {
    sl.registerLazySingleton<SupabaseClient>(
      () => Supabase.instance.client,
    );
  }

  if (!sl.isRegistered<AuthRepository>()) {
    sl.registerLazySingleton<AuthRepository>(
      () => AuthRepository(client: sl<SupabaseClient>()),
    );
  }

  if (!sl.isRegistered<InventoryRepository>()) {
    sl.registerLazySingleton<InventoryRepository>(() => InventoryRepository());
  }

  if (!sl.isRegistered<PurchaseRepository>()) {
    sl.registerLazySingleton<PurchaseRepository>(() => PurchaseRepository());
  }

  if (!sl.isRegistered<SalesRepository>()) {
    sl.registerLazySingleton<SalesRepository>(() => SalesRepository());
  }

  if (!sl.isRegistered<ExportRepository>()) {
    sl.registerLazySingleton<ExportRepository>(() => ExportRepository());
  }

  if (!sl.isRegistered<SupplierRepository>()) {
    sl.registerLazySingleton<SupplierRepository>(() => SupplierRepository());
  }

  if (!sl.isRegistered<DashboardRepository>()) {
    sl.registerLazySingleton<DashboardRepository>(() => DashboardRepository());
  }

  if (!sl.isRegistered<AuthCubit>()) {
    sl.registerFactory<AuthCubit>(
      () => AuthCubit(repository: sl<AuthRepository>()),
    );
  }

  if (!sl.isRegistered<CustomerCubit>()) {
    sl.registerFactory<CustomerCubit>(() => CustomerCubit());
  }

  if (!sl.isRegistered<SupplierCubit>()) {
    sl.registerFactory<SupplierCubit>(() => SupplierCubit());
  }

  if (!sl.isRegistered<InvoiceCubit>()) {
    sl.registerFactory<InvoiceCubit>(() => InvoiceCubit(type: 'sale'));
  }

  if (!sl.isRegistered<PurchaseCubit>()) {
    sl.registerFactory<PurchaseCubit>(() => PurchaseCubit());
  }

  if (!sl.isRegistered<AccountCubit>()) {
    sl.registerFactory<AccountCubit>(() => AccountCubit());
  }

  if (!sl.isRegistered<CashboxCubit>()) {
    sl.registerFactory<CashboxCubit>(() => CashboxCubit());
  }

  if (!sl.isRegistered<AccountingCubit>()) {
    sl.registerFactory<AccountingCubit>(() => AccountingCubit());
  }

  if (!sl.isRegistered<CashReceiptCubit>()) {
    sl.registerFactory<CashReceiptCubit>(() => CashReceiptCubit());
  }

  if (!sl.isRegistered<CashPaymentCubit>()) {
    sl.registerFactory<CashPaymentCubit>(() => CashPaymentCubit());
  }

  if (!sl.isRegistered<StatementCubit>()) {
    sl.registerFactory<StatementCubit>(() => StatementCubit());
  }

  if (!sl.isRegistered<SupplierStatementCubit>()) {
    sl.registerFactory<SupplierStatementCubit>(
        () => SupplierStatementCubit());
  }

  if (!sl.isRegistered<BriefStatementCubit>()) {
    sl.registerFactory<BriefStatementCubit>(() => BriefStatementCubit());
  }

  if (!sl.isRegistered<ReportCubit>()) {
    sl.registerFactory<ReportCubit>(() => ReportCubit());
  }

  if (!sl.isRegistered<SettingsCubit>()) {
    sl.registerFactory<SettingsCubit>(() => SettingsCubit());
  }

  if (!sl.isRegistered<ClearingAgentCubit>()) {
    sl.registerFactory<ClearingAgentCubit>(() => ClearingAgentCubit());
  }

  if (!sl.isRegistered<ShippingCompanyCubit>()) {
    sl.registerFactory<ShippingCompanyCubit>(() => ShippingCompanyCubit());
  }

  if (!sl.isRegistered<StationCubit>()) {
    sl.registerFactory<StationCubit>(() => StationCubit());
  }

  if (!sl.isRegistered<TransferCubit>()) {
    sl.registerFactory<TransferCubit>(() => TransferCubit());
  }

  if (!sl.isRegistered<JournalEntryCubit>()) {
    sl.registerFactory<JournalEntryCubit>(() => JournalEntryCubit());
  }

  if (!sl.isRegistered<UserManagementCubit>()) {
    sl.registerFactory<UserManagementCubit>(() => UserManagementCubit());
  }

  if (!sl.isRegistered<ChequeCubit>()) {
    sl.registerFactory<ChequeCubit>(() => ChequeCubit());
  }

  if (!sl.isRegistered<ExportCustomerStatementCubit>()) {
    sl.registerFactory<ExportCustomerStatementCubit>(
        () => ExportCustomerStatementCubit());
  }

  if (!sl.isRegistered<DashboardDao>()) {
    sl.registerLazySingleton<DashboardDao>(() => DashboardDao());
  }

  if (!sl.isRegistered<DashboardCubit>()) {
    sl.registerFactory<DashboardCubit>(
      () => DashboardCubit(sl<DashboardDao>()),
    );
  }

  if (!sl.isRegistered<ReportDao>()) {
    sl.registerLazySingleton<ReportDao>(() => ReportDao());
  }

  if (!sl.isRegistered<ReportCalculationService>()) {
    sl.registerLazySingleton<ReportCalculationService>(
      () => ReportCalculationService(sl<ReportDao>()),
    );
  }

  if (!sl.isRegistered<ReportFilterService>()) {
    sl.registerLazySingleton<ReportFilterService>(() => ReportFilterService());
  }

  if (!sl.isRegistered<ReportValidationService>()) {
    sl.registerLazySingleton<ReportValidationService>(
      () => ReportValidationService(sl<ReportDao>()),
    );
  }

  if (!sl.isRegistered<TrialBalanceCubit>()) {
    sl.registerFactory<TrialBalanceCubit>(
      () => TrialBalanceCubit(
        calculationService: sl<ReportCalculationService>(),
        filterService: sl<ReportFilterService>(),
        validationService: sl<ReportValidationService>(),
      ),
    );
  }

  if (!sl.isRegistered<GeneralLedgerCubit>()) {
    sl.registerFactory<GeneralLedgerCubit>(
      () => GeneralLedgerCubit(
        filterService: sl<ReportFilterService>(),
      ),
    );
  }

  if (!sl.isRegistered<BalanceSheetCubit>()) {
    sl.registerFactory<BalanceSheetCubit>(
      () => BalanceSheetCubit(
        calculationService: sl<ReportCalculationService>(),
        filterService: sl<ReportFilterService>(),
        validationService: sl<ReportValidationService>(),
      ),
    );
  }

  if (!sl.isRegistered<IncomeStatementCubit>()) {
    sl.registerFactory<IncomeStatementCubit>(
      () => IncomeStatementCubit(
        calculationService: sl<ReportCalculationService>(),
        filterService: sl<ReportFilterService>(),
        validationService: sl<ReportValidationService>(),
      ),
    );
  }

  if (!sl.isRegistered<CashFlowCubit>()) {
    sl.registerFactory<CashFlowCubit>(
      () => CashFlowCubit(
        calculationService: sl<ReportCalculationService>(),
        filterService: sl<ReportFilterService>(),
      ),
    );
  }

  // ── Fiscal Year (Singletons) ──

  if (!sl.isRegistered<FiscalYearDao>()) {
    sl.registerLazySingleton<FiscalYearDao>(() => FiscalYearDao());
  }

  if (!sl.isRegistered<FiscalYearService>()) {
    sl.registerLazySingleton<FiscalYearService>(
      () => FiscalYearService(dao: sl<FiscalYearDao>()),
    );
  }

  if (!sl.isRegistered<ClosingValidationService>()) {
    sl.registerLazySingleton<ClosingValidationService>(
      () => ClosingValidationService(),
    );
  }

  if (!sl.isRegistered<ClosingAuditService>()) {
    sl.registerLazySingleton<ClosingAuditService>(
      () => ClosingAuditService(dao: sl<FiscalYearDao>()),
    );
  }

  if (!sl.isRegistered<ClosingReportService>()) {
    sl.registerLazySingleton<ClosingReportService>(
      () => ClosingReportService(dao: sl<FiscalYearDao>()),
    );
  }

  if (!sl.isRegistered<FiscalYearClosingEngine>()) {
    sl.registerLazySingleton<FiscalYearClosingEngine>(
      () => FiscalYearClosingEngine(
        dao: sl<FiscalYearDao>(),
        validationService: sl<ClosingValidationService>(),
        auditService: sl<ClosingAuditService>(),
      ),
    );
  }

  if (!sl.isRegistered<FiscalYearCubit>()) {
    sl.registerFactory<FiscalYearCubit>(
      () => FiscalYearCubit(
        service: sl<FiscalYearService>(),
        closingEngine: sl<FiscalYearClosingEngine>(),
        validationService: sl<ClosingValidationService>(),
        auditService: sl<ClosingAuditService>(),
        reportService: sl<ClosingReportService>(),
      ),
    );
  }

  if (!sl.isRegistered<FiscalYearHealthCheck>()) {
    sl.registerLazySingleton<FiscalYearHealthCheck>(
      () => FiscalYearHealthCheck(),
    );
  }

  if (!sl.isRegistered<ConsistencyScanner>()) {
    sl.registerLazySingleton<ConsistencyScanner>(
      () => ConsistencyScanner(),
    );
  }

  if (!sl.isRegistered<FiscalYearProgressService>()) {
    sl.registerLazySingleton<FiscalYearProgressService>(
      () => FiscalYearProgressService(),
    );
  }

  if (!sl.isRegistered<FiscalYearNotificationService>()) {
    sl.registerLazySingleton<FiscalYearNotificationService>(
      () => FiscalYearNotificationService(),
    );
  }

  if (!sl.isRegistered<FiscalYearDryRunService>()) {
    sl.registerLazySingleton<FiscalYearDryRunService>(
      () => FiscalYearDryRunService(),
    );
  }

  if (!sl.isRegistered<ClosingReadinessReportService>()) {
    sl.registerLazySingleton<ClosingReadinessReportService>(
      () => ClosingReadinessReportService(),
    );
  }

  if (!sl.isRegistered<FiscalYearDiagnosticsService>()) {
    sl.registerLazySingleton<FiscalYearDiagnosticsService>(
      () => FiscalYearDiagnosticsService(),
    );
  }

  if (!sl.isRegistered<FiscalYearProductionValidator>()) {
    sl.registerLazySingleton<FiscalYearProductionValidator>(
      () => FiscalYearProductionValidator(),
    );
  }
}
