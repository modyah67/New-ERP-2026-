// lib/core/router.dart
// ─────────────────────────────────────────────
// Application router using go_router.
// Auth redirect is driven by AuthCubit via a
// ValueNotifier that the router listens to.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'auth_state_notifier.dart';
import 'injection.dart';
import '../features/auth/auth_cubit.dart';
import '../features/auth/login_page.dart';
import '../features/auth/sign_up_page.dart';
import '../ui/pages/shell_page.dart';
import '../ui/pages/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/tenant_service.dart';
// Feature pages
import '../ui/pages/home_page.dart';
import '../features/customers/customers_page.dart';
import '../features/suppliers/suppliers_page.dart';
import '../features/invoices/invoices_page.dart';
import '../features/invoices/invoice_form_page.dart';
import '../features/purchases/purchases_page.dart';
import '../features/purchases/purchase_form_page.dart';
import '../features/returns/returns_page.dart';
import '../features/returns/return_form_page.dart';
import '../features/accounting/cash_receipt_page.dart';
import '../features/accounting/cash_payment_page.dart';
import '../features/accounting/cashbox_page.dart';
import '../features/journal_entry/journal_entry_page.dart';
import '../features/reports/reports_page.dart';
import '../features/settings/settings_page.dart';
import '../features/statements/statement_page.dart';
import '../features/statements/supplier_statement_page.dart';
import '../features/statements/brief_statement_page.dart';
import '../features/statements/consolidated_statement_page.dart';
import '../features/exports/exports_page.dart';
import '../features/exports/export_shipment_form_page.dart';
import '../accounting/fiscal_year/ui/fiscal_year_list_page.dart';
import '../accounting/fiscal_year/cubit/fiscal_year_cubit.dart';
import '../features/exports/shipment_costing_page.dart';
import '../features/exports/profit_dashboard_page.dart';
import '../features/exports/export_shipment_cubit.dart';
import '../features/exports/cost_summary_report_page.dart';
import '../features/exports/cost_categories_page.dart';
import '../features/exports/profit_distribution_page.dart';
import '../features/exports/export_customer_statement_page.dart';
import '../features/exports/export_customer_statement_cubit.dart';
import '../features/stations/stations_page.dart';
import '../features/shipping_companies/shipping_companies_page.dart';
import '../features/stations/station_products_page.dart';
import '../features/stations/station_product_details_page.dart';
import '../features/transfers/transfers_page.dart';
import '../features/clearing_agents/clearing_agents_page.dart';
import '../features/treasury/treasury_page.dart';
import '../features/user_management/user_management_page.dart';
import '../features/backup/comprehensive_backup_page.dart';
import '../features/cheques/cheques_page.dart';
import '../features/lots/lots_page.dart';
import '../features/lots/lot_form_page.dart';
import '../features/lots/lot_returns_page.dart';
import '../features/packing/packing_orders_page.dart';
import '../features/packing/packing_order_form_page.dart';
import '../features/packing/packing_wastes_page.dart';
import '../features/packing/packing_waste_page.dart';
import '../features/packing/packing_recipe_page.dart';
import '../features/packing/packing_material_transfer_page.dart';
import '../features/packing/sorting_page.dart';
import '../data/models/packing_order_model.dart';
import '../features/exports/preparation_center_invoice_screen.dart';
import '../features/bank_accounts/bank_accounts_page.dart';
import '../features/accounts/chart_of_accounts_page.dart';
import '../data/models/export_shipment_model.dart';
import '../features/suppliers/supplier_account_statement_page.dart';
import '../features/suppliers/supplier_account_statement_cubit.dart';
import '../features/clearing_agents/clearing_agent_statement_page.dart';
import '../features/clearing_agents/clearing_agent_statement_cubit.dart';
import '../features/shipping_companies/shipping_company_statement_page.dart';
import '../features/shipping_companies/shipping_company_statement_cubit.dart';
import '../features/warehouse_tracking/warehouse_tracking_page.dart';
import '../features/warehouse_tracking/warehouse_tracking_details_page.dart';
import '../features/warehouse_tracking/warehouse_tracking_cubit.dart';
import '../data/models/station_model.dart';
import '../features/raw_materials/raw_materials_page.dart';
import '../features/raw_materials/raw_material_detail_page.dart';
import '../features/fruit_types/fruit_types_page.dart';
import '../features/shareholders/shareholders_page.dart';
import '../features/shareholders/shareholder_statement_page.dart';
import '../features/shareholders/shareholder_statement_cubit.dart';
import '../features/proforma/proforma_invoices_page.dart';
import '../features/proforma/proforma_invoice_form_page.dart';
import '../features/proforma/proforma_invoice_cubit.dart';
import '../features/proforma/proforma_invoice_model.dart';

