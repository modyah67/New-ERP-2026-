import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/models/treasury_model.dart';
import '../../data/models/expense_category_model.dart';
import '../../data/models/treasury_stats_model.dart';
import '../../data/models/purchase_model.dart';
import '../../data/services/supplier_settlement_service.dart';
import '../../data/services/chart_of_accounts_cache_service.dart';
import '../../core/data_change_event_bus.dart';
import 'treasury_state.dart';

class TreasuryCubit extends Cubit<TreasuryState> {
  final TreasuryDao _dao = TreasuryDao();
  final _client = Supabase.instance.client;

  int _offset = 0;
  static const int _limit = 50;
  DateTime? _lastLoadAll;
  static const Duration _throttle = Duration(seconds: 2);

  RealtimeChannel? _realtimeChannel;

  TreasuryCubit() : super(TreasuryInitial());

  void init() {
    loadAll();
    _subscribe();
  }

  @override
  Future<void> close() {
    _refreshDebounce?.cancel();
    _unsubscribe();
    return super.close();
  }

  void _subscribe() {
    _unsubscribe();
    _realtimeChannel = _client
        .channel('treasury-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'treasury_balances',
          callback: (_) => refreshStats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'treasury_transactions',
          callback: (_) => refreshStats(),
        )
        .subscribe();
    debugPrint('💰 Realtime subscribed: treasury_balances, treasury_transactions');
  }

