import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/dao/cashbox_dao.dart';
import '../../data/models/cashbox_model.dart';
import 'cashbox_state.dart';

class CashboxCubit extends Cubit<CashboxState> {
  final CashboxDao _dao = CashboxDao();
  final _client = Supabase.instance.client;

  CashboxCubit() : super(const CashboxInitial()) {
    loadAll();
  }

  Future<void> loadAll() async {
    emit(const CashboxLoading());
    try {
      final currentState = state;
      DateTime? fromDate;
      DateTime? toDate;
      if (currentState is CashboxLoaded) {
        fromDate = currentState.fromDate;
        toDate = currentState.toDate;
      }

      final fromStr =
          fromDate != null ? AppUtils.formatDateForDb(fromDate) : null;
      final toStr =
          toDate != null ? AppUtils.formatDateForDb(toDate) : null;

      final entries =
          await _dao.getAll(fromDate: fromStr, toDate: toStr);
      final currentBalance = await _dao.getCurrentBalance();

      double inSum = 0;
      double outSum = 0;
      for (final e in entries) {
        if (e.type == TransactionType.debit) {
          inSum += e.amount;
        } else if (e.type == TransactionType.credit) {
          outSum += e.amount;
        }
      }

      emit(CashboxLoaded(
        entries: entries,
        currentBalance: currentBalance,
        totalIn: inSum,
        totalOut: outSum,
        fromDate: fromDate,
        toDate: toDate,
      ));
    } catch (e) {
      emit(CashboxError(message: 'حدث خطأ: $e'));
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    final currentDate = currentState is CashboxLoaded
        ? currentState.fromDate
        : null;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      if (currentState is CashboxLoaded) {
        emit(currentState.copyWith(fromDate: picked));
      }
      await loadAll();
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    final currentDate =
        currentState is CashboxLoaded ? currentState.toDate : null;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      if (currentState is CashboxLoaded) {
        emit(currentState.copyWith(toDate: picked));
      }
      await loadAll();
    }
  }

  Future<bool> addEntry({
    required String type,
    required double amount,
    required String description,
    required DateTime transactionDate,
  }) async {
    if (amount <= 0) {
      return false;
    }

    final now = DateTime.now().toIso8601String();
    final dateStr = AppUtils.formatDateForDb(transactionDate);

    try {
      bool success = false;
      String? errorMessage;

      // Get current balance
      final prevBalance = await _dao.getCurrentBalance();

      final isOut = type == TransactionType.credit;
      final newBalance =
          isOut ? prevBalance - amount : prevBalance + amount;

      if (isOut && newBalance < 0) {
        errorMessage = 'لا يمكن الصرف — الرصيد الحالي '
            '(${AppUtils.formatCurrency(prevBalance)}) '
            'أقل من المبلغ المطلوب '
            '(${AppUtils.formatCurrency(amount)})';
      } else {
        final desc = description.trim().isEmpty
            ? (type == TransactionType.debit
                ? 'إيداع نقدي'
                : 'صرف نقدي')
            : description.trim();

        await _client.from('cashbox').insert({
          'transaction_date': dateStr,
          'type': type,
          'amount': amount,
          'balance_after': newBalance,
          'description': desc,
          'related_transaction_id': null,
          'created_at': now,
        });
        success = true;
      }

      if (!success) {
        if (errorMessage != null) {
          emit(CashboxError(message: errorMessage!));
        }
        return false;
      }

      await loadAll();
      return true;
    } catch (e) {
      emit(CashboxError(message: 'فشل الحفظ: $e'));
      return false;
    }
  }

  @override
  void onChange(Change<CashboxState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    return super.close();
  }
}
