import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/dao/profit_distribution_dao.dart';
import '../../data/dao/exchange_rate_dao.dart';
import '../../data/dao/statement_notes_dao.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/statement_row_model.dart';
import '../../core/utils.dart';
import '../../data/services/currency_conversion_service.dart';
import 'shareholder_statement_state.dart';

class ShareholderStatementCubit extends Cubit<ShareholderStatementState> {
  final ShareholderDao _dao = ShareholderDao();
  final ProfitDistributionDao _settingsDao = ProfitDistributionDao();
  final ExchangeRateDao _exchangeRateDao = ExchangeRateDao();
  final StatementNotesDao _notesDao = StatementNotesDao();

  ShareholderStatementCubit() : super(const ShareholderStatementState()) {
    _init();
  }

  Future<void> init() => _init();

  Future<void> _init() async {
    try {
      final shareholders = await _dao.getAll(limit: 2000, offset: 0);
      final now = DateTime.now();
      emit(ShareholderStatementState(
        shareholders: shareholders,
        fromDate: DateTime(now.year, now.month, 1),
        toDate: now,
      ));
    } catch (e) {
      debugPrint('ShareholderStatement init error: $e');
    }
  }

  Future<void> refreshData() async {
    final s = state;
    try {
      final shareholders = await _dao.getAll(limit: 2000, offset: 0);
      emit(s.copyWith(shareholders: shareholders));
    } catch (_) {}
  }

  Future<void> selectShareholder(ShareholderModel? shareholder) async {
    final s = state;
    emit(s.copyWith(selectedShareholder: shareholder, clearSelected: shareholder == null));
    if (shareholder != null) await loadStatement();
  }

  void setFromDate(DateTime? d) {
    final s = state;
    emit(s.copyWith(fromDate: d));
  }

  void setToDate(DateTime? d) {
    final s = state;
    emit(s.copyWith(toDate: d));
  }

  void setCurrency(String currency) {
    final s = state;
    emit(s.copyWith(selectedCurrency: currency));
    if (s.selectedShareholder != null) loadStatement();
  }

  Future<void> loadStatement() async {
    final s = state;
    if (s.selectedShareholder == null) return;

    emit(s.copyWith(loading: true, rows: [], totalDebit: 0, totalCredit: 0, finalBalance: 0, totalProfitShare: 0));

    try {
      final shareholder = s.selectedShareholder!;
      final shareholderId = shareholder.id!;
      final from = s.fromDate != null ? AppUtils.formatDateForDb(s.fromDate!) : null;
      final to = s.toDate != null ? AppUtils.formatDateForDb(s.toDate!) : null;
      final currency = s.selectedCurrency;

      final results = await Future.wait([
        _fetchTreasuryTransactions(shareholderId, from, to, currency: currency),
        _fetchBankTransactions(shareholderId, from, to, currency: currency),
        _fetchCheques(shareholderId, from, to, currency: currency),
        _fetchProfitTransactions(shareholderId, from, to, currency: currency),
      ]);

      final treasuryRows = results[0] as List<StatementRow>;
      final bankRows = results[1] as List<StatementRow>;
      final chequeRows = results[2] as List<StatementRow>;
      final profitRows = results[3] as List<StatementRow>;

      final allRows = <StatementRow>[...treasuryRows, ...bankRows, ...chequeRows, ...profitRows];

      allRows.sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });

      double initialBalance = 0;
      if (currency == 'EGP') {
        initialBalance += shareholder.initialBalanceEgp;
      } else if (currency == 'USD') {
        initialBalance += shareholder.initialBalanceUsd;
      } else if (currency == 'EUR') {
        initialBalance += shareholder.initialBalanceEur;
      } else if (currency == 'GBP') {
        initialBalance += shareholder.initialBalanceGbp;
      }

      double openingBalance = initialBalance;