  void _unsubscribe() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
  }

  // ── Load ──

  Future<void> loadAll({bool reset = false}) async {
    // Throttle: skip if called within 2s of last completion while already loaded
    if (!reset &&
        state is TreasuryLoaded &&
        _lastLoadAll != null &&
        DateTime.now().difference(_lastLoadAll!) < _throttle) {
      debugPrint('💰 loadAll throttled (${DateTime.now().difference(_lastLoadAll!).inMilliseconds}ms since last)');
      return;
    }

    if (reset) {
      _offset = 0;
    }

    if (isClosed) return;
    if (state is! TreasuryLoaded) {
      emit(TreasuryLoading());
    }

    final currentUser = _client.auth.currentUser;
    debugPrint('💰 TreasuryCubit.loadAll');
    debugPrint('   auth.currentUser.id:    ${currentUser?.id ?? 'null'}');

    if (currentUser == null) {
      debugPrint('   ❌ USER NOT AUTHENTICATED');
      if (!isClosed) emit(const TreasuryError(message: 'User not authenticated'));
      return;
    }

    try {
      // Parallelize permission checks + initial data (3 calls → 1 round trip)
      final permResults = await Future.wait([
        _dao.isCurrentUserAdmin(),
        _dao.hasOwnerSafePermission(),
        _dao.getAll(),
      ]);

      final isAdmin = permResults[0] as bool;
      final hasOwnerSafe = permResults[1] as bool;
      final allTreasuries = permResults[2] as List<TreasuryModel>;

      debugPrint('💰 isAdmin result: $isAdmin  (uid: ${currentUser.id})');
      debugPrint('💰 hasOwnerSafe result: $hasOwnerSafe');

      List<TreasuryModel> treasuries;

      if (isAdmin) {
        treasuries = allTreasuries;
      } else {
        final userId = _client.auth.currentUser?.id;
        if (userId == null) {
          if (!isClosed) emit(const TreasuryError(message: 'User not authenticated'));
          return;
        }
        final employeeTreasuries = await _dao.getAllByUserId(userId);
        if (hasOwnerSafe) {
          final mainTreasuries = allTreasuries.where((t) => t.isMain).toList();
          final seen = <String>{...employeeTreasuries.map((t) => t.id ?? '')};
          treasuries = [...employeeTreasuries];
          for (final m in mainTreasuries) {
            if (!seen.contains(m.id ?? '')) treasuries.add(m);
          }
        } else {
          treasuries = employeeTreasuries;
        }
      }

      final mainTreasury = allTreasuries.where((t) => t.isMain).toList();
      final employeeTreasuries = allTreasuries.where((t) => t.isEmployee).toList();

      final treasuryForTx = isAdmin
          ? mainTreasury.isNotEmpty
              ? mainTreasury.first
              : null
          : hasOwnerSafe
              ? mainTreasury.isNotEmpty
                  ? mainTreasury.first
                  : null
              : treasuries.isNotEmpty
                  ? treasuries.first
                  : null;

      // Preserve current selection if it still exists in the refreshed list
      final loadedState = state is TreasuryLoaded ? state as TreasuryLoaded : null;
      TreasuryModel? activeTreasury = treasuryForTx;
      if (loadedState?.selectedTreasury != null) {
        final idx = treasuries.indexWhere((t) => t.id == loadedState!.selectedTreasury!.id);
        if (idx >= 0) activeTreasury = treasuries[idx];
      }

      debugPrint('💰 loadAll: treasuryForTx=${treasuryForTx?.id} activeTreasury=${activeTreasury?.id} mainTreasury=${mainTreasury.isNotEmpty ? mainTreasury.first.id : "null"}');

      // Load transactions + categories + expense accounts + stats in parallel
      final dataFutures = <Future<dynamic>>[];
      if (activeTreasury != null) {
        dataFutures.add(_dao.getTransactions(
          activeTreasury.id!,
          limit: _limit,
          offset: 0,
          startDate: loadedState?.startDate,
          endDate: loadedState?.endDate,
          currency: loadedState?.selectedCurrencyFilter,
        ));
      } else {
        dataFutures.add(Future.value(<TreasuryTransactionModel>[]));
      }

      if (isAdmin || hasOwnerSafe) {
        dataFutures.add(_dao.getExpenseCategories().catchError((_) => <ExpenseCategoryModel>[]));
        dataFutures.add(ChartOfAccountsCacheService().getExpenseAccounts(forceRefresh: true).catchError((_) => <Map<String, dynamic>>[]));
        dataFutures.add(_dao.getTreasuryStats(
          mainTreasuryId: mainTreasury.isNotEmpty ? mainTreasury.first.id! : '',
          allTreasuries: isAdmin,
        ).catchError((_) => const TreasuryStatsModel()));
      } else {
        dataFutures.add(Future.value(<ExpenseCategoryModel>[]));
        dataFutures.add(Future.value(<Map<String, dynamic>>[]));
        dataFutures.add(Future.value(const TreasuryStatsModel()));
      }

      final dataResults = await Future.wait(dataFutures);

      List<TreasuryTransactionModel> transactions = dataResults[0] as List<TreasuryTransactionModel>;
      List<ExpenseCategoryModel> categories = dataResults[1] as List<ExpenseCategoryModel>;
      List<Map<String, dynamic>> expenseAccounts = dataResults[2] as List<Map<String, dynamic>>;
      TreasuryStatsModel? stats = dataResults[3] as TreasuryStatsModel?;
      List<CurrencyTotal> currencyTotals = stats?.currencyTotals ?? [];
      double totalEmployeeCustody = stats?.totalEmployeeCustody ?? 0.0;

      debugPrint('💰 Categories loaded: ${categories.length}');
      debugPrint('💰 Expense accounts loaded: ${expenseAccounts.length}');
      if (stats != null) {
        debugPrint('💰 Stats loaded: expenses=${stats.totalExpenses}');
      }

      if (isClosed) return;
      emit(TreasuryLoaded(
        treasuries: treasuries,
        mainTreasury: mainTreasury.isNotEmpty ? mainTreasury.first : null,
        employeeTreasuries: employeeTreasuries,
        isAdmin: isAdmin,
        hasOwnerSafe: hasOwnerSafe,
        transactions: transactions,
        selectedTreasury: activeTreasury,
        hasMore: transactions.length >= _limit,
        categories: categories,
        expenseAccounts: expenseAccounts,
        currencyTotals: currencyTotals,
        totalEmployeeCustody: totalEmployeeCustody,
        stats: stats,
        searchQuery: loadedState?.searchQuery,
        selectedFromAccountId: loadedState?.selectedFromAccountId,
        selectedToAccountId: loadedState?.selectedToAccountId,
        startDate: loadedState?.startDate,
        endDate: loadedState?.endDate,
        selectedCurrencyFilter: loadedState?.selectedCurrencyFilter,
      ));
      _lastLoadAll = DateTime.now();
    } catch (e, st) {
      debugPrint('TreasuryCubit.loadAll error: $e\n$st');
      if (!isClosed) emit(TreasuryError(message: 'فشل تحميل البيانات: $e'));
    }
  }

  // ── Select Treasury ──

  Future<void> selectTreasury(TreasuryModel treasury) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isFetchingMore: true));

    try {
      _offset = 0;
      final transactions = await _dao.getTransactions(
        treasury.id!,
        limit: _limit,
        offset: 0,
        startDate: loaded.startDate,
        endDate: loaded.endDate,
        currency: loaded.selectedCurrencyFilter,
      );

      if (isClosed) return;
      emit(loaded.copyWith(
        selectedTreasury: treasury,
        transactions: transactions,
        hasMore: transactions.length >= _limit,
        isFetchingMore: false,
      ));
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isFetchingMore: false,
        errorMessage: 'فشل تحميل الحركات: $e',
      ));
    }
  }

  // ── Load More Transactions ──

  Future<void> loadMoreTransactions() async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    if (loaded.isFetchingMore || !loaded.hasMore) return;
    if (loaded.selectedTreasury == null) return;

    emit(loaded.copyWith(isFetchingMore: true));

    try {
      _offset += _limit;
      final newTx = await _dao.getTransactions(
        loaded.selectedTreasury!.id!,
        limit: _limit,
        offset: _offset,
        startDate: loaded.startDate,
        endDate: loaded.endDate,
        currency: loaded.selectedCurrencyFilter,
      );

      if (isClosed) return;
      emit(loaded.copyWith(
        transactions: [...loaded.transactions, ...newTx],
        hasMore: newTx.length >= _limit,
        isFetchingMore: false,
      ));
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(isFetchingMore: false));
    }
  }

  // ── Create Treasury (Admin only) ──

  Future<void> createTreasury({
    required String name,
    required String type,
    String? employeeId,
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.createTreasury(
        name: name,
        type: type,
        employeeId: employeeId,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل إنشاء الخزنة: $e',
      ));
    }
  }

  // ── Disbursement (Admin only) ──

  Future<void> createDisbursement({
    required int toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
      if ((!loaded.isAdmin && !loaded.hasOwnerSafe) || loaded.mainTreasury == null) {
      if (!isClosed) emit(loaded.copyWith(errorMessage: 'غير مصرح لك بهذه العملية'));
      return;
    }

    debugPrint('💰 createDisbursement: from=${loaded.mainTreasury!.id!} to=$toTreasuryId cur=$currency amt=$amount');

    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.createDisbursement(
        fromTreasuryId: loaded.mainTreasury!.id!,
        toTreasuryId: toTreasuryId.toString(),
        currency: currency,
        amount: amount,
        description: description,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل صرف العهدة: $e',
      ));
    }
  }

  // ── Transfer ──

  Future<void> transferCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.transferCustody(
        fromTreasuryId: fromTreasuryId,
        toTreasuryId: toTreasuryId,
        currency: currency,
        amount: amount,
        description: description,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل تحويل العهدة: $e',
      ));
    }
  }

  // ── Expense ──

  Future<void> spend({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? ledgerDescription,
    String? expenseAccountId,
    String? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    PurchaseModel? invoice,
    String? notes,
  }) async {
    debugPrint('═══════════════════════════════════════════════');
    debugPrint('💥 TREASURY_CUBIT.spend() ENTRY');
    debugPrint('  expenseAccountId = "$expenseAccountId" (${expenseAccountId.runtimeType})');
    debugPrint('  treasuryId       = "$treasuryId" (${treasuryId.runtimeType})');
    debugPrint('  currency         = "$currency"');
    debugPrint('  amount           = $amount');
    debugPrint('  supplierId       = "$supplierId"');
    debugPrint('═══════════════════════════════════════════════');

    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;

    // Run validation before any saving state change or database operation
    try {
      SupplierSettlementService.instance.validateSupplierPayment(
        invoice: invoice,
        paymentAmount: amount,
      );
    } catch (e) {
      emit(loaded.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      ));
      return;
    }

    emit(loaded.copyWith(isSaving: true, clearError: true));

    debugPrint('💥 cubit.spend → calling _dao.spend(expenseAccountId: $expenseAccountId)');
    try {
      await _dao.spend(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        description: description,
        ledgerDescription: ledgerDescription,
        expenseAccountId: expenseAccountId,
        customerId: customerId,
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
        invoice: invoice,
        notes: notes,
      );
      await loadAll(reset: true);
      _notifyCounterpartyChanged(
        customerId: customerId != null ? int.tryParse(customerId) : null,
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
      );
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل صرف المصروف: $e',
      ));
    }
  }

  // ── Expense With Category ──

  Future<void> spendWithCategory({
    required int treasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? ledgerDescription,
    required int categoryId,
    String? expenseAccountId,
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    PurchaseModel? invoice,
    String? notes,
  }) async {
    debugPrint('💥 spendWithCategory ENTERED (state=${state.runtimeType})');
    debugPrint('═══════════════════════════════════════════════');
    debugPrint('💥 TREASURY_CUBIT.spendWithCategory() ENTRY');
    debugPrint('  expenseAccountId = "$expenseAccountId" (${expenseAccountId.runtimeType})');
    debugPrint('  treasuryId       = $treasuryId (${treasuryId.runtimeType})');
    debugPrint('  currency         = "$currency"');
    debugPrint('  amount           = $amount');
    debugPrint('  categoryId       = $categoryId');
    debugPrint('  supplierId       = "$supplierId"');
    debugPrint('═══════════════════════════════════════════════');
    if (state is! TreasuryLoaded) {
      debugPrint('💥 EARLY RETURN: state is ${state.runtimeType}, not TreasuryLoaded');
      return;
    }
    final loaded = state as TreasuryLoaded;

    // Run validation before any saving state change or database operation
    try {
      SupplierSettlementService.instance.validateSupplierPayment(
        invoice: invoice,
        paymentAmount: amount,
      );
    } catch (e) {
      emit(loaded.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      ));
      return;
    }

    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      debugPrint('💰 spendWithCategory: treasury=$treasuryId currency=$currency amount=$amount categoryId=$categoryId');
      await _dao.spendWithCategory(
        treasuryId: treasuryId.toString(),
        currency: currency,
        amount: amount,
        description: description,
        ledgerDescription: ledgerDescription,
        categoryId: categoryId.toString(),
        expenseAccountId: expenseAccountId,
        customerId: customerId?.toString(),
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
        invoice: invoice,
        notes: notes,
      );
      debugPrint('💰 spendWithCategory: RPC OK, reloading stats...');
      await loadAll(reset: true);
      _notifyCounterpartyChanged(
        customerId: customerId,
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
      );
      debugPrint('💰 spendWithCategory: loadAll done');
    } catch (e) {
      debugPrint('💰 spendWithCategory FAILED: $e');
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل صرف المصروف: $e',
      ));
    }
  }

  // ── Deposit ──

  Future<void> deposit({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    int? revenueAccountId,
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.deposit(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        description: description,
        revenueAccountId: revenueAccountId,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل الإيداع: $e',
      ));
    }
  }

  // ── Return ──

  Future<void> returnCustody({
    required String fromTreasuryId,
    required String toTreasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.returnCustody(
        fromTreasuryId: fromTreasuryId,
        toTreasuryId: toTreasuryId,
        currency: currency,
        amount: amount,
        description: description,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل إرجاع العهدة: $e',
      ));
    }
  }

  // ── Withdraw (Admin only) ──

  Future<void> withdraw({
    required String treasuryId,
    required String currency,
    required double amount,
    String description = '',
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.withdraw(
        treasuryId: treasuryId,
        currency: currency,
        amount: amount,
        description: description,
        notes: notes,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل السحب: $e',
      ));
    }
  }

  // ── Update Transaction ──

  Future<void> updateTransaction({
    required int transactionId,
    String? description,
    int? categoryId,
    double? amount,
    String? transactionType,
    int? treasuryId,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.updateTransaction(
        transactionId: transactionId.toString(),
        description: description,
        categoryId: categoryId?.toString(),
        amount: amount,
        transactionType: transactionType,
        treasuryId: treasuryId?.toString(),
      );
      await loadAll(reset: true);
      _notifyAllCounterpartiesChanged();
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل تحديث الحركة: $e',
      ));
    }
  }

  // ── Delete Transaction (Admin only) ──

  Future<void> deleteTransaction({required String transactionId}) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.deleteTransaction(transactionId: transactionId);
      await loadAll(reset: true);
      _notifyAllCounterpartiesChanged();
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حذف الحركة: $e',
      ));
    }
  }

  // ── Currency Exchange (Main Treasury only) ──

  Future<void> exchangeCurrency({
    required String fromCurrency,
    required String toCurrency,
    required double amountFrom,
    required double amountTo,
    required double exchangeRate,
    String transferMode = 'exchange',
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    if (loaded.mainTreasury == null) {
      if (!isClosed) emit(loaded.copyWith(errorMessage: 'لا توجد خزينة رئيسية لإتمام عملية التحويل'));
      return;
    }

    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.exchangeCurrency(
        treasuryId: loaded.mainTreasury!.id!,
        fromCurrency: fromCurrency,
        toCurrency: toCurrency,
        amountFrom: amountFrom,
        amountTo: amountTo,
        exchangeRate: exchangeRate,
        transferMode: transferMode,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  // ── Expense Categories CRUD ──

  Future<void> createCategory({
    required String name,
    required String color,
    required String currency,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.createExpenseCategory(name: name, color: color, currency: currency);
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل إنشاء التصنيف: $e',
      ));
    }
  }

  Future<void> updateCategory({
    required String id,
    String? name,
    String? color,
    String? currency,
    bool? isActive,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.updateExpenseCategory(
        id: id,
        name: name,
        color: color,
        currency: currency,
        isActive: isActive,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل تحديث التصنيف: $e',
      ));
    }
  }

  Future<void> deleteCategory(String id) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.deleteExpenseCategory(id);
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حذف التصنيف: $e',
      ));
    }
  }

  // ── Full Refresh (triggered by realtime) ──

  Timer? _refreshDebounce;

  Future<void> refreshStats() async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    if (!loaded.isAdmin && !loaded.hasOwnerSafe) return;

    // Debounce: skip if called within 1s of last refresh
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(seconds: 1), () => _doRefresh(loaded));
  }

  Future<void> _doRefresh(TreasuryLoaded loaded) async {
    try {
      // Run all 4 queries in parallel
      final results = await Future.wait([
        _dao.getAll(),
        loaded.selectedTreasury != null
            ? _dao.getTransactions(loaded.selectedTreasury!.id!, currency: loaded.selectedCurrencyFilter)
            : Future.value(<TreasuryTransactionModel>[]),
        _dao.getExpenseCategories().catchError((_) => <ExpenseCategoryModel>[]),
        _dao.getTreasuryStats(
          mainTreasuryId: loaded.mainTreasury?.id ?? '',
          allTreasuries: true,
        ).catchError((_) => const TreasuryStatsModel()),
      ]);

      final treasuries = results[0] as List<TreasuryModel>;
      final transactions = results[1] as List<TreasuryTransactionModel>;
      final categories = results[2] as List<ExpenseCategoryModel>;
      final stats = results[3] as TreasuryStatsModel;

      final mainList = treasuries.where((t) => t.isMain).toList();
      final employeeList = treasuries.where((t) => t.isEmployee).toList();

      TreasuryModel? selected;
      if (loaded.selectedTreasury != null) {
        final idx = treasuries.indexWhere((t) => t.id == loaded.selectedTreasury!.id);
        if (idx >= 0) selected = treasuries[idx];
      }
      selected ??= mainList.isNotEmpty ? mainList.first : treasuries.isNotEmpty ? treasuries.first : null;

      if (isClosed) return;
      emit(loaded.copyWith(
        treasuries: treasuries,
        mainTreasury: mainList.isNotEmpty ? mainList.first : null,
        employeeTreasuries: employeeList,
        selectedTreasury: selected,
        transactions: transactions,
        categories: categories,
        stats: stats,
        currencyTotals: stats.currencyTotals,
        totalEmployeeCustody: stats.totalEmployeeCustody,
        hasMore: transactions.length >= _limit,
      ));
    } catch (e) {
      debugPrint('💰 refreshStats error: $e');
    }
  }

  void clearError() {
    if (state is TreasuryLoaded) {
      emit((state as TreasuryLoaded).copyWith(clearError: true));
    }
  }

  Future<void> setDateFilter(DateTime? start, DateTime? end) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(
      startDate: start,
      endDate: end,
      clearDateRange: start == null && end == null,
    ));
    await loadAll(reset: true);
  }

  void setSearchQuery(String? query) {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(
      searchQuery: query,
      clearSearchQuery: query == null || query.trim().isEmpty,
    ));
  }

  void setFromAccountFilter(String? fromId) {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(
      selectedFromAccountId: fromId,
      clearFromAccount: fromId == null || fromId.isEmpty,
    ));
  }

  void setToAccountFilter(String? toId) {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(
      selectedToAccountId: toId,
      clearToAccount: toId == null || toId.isEmpty,
    ));
  }

  Future<void> clearAllFilters() async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(
      clearSearchQuery: true,
      clearFromAccount: true,
      clearToAccount: true,
      clearDateRange: true,
      clearCurrencyFilter: true,
    ));
    await loadAll(reset: true);
  }

  Future<void> setCurrencyFilter(String? currency) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    final actualCurrency = currency == 'ALL' ? null : currency;
    emit(loaded.copyWith(selectedCurrencyFilter: actualCurrency, clearCurrencyFilter: actualCurrency == null));
    await loadAll(reset: true);
  }

  void _notifyCounterpartyChanged({
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
  }) {
    if (customerId != null) DataChangeEventBus.instance.notifyCustomersChanged();
    if (supplierId != null) DataChangeEventBus.instance.notifySuppliersChanged();
    if (clearingAgentId != null) DataChangeEventBus.instance.notifyClearingAgentsChanged();
    if (shippingCompanyId != null) DataChangeEventBus.instance.notifyShippingCompaniesChanged();
    if (shareholderId != null) DataChangeEventBus.instance.notifyShareholdersChanged();
  }

  void _notifyAllCounterpartiesChanged() {
    DataChangeEventBus.instance.notifyCustomersChanged();
    DataChangeEventBus.instance.notifySuppliersChanged();
    DataChangeEventBus.instance.notifyClearingAgentsChanged();
    DataChangeEventBus.instance.notifyShippingCompaniesChanged();
    DataChangeEventBus.instance.notifyShareholdersChanged();
  }

  // ── Draft Operations ──

  Future<void> saveDraftExpense({
    required int treasuryId,
    required String currency,
    required double amount,
    String description = '',
    int? categoryId,
    String? expenseAccountId,
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    String? notes,
    PurchaseModel? invoice,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      final parsedExpenseAccountId = expenseAccountId != null ? int.tryParse(expenseAccountId) : null;
      String? refType;
      String? refId;
      if (invoice != null) {
        if (invoice.notes == 'crop_lot' || invoice.id?.startsWith('lot_') == true) {
          refType = 'lot_receipt';
          refId = invoice.id?.replaceFirst('lot_', '') ?? invoice.purchaseNumber;
        } else {
          refType = 'purchase_invoice';
          refId = invoice.id?.toString() ?? invoice.purchaseNumber;
        }
      }

      final payload = <String, dynamic>{
        if (refType != null) 'reference_type': refType,
        if (refId != null) 'reference_id': refId,
      };

      await _dao.saveDraft(
        treasuryId: treasuryId,
        type: 'expense',
        amount: amount,
        currency: currency,
        description: description,
        notes: notes,
        categoryId: categoryId,
        expenseAccountId: parsedExpenseAccountId,
        customerId: customerId,
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
        payload: payload,
      );

      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حفظ المسودة: $e',
      ));
    }
  }

  Future<void> saveDraftReceivePayment({
    required int treasuryId,
    required String receiptType,
    required double amount,
    required String currency,
    String? counterpartyType,
    int? customerId,
    String? supplierId,
    String? shareholderId,
    String? description,
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      final payload = <String, dynamic>{
        'receipt_type': receiptType,
        if (counterpartyType != null) 'counterparty_type': counterpartyType,
      };

      await _dao.saveDraft(
        treasuryId: treasuryId,
        type: 'deposit',
        amount: amount,
        currency: currency,
        description: description,
        notes: notes,
        customerId: customerId,
        supplierId: supplierId,
        shareholderId: shareholderId,
        payload: payload,
      );

      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حفظ مسودة الاستلام: $e',
      ));
    }
  }

  Future<void> saveDraftMultiPayment({
    required int treasuryId,
    required double amount,
    required String currency,
    required String entityType,
    required String entityId,
    String? description,
    String? notes,
    int? expenseAccountId,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      final payload = <String, dynamic>{
        'is_multi_payment': true,
        'entity_type': entityType,
        'entity_id': entityId,
      };

      await _dao.saveDraft(
        treasuryId: treasuryId,
        type: 'multi_payment',
        amount: amount,
        currency: currency,
        description: description,
        notes: notes,
        expenseAccountId: expenseAccountId,
        supplierId: entityType == 'SUPPLIER' ? entityId : null,
        clearingAgentId: entityType == 'CLEARING_AGENT' ? int.tryParse(entityId) : null,
        shippingCompanyId: entityType == 'SHIPPING_COMPANY' ? int.tryParse(entityId) : null,
        payload: payload,
      );

      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حفظ مسودة السداد: $e',
      ));
    }
  }

  Future<void> saveDraftCurrencyExchange({
    required int treasuryId,
    required String fromCurrency,
    required String toCurrency,
    required double amountFrom,
    required double amountTo,
    required double exchangeRate,
    String? description,
    String? notes,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      final payload = <String, dynamic>{
        'from_currency': fromCurrency,
        'to_currency': toCurrency,
        'amount_from': amountFrom,
        'amount_to': amountTo,
        'exchange_rate': exchangeRate,
        'transfer_mode': 'exchange',
      };

      final desc = description?.isNotEmpty == true
          ? description!
          : 'تحويل عملة من $fromCurrency ($amountFrom) إلى $toCurrency ($amountTo)';

      await _dao.saveDraft(
        treasuryId: treasuryId,
        type: 'currency_exchange',
        amount: amountFrom,
        currency: fromCurrency,
        description: desc,
        notes: notes,
        payload: payload,
      );

      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حفظ مسودة تحويل العملة: $e',
      ));
    }
  }

  Future<void> updateDraftTransaction({
    required int transactionId,
    int? treasuryId,
    double? amount,
    String? currency,
    String? description,
    String? notes,
    int? categoryId,
    int? expenseAccountId,
    int? revenueAccountId,
    int? customerId,
    String? supplierId,
    int? clearingAgentId,
    int? shippingCompanyId,
    String? shareholderId,
    Map<String, dynamic>? payload,
  }) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.updateDraft(
        transactionId: transactionId,
        treasuryId: treasuryId,
        amount: amount,
        currency: currency,
        description: description,
        notes: notes,
        categoryId: categoryId,
        expenseAccountId: expenseAccountId,
        revenueAccountId: revenueAccountId,
        customerId: customerId,
        supplierId: supplierId,
        clearingAgentId: clearingAgentId,
        shippingCompanyId: shippingCompanyId,
        shareholderId: shareholderId,
        payload: payload,
      );
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل تعديل المسودة: $e',
      ));
    }
  }

  Future<void> deleteDraft(int transactionId) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.deleteDraft(transactionId);
      await loadAll(reset: true);
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل حذف المسودة: $e',
      ));
    }
  }

  Future<void> confirmDraft(int transactionId) async {
    if (state is! TreasuryLoaded) return;
    final loaded = state as TreasuryLoaded;
    emit(loaded.copyWith(isSaving: true, clearError: true));

    try {
      await _dao.confirmDraft(transactionId);
      await loadAll(reset: true);
      _notifyAllCounterpartiesChanged();
    } catch (e) {
      if (!isClosed) emit(loaded.copyWith(
        isSaving: false,
        errorMessage: 'فشل تأكيد المسودة: $e',
      ));
    }
  }
}