// Trial Balance
import '../features/trial_balance/trial_balance_page.dart';
import '../features/trial_balance/trial_balance_cubit.dart';

// General Ledger
import '../features/general_ledger/general_ledger_page.dart';
import '../features/general_ledger/general_ledger_cubit.dart';

// Balance Sheet
import '../features/balance_sheet/balance_sheet_page.dart';
import '../features/balance_sheet/balance_sheet_cubit.dart';

// Income Statement
import '../features/income_statement/income_statement_page.dart';
import '../features/income_statement/income_statement_cubit.dart';

// Cash Flow
import '../features/cash_flow/cash_flow_page.dart';
import '../features/cash_flow/cash_flow_cubit.dart';

// Fiscal Year Closing
import '../accounting/fiscal_year/ui/fiscal_year_dashboard_page.dart';
import '../accounting/fiscal_year/ui/fiscal_year_recovery_page.dart';
import '../accounting/fiscal_year/ui/fiscal_year_diagnostics_page.dart';
import '../accounting/closing/ui/fiscal_year_closing_page.dart';
import '../accounting/closing/cubit/fiscal_year_cubit.dart';
import '../accounting/closing/services/fiscal_year_closing_service.dart';
import '../accounting/closing/services/audit_log_service.dart';

import '../features/exchange_rates/exchange_rates_page.dart';

// Cubits
import '../features/customers/customer_cubit.dart';
import '../features/suppliers/supplier_cubit.dart';
import '../features/invoices/invoice_cubit.dart';
import '../features/purchases/purchase_cubit.dart';
import '../features/accounting/cashbox_cubit.dart';
import '../features/statements/statement_cubit.dart';
import '../features/statements/supplier_statement_cubit.dart';
import '../features/statements/brief_statement_cubit.dart';
import '../features/settings/settings_cubit.dart';
import '../features/reports/report_cubit.dart';

/// Global navigator key for Programmatic navigation
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// ── Route paths ────────────────────────────

class RoutePaths {
  RoutePaths._();

