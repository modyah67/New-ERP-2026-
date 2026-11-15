import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/bank_account_dao.dart';
import 'bank_accounts_state.dart';

class BankAccountsCubit extends Cubit<BankAccountsState> {
  final BankAccountDao _dao = BankAccountDao();

  BankAccountsCubit() : super(const BankAccountsInitial());

  Future<void> loadAll() async {
    emit(const BankAccountsLoading());
    try {
      // Run both queries in parallel
      final accountsFuture = _dao.getAll();
      final usersFuture = Supabase.instance.client.from('users').select('id, full_name').catchError((_) => <dynamic>[]);
      final accounts = await accountsFuture;
      final rawUsers = await usersFuture;
      Map<String, String> userNamesCache = {};
      for (final u in (rawUsers as List)) {
        final m = Map<String, dynamic>.from(u);
        userNamesCache[m['id'].toString()] = (m['full_name'] ?? '').toString();
      }
      emit(BankAccountsLoaded(accounts: accounts, userNamesCache: userNamesCache));
    } catch (e) {
      emit(BankAccountsError('فشل تحميل الحسابات: $e'));
    }
  }

  Future<void> loadTransactions(int accountId, {DateTime? startDate, DateTime? endDate, bool clearDates = false}) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    
    final sDate = clearDates ? null : (startDate ?? loaded.startDate);
    final eDate = clearDates ? null : (endDate ?? loaded.endDate);
    