      if (from != null && s.fromDate != null) {
        final beforeDate = s.fromDate!.subtract(const Duration(days: 1));
        final dayBefore = AppUtils.formatDateForDb(beforeDate);
        
        final priorResults = await Future.wait([
          _fetchTreasuryTransactions(shareholderId, null, dayBefore, currency: currency),
          _fetchBankTransactions(shareholderId, null, dayBefore, currency: currency),
          _fetchCheques(shareholderId, null, dayBefore, currency: currency),
          _fetchProfitTransactions(shareholderId, null, dayBefore, currency: currency),
        ]);

        final priorTreasury = priorResults[0] as List<StatementRow>;
        final priorBank = priorResults[1] as List<StatementRow>;
        final priorCheques = priorResults[2] as List<StatementRow>;
        final priorProfitRows = priorResults[3] as List<StatementRow>;
        
        final priorAllRows = <StatementRow>[...priorTreasury, ...priorBank, ...priorCheques, ...priorProfitRows];
        for (final row in priorAllRows) {
           openingBalance += row.credit - row.debit;
        }
      }

      if (from == null && initialBalance != 0) {
        allRows.insert(0, StatementRow(
          transactionNumber: '-',
          date: '',
          accountName: 'رصيد افتتاحي',
          description: 'رصيد افتتاحي',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: initialBalance < 0 ? initialBalance.abs() : 0,
          credit: initialBalance > 0 ? initialBalance : 0,
          balance: initialBalance,
          type: 'initial',
          createdAt: '',
        ));
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
        allRows.insert(0, obRow);
      }

      double running = openingBalance;
      final withBalance = allRows.map((row) {
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

      final totalDebit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial' && r.type != 'profit').fold(0.0, (s2, r) => s2 + r.debit);
      final totalCredit = withBalance.where((r) => r.type != 'opening' && r.type != 'initial' && r.type != 'profit').fold(0.0, (s2, r) => s2 + r.credit);
      final totalProfitShare = withBalance.where((r) => r.type == 'profit').fold(0.0, (s2, r) => s2 + r.credit);

      final finalBalance = withBalance.isNotEmpty ? withBalance.last.balance : openingBalance;

      // Load persisted notes from DB
      final savedNotes = await _notesDao.getNotes(
        entityType: 'shareholder',
        entityId: shareholderId,
      );

      if (!isClosed) {
        emit(ShareholderStatementState(
          shareholders: state.shareholders,
          selectedShareholder: shareholder,
          fromDate: state.fromDate,
          toDate: state.toDate,
          selectedCurrency: state.selectedCurrency,
          rows: withBalance,
          totalDebit: totalDebit,
          totalCredit: totalCredit,
          finalBalance: finalBalance,
          totalProfitShare: totalProfitShare,
          openingBalance: openingBalance,
          rowNotes: savedNotes,
          loading: false,
        ));
      }
    } catch (e, st) {
      debugPrint('ShareholderStatement loadStatement error: $e\n$st');
      if (!isClosed) {
        emit(ShareholderStatementState(
          shareholders: state.shareholders,
          selectedShareholder: state.selectedShareholder,
          fromDate: state.fromDate,
          toDate: state.toDate,
          rows: [],
          loading: false,
        ));
      }
    }
  }

