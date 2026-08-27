import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/statement_notes_dao.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import 'clearing_agent_statement_state.dart';

class ClearingAgentStatementCubit extends Cubit<ClearingAgentStatementState> {
  final ClearingAgentDao _dao = ClearingAgentDao();
  final StatementNotesDao _notesDao = StatementNotesDao();

  ClearingAgentStatementCubit() : super(const ClearingAgentStatementInitial()) {
    _init();
  }

  Future<void> init() => _init();

  Future<void> _init() async {
    try {
      final agents = await _dao.getAll(limit: 2000, offset: 0);
      final now = DateTime.now();
      if (!isClosed) {
        emit(ClearingAgentStatementLoaded(
          agents: agents,
          fromDate: DateTime(now.year, now.month, 1),
          toDate: now,
        ));
      }
    } catch (e) {
      if (!isClosed) emit(ClearingAgentStatementError(message: 'فشل تحميل المخلصين: $e'));
    }
  }

  Future<void> refreshData() async {
    final currentState = state;
    if (currentState is ClearingAgentStatementLoaded) {
      try {
        final agents = await _dao.getAll(limit: 2000, offset: 0);
        emit(currentState.copyWith(agents: agents));
      } catch (e) {
        emit(ClearingAgentStatementError(message: 'فشل تحميل البيانات: $e'));
      }
    }
  }