    try {
      final transactions = await _dao.getTransactions(
        accountId,
        startDate: sDate,
        endDate: eDate,
        userNamesCache: loaded.userNamesCache,
      );
      emit(loaded.copyWith(
        transactions: transactions, 
        selectedAccountId: accountId,
        startDate: sDate,
        endDate: eDate,
        clearDates: clearDates,
      ));
    } catch (e) {
      emit(BankAccountsError('فشل تحميل الحركات: $e'));
    }
  }

  Future<void> setDateFilter(DateTime? start, DateTime? end, {bool clear = false}) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(startDate: start, endDate: end, clearDates: clear));
    if (loaded.selectedAccountId != null) {
      await loadTransactions(loaded.selectedAccountId!, startDate: start, endDate: end, clearDates: clear);
    }
  }

  Future<void> deposit({
    required int accountId,
    required double amount,
    String? description,
    int? revenueAccountId,
    String? notes,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.deposit(
        accountId: accountId,
        amount: amount,
        description: description,
        revenueAccountId: revenueAccountId,
        notes: notes,
      );
      // Update balance in-place
      final updatedAccounts = loaded.accounts.map((a) {
        if (a.id == accountId) {
          return a.copyWith(balance: a.balance + amount);
        }
        return a;
      }).toList();
      emit(loaded.copyWith(accounts: updatedAccounts, isSaving: false));
      // Reload only transactions if an account is selected
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل الإيداع: $e'));
    }
  }

  Future<void> depositWithCounterparty({
    required int accountId,
    required double amount,
    String? description,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? counterpartyName,
    int? revenueAccountId,
    String? notes,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.depositWithCounterparty(
        accountId: accountId,
        amount: amount,
        description: description,
        counterpartyType: counterpartyType,
        counterpartyId: counterpartyId,
        supplierId: supplierId,
        shareholderId: shareholderId,
        counterpartyName: counterpartyName,
        revenueAccountId: revenueAccountId,
        notes: notes,
      );
      final updatedAccounts = loaded.accounts.map((a) {
        if (a.id == accountId) {
          return a.copyWith(balance: a.balance + amount);
        }
        return a;
      }).toList();
      emit(loaded.copyWith(accounts: updatedAccounts, isSaving: false));
      if (counterpartyType == 'supplier' || supplierId != null) {
        DataChangeEventBus.instance.notifySuppliersChanged();
      } else if (counterpartyType == 'customer') {
        DataChangeEventBus.instance.notifyCustomersChanged();
      } else if (counterpartyType == 'shareholder' || shareholderId != null) {
        DataChangeEventBus.instance.notifyShareholdersChanged();
      }
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل الإيداع: $e'));
    }
  }

  Future<void> withdraw({
    required int accountId,
    required double amount,
    String? description,
    int? expenseAccountId,
    String? notes,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.withdraw(
        accountId: accountId,
        amount: amount,
        description: description,
        expenseAccountId: expenseAccountId,
        notes: notes,
      );
      final updatedAccounts = loaded.accounts.map((a) {
        if (a.id == accountId) {
          return a.copyWith(balance: a.balance - amount);
        }
        return a;
      }).toList();
      emit(loaded.copyWith(accounts: updatedAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل الصرف: $e'));
    }
  }

  Future<void> withdrawWithCounterparty({
    required int accountId,
    required double amount,
    String? description,
    String? counterpartyType,
    int? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? counterpartyName,
    int? expenseAccountId,
    String? notes,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.withdrawWithCounterparty(
        accountId: accountId,
        amount: amount,
        description: description,
        counterpartyType: counterpartyType,
        counterpartyId: counterpartyId,
        supplierId: supplierId,
        shareholderId: shareholderId,
        counterpartyName: counterpartyName,
        expenseAccountId: expenseAccountId,
        notes: notes,
      );
      final updatedAccounts = loaded.accounts.map((a) {
        if (a.id == accountId) {
          return a.copyWith(balance: a.balance - amount);
        }
        return a;
      }).toList();
      emit(loaded.copyWith(accounts: updatedAccounts, isSaving: false));
      if (counterpartyType == 'supplier' || supplierId != null) {
        DataChangeEventBus.instance.notifySuppliersChanged();
      } else if (counterpartyType == 'customer') {
        DataChangeEventBus.instance.notifyCustomersChanged();
      } else if (counterpartyType == 'shareholder' || shareholderId != null) {
        DataChangeEventBus.instance.notifyShareholdersChanged();
      }
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل الصرف: $e'));
    }
  }

  Future<void> updateTransaction({
    required int transactionId,
    required double newAmount,
    String? newDescription,
    String? newType,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.updateTransaction(
        transactionId: transactionId,
        newAmount: newAmount,
        newDescription: newDescription,
        newType: newType,
      );
      // For edit/delete we don't know the delta, reload accounts then transactions
      final freshAccounts = await _dao.getAll();
      emit(loaded.copyWith(accounts: freshAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل تعديل الحركة: $e'));
      rethrow;
    }
  }

  Future<void> deleteTransaction({required int transactionId}) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.deleteTransaction(transactionId: transactionId);
      final freshAccounts = await _dao.getAll();
      emit(loaded.copyWith(accounts: freshAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل حذف الحركة: $e'));
    }
  }

  void setSearchQuery(String query) {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(searchQuery: query));
  }

  void setCurrencyFilter(String? currency) {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    if (currency == null) {
      emit(loaded.copyWith(clearCurrencyFilter: true));
    } else {
      emit(loaded.copyWith(currencyFilter: currency));
    }
  }

  void setAccountFilter(int? accountId) {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    if (accountId == null) {
      emit(loaded.copyWith(clearAccountFilter: true));
    } else {
      emit(loaded.copyWith(accountFilter: accountId));
    }
  }

  void clearAllFilters() {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(
      clearDates: true,
      clearCurrencyFilter: true,
      clearAccountFilter: true,
      searchQuery: '',
    ));
    if (loaded.selectedAccountId != null) {
      loadTransactions(loaded.selectedAccountId!, clearDates: true);
    }
  }

  Future<void> exchangeCurrency({
    required int fromAccountId,
    required int toAccountId,
    required double amountFrom,
    required double amountTo,
    required double exchangeRate,
    double bankFee = 0.0,
    String transferMode = 'exchange',
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.exchangeCurrency(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amountFrom: amountFrom,
        amountTo: amountTo,
        exchangeRate: exchangeRate,
        bankFee: bankFee,
        transferMode: transferMode,
      );
      
      // Reload accounts and transactions
      final freshAccounts = await _dao.getAll();
      emit(loaded.copyWith(accounts: freshAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل تحويل العملة: $e'));
    }
  }

  Future<void> transferFunds({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    String? description,
    double bankFee = 0.0,
    String? notes,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.transferFunds(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amount: amount,
        description: description,
        bankFee: bankFee,
        notes: notes,
      );

      final freshAccounts = await _dao.getAll();
      emit(loaded.copyWith(accounts: freshAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل التحويل البنكي: $e'));
    }
  }

  // ── Draft Workflow ──

  Future<void> saveDraft({
    required int bankAccountId,
    required String type,
    required double amount,
    String? description,
    String? notes,
    String? entityType,
    String? entityId,
    String? counterpartyName,
    Map<String, dynamic> payload = const {},
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.saveDraft(
        bankAccountId: bankAccountId,
        type: type,
        amount: amount,
        description: description,
        notes: notes,
        entityType: entityType,
        entityId: entityId,
        counterpartyName: counterpartyName,
        payload: payload,
      );
      emit(loaded.copyWith(isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل حفظ المسودة: $e'));
    }
  }

  Future<void> updateDraft({
    required int transactionId,
    int? bankAccountId,
    String? type,
    double? amount,
    String? description,
    String? notes,
    String? entityType,
    String? entityId,
    String? counterpartyName,
    Map<String, dynamic>? payload,
  }) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.updateDraft(
        transactionId: transactionId,
        bankAccountId: bankAccountId,
        type: type,
        amount: amount,
        description: description,
        notes: notes,
        entityType: entityType,
        entityId: entityId,
        counterpartyName: counterpartyName,
        payload: payload,
      );
      emit(loaded.copyWith(isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل تعديل المسودة: $e'));
    }
  }

  Future<void> confirmDraft({required int transactionId}) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.confirmDraft(transactionId: transactionId);
      final freshAccounts = await _dao.getAll();
      emit(loaded.copyWith(accounts: freshAccounts, isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل تأكيد المسودة: $e'));
    }
  }

  Future<void> deleteDraft({required int transactionId}) async {
    if (state is! BankAccountsLoaded) return;
    final loaded = state as BankAccountsLoaded;
    emit(loaded.copyWith(isSaving: true));
    try {
      await _dao.deleteDraft(transactionId: transactionId);
      emit(loaded.copyWith(isSaving: false));
      if (loaded.selectedAccountId != null) {
        await loadTransactions(loaded.selectedAccountId!);
      }
    } catch (e) {
      emit(BankAccountsError('فشل حذف المسودة: $e'));
    }
  }
}