  // ── Fetch treasury transactions for shareholder ──
  Future<List<StatementRow>> _fetchTreasuryTransactions(String shareholderId, String? from, String? to, {String? currency}) async {
    try {
      var query = Supabase.instance.client
          .from('treasury_transactions')
          .select('*, treasuries!treasury_transactions_treasury_id_fkey(name)')
          .eq('shareholder_id', shareholderId)
          .neq('status', 'draft')
          .not('description', 'like', '%شيك%');

      if (from != null) query = query.gte('created_at', from);
      if (to != null) query = query.lte('created_at', '${to}T23:59:59');
      if (currency != null) query = query.eq('currency', currency);
      final data = await query.order('created_at', ascending: true);

      return (data as List).map((t) {
        final map = Map<String, dynamic>.from(t);
        final treasuryName = (map['treasuries'] is Map) ? map['treasuries']['name']?.toString() ?? '' : '';
        final typeRaw = map['type']?.toString() ?? '';
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = map['currency']?.toString() ?? 'EGP';
        final date = _toLocalDate(map['created_at']);
        final desc = map['description']?.toString() ?? '';
        
        final isProfit = desc.contains('توزيع أرباح');
        final isDeposit = typeRaw == 'deposit';
        final type = isProfit ? 'profit' : (isDeposit ? 'credit' : 'debit');

        String accountName;
        double debit = 0;
        double credit = 0;
        if (isDeposit) {
          accountName = isProfit ? 'توزيع أرباح' : 'استلام نقدية - $treasuryName';
          credit = amount;
        } else {
          accountName = 'صرف نقدية - $treasuryName';
          debit = amount;
        }

        final currencyNote = currency != 'EGP' ? ' [$currency]' : '';

        return StatementRow(
          transactionNumber: (map['id']?.toString() ?? '').length > 8 ? map['id'].toString().substring(0, 8) : (map['id']?.toString() ?? '—'),
          date: date,
          accountName: accountName,
          description: '$desc$currencyNote',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: debit,
          credit: credit,
          balance: 0,
          type: type,
          createdAt: (map['created_at'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('_fetchTreasuryTransactions error: $e');
      return [];
    }
  }

  // ── Fetch bank transactions for shareholder ──
  Future<List<StatementRow>> _fetchBankTransactions(String shareholderId, String? from, String? to, {String? currency}) async {
    try {
      // If filtering by currency, first get matching bank account IDs
      List<int>? allowedBankIds;
      if (currency != null) {
        final accs = await Supabase.instance.client
            .from('bank_accounts')
            .select('id')
            .eq('currency', currency);
        allowedBankIds = (accs as List).map((a) => (a['id'] as num).toInt()).toList();
        if (allowedBankIds.isEmpty) return [];
      }

      var query = Supabase.instance.client
          .from('bank_account_transactions')
          .select('*, bank_accounts(name, currency)')
          .eq('entity_type', 'shareholder')
          .eq('entity_id', shareholderId)
          .neq('status', 'draft')
          .not('description', 'like', '%شيك%');

      if (from != null) query = query.gte('created_at', from);
      if (to != null) query = query.lte('created_at', '${to}T23:59:59');
      if (allowedBankIds != null) query = query.inFilter('bank_account_id', allowedBankIds);
      final data = await query.order('created_at', ascending: true);

      return (data as List).map((t) {
        final map = Map<String, dynamic>.from(t);
        final bankName = (map['bank_accounts'] is Map) ? map['bank_accounts']['name']?.toString() ?? '' : '';
        final currency = (map['bank_accounts'] is Map) ? map['bank_accounts']['currency']?.toString() ?? 'EGP' : 'EGP';
        final type = map['type']?.toString() ?? '';
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final date = _toLocalDate(map['created_at']);
        final desc = map['description']?.toString() ?? '';

        final isDeposit = type == 'deposit';
        double debit = 0;
        double credit = 0;
        String accountName;
        if (isDeposit) {
          accountName = 'إيداع بنكي - $bankName';
          credit = amount;
        } else {
          accountName = 'سحب بنكي - $bankName';
          debit = amount;
        }

        final currencyNote = currency != 'EGP' ? ' [$currency]' : '';

        return StatementRow(
          transactionNumber: (map['id']?.toString() ?? '').length > 8 ? map['id'].toString().substring(0, 8) : (map['id']?.toString() ?? '—'),
          date: date,
          accountName: accountName,
          description: '$desc$currencyNote',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: debit,
          credit: credit,
          balance: 0,
          type: 'bank',
          createdAt: (map['created_at'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('_fetchBankTransactions error: $e');
      return [];
    }
  }

  // ── Fetch cheques for shareholder ──
  Future<List<StatementRow>> _fetchCheques(String shareholderId, String? from, String? to, {String? currency}) async {
    try {
      var query = Supabase.instance.client
          .from('cheques')
          .select()
          .eq('shareholder_id', shareholderId)
          .eq('status', 'cleared');

      if (from != null) query = query.gte('created_at', from);
      if (to != null) query = query.lte('created_at', '${to}T23:59:59');
      if (currency != null) query = query.eq('currency', currency);
      final data = await query.order('created_at', ascending: true);

      return (data as List).map((t) {
        final map = Map<String, dynamic>.from(t);
        final type = map['type']?.toString() ?? '';
        final status = map['status']?.toString() ?? '';
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final currency = map['currency']?.toString() ?? 'EGP';
        final date = _toLocalDate(map['created_at']);
        final number = map['number']?.toString() ?? '';
        final dueDate = map['due_date']?.toString() ?? '';

        final isIncoming = type == 'incoming';
        double debit = 0;
        double credit = 0;
        String accountName;
        String desc;
        if (isIncoming) {
          accountName = 'شيك وارد';
          credit = amount;
          desc = 'شيك وارد #$number - $status';
        } else {
          accountName = 'شيك صادر';
          debit = amount;
          desc = 'شيك صادر #$number - $status';
        }

        final currencyNote = currency != 'EGP' ? ' [$currency]' : '';
        final dueStr = dueDate.isNotEmpty ? ' - استحقاق: $dueDate' : '';

        return StatementRow(
          transactionNumber: number.isNotEmpty ? number : ((map['id']?.toString() ?? '').length > 8 ? map['id'].toString().substring(0, 8) : (map['id']?.toString() ?? '—')),
          date: date,
          accountName: accountName,
          description: '$desc$dueStr$currencyNote',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: debit,
          credit: credit,
          balance: 0,
          type: 'cheque',
          createdAt: (map['created_at'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('_fetchCheques error: $e');
      return [];
    }
  }

  // _fetchProfitShare removed.

  // ── Fetch profit distributions for shareholder ──
  Future<List<StatementRow>> _fetchProfitTransactions(String shareholderId, String? from, String? to, {String? currency}) async {
    try {
      var query = Supabase.instance.client
          .from('shareholder_profit_distributions')
          .select('*, export_shipments(shipment_no)')
          .eq('shareholder_id', shareholderId)
          .isFilter('deleted_at', null);
      
      if (from != null) query = query.gte('created_at', from);
      if (to != null) query = query.lte('created_at', '${to}T23:59:59');
      if (currency != null) query = query.eq('currency', currency);
      
      final data = await query.order('created_at', ascending: true);
      return (data as List).map((p) {
        final map = Map<String, dynamic>.from(p);
        final shipmentNo = (map['export_shipments'] is Map) ? map['export_shipments']['shipment_no']?.toString() ?? '' : '';
        final amount = (map['converted_amount'] as num?)?.toDouble() ?? 0.0;
        final curr = map['currency']?.toString() ?? 'EGP';
        final date = _toLocalDate(map['created_at']);
        
        final currencyNote = curr != 'EGP' ? ' [$curr]' : '';
        
        return StatementRow(
          transactionNumber: (map['id']?.toString() ?? '').length > 8 ? map['id'].toString().substring(0, 8) : (map['id']?.toString() ?? '—'),
          date: date,
          accountName: 'توزيع أرباح',
          description: 'توزيع أرباح شحنة - $shipmentNo$currencyNote',
          piecesCount: 0, quantity: 0, unitPrice: 0,
          debit: 0,
          credit: amount,
          balance: 0,
          type: 'profit',
          createdAt: (map['created_at'] ?? '').toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('_fetchProfitTransactions error: $e');
      return [];
    }
  }

  void setRowNote(String transactionNumber, String note) {
    final newNotes = Map<String, String>.from(state.rowNotes);
    if (note.isEmpty) {
      newNotes.remove(transactionNumber);
    } else {
      newNotes[transactionNumber] = note;
    }
    emit(state.copyWith(rowNotes: newNotes));

    // Persist to DB
    if (state.selectedShareholder?.id != null) {
      _notesDao.upsertNote(
        entityType: 'shareholder',
        entityId: state.selectedShareholder!.id!.toString(),
        referenceId: transactionNumber,
        note: note,
      );
    }
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
