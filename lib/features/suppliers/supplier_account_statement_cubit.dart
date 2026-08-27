import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/statement_notes_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import '../../data/services/supplier_settlement_service.dart';
import 'supplier_account_statement_state.dart';

class SupplierAccountStatementCubit extends Cubit<SupplierAccountStatementState> {
  final SupplierDao _supplierDao = SupplierDao();
  final StatementNotesDao _notesDao = StatementNotesDao();

  SupplierAccountStatementCubit() : super(const SupplierAccountStatementInitial()) {
    _init();
  }

  Future<void> init() => _init();

  Future<void> _init() async {
    try {
      final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
      final now = DateTime.now();
      if (!isClosed) {
        emit(SupplierAccountStatementLoaded(
          suppliers: suppliers,
          fromDate: DateTime(now.year, now.month, 1),
          toDate: now,
        ));
      }
    } catch (e) {
      if (!isClosed) emit(SupplierAccountStatementError(message: 'فشل تحميل الموردين: $e'));
    }
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      try {
        final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
        emit(currentState.copyWith(suppliers: suppliers));
      } catch (e) {
        emit(SupplierAccountStatementError(message: 'فشل تحميل البيانات: $e'));
      }
    }
  }

  Future<void> selectSupplier(SupplierModel? supplier) async {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      emit(currentState.copyWith(
        selectedSupplier: supplier,
        clearSelectedSupplier: supplier == null,
      ));
      if (supplier != null) await loadStatement();
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) emit(currentState.copyWith(fromDate: picked));
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) emit(currentState.copyWith(toDate: picked));
  }

  Future<void> loadStatement() async {
    final currentState = state;
    if (currentState is! SupplierAccountStatementLoaded) return;
    if (currentState.selectedSupplier == null) return;

    emit(currentState.copyWith(statementRows: [], totalDebit: 0, totalCredit: 0, finalBalance: 0));

    try {
      final supplierId = currentState.selectedSupplier!.id;
      final supplierCode = currentState.selectedSupplier!.supplierCode;
      final from = currentState.fromDate != null ? AppUtils.formatDateForDb(currentState.fromDate!) : null;
      final to = currentState.toDate != null ? AppUtils.formatDateForDb(currentState.toDate!) : null;

      // 1. Fetch purchases, payments, and treasury txs in parallel
      final currentResults = await Future.wait([
        _fetchPurchases(supplierId.toString(), from, to),
        _fetchPayments(supplierCode, supplierId, from, to),
        _fetchTreasuryTx(supplierId.toString(), from, to),
        _fetchCheques(supplierId.toString(), from, to),
        _fetchBankTx(supplierId.toString(), from, to),
        _fetchLots(supplierId.toString(), from, to),
      ]);
      final purchases = currentResults[0];
      final payments = currentResults[1];
      final treasuryTxs = currentResults[2];
      final cheques = currentResults[3];
      final bankTxs = currentResults[4];
      final lots = currentResults[5];

      // 2. Build rows
      final rows = <StatementRow>[];

      // 3. Calculate opening balance for running balance calculation
      double openingBalance = currentState.selectedSupplier!.initialBalance;

      if (from != null) {
        final priorDateStr = AppUtils.formatDateForDb(currentState.fromDate!.subtract(const Duration(days: 1)));
        final priorResults = await Future.wait([
          _fetchPurchases(supplierId.toString(), null, priorDateStr),
          _fetchPayments(supplierCode, supplierId, null, priorDateStr),
          _fetchTreasuryTx(supplierId.toString(), null, priorDateStr),
          _fetchCheques(supplierId.toString(), null, priorDateStr),
          _fetchBankTx(supplierId.toString(), null, priorDateStr),
          _fetchLots(supplierId.toString(), null, priorDateStr),
        ]);
        final priorPurchases = priorResults[0];
        final priorPayments = priorResults[1];
        final priorTreasuryTxs = priorResults[2];
        final priorCheques = priorResults[3];
        final priorBankTxs = priorResults[4];
        final priorLots = priorResults[5];

        // Deduplicate: skip ledger entries that reference treasury transactions
        final priorTreasuryIds = priorTreasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

        for (final p in priorPurchases) {
          openingBalance += (p['total_amount'] as num?)?.toDouble() ?? 0;
        }
        for (final l in priorLots) {
          openingBalance += (l['total_fruit_cost'] as num?)?.toDouble() ?? 0;
        }
        for (final p in priorPayments) {
          final refId = p['reference_id']?.toString() ?? '';
          if (refId.isNotEmpty && priorTreasuryIds.contains(refId)) continue;
          final refType = p['reference_type']?.toString() ?? '';
          if (refType == 'lot_receipt') continue; // Skip legacy lot_receipts from ledger_entries
          final amt = (p['amount'] as num?)?.toDouble() ?? 0;
          final isCredit = p['entry_type']?.toString() == 'credit';
          openingBalance += isCredit ? amt : -amt;
        }
        for (final tx in priorTreasuryTxs) {
          final isCredit = tx['type']?.toString() == 'deposit' || tx['type']?.toString() == 'receive' || tx['type']?.toString() == 'income';
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          openingBalance += isCredit ? amt : -amt;
        }
        for (final ch in priorCheques) {
          final amt = (ch['amount'] as num?)?.toDouble() ?? 0;
          final isCredit = ch['type']?.toString() == 'incoming';
          openingBalance += isCredit ? amt : -amt;
        }
        for (final tx in priorBankTxs) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
          final type = tx['type']?.toString() ?? '';
          final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
          openingBalance += isCredit ? amt : -amt;
        }
      }

      // Collect treasury transaction IDs to avoid duplicating ledger entries
      final treasuryTxIds = treasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

      // Add purchases as debit rows
      for (final purchase in purchases) {
        final amount = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
        final purchaseDate = (purchase['invoice_date'] ?? '').toString().substring(0, 10);
        final invoiceNo = purchase['invoice_number']?.toString() ?? purchase['id']?.toString() ?? '—';
        final notes = purchase['notes']?.toString() ?? '';
        final description = notes.isNotEmpty ? 'مشتريات رقم $invoiceNo - $notes' : 'مشتريات رقم $invoiceNo';

        rows.add(StatementRow(
          transactionNumber: invoiceNo,
          date: purchaseDate,
          accountName: 'مشتريات',
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: amount,
          balance: 0,
          type: 'purchase',
          createdAt: (purchase['created_at'] ?? '').toString(),
        ));
      }

      // Add lots as debit rows (wait, buying crop increases supplier credit)
      for (final lot in lots) {
        final amount = (lot['total_fruit_cost'] as num?)?.toDouble() ?? 0;
        final lotDate = (lot['receipt_date'] ?? '').toString().substring(0, 10);
        final lotNo = lot['lot_number']?.toString() ?? lot['id']?.toString() ?? '—';
        final notes = lot['notes']?.toString() ?? '';
        final description = notes.isNotEmpty ? 'شراء محصول رقم $lotNo - $notes' : 'شراء محصول رقم $lotNo';

        rows.add(StatementRow(
          transactionNumber: lotNo,
          date: lotDate,
          accountName: 'شراء محصول',
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: 0,
          credit: amount,
          balance: 0,
          type: 'lot_receipt',
          createdAt: (lot['created_at'] ?? '').toString(),
        ));
      }

      // Add ledger entries (payments/expenses/receive)
      // Skip entries whose reference_id matches a treasury transaction (already shown)
      for (final payment in payments) {
        final refType = payment['reference_type']?.toString() ?? '';
        if (refType == 'lot_receipt') continue; // Skip legacy lot_receipts from ledger_entries

        final refId = payment['reference_id']?.toString() ?? '';
        if (refId.isNotEmpty && treasuryTxIds.contains(refId)) continue;

        final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
        final paymentDate = _toLocalDate(payment['created_at']);
        final entryType = payment['entry_type']?.toString() ?? 'debit';
        final isCredit = entryType == 'credit';
        final accountName = refType == 'lot_receipt' ? 'شراء محصول' :
            refType == 'lot_return' ? 'مرتجع شراء محصول' :
            refType == 'packing_order_debit_note' ? 'إشعار خصم أمر تعبئة' :
            refType == 'cheque_cleared_outgoing' ? 'شيك صادر' :
            refType == 'cheque_cleared_incoming' ? 'شيك وارد' :
            isCredit ? 'سند قبض' : 'مصروف';
        final description = refType == 'lot_receipt'
            ? (payment['description']?.toString().isNotEmpty == true
                ? payment['description'].toString()
                : 'شراء محصول')
            : refType == 'lot_return'
                ? (payment['description']?.toString().isNotEmpty == true
                    ? payment['description'].toString()
                    : 'مرتجع شراء محصول')
                : (payment['description']?.toString() ??
             (refType == 'packing_order_debit_note' ? 'إشعار خصم وتسوية أمر تعبئة' :
              refType == 'cheque_cleared_incoming' ? 'سند قبض شيك' :
              refType == 'receive' ? 'استلام' :
              refType == 'expense' ? 'مصروف' : 'سند قبض'));

        rows.add(StatementRow(
          transactionNumber: payment['id']?.toString() ?? '—',
          date: paymentDate,
          accountName: accountName,
          description: description,
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: refType == 'lot_return' ? 'lot_return' : refType == 'lot_receipt' ? 'lot_receipt' : 'payment',
          createdAt: (payment['created_at'] ?? '').toString(),
        ));
      }

      // Add treasury transactions
      for (final tx in treasuryTxs) {
        final isCredit = tx['type']?.toString() == 'deposit' || tx['type']?.toString() == 'receive' || tx['type']?.toString() == 'income';
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = tx['created_at'];
        final date = _toLocalDate(dateRaw);

        rows.add(StatementRow(
          transactionNumber: tx['id']?.toString() ?? '-',
          date: date,
          createdAt: dateRaw?.toString() ?? '',
          accountName: isCredit ? 'توريد من مورد' : 'سداد للمورد',
          description: tx['description']?.toString() ?? tx['notes']?.toString() ?? (isCredit ? 'إيصال استلام من مورد' : 'إيصال صرف للمورد'),
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isCredit ? 0 : amt,
          credit: isCredit ? amt : 0,
          balance: 0,
          type: 'treasury',
        ));
      }

      // Add cheques
      for (final cheque in cheques) {
        final amt = (cheque['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = cheque['cleared_at'] ?? cheque['created_at'];
        final date = _toLocalDate(dateRaw);
        final chequeNum = cheque['cheque_number']?.toString() ?? '';
        final bankName = cheque['bank_name']?.toString() ?? '';
        final isCredit = cheque['type']?.toString() == 'incoming';
        
        final bankDesc = bankName.isNotEmpty ? ' ($bankName)' : '';
        rows.add(StatementRow(
          transactionNumber: cheque['id']?.toString() ?? '-',
          date: date,
          createdAt: dateRaw?.toString() ?? '',
          accountName: isCredit ? 'شيك وارد' : 'شيك صادر',
          description: isCredit ? 'تحصيل شيك رقم $chequeNum$bankDesc' : 'صرف شيك رقم $chequeNum$bankDesc',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isCredit ? 0 : amt,
          credit: isCredit ? amt : 0,
          balance: 0,
          type: 'cheque',
        ));
      }

      // Add bank transactions
      for (final tx in bankTxs) {
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
        final type = tx['type']?.toString() ?? '';
        final isCredit = type == 'deposit' || type == 'receive' || type == 'income';
        final dateRaw = tx['transaction_date'] ?? tx['created_at'];
        final date = _toLocalDate(dateRaw);

        rows.add(StatementRow(
          transactionNumber: tx['id']?.toString() ?? '-',
          date: date,
          createdAt: (tx['created_at'] ?? '').toString(),
          accountName: isCredit ? 'سند قبض (بنك)' : 'سند صرف (بنك)',
          description: tx['description']?.toString() ?? (isCredit ? 'تحصيل بنكي' : 'دفع بنكي'),
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: isCredit ? 0 : amt,
          credit: isCredit ? amt : 0,
          balance: 0,
          type: 'bank',
        ));
      }

      // Sort by date
      rows.sort((a, b) {
        if (a.type == 'opening' || a.type == 'initial') return -1;
        if (b.type == 'opening' || b.type == 'initial') return 1;
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

      // Insert opening balance - only show when no date filter
      if (from == null && currentState.selectedSupplier!.initialBalance != 0) {
        final initRow = StatementRow(
          transactionNumber: '-',
          date: '',
          accountName: 'رصيد افتتاحي',
          description: 'رصيد افتتاحي',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: currentState.selectedSupplier!.initialBalance < 0 ? currentState.selectedSupplier!.initialBalance.abs() : 0,
          credit: currentState.selectedSupplier!.initialBalance > 0 ? currentState.selectedSupplier!.initialBalance : 0,
          balance: currentState.selectedSupplier!.initialBalance,
          type: 'initial',
          createdAt: '',
        );
        rows.insert(0, initRow);
      }

      if (from != null) {
        final obRow = StatementRow(
          transactionNumber: '—',
          date: from,
          createdAt: '',
          accountName: 'رصيد سابق',
          description: 'رصيد سابق',
          piecesCount: 0,
          quantity: 0,
          unitPrice: 0,
          debit: openingBalance < 0 ? openingBalance.abs() : 0,
          credit: openingBalance > 0 ? openingBalance : 0,
          balance: openingBalance,
          type: 'opening',
        );
        rows.insert(0, obRow);
      }

      // Apply running balance
      double running = openingBalance;
      final withBalance = rows.map((row) {
        if (row.type == 'opening' || row.type == 'initial') {
          running = row.balance;
          return row;
        }
        running += row.credit - row.debit;
        return StatementRow(
          transactionNumber: row.transactionNumber,
          date: row.date,
          accountName: row.accountName,
          description: row.description,
          piecesCount: row.piecesCount,
          quantity: row.quantity,
          unitPrice: row.unitPrice,
          debit: row.debit,
          credit: row.credit,
          balance: running,
          type: row.type,
          createdAt: row.createdAt,
        );
      }).toList();

      final totalDebit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial').fold(0.0, (s, r) => s + r.debit);
      final totalCredit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial').fold(0.0, (s, r) => s + r.credit);
      final finalBalance = withBalance.isNotEmpty ? withBalance.last.balance : 0.0;
      final statementNumber = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final savedNotes = await _notesDao.getNotes(
        entityType: 'supplier',
        entityId: currentState.selectedSupplier!.id!.toString(),
      );

      emit(currentState.copyWith(
        statementRows: withBalance,
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        finalBalance: finalBalance,
        statementNumber: statementNumber,
        openingBalance: openingBalance,
        rowNotes: savedNotes,
      ));
    } catch (e, st) {
      debugPrint('SupplierAccountStatement error: $e\n$st');
      if (!isClosed) {
        emit(SupplierAccountStatementError(message: 'فشل تحميل كشف الحساب: $e'));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPurchases(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client.from('purchase_invoices').select('*').eq('supplier_id', supplierId).eq('status', 'confirmed');
    if (fromDate != null) query = query.gte('invoice_date', fromDate);
    if (toDate != null) query = query.lte('invoice_date', toDate);
    final data = await query.order('invoice_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchLots(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client.from('lot_receipts').select('*').eq('supplier_id', supplierId).eq('is_confirmed', true);
    if (fromDate != null) query = query.gte('receipt_date', fromDate);
    if (toDate != null) query = query.lte('receipt_date', toDate);
    final data = await query.order('receipt_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(
      String supplierCode, String? supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    
    // We search by either supplierCode or supplierId
    String orFilter = 'entity_id.eq.$supplierCode';
    if (supplierId != null && supplierId.isNotEmpty) {
      orFilter += ',entity_id.eq.$supplierId';
    }

    var query = client
        .from('ledger_entries')
        .select('*')
        .eq('entity_type', 'supplier')
        .or(orFilter);
        
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchTreasuryTx(String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('treasury_transactions')
        .select('*')
        .eq('supplier_id', supplierId)
        .neq('status', 'draft');
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchCheques(
      String supplierId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('cheques')
        .select('*')
        .eq('counterparty_type', 'supplier')
        .eq('supplier_id', supplierId)
        .eq('status', 'cleared');
    if (fromDate != null) query = query.gte('cleared_at', fromDate);
    if (toDate != null) query = query.lte('cleared_at', '${toDate}T23:59:59');
    final data = await query.order('cleared_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchBankTx(
      String supplierId, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('bank_account_transactions')
          .select('*')
          .eq('entity_type', 'supplier')
          .eq('entity_id', supplierId)
          .neq('status', 'draft');
          
      if (fromDate != null) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null) {
        query = query.lte('created_at', '${toDate}T23:59:59');
      }
      final data = await query.order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ _fetchBankTx error: $e');
      return [];
    }
  }

  void setRowNote(String transactionNumber, String note) {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      final newNotes = Map<String, String>.from(currentState.rowNotes);
      if (note.isEmpty) {
        newNotes.remove(transactionNumber);
      } else {
        newNotes[transactionNumber] = note;
      }
      emit(currentState.copyWith(rowNotes: newNotes));

      if (currentState.selectedSupplier?.id != null) {
        _notesDao.upsertNote(
          entityType: 'supplier',
          entityId: currentState.selectedSupplier!.id!.toString(),
          referenceId: transactionNumber,
          note: note,
        );
      }
    }
  }

  void reset() {
    final currentState = state;
    if (currentState is SupplierAccountStatementLoaded) {
      final now = DateTime.now();
      emit(currentState.copyWith(
        clearSelectedSupplier: true,
        statementRows: [],
        totalDebit: 0,
        totalCredit: 0,
        finalBalance: 0,
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    }
    refreshData();
  }

  String _toLocalDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw.toString().substring(0, raw.toString().length >= 10 ? 10 : raw.toString().length);
    }
  }
}