  Future<void> selectAgent(ClearingAgentModel? agent) async {
    final currentState = state;
    if (currentState is ClearingAgentStatementLoaded) {
      emit(currentState.copyWith(
        selectedAgent: agent,
        clearSelectedAgent: agent == null,
      ));
      if (agent != null) await loadStatement();
    }
  }

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! ClearingAgentStatementLoaded) return;
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
    if (currentState is! ClearingAgentStatementLoaded) return;
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
    if (currentState is! ClearingAgentStatementLoaded) return;
    if (currentState.selectedAgent == null) return;

    emit(currentState.copyWith(statementRows: [], totalDebit: 0, totalCredit: 0, finalBalance: 0));

    try {
      final agent = currentState.selectedAgent!;
      final agentId = agent.id;
      final from = currentState.fromDate != null ? AppUtils.formatDateForDb(currentState.fromDate!) : null;
      final to = currentState.toDate != null ? AppUtils.formatDateForDb(currentState.toDate!) : null;

      final costItems = await _fetchCostItems(agentId.toString(), from, to);
      final payments = await _fetchPayments(agentId.toString(), from, to);

      final shipmentIds = costItems.map((c) => c['shipment_id']).where((id) => id != null).toSet().toList();
      final shipmentsMap = <dynamic, Map<String, dynamic>>{};
      if (shipmentIds.isNotEmpty) {
        final data = await Supabase.instance.client
            .from('export_shipments')
            .select('id, shipment_no')
            .inFilter('id', shipmentIds);
        for (final row in data) {
          shipmentsMap[row['id']] = Map<String, dynamic>.from(row);
        }
      }

      final cheques = await _fetchCheques(agentId.toString(), from, to);
      final bankTxs = await _fetchBankTx(agentId.toString(), from, to);

      final rows = <StatementRow>[];

      double openingBalance = agent.initialBalance;

      if (from != null) {
        final beforeDate = currentState.fromDate!.subtract(const Duration(days: 1));
        final dayBefore = AppUtils.formatDateForDb(beforeDate);
        
        final results = await Future.wait([
          _fetchCostItems(agentId.toString(), null, dayBefore),
          _fetchPayments(agentId.toString(), null, dayBefore),
          _fetchTreasuryTx(agentId.toString(), null, dayBefore),
          _fetchCheques(agentId.toString(), null, dayBefore),
          _fetchBankTx(agentId.toString(), null, dayBefore),
        ]);
        final priorItems = results[0];
        final priorPaymentsList = results[1];
        final priorTreasuryTxs = results[2];
        final priorCheques = results[3];
        final priorBankTxs = results[4];

        for (final item in priorItems) {
          final rawAmt = (item['total_price'] as num?)?.toDouble() ?? 0;
          final exchange = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          openingBalance += rawAmt / exchange;
        }

        final priorTreasuryIds = priorTreasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();
        for (final p in priorPaymentsList) {
          final refId = p['reference_id']?.toString() ?? '';
          if (refId.isNotEmpty && priorTreasuryIds.contains(refId)) continue;
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

      if (from == null && agent.initialBalance != 0) {
        final initRow = StatementRow(
          transactionNumber: '-',
          date: '',
          accountName: 'رصيد افتتاحي',
          description: 'رصيد افتتاحي',
          debit: agent.initialBalance < 0 ? agent.initialBalance.abs() : 0,
          credit: agent.initialBalance > 0 ? agent.initialBalance : 0,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          balance: agent.initialBalance,
          type: 'initial',
          createdAt: '',
        );
        rows.insert(0, initRow);
      }

      for (final item in costItems) {
        final rawAmt = (item['total_price'] as num?)?.toDouble() ?? 0;
        final exchange = (item['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final amount = rawAmt / exchange;
        final shipmentId = item['shipment_id'];
        var shipmentNo = AppUtils.cleanShipmentNo(
            shipmentsMap[shipmentId]?['shipment_no']?.toString() ?? '',
            shipmentId);
        final itemDate = _toLocalDate(item['created_at']);
        final categoryStr = item['category']?.toString() ?? '';
        final category = AppUtils.costCategoryLabel(categoryStr);
        String description;
        if (categoryStr.toLowerCase() == 'manual' || categoryStr.toLowerCase() == 'other') {
          description = shipmentNo.isNotEmpty ? 'شحنة $shipmentNo' : 'تكلفة شحن';
        } else {
          description = shipmentNo.isNotEmpty ? 'شحنة $shipmentNo - $category' : 'تكلفة شحن - $category';
        }

        rows.add(StatementRow(
          transactionNumber: shipmentNo.isNotEmpty ? shipmentNo : (item['id']?.toString() ?? '-'),
          date: itemDate,
          accountName: 'تكليف شحن',
          description: description,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: 0,
          credit: amount,
          balance: 0,
          type: 'cost',
          createdAt: (item['created_at'] ?? '').toString(),
        ));
      }

      final treasuryTxs = await _fetchTreasuryTx(agentId.toString(), from, to);
      final currentTreasuryIds = treasuryTxs.map((tx) => tx['id']?.toString() ?? '').toSet();

      for (final p in payments) {
        final refId = p['reference_id']?.toString() ?? '';
        if (refId.isNotEmpty && currentTreasuryIds.contains(refId)) continue;
        final amount = (p['amount'] as num?)?.toDouble() ?? 0;
        final date = _toLocalDate(p['created_at']);
        final refType = p['reference_type']?.toString() ?? '';
        final entryType = p['entry_type']?.toString() ?? 'debit';
        final desc = p['description']?.toString() ??
            (refType == 'receive' ? 'استلام' : refType == 'expense' ? 'مصاريف' : 'سداد');
        final isCredit = entryType == 'credit';
        rows.add(StatementRow(
          transactionNumber: p['reference_id']?.toString() ?? p['id'].toString(),
          date: date,
          accountName: isCredit ? 'سند قبض' : 'سند صرف',
          description: desc,
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isCredit ? 0 : amount,
          credit: isCredit ? amount : 0,
          balance: 0,
          type: 'payment',
          createdAt: (p['created_at'] ?? '').toString(),
        ));
      }

      for (final tx in treasuryTxs) {
        final isCredit = tx['type']?.toString() == 'deposit' || tx['type']?.toString() == 'receive' || tx['type']?.toString() == 'income';
        final amt = (tx['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = tx['created_at'];
        final date = dateRaw != null ? dateRaw.toString().split('T')[0] : '';
        
        if (isCredit) {
          rows.add(StatementRow(
            transactionNumber: tx['id']?.toString() ?? '-',
            date: date,
            createdAt: dateRaw?.toString() ?? '',
            accountName: 'توريد من مخلص',
            description: tx['notes']?.toString() ?? 'ايصال استلام من مخلص',
            piecesCount: 0, quantity: 0, unitPrice: 0,
            debit: 0,
            credit: amt,
            balance: 0,
            type: 'treasury',
          ));
        } else {
          rows.add(StatementRow(
            transactionNumber: tx['id']?.toString() ?? '-',
            date: date,
            createdAt: dateRaw?.toString() ?? '',
            accountName: 'سداد لمخلص',
            description: tx['notes']?.toString() ?? 'ايصال صرف لمخلص',
            piecesCount: 0, quantity: 0, unitPrice: 0,
            debit: amt,
            credit: 0,
            balance: 0,
            type: 'treasury',
          ));
        }
      }

      // Add cheques
      for (final cheque in cheques) {
        final amt = (cheque['amount'] as num?)?.toDouble() ?? 0;
        final dateRaw = cheque['cleared_at'] ?? cheque['created_at'];
        final date = dateRaw != null ? dateRaw.toString().split('T')[0] : '';
        final chequeNum = cheque['cheque_number']?.toString() ?? '';
        final isCredit = cheque['type']?.toString() == 'incoming';
        
        rows.add(StatementRow(
          transactionNumber: cheque['id']?.toString() ?? '-',
          date: date,
          createdAt: dateRaw?.toString() ?? '',
          accountName: isCredit ? 'شيك وارد' : 'شيك صادر',
          description: isCredit ? 'تحصيل شيك رقم $chequeNum' : 'صرف شيك رقم $chequeNum',
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
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: isCredit ? 0 : amt,
          credit: isCredit ? amt : 0,
          balance: 0,
          type: 'bank',
        ));
      }

      rows.sort((a, b) {
        if (a.type == 'opening' || a.type == 'initial') return -1;
        if (b.type == 'opening' || b.type == 'initial') return 1;
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

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
        entityType: 'clearing_agent',
        entityId: currentState.selectedAgent!.id!.toString(),
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
      debugPrint('ClearingAgentStatement error: $e\n$st');
      if (!isClosed) {
        emit(ClearingAgentStatementError(message: 'فشل تحميل كشف الحساب: $e'));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCostItems(String agentId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('shipment_cost_items')
        .select('id, shipment_id, category, total_price, exchange_rate, created_at')
        .eq('vendor_type', 'clearing_agent')
        .eq('vendor_id', agentId.toString());
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchPayments(String agentId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('ledger_entries')
        .select('*')
        .eq('entity_type', 'clearing_agent')
        .eq('entity_id', agentId)
        .neq('reference_type', 'expense')
        .neq('reference_type', 'receive')
        .neq('reference_type', 'shipment_cost_item');
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchTreasuryTx(String agentId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('treasury_transactions')
        .select('*')
        .eq('clearing_agent_id', agentId)
        .neq('status', 'draft');
    if (fromDate != null) query = query.gte('created_at', fromDate);
    if (toDate != null) query = query.lte('created_at', '${toDate}T23:59:59');
    final data = await query.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchCheques(
      String agentId, String? fromDate, String? toDate) async {
    final client = Supabase.instance.client;
    var query = client
        .from('cheques')
        .select('*')
        .eq('counterparty_type', 'clearing_agent')
        .eq('clearing_agent_id', agentId)
        .eq('status', 'cleared');
    if (fromDate != null) query = query.gte('cleared_at', fromDate);
    if (toDate != null) query = query.lte('cleared_at', '${toDate}T23:59:59');
    final data = await query.order('cleared_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> _fetchBankTx(
      String agentId, String? fromDate, String? toDate) async {
    try {
      final client = Supabase.instance.client;
      var query = client
          .from('bank_account_transactions')
          .select('*')
          .eq('entity_type', 'clearing_agent')
          .eq('entity_id', agentId)
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
    if (currentState is ClearingAgentStatementLoaded) {
      final newNotes = Map<String, String>.from(currentState.rowNotes);
      if (note.isEmpty) {
        newNotes.remove(transactionNumber);
      } else {
        newNotes[transactionNumber] = note;
      }
      emit(currentState.copyWith(rowNotes: newNotes));

      if (currentState.selectedAgent?.id != null) {
        _notesDao.upsertNote(
          entityType: 'clearing_agent',
          entityId: currentState.selectedAgent!.id!.toString(),
          referenceId: transactionNumber,
          note: note,
        );
      }
    }
  }

  void reset() {
    final currentState = state;
    if (currentState is ClearingAgentStatementLoaded) {
      final now = DateTime.now();
      emit(currentState.copyWith(
        clearSelectedAgent: true,
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