  static const splash = '/splash';
  static const login = '/login';
  static const signUp = '/sign-up';
  static const home = '/home';
  static const customers = '/customers';
  static const suppliers = '/suppliers';
  static const items = '/items';
  static const invoices = '/invoices';
  static const invoiceNew = '/invoices/new';
  static const purchases = '/purchases';
  static const purchaseNew = '/purchases/new';
  static const returns = '/returns';
  static const returnNew = '/returns/new';
  static const accounts = '/accounts';
  static const chartOfAccounts = '/chart-of-accounts';
  static const exchangeRates = '/exchange-rates';
  static const cashReceipt = '/cash-receipt';
  static const cashPayment = '/cash-payment';
  static const cashbox = '/cashbox';
  static const journalEntry = '/journal-entry';
  static const reports = '/reports';
  static const settings = '/settings';
  static const statement = '/statement';
  static const supplierStatement = '/supplier-statement';
  static const briefStatement = '/brief-statement';
  static const consolidatedStatement = '/consolidated-statement';
  static const exports = '/exports';
  static const exportNew = '/exports/new';
  static const exportEdit = '/exports/edit';
  static const exportCosting = '/exports/costing/:id';
  static const exportProfit = '/exports/profit';
  static const exportCostSummary = '/exports/cost-summary';
  static const exportCostCategories = '/exports/cost-categories';
  static const profitDistribution = '/exports/profit-distribution';
  static const stations = '/stations';
  static const stationProducts = '/station-products';
  static const stationProductDetails = '/station-product-details';
  static const transfers = '/transfers';
  static const clearingAgents = '/clearing-agents';
  static const userManagement = '/user-management';
  static const cheques = '/cheques';
  static const lots = '/lots';
  static const lotNew = '/lots/new';
  static const lotReturns = '/lots/returns';
  static const packing = '/packing';
  static const packingNew = '/packing/new';
  static const packingView = '/packing/view';
  static const packingWaste = '/packing/waste';
  static const packingWasteForm = '/packing/waste/form';
  static const packingRecipes = '/packing/recipes';
  static const packingTransfer = '/packing/transfer';
  static const sorting = '/sorting';
  static const prepCenterInvoice = '/preparation-center-invoice';
  static const bankAccounts = '/bank-accounts';
  static const shippingCompanies = '/shipping-companies';
  static const exportCustomerStatement = '/export-customer-statement';
  static const supplierStatementPage = '/supplier-statement-page';
  static const clearingAgentStatement = '/clearing-agent-statement';
  static const shippingCompanyStatement = '/shipping-company-statement';
  static const warehouseTracking = '/warehouse-tracking';
  static const warehouseTrackingDetail = '/warehouse-tracking/detail';
  static const rawMaterials = '/raw-materials';
  static const fruitTypes = '/fruit-types';
  static const shareholders = '/shareholders';
  static const shareholderStatement = '/shareholder-statement';
  static const proformaInvoices = '/proforma-invoices';
  static const proformaInvoiceNew = '/proforma-invoices/new';
  static const trialBalance = '/trial-balance';
  static const generalLedger = '/general-ledger';
  static const balanceSheet = '/balance-sheet';
  static const incomeStatement = '/income-statement';
  static const cashFlow = '/cash-flow';
  static const fiscalYearClosing = '/fiscal-year-closing';
  static const fiscalYearDashboard = '/fiscal-year-dashboard';
  static const fiscalYearRecovery = '/fiscal-year-recovery';
  static const fiscalYearDiagnostics = '/fiscal-year-diagnostics';
}

/// ── Router provider ────────────────────────

bool _isFormRoute(String path) {
  return path.endsWith('/new') ||
      path.endsWith('/edit') ||
      path.contains('/new/') ||
      path.contains('/edit/') ||
      path == '/cash-receipt' ||
      path == '/cash-payment' ||
      path == '/journal-entry';
}

