import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/models/transport_supplier_model.dart';
import '../../core/data_change_event_bus.dart';
import 'transport_supplier_statement_state.dart';

class TransportSupplierStatementCubit
    extends Cubit<TransportSupplierStatementState> {
  final TransportSupplierDao _dao = TransportSupplierDao();
  late final StreamSubscription<void> _sub;

  TransportSupplierStatementCubit({int? initialSupplierId})
      : super(const TransportSupplierStatementInitial()) {
    _sub = DataChangeEventBus.instance.transportSuppliersStream
        .listen((_) => refreshData());
    _init(initialSupplierId: initialSupplierId);
  }

  Future<void> init({int? initialSupplierId}) =>
      _init(initialSupplierId: initialSupplierId);

  Future<void> _init({int? initialSupplierId}) async {
    try {
      final suppliers = await _dao.getAll(limit: 500, offset: 0);
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final to = now;

      TransportSupplierModel? selected;
      if (initialSupplierId != null) {
        selected = suppliers.firstWhere(
          (s) => s.id == initialSupplierId,
          orElse: () => suppliers.isNotEmpty ? suppliers.first : throw Exception(),
        );
      }

      if (!isClosed) {
        emit(TransportSupplierStatementLoaded(
          suppliers: suppliers,
          selectedSupplier: selected,
          fromDate: from,
          toDate: to,
        ));
      }

      if (selected != null) {
        await loadStatement();
      }
    } catch (e) {
      if (!isClosed) {
        emit(TransportSupplierStatementError(
            message: 'فشل تحميل موردين النقل: $e'));
      }
    }
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is TransportSupplierStatementLoaded) {
      try {
        final suppliers = await _dao.getAll(limit: 500, offset: 0);
        TransportSupplierModel? updatedSelected;
        if (currentState.selectedSupplier != null) {
          updatedSelected = suppliers.firstWhere(
            (s) => s.id == currentState.selectedSupplier!.id,
            orElse: () => currentState.selectedSupplier!,
          );
        }
        emit(currentState.copyWith(
          suppliers: suppliers,
          selectedSupplier: updatedSelected,
        ));
        if (updatedSelected != null) {
          await loadStatement();
        }
      } catch (e) {
        emit(TransportSupplierStatementError(
            message: 'فشل تحديث البيانات: $e'));
      }
    }
  }

  Future<void> selectSupplier(TransportSupplierModel? supplier) async {
    final currentState = state;
    if (currentState is TransportSupplierStatementLoaded) {
      emit(currentState.copyWith(
        selectedSupplier: supplier,
        clearSelectedSupplier: supplier == null,
      ));
      if (supplier != null) {
        await loadStatement();
      }
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! TransportSupplierStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00B4D8),
            surface: Color(0xFF0F2338),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      emit(currentState.copyWith(fromDate: picked));
      await loadStatement();
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! TransportSupplierStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00B4D8),
            surface: Color(0xFF0F2338),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      emit(currentState.copyWith(toDate: picked));
      await loadStatement();
    }
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! TransportSupplierStatementLoaded) return;
    final supplier = currentState.selectedSupplier;
    if (supplier == null || supplier.id == null) return;

    emit(currentState.copyWith(isLoadingStatement: true));

    try {
      final supplierId = supplier.id!;
      final allTx = await _dao.getTransactions(supplierId);

      double opening = supplier.initialBalanceDirection == 'CREDIT'
          ? supplier.initialBalance
          : -supplier.initialBalance;

      final fromStr = currentState.fromDate?.toIso8601String().substring(0, 10);
      final toStr = currentState.toDate?.toIso8601String().substring(0, 10);

      // Calculate movements prior to fromDate
      if (fromStr != null) {
        for (final tx in allTx) {
          if (tx.date.compareTo(fromStr) < 0) {
            opening += (tx.credit - tx.debit);
          }
        }
      }

      // Filter movements within date range
      final inRangeTx = allTx.where((tx) {
        if (fromStr != null && tx.date.compareTo(fromStr) < 0) return false;
        if (toStr != null && tx.date.compareTo(toStr) > 0) return false;
        return true;
      }).toList();

      double totalDebit = 0.0;
      double totalCredit = 0.0;

      for (final tx in inRangeTx) {
        totalDebit += tx.debit;
        totalCredit += tx.credit;
      }

      final finalBalance = opening + totalCredit - totalDebit;

      if (!isClosed) {
        emit(currentState.copyWith(
          transactions: inRangeTx,
          openingBalance: opening,
          totalDebit: totalDebit,
          totalCredit: totalCredit,
          finalBalance: finalBalance,
          isLoadingStatement: false,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(TransportSupplierStatementError(
            message: 'فشل استخراج كشف الحساب: $e'));
      }
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