GoRouter createRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.splash,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = authNotifier.value;

      if (authState is AuthInitial || authState is AuthLoading) {
        return null;
      }

      final isAuth = authState is AuthAuthenticated;
      final isSplash = state.matchedLocation == RoutePaths.splash;
      final isLogin = state.matchedLocation == RoutePaths.login ||
          state.matchedLocation == RoutePaths.signUp;

      if (!isAuth && !isLogin) {
        return RoutePaths.login;
      }

      if (isAuth) {
        if (isLogin || isSplash) {
          if (authState is AuthAuthenticated) {
            if (authState.isAdmin) {
              return RoutePaths.home;
            } else if (authState.allowedPages.isNotEmpty) {
              return authState.allowedPages.first;
            } else {
              // Return a safe empty route or stay on shell with no content
              // We'll let them go to home, but we'll protect home later, or just let them see an empty shell.
              // Actually, if we return null, they go to the requested page.
              return RoutePaths.home;
            }
          }
          return RoutePaths.home;
        }

        // Guard routes for non-admin
        if (authState is AuthAuthenticated && !authState.isAdmin) {
          final target = state.matchedLocation;
          bool hasAccess = false;

          if (target == RoutePaths.home &&
              authState.allowedPages.contains(RoutePaths.home)) {
            hasAccess = true;
          } else if (target != RoutePaths.home) {
            for (final p in authState.allowedPages) {
              if (target.startsWith(p)) {
                hasAccess = true;
                break;
              }
            }
          }

          if (!hasAccess) {
            if (authState.allowedPages.isNotEmpty) {
              return authState.allowedPages.first;
            } else {
              // They have no allowed pages, keep them on a blank page if possible
              // We will modify HomePage to show "No Access" if they are not admin and don't have home access.
              return RoutePaths.home;
            }
          }
        }
      }

      return null;
    },
    routes: [
      // ── Splash (public) ──
      GoRoute(
        path: RoutePaths.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Login (public) ──
      GoRoute(
        path: RoutePaths.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),

      // ── Sign Up (public) ──
      GoRoute(
        path: RoutePaths.signUp,
        name: 'signUp',
        builder: (context, state) => const SignUpPage(),
      ),

      // ── Shell (all authenticated routes) ──
      ShellRoute(
        builder: (context, state, child) {
          return ShellPage(child: child);
        },
        routes: [
          GoRoute(
            path: RoutePaths.home,
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomePage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.customers,
            name: 'customers',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<CustomerCubit>()..init(),
                child: const CustomersPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.suppliers,
            name: 'suppliers',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<SupplierCubit>()..init(),
                child: const SuppliersPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.invoices,
            name: 'invoices',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => InvoiceCubit(type: 'sale')..init(),
                child: const InvoicesPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'invoice-new',
                builder: (context, state) => BlocProvider(
                  create: (_) => InvoiceCubit(type: 'sale')..init(),
                  child: const InvoiceFormPage(),
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.purchases,
            name: 'purchases',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<PurchaseCubit>()..init(),
                child: const PurchasesPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'view',
                name: 'purchase-view',
                builder: (context, state) {
                  final cubit = state.extra as PurchaseCubit?;
                  if (cubit != null) {
                    return BlocProvider<PurchaseCubit>.value(
                      value: cubit,
                      child: const PurchaseFormPage(viewOnly: true),
                    );
                  }
                  return BlocProvider(
                    create: (_) => sl<PurchaseCubit>()..init(),
                    child: const PurchaseFormPage(viewOnly: true),
                  );
                },
              ),
              GoRoute(
                path: 'new',
                name: 'purchase-new',
                builder: (context, state) {
                  final cubit = state.extra as PurchaseCubit?;
                  if (cubit != null) {
                    return BlocProvider<PurchaseCubit>.value(
                      value: cubit,
                      child: const PurchaseFormPage(),
                    );
                  }
                  return BlocProvider(
                    create: (_) => sl<PurchaseCubit>()..init(),
                    child: const PurchaseFormPage(),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.returns,
            name: 'returns',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => InvoiceCubit(type: 'return')..init(),
                child: const ReturnsPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'return-new',
                builder: (context, state) => BlocProvider(
                  create: (_) => InvoiceCubit(type: 'return')..init(),
                  child: const ReturnFormPage(),
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.accounts,
            name: 'accounts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TreasuryPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.chartOfAccounts,
            name: 'chart-of-accounts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ChartOfAccountsPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.exchangeRates,
            name: 'exchange-rates',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExchangeRatesPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.bankAccounts,
            name: 'bank-accounts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BankAccountsPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.cashReceipt,
            name: 'cash-receipt',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CashReceiptPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.cashPayment,
            name: 'cash-payment',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CashPaymentPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.cashbox,
            name: 'cashbox',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<CashboxCubit>()..loadAll(),
                child: const CashboxPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.journalEntry,
            name: 'journal-entry',
            pageBuilder: (context, state) => NoTransitionPage(
              key: ValueKey(state.uri.toString()),
              child: JournalEntryPage(
                key: ValueKey(state.uri.toString()),
                initialEntryNumber: state.uri.queryParameters['entryNumber'],
                initialJournalEntryId: state.uri.queryParameters['journalEntryId'],
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.trialBalance,
            name: 'trial-balance',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<TrialBalanceCubit>()..init(),
                child: const TrialBalancePage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.generalLedger,
            name: 'general-ledger',
            pageBuilder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return NoTransitionPage(
                child: BlocProvider(
                  create: (_) => sl<GeneralLedgerCubit>()
                    ..init(
                      accountId: extra?['accountId'] as String?,
                      accountCode: extra?['accountCode'] as String?,
                      accountName: extra?['accountName'] as String?,
                      fromDate: extra?['fromDate'] as DateTime?,
                      toDate: extra?['toDate'] as DateTime?,
                    ),
                  child: const GeneralLedgerPage(),
                ),
              );
            },
          ),
          GoRoute(
            path: RoutePaths.balanceSheet,
            name: 'balance-sheet',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<BalanceSheetCubit>()..init(),
                child: const BalanceSheetPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.incomeStatement,
            name: 'income-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<IncomeStatementCubit>()..init(),
                child: const IncomeStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.cashFlow,
            name: 'cash-flow',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<CashFlowCubit>()..init(),
                child: const CashFlowPage(),
              ),
            ),
          ),
          // Fiscal Year Management
          GoRoute(
            path: RoutePaths.fiscalYearClosing,
            name: 'fiscal-year',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<FiscalYearCubit>()..loadFiscalYears(),
                child: const FiscalYearListPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.fiscalYearDashboard,
            name: 'fiscal-year-dashboard',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<FiscalYearCubit>()..loadFiscalYears(),
                child: const FiscalYearDashboardPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.fiscalYearRecovery,
            name: 'fiscal-year-recovery',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<FiscalYearCubit>()..loadFiscalYears(),
                child: const FiscalYearRecoveryPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.fiscalYearDiagnostics,
            name: 'fiscal-year-diagnostics',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<FiscalYearCubit>()..loadFiscalYears(),
                child: const FiscalYearDiagnosticsPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.reports,
            name: 'reports',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ReportCubit(),
                child: const ReportsPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.settings,
            name: 'settings',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<SettingsCubit>()..loadSettings(),
                child: const SettingsPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.statement,
            name: 'statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<StatementCubit>()..init(),
                child: const StatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.supplierStatement,
            name: 'supplier-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<SupplierStatementCubit>()..init(),
                child: const SupplierStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.briefStatement,
            name: 'brief-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => sl<BriefStatementCubit>()..init(),
                child: const BriefStatementPage(isCustomerMode: true),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.consolidatedStatement,
            name: 'consolidated-statement',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ConsolidatedStatementPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.exports,
            name: 'exports',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ExportShipmentCubit(),
                child: const ExportsPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'export-new',
                builder: (context, state) => BlocProvider(
                  create: (_) => ExportShipmentCubit(),
                  child: ExportShipmentFormPage(
                    isReadOnly: (state.extra
                            as Map<String, dynamic>?)?['isReadOnly'] as bool? ??
                        false,
                  ),
                ),
              ),
              GoRoute(
                path: 'costing/:id',
                name: 'export-costing',
                builder: (context, state) {
                  final id =
                      int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                  return ShipmentCostingPage(shipmentId: id);
                },
              ),
              GoRoute(
                path: 'profit',
                name: 'export-profit',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfitDashboardPage(),
                ),
              ),
              GoRoute(
                path: 'cost-summary',
                name: 'export-cost-summary',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: CostSummaryReportPage(),
                ),
              ),
              GoRoute(
                path: 'cost-categories',
                name: 'cost-categories',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: CostReportCategoriesPage(),
                ),
              ),
              GoRoute(
                path: 'profit-distribution',
                name: 'profit-distribution',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfitDistributionPage(),
                ),
              ),
              GoRoute(
                path: 'edit',
                name: 'export-edit',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>?;
                  return BlocProvider(
                    create: (_) => ExportShipmentCubit(),
                    child: ExportShipmentFormPage(
                      shipment: extra?['shipment'] as ExportShipmentModel?,
                      isReadOnly: extra?['isReadOnly'] as bool? ?? false,
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'preparation-center-invoice/:id',
                name: 'prep-center-invoice',
                builder: (context, state) {
                  final id =
                      int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                  return PreparationCenterInvoiceScreen(shipmentId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.stations,
            name: 'stations',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: StationsPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.stationProducts,
            name: 'station-products',
            pageBuilder: (context, state) {
              final stationId =
                  int.parse(state.uri.queryParameters['id'] ?? '0');
              final stationName = state.uri.queryParameters['name'] ?? '';
              final stationCode = state.uri.queryParameters['code'] ?? '';
              final stationType = state.uri.queryParameters['type'] ?? 'sub';
              return NoTransitionPage(
                child: StationProductsPage(
                  stationId: stationId,
                  stationName: stationName,
                  stationCode: stationCode,
                  stationType: stationType,
                ),
              );
            },
          ),
          GoRoute(
            path: RoutePaths.stationProductDetails,
            name: 'station-product-details',
            pageBuilder: (context, state) {
              final stationId =
                  int.parse(state.uri.queryParameters['id'] ?? '0');
              final stationName = state.uri.queryParameters['name'] ?? '';
              final stationCode = state.uri.queryParameters['code'] ?? '';
              final stationType = state.uri.queryParameters['type'] ?? 'sub';
              final productName =
                  state.uri.queryParameters['productName'] ?? '';
              final productCode =
                  state.uri.queryParameters['productCode'] ?? '';
              final quantity = double.tryParse(
                      state.uri.queryParameters['quantity'] ?? '0') ??
                  0;
              final currency = state.uri.queryParameters['currency'] ?? 'EGP';
              final rawMaterialId = state.uri.queryParameters['rawMaterialId'];
              final fruitTypeId = int.tryParse(state.uri.queryParameters['fruitTypeId'] ?? '');
              final itemType = state.uri.queryParameters['itemType'] ?? '';
              return NoTransitionPage(
                child: StationProductDetailsPage(
                  stationId: stationId,
                  stationName: stationName,
                  stationCode: stationCode,
                  stationType: stationType,
                  productName: productName,
                  productCode: productCode,
                  quantity: quantity,
                  currency: currency,
                  rawMaterialId: rawMaterialId,
                  fruitTypeId: fruitTypeId,
                  itemType: itemType,
                ),
              );
            },
          ),
          GoRoute(
            path: RoutePaths.transfers,
            name: 'transfers',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TransfersPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.clearingAgents,
            name: 'clearing-agents',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ClearingAgentsPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.shippingCompanies,
            name: 'shipping-companies',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShippingCompaniesPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.exportCustomerStatement,
            name: 'export-customer-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ExportCustomerStatementCubit()..init(),
                child: const ExportCustomerStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.supplierStatementPage,
            name: 'supplier-statement-page',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => SupplierAccountStatementCubit()..init(),
                child: const SupplierAccountStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.clearingAgentStatement,
            name: 'clearing-agent-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ClearingAgentStatementCubit()..init(),
                child: const ClearingAgentStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.shippingCompanyStatement,
            name: 'shipping-company-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ShippingCompanyStatementCubit()..init(),
                child: const ShippingCompanyStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.userManagement,
            name: 'user-management',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: UserManagementPage(),
            ),
          ),
          GoRoute(
            path: '/backup',
            name: 'backup',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ComprehensiveBackupPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.warehouseTracking,
            name: 'warehouse-tracking',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => WarehouseTrackingCubit()..init(),
                child: const WarehouseTrackingPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'detail',
                name: 'warehouse-tracking-detail',
                pageBuilder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>?;
                  final station = extra?['station'] as StationModel;
                  final cubit = extra?['cubit'] as WarehouseTrackingCubit;
                  return NoTransitionPage(
                    child: BlocProvider<WarehouseTrackingCubit>.value(
                      value: cubit,
                      child: WarehouseTrackingDetailsPage(
                        station: station,
                        cubit: cubit,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.cheques,
            name: 'cheques',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ChequesPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.lots,
            name: 'lots',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LotsPage(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'lot-new',
                builder: (context, state) {
                  final lot = state.extra as dynamic;
                  return LotFormPage(lot: lot as dynamic);
                },
              ),
              GoRoute(
                path: 'returns',
                name: 'lot-returns',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: LotReturnsPage(),
                ),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.packing,
            name: 'packing',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PackingOrdersPage(),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'packing-new',
                builder: (context, state) {
                  final order = state.extra as PackingOrderModel?;
                  return PackingOrderFormPage(existingOrder: order);
                },
              ),
              GoRoute(
                path: 'view',
                name: 'packing-view',
                builder: (context, state) {
                  final order = state.extra as PackingOrderModel?;
                  return PackingOrderFormPage(
                      existingOrder: order, viewOnly: true);
                },
              ),
              GoRoute(
                path: 'waste',
                name: 'packing-waste',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: PackingWastesPage(),
                ),
                routes: [
                  GoRoute(
                    path: 'form',
                    name: 'packing-waste-form',
                    builder: (context, state) {
                      final extra = state.extra as Map<String, dynamic>?;
                      final wasteId = extra?['wasteId'] as int?;
                      final viewOnly = extra?['viewOnly'] as bool? ?? false;
                      return PackingWastePage(
                        existingWasteId: wasteId,
                        viewOnly: viewOnly,
                      );
                    },
                  ),
                ],
              ),
              GoRoute(
                path: 'recipes',
                name: 'packing-recipes',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: PackingRecipePage(),
                ),
              ),
              GoRoute(
                path: 'transfer',
                name: 'packing-transfer',
                builder: (context, state) =>
                    const PackingMaterialTransferPage(),
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.sorting,
            name: 'sorting',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SortingPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.rawMaterials,
            name: 'raw-materials',
            pageBuilder: (context, state) {
              final lowStockOnly = state.extra == true;
              return NoTransitionPage(
                child: RawMaterialsPage(lowStockOnly: lowStockOnly),
              );
            },
            routes: [
              GoRoute(
                path: ':id',
                name: 'raw-material-detail',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(
                    child: RawMaterialDetailPage(materialId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RoutePaths.fruitTypes,
            name: 'fruit-types',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FruitTypesPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.shareholders,
            name: 'shareholders',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShareholdersPage(),
            ),
          ),
          GoRoute(
            path: RoutePaths.shareholderStatement,
            name: 'shareholder-statement',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ShareholderStatementCubit()..init(),
                child: const ShareholderStatementPage(),
              ),
            ),
          ),
          GoRoute(
            path: RoutePaths.proformaInvoices,
            name: 'proforma-invoices',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => ProformaInvoiceCubit()..load(),
                child: const ProformaInvoicesPage(),
              ),
            ),
            routes: [
              GoRoute(
                path: 'new',
                name: 'proforma-invoice-new',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: BlocProvider(
                    create: (_) => ProformaInvoiceCubit()..loadForm(null),
                    child: const ProformaInvoiceFormPage(),
                  ),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                name: 'proforma-invoice-edit',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  final invoice = state.extra as ProformaInvoiceModel?;
                  return NoTransitionPage(
                    child: BlocProvider(
                      create: (_) => ProformaInvoiceCubit()..loadForm(id),
                      child: ProformaInvoiceFormPage(invoice: invoice),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) GoRouter.of(context).go(RoutePaths.login);
            },
            child: const Text('تسجيل الخروج'),
          ),
        ),
      );
    },
  );
}
