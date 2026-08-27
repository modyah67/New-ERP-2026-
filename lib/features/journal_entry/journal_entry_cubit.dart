import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils.dart';
import '../../data/dao/account_dao.dart';
import '../../data/models/account_model.dart';
import '../../data/models/transaction_model.dart';
import '../../core/data_change_event_bus.dart';
import 'journal_entry_state.dart';

class JournalEntryCubit extends Cubit<JournalEntryState> {
  final AccountDao _accountDao = AccountDao();
  final _client = Supabase.instance.client;

  // ── Form controllers ──
  final amountCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  final debitCtrl = TextEditingController();
  final creditCtrl = TextEditingController();

  // ── Focus nodes ──
  final FocusNode debitFocusNode = FocusNode();
  final FocusNode creditFocusNode = FocusNode();
  final FocusNode amountFocusNode = FocusNode();
  final FocusNode notesFocusNode = FocusNode();

  // ── Keyboard navigation ──
  // (moved to state: debitHighlightIdx, creditHighlightIdx)

  // ── Stream subscriptions ──
  late final StreamSubscription<void> _accountsSub;

  JournalEntryCubit({
    String? initialJournalEntryId,
    String? initialEntryNumber,
  }) : super(const JournalEntryInitial()) {
    _accountsSub =
        DataChangeEventBus.instance.accountsStream.listen((_) {
          if (initialJournalEntryId == null || initialJournalEntryId.isEmpty) {
            loadAll();
          }
        });
    if (initialJournalEntryId != null && initialJournalEntryId.isNotEmpty) {
      loadEntryById(initialJournalEntryId);
    } else if (initialEntryNumber != null && initialEntryNumber.isNotEmpty) {
      setHistorySearchQuery(initialEntryNumber);
      loadAll();
    } else {
      loadAll();
    }
  }

  Future<void> loadAll() async {
    emit(const JournalEntryLoading());
    try {
      await loadHistory();
      final currentState = state;
      if (currentState is JournalEntryLoaded) {
        _computeStats(currentState);
      }
    } catch (e) {
      emit(JournalEntryError(message: 'خطأ أثناء تحميل البيانات: $e'));
    }
  }

  Future<void> loadHistory() async {
    debugPrint('loadHistory started');
    try {
      String? fromDateFilter;
      String? toDateFilter;
      String? searchQuery;

      final currentState = state;
      if (currentState is JournalEntryLoaded) {
        if (currentState.historyFromDate != null) {
          fromDateFilter = AppUtils.formatDateForDb(currentState.historyFromDate!);
        }
        if (currentState.historyToDate != null) {
          toDateFilter = AppUtils.formatDateForDb(currentState.historyToDate!);
        }
        searchQuery = currentState.historySearchQuery.trim();
      }

      final rows = await _client.rpc('rpc_get_journal_history', params: {
        'p_search': searchQuery?.isEmpty == true ? null : searchQuery,
        'p_from_date': fromDateFilter,
        'p_to_date': toDateFilter,
        'p_limit': 1000,
      });

      final txList = (rows as List).map((r) {
        return TransactionModel.fromMap(r as Map<String, dynamic>);
      }).toList();

      final Map<String, List<TransactionModel>> grouped = {};
      for (var tx in txList) {
        final key = tx.journalEntryId ?? tx.entryNumber ?? tx.id ?? '';
        if (key.isNotEmpty) {
          grouped.putIfAbsent(key, () => []).add(tx);
        }
      }

      final entriesList = <Map<String, dynamic>>[];
      grouped.forEach((groupKey, txs) {
        if (txs.isEmpty) return;

        final firstTx = txs.first;
        final entryNum = firstTx.entryNumber ?? groupKey;
        final entryId = firstTx.journalEntryId ?? groupKey;

        final debitLegs = txs.where((t) => t.type == 'debit').toList();
        final creditLegs = txs.where((t) => t.type == 'credit').toList();

        final debitLeg = debitLegs.isNotEmpty ? debitLegs.first : (txs.isNotEmpty ? txs.first : null);
        final creditLeg = creditLegs.isNotEmpty ? creditLegs.first : (txs.length > 1 ? txs[1] : null);

        if (debitLeg == null) return;

        final debitNames = debitLegs.map((d) {
          return d.accountName ?? 'حساب غير معروف';
        }).toSet().join('، ');

        final creditNames = creditLegs.map((c) {
          return c.accountName ?? 'حساب غير معروف';
        }).toSet().join('، ');

        final debitCodes = debitLegs.map((d) => d.accountCode ?? '').where((c) => c.isNotEmpty).toSet().join('، ');
        final creditCodes = creditLegs.map((c) => c.accountCode ?? '').where((c) => c.isNotEmpty).toSet().join('، ');

        final debitCurrencies = debitLegs.map((d) => d.currency ?? 'EGP').toSet().join('، ');
        final creditCurrencies = creditLegs.map((c) => c.currency ?? 'EGP').toSet().join('، ');

        final foreignDebitLegs = debitLegs.where((d) => (d.currency ?? 'EGP') != 'EGP').toList();
        final foreignCreditLegs = creditLegs.where((c) => (c.currency ?? 'EGP') != 'EGP').toList();

        String primaryCurrency = 'EGP';
        double totalAmount = 0.0;
        double totalBaseAmount = 0.0;

        if (foreignDebitLegs.isNotEmpty) {
          primaryCurrency = foreignDebitLegs.first.currency ?? 'USD';
          totalAmount = foreignDebitLegs
              .where((d) => (d.currency ?? 'EGP') == primaryCurrency)
              .fold<double>(0.0, (sum, t) => sum + t.amount);
          totalBaseAmount = foreignDebitLegs
              .where((d) => (d.currency ?? 'EGP') == primaryCurrency)
              .fold<double>(0.0, (sum, t) => sum + (t.amountInBaseCurrency ?? t.amount));
        } else if (foreignCreditLegs.isNotEmpty) {
          primaryCurrency = foreignCreditLegs.first.currency ?? 'USD';
          totalAmount = foreignCreditLegs
              .where((c) => (c.currency ?? 'EGP') == primaryCurrency)
              .fold<double>(0.0, (sum, t) => sum + t.amount);
          totalBaseAmount = foreignCreditLegs
              .where((c) => (c.currency ?? 'EGP') == primaryCurrency)
              .fold<double>(0.0, (sum, t) => sum + (t.amountInBaseCurrency ?? t.amount));
        } else {
          primaryCurrency = debitLeg.currency ?? 'EGP';
          final totalDebit = debitLegs.fold<double>(0.0, (sum, t) => sum + t.amount);
          totalAmount = totalDebit > 0 ? totalDebit : debitLeg.amount;
          totalBaseAmount = totalAmount;
        }

        final debitBaseAmount = debitLegs.fold<double>(0.0, (sum, t) {
          final b = t.amountInBaseCurrency;
          return sum + ((b != null && b > 0) ? b : (t.currency == 'EGP' ? t.amount : t.amount));
        });

        final creditBaseAmount = creditLegs.fold<double>(0.0, (sum, t) {
          final b = t.amountInBaseCurrency;
          return sum + ((b != null && b > 0) ? b : (t.currency == 'EGP' ? t.amount : t.amount));
        });

        if (totalBaseAmount <= 0) {
          totalBaseAmount = debitBaseAmount > 0 ? debitBaseAmount : (creditBaseAmount > 0 ? creditBaseAmount : totalAmount);
        }

        final notes = txs
            .map((t) => t.description)
            .where((d) => d.trim().isNotEmpty)
            .toSet()
            .join(' | ');

        entriesList.add({
          'id': entryId,
          'entryNum': entryNum,
          'date': debitLeg.transactionDate,
          'amount': totalAmount,
          'currency': primaryCurrency,
          'totalBaseAmount': totalBaseAmount,
          'debitName': debitNames.isNotEmpty
              ? debitNames
              : (debitLeg.accountName ?? 'حساب غير معروف'),
          'debitCode': debitCodes.isNotEmpty ? debitCodes : (debitLeg.accountCode ?? ''),
          'debitCurrency': debitCurrencies.isNotEmpty ? debitCurrencies : (debitLeg.currency ?? 'EGP'),
          'debitAmount': debitLegs.fold<double>(0.0, (sum, t) => sum + t.amount),
          'debitBaseAmount': debitBaseAmount,
          'creditName': creditNames.isNotEmpty
              ? creditNames
              : (creditLeg?.accountName ?? 'حساب غير معروف'),
          'creditCode': creditCodes.isNotEmpty ? creditCodes : (creditLeg?.accountCode ?? ''),
          'creditCurrency': creditCurrencies.isNotEmpty ? creditCurrencies : (creditLeg?.currency ?? 'EGP'),
          'creditAmount': creditLegs.fold<double>(0.0, (sum, t) => sum + t.amount),
          'creditBaseAmount': creditBaseAmount,
          'notes': notes.isNotEmpty
              ? notes
              : (debitLeg.description.isNotEmpty ? debitLeg.description : 'من ${debitLeg.accountName ?? ''} إلى ${creditLeg?.accountName ?? ''}'),
          'debitAccountId': debitLeg.accountId,
          'creditAccountId': creditLeg?.accountId,
          'lines': txs,
        });
      });

      if (currentState is JournalEntryLoaded) {
        emit(currentState.copyWith(journalEntries: entriesList));
        _computeStats(currentState.copyWith(journalEntries: entriesList));
      } else {
        final allAccounts = await _accountDao.getAll();
        _computeStatsForInitial(allAccounts, entriesList);
      }
    } catch (e) {
      debugPrint('JournalEntryCubit.loadHistory error: $e');
      final currentState = state;
      if (currentState is JournalEntryLoaded) {
        emit(currentState.copyWith(journalEntries: []));
      }
    }
  }

  /// Load a single journal entry by its ID or entry number (direct navigation).
  Future<void> loadEntryById(String journalEntryId) async {
    final rawId = journalEntryId.trim();
    if (rawId.isEmpty) return;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('JournalEntryCubit.loadEntryById');
    debugPrint('  rawId = "$rawId"');

    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      emit(currentState.copyWith(
        journalEntries: const [],
        isSingleEntryLoading: true,
        clearSingleEntryError: true,
      ));
    } else {
      emit(JournalEntryLoaded(
        accounts: const [],
        journalEntries: const [],
        transactionDate: DateTime.now(),
        totalBalances: 0.0,
        totalAccountsCount: 0,
        totalEntriesCount: 0,
        isSingleEntryLoading: true,
      ));
    }

    try {
      final cleanId = rawId.replaceAll('#', '').trim();
      final parsedId = int.tryParse(cleanId) ?? 0;
      debugPrint('  parsedId = $parsedId (cleanId = "$cleanId")');

      // Strategy 1: RPC rpc_get_journal_entry
      try {
        final rpcRes = await _client.rpc('rpc_get_journal_entry', params: {
          'p_journal_entry_id': parsedId > 0 ? parsedId : null,
          'p_entry_number': parsedId == 0 ? rawId : null,
        });

        debugPrint('  Strategy 1 (RPC): ${rpcRes != null ? "FOUND" : "NULL"}');
        if (rpcRes != null && rpcRes is Map) {
          debugPrint('    entry_id=${rpcRes['id']}, entry_number=${rpcRes['entry_number']}');
        }

        if (rpcRes != null && rpcRes is Map && rpcRes['id'] != null) {
          final data = Map<String, dynamic>.from(rpcRes);
          final rawLines = (data['lines'] as List? ?? []);
          final lines = rawLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();

          final debitLegs = lines.where((r) => ((r['debit'] ?? 0) as num) > 0).toList();
          final creditLegs = lines.where((r) => ((r['credit'] ?? 0) as num) > 0).toList();

          final debitNames = debitLegs.map((d) => d['account_name']?.toString() ?? 'حساب غير معروف').toSet().join('، ');
          final creditNames = creditLegs.map((c) => c['account_name']?.toString() ?? 'حساب غير معروف').toSet().join('، ');

          final debitCodes = debitLegs.map((d) => d['account_code']?.toString() ?? '').where((c) => c.isNotEmpty).toSet().join('، ');
          final creditCodes = creditLegs.map((c) => c['account_code']?.toString() ?? '').where((c) => c.isNotEmpty).toSet().join('، ');

          final foreignDebitLegs = debitLegs.where((d) => (d['currency']?.toString() ?? 'EGP') != 'EGP').toList();
          final foreignCreditLegs = creditLegs.where((c) => (c['currency']?.toString() ?? 'EGP') != 'EGP').toList();

          String currency = 'EGP';
          double totalAmount = 0.0;

          if (foreignDebitLegs.isNotEmpty) {
            currency = foreignDebitLegs.first['currency']?.toString() ?? 'USD';
            totalAmount = foreignDebitLegs
                .where((d) => (d['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final v = r['debit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
          } else if (foreignCreditLegs.isNotEmpty) {
            currency = foreignCreditLegs.first['currency']?.toString() ?? 'USD';
            totalAmount = foreignCreditLegs
                .where((c) => (c['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final v = r['credit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
          } else {
            currency = debitLegs.isNotEmpty ? (debitLegs.first['currency']?.toString() ?? 'EGP') : 'EGP';
            totalAmount = debitLegs.fold<double>(0.0, (sum, r) {
              final v = r['debit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
          }

          final entryNumber = data['entry_number']?.toString() ?? rawId;
          final entryMap = <String, dynamic>{
            'entryNum': entryNumber,
            'date': data['entry_date']?.toString() ?? '',
            'amount': totalAmount,
            'currency': currency,
            'debitName': debitNames.isNotEmpty ? debitNames : 'حساب غير معروف',
            'debitCode': debitCodes,
            'creditName': creditNames.isNotEmpty ? creditNames : 'حساب غير معروف',
            'creditCode': creditCodes,
            'notes': data['description'] ?? '',
            'sourceType': data['source_type'] ?? '',
            'lines': lines,
          };

          _emitSingleEntrySuccess(entryMap, 'القيد المحاسبي رقم $entryNumber');
          return;
        }
      } catch (_) {
        // Fallback to view query
      }

      // Strategy 2: Query v_journal_entry_lines view
      try {
        List<dynamic>? viewLines;

        // 2a. Try exact entry_number match
        try {
          final resExact = await _client
              .from('v_journal_entry_lines')
              .select('*')
              .eq('entry_number', rawId);
          if (resExact.isNotEmpty) {
            viewLines = resExact;
          }
        } catch (_) {}

        // 2b. If not found, try matching by source_id
        if (viewLines == null) {
          try {
            final resSource = await _client
                .from('v_journal_entry_lines')
                .select('*')
                .eq('source_id', rawId);
            if (resSource.isNotEmpty) {
              viewLines = resSource;
            }
          } catch (_) {}
        }

        // 2c. If not found and parsedId > 0, check specific exact prefix patterns
        if (viewLines == null && parsedId > 0) {
          final padded = parsedId.toString().padLeft(5, '0');
          try {
            final resPattern = await _client
                .from('v_journal_entry_lines')
                .select('*')
                .or('entry_number.eq.LOT-$padded,entry_number.eq.RET-$padded,entry_number.eq.PPAY-$padded,entry_number.eq.TMPY-$padded,entry_number.eq.BMPY-$padded,entry_number.eq.BKW-$padded,entry_number.eq.BKD-$padded,entry_number.eq.PINV-$padded,entry_number.eq.SINV-$padded,entry_number.eq.JE-$padded,entry_number.eq.OB-$padded,entry_number.eq.OB-CUS-$padded,entry_number.eq.OB-SUP-$padded,entry_number.eq.OB-CLR-$padded,entry_number.eq.OB-SHP-$padded,entry_number.eq.OB-SH-$padded,entry_number.eq.PAC-OB-$padded,entry_number.eq.$padded,entry_number.eq.$parsedId');
            if (resPattern.isNotEmpty) {
              viewLines = resPattern;
            }
          } catch (_) {}
        }

        debugPrint('  Strategy 2 (view): ${viewLines != null ? "FOUND (${viewLines.length} lines)" : "NULL"}');

        if (viewLines != null && viewLines.isNotEmpty) {
          final lines = viewLines.map((l) => Map<String, dynamic>.from(l as Map)).toList();
          final first = lines.first;

          // Resolve account names if not provided in the view
          final accountIds = <int>{};
          for (var r in lines) {
            if (r['account_id'] != null) {
              final id = r['account_id'];
              accountIds.add(id is int ? id : int.tryParse(id.toString()) ?? 0);
            }
          }

          final accountNames = <int, String?>{};
          final accountCodes = <int, String?>{};
          if (accountIds.isNotEmpty) {
            try {
              final acctsRes = await _client
                  .from('accounts')
                  .select('id, name, account_name, code, account_code')
                  .inFilter('id', accountIds.toList());
              for (var a in acctsRes as List) {
                final rowMap = Map<String, dynamic>.from(a as Map);
                final aId = rowMap['id'];
                final key = aId is int ? aId : int.tryParse(aId.toString()) ?? 0;
                final model = AccountModel.fromMap(rowMap);
                accountNames[key] = model.displayName;
                accountCodes[key] = model.code;
              }
            } catch (_) {}
          }

          final debitLegs = lines.where((r) => ((r['debit'] ?? 0) as num) > 0).toList();
          final creditLegs = lines.where((r) => ((r['credit'] ?? 0) as num) > 0).toList();

          final debitNames = debitLegs.map((d) {
            final id = d['account_id'];
            final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
            return d['account_name']?.toString() ?? accountNames[key] ?? 'حساب غير معروف';
          }).toSet().join('، ');

          final creditNames = creditLegs.map((c) {
            final id = c['account_id'];
            final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
            return c['account_name']?.toString() ?? accountNames[key] ?? 'حساب غير معروف';
          }).toSet().join('، ');

          final debitCodes = debitLegs.map((d) {
            final id = d['account_id'];
            final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
            return d['account_code']?.toString() ?? accountCodes[key] ?? '';
          }).where((c) => c.isNotEmpty).toSet().join('، ');

          final creditCodes = creditLegs.map((c) {
            final id = c['account_id'];
            final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
            return c['account_code']?.toString() ?? accountCodes[key] ?? '';
          }).where((c) => c.isNotEmpty).toSet().join('، ');

          final foreignDebitLegs = debitLegs.where((d) => (d['currency']?.toString() ?? 'EGP') != 'EGP').toList();
          final foreignCreditLegs = creditLegs.where((c) => (c['currency']?.toString() ?? 'EGP') != 'EGP').toList();

          String currency = 'EGP';
          double totalAmount = 0.0;
          double totalBaseAmount = 0.0;

          if (foreignDebitLegs.isNotEmpty) {
            currency = foreignDebitLegs.first['currency']?.toString() ?? 'USD';
            totalAmount = foreignDebitLegs
                .where((d) => (d['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final v = r['debit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
            totalBaseAmount = foreignDebitLegs
                .where((d) => (d['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final b = r['amount_in_base_currency'];
                  if (b is num) return sum + b.toDouble();
                  final parsedB = double.tryParse(b?.toString() ?? '');
                  if (parsedB != null && parsedB > 0) return sum + parsedB;
                  final v = r['debit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
          } else if (foreignCreditLegs.isNotEmpty) {
            currency = foreignCreditLegs.first['currency']?.toString() ?? 'USD';
            totalAmount = foreignCreditLegs
                .where((c) => (c['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final v = r['credit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
            totalBaseAmount = foreignCreditLegs
                .where((c) => (c['currency']?.toString() ?? 'EGP') == currency)
                .fold<double>(0.0, (sum, r) {
                  final b = r['amount_in_base_currency'];
                  if (b is num) return sum + b.toDouble();
                  final parsedB = double.tryParse(b?.toString() ?? '');
                  if (parsedB != null && parsedB > 0) return sum + parsedB;
                  final v = r['credit'];
                  return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
                });
          } else {
            currency = debitLegs.isNotEmpty ? (debitLegs.first['currency']?.toString() ?? 'EGP') : 'EGP';
            totalAmount = debitLegs.fold<double>(0.0, (sum, r) {
              final v = r['debit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
            totalBaseAmount = totalAmount;
          }

          final debitCurrencies = debitLegs.map((d) => d['currency']?.toString() ?? 'EGP').toSet().join('، ');
          final creditCurrencies = creditLegs.map((c) => c['currency']?.toString() ?? 'EGP').toSet().join('، ');

          final debitBaseAmount = debitLegs.fold<double>(0.0, (sum, r) {
            final b = r['amount_in_base_currency'];
            if (b is num) return sum + b.toDouble();
            final parsedB = double.tryParse(b?.toString() ?? '');
            if (parsedB != null && parsedB > 0) return sum + parsedB;
            final v = r['debit'];
            return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
          });

          final creditBaseAmount = creditLegs.fold<double>(0.0, (sum, r) {
            final b = r['amount_in_base_currency'];
            if (b is num) return sum + b.toDouble();
            final parsedB = double.tryParse(b?.toString() ?? '');
            if (parsedB != null && parsedB > 0) return sum + parsedB;
            final v = r['credit'];
            return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
          });

          if (totalBaseAmount <= 0) {
            totalBaseAmount = debitBaseAmount > 0 ? debitBaseAmount : (creditBaseAmount > 0 ? creditBaseAmount : totalAmount);
          }

          final entryNumber = first['entry_number']?.toString() ?? rawId;
          final entryMap = <String, dynamic>{
            'entryNum': entryNumber,
            'date': first['transaction_date']?.toString() ?? '',
            'amount': totalAmount,
            'currency': currency,
            'totalBaseAmount': totalBaseAmount,
            'debitName': debitNames.isNotEmpty ? debitNames : 'حساب غير معروف',
            'debitCode': debitCodes,
            'debitCurrency': debitCurrencies.isNotEmpty ? debitCurrencies : 'EGP',
            'debitAmount': debitLegs.fold<double>(0.0, (sum, r) {
              final v = r['debit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            }),
            'debitBaseAmount': debitBaseAmount,
            'creditName': creditNames.isNotEmpty ? creditNames : 'حساب غير معروف',
            'creditCode': creditCodes,
            'creditCurrency': creditCurrencies.isNotEmpty ? creditCurrencies : 'EGP',
            'creditAmount': creditLegs.fold<double>(0.0, (sum, r) {
              final v = r['credit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            }),
            'creditBaseAmount': creditBaseAmount,
            'notes': first['description'] ?? '',
            'sourceType': first['source_type'] ?? '',
            'lines': lines,
          };

          _emitSingleEntrySuccess(entryMap, 'القيد المحاسبي رقم $entryNumber');
          return;
        }
      } catch (e) {
        debugPrint('v_journal_entry_lines fallback: $e');
      }

      // Strategy 3: Direct tables lookup
      Map<String, dynamic>? jeRes;
      if (parsedId > 0) {
        jeRes = await _client
            .from('journal_entries')
            .select('id, entry_number, entry_date, description, source_type, status, created_at')
            .eq('id', parsedId)
            .maybeSingle();
        debugPrint('  Strategy 3a (by id=$parsedId): ${jeRes != null ? "FOUND" : "NULL"}');
      }
      jeRes ??= await _client
          .from('journal_entries')
          .select('id, entry_number, entry_date, description, source_type, status, created_at')
          .eq('entry_number', rawId)
          .maybeSingle();
      debugPrint('  Strategy 3b (by entry_number=$rawId): ${jeRes != null ? "FOUND" : "NULL"}');

      if (jeRes == null) {
        debugPrint('  ❌ ALL STRATEGIES FAILED for rawId="$rawId"');
        debugPrint('═══════════════════════════════════════════');
        final s = state;
        if (s is JournalEntryLoaded) {
          emit(s.copyWith(
            isSingleEntryLoading: false,
            singleEntryError: 'تعذر العثور على القيد المحاسبي رقم $rawId.',
          ));
        }
        return;
      }

      final aleRes = await _client
          .from('account_ledger_entries')
          .select('id, account_id, debit, credit, currency, amount_in_base_currency, description')
          .eq('journal_entry_id', jeRes['id'] as int)
          .order('id', ascending: true);

      final accountIds = <int>{};
      for (var r in aleRes as List) {
        if (r['account_id'] != null) {
          final id = r['account_id'];
          accountIds.add(id is int ? id : int.tryParse(id.toString()) ?? 0);
        }
      }

      final accountNames = <int, String?>{};
      final accountCodes = <int, String?>{};
      if (accountIds.isNotEmpty) {
        final acctsRes = await _client
            .from('accounts')
            .select('id, name, account_name, code, account_code')
            .inFilter('id', accountIds.toList());
        for (var a in acctsRes as List) {
          final rowMap = Map<String, dynamic>.from(a as Map);
          final aId = rowMap['id'];
          final key = aId is int ? aId : int.tryParse(aId.toString()) ?? 0;
          final model = AccountModel.fromMap(rowMap);
          accountNames[key] = model.displayName;
          accountCodes[key] = model.code;
        }
      }

      final debitLegs = (aleRes as List).where((r) => (r['debit'] ?? 0) > 0).toList();
      final creditLegs = (aleRes as List).where((r) => (r['credit'] ?? 0) > 0).toList();

      final debitNames = debitLegs.map((d) {
        final id = d['account_id'];
        final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
        return (accountNames[key]) ?? 'حساب غير معروف';
      }).toSet().join('، ');

      final creditNames = creditLegs.map((c) {
        final id = c['account_id'];
        final key = id is int ? id : int.tryParse(id?.toString() ?? '') ?? 0;
        return (accountNames[key]) ?? 'حساب غير معروف';
      }).toSet().join('، ');

      final foreignDebitLegs = debitLegs.where((d) => (d['currency']?.toString() ?? 'EGP') != 'EGP').toList();
      final foreignCreditLegs = creditLegs.where((c) => (c['currency']?.toString() ?? 'EGP') != 'EGP').toList();

      String currency = 'EGP';
      double totalAmount = 0.0;
      double totalBaseAmount = 0.0;

      if (foreignDebitLegs.isNotEmpty) {
        currency = foreignDebitLegs.first['currency']?.toString() ?? 'USD';
        totalAmount = foreignDebitLegs
            .where((d) => (d['currency']?.toString() ?? 'EGP') == currency)
            .fold<double>(0.0, (sum, r) {
              final v = r['debit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
        totalBaseAmount = foreignDebitLegs
            .where((d) => (d['currency']?.toString() ?? 'EGP') == currency)
            .fold<double>(0.0, (sum, r) {
              final b = r['amount_in_base_currency'];
              if (b is num) return sum + b.toDouble();
              final parsedB = double.tryParse(b?.toString() ?? '');
              if (parsedB != null && parsedB > 0) return sum + parsedB;
              final v = r['debit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
      } else if (foreignCreditLegs.isNotEmpty) {
        currency = foreignCreditLegs.first['currency']?.toString() ?? 'USD';
        totalAmount = foreignCreditLegs
            .where((c) => (c['currency']?.toString() ?? 'EGP') == currency)
            .fold<double>(0.0, (sum, r) {
              final v = r['credit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
        totalBaseAmount = foreignCreditLegs
            .where((c) => (c['currency']?.toString() ?? 'EGP') == currency)
            .fold<double>(0.0, (sum, r) {
              final b = r['amount_in_base_currency'];
              if (b is num) return sum + b.toDouble();
              final parsedB = double.tryParse(b?.toString() ?? '');
              if (parsedB != null && parsedB > 0) return sum + parsedB;
              final v = r['credit'];
              return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
            });
      } else {
        currency = debitLegs.isNotEmpty ? (debitLegs.first['currency']?.toString() ?? 'EGP') : 'EGP';
        totalAmount = debitLegs.fold<double>(0.0, (sum, r) {
          final v = r['debit'];
          return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
        });
        totalBaseAmount = totalAmount;
      }

      final debitCurrencies = debitLegs.map((d) => d['currency']?.toString() ?? 'EGP').toSet().join('، ');
      final creditCurrencies = creditLegs.map((c) => c['currency']?.toString() ?? 'EGP').toSet().join('، ');

      final debitBaseAmount = debitLegs.fold<double>(0.0, (sum, r) {
        final b = r['amount_in_base_currency'];
        if (b is num) return sum + b.toDouble();
        final parsedB = double.tryParse(b?.toString() ?? '');
        if (parsedB != null && parsedB > 0) return sum + parsedB;
        final v = r['debit'];
        return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
      });

      final creditBaseAmount = creditLegs.fold<double>(0.0, (sum, r) {
        final b = r['amount_in_base_currency'];
        if (b is num) return sum + b.toDouble();
        final parsedB = double.tryParse(b?.toString() ?? '');
        if (parsedB != null && parsedB > 0) return sum + parsedB;
        final v = r['credit'];
        return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
      });

      if (totalBaseAmount <= 0) {
        totalBaseAmount = debitBaseAmount > 0 ? debitBaseAmount : (creditBaseAmount > 0 ? creditBaseAmount : totalAmount);
      }

      final debitAcctId = debitLegs.isNotEmpty ? (debitLegs.first['account_id'] is int ? debitLegs.first['account_id'] : int.tryParse(debitLegs.first['account_id']?.toString() ?? '')) : null;
      final creditAcctId = creditLegs.isNotEmpty ? (creditLegs.first['account_id'] is int ? creditLegs.first['account_id'] : int.tryParse(creditLegs.first['account_id']?.toString() ?? '')) : null;

      final entryNumber = jeRes['entry_number']?.toString() ?? rawId;
      debugPrint('  ✅ FOUND: id=${jeRes['id']}, entry_number=$entryNumber');
      debugPrint('═══════════════════════════════════════════');
      final entryMap = <String, dynamic>{
        'entryNum': entryNumber,
        'date': jeRes['entry_date']?.toString() ?? '',
        'amount': totalAmount,
        'currency': currency,
        'totalBaseAmount': totalBaseAmount,
        'debitName': debitNames.isNotEmpty ? debitNames : (debitAcctId != null ? (accountNames[debitAcctId] ?? 'حساب غير معروف') : 'حساب غير معروف'),
        'debitCode': (debitAcctId != null ? (accountCodes[debitAcctId] ?? '') : ''),
        'debitCurrency': debitCurrencies.isNotEmpty ? debitCurrencies : 'EGP',
        'debitAmount': debitLegs.fold<double>(0.0, (sum, r) {
          final v = r['debit'];
          return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
        }),
        'debitBaseAmount': debitBaseAmount,
        'creditName': creditNames.isNotEmpty ? creditNames : (creditAcctId != null ? (accountNames[creditAcctId] ?? 'حساب غير معروف') : 'حساب غير معروف'),
        'creditCode': (creditAcctId != null ? (accountCodes[creditAcctId] ?? '') : ''),
        'creditCurrency': creditCurrencies.isNotEmpty ? creditCurrencies : 'EGP',
        'creditAmount': creditLegs.fold<double>(0.0, (sum, r) {
          final v = r['credit'];
          return sum + ((v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0);
        }),
        'creditBaseAmount': creditBaseAmount,
        'notes': jeRes['description'] ?? '',
        'sourceType': jeRes['source_type'] ?? '',
        'lines': aleRes,
      };

      _emitSingleEntrySuccess(entryMap, 'القيد المحاسبي رقم $entryNumber');
    } catch (e) {
      debugPrint('JournalEntryCubit.loadEntryById error: $e');
      final s = state;
      if (s is JournalEntryLoaded) {
        emit(s.copyWith(
          isSingleEntryLoading: false,
          singleEntryError: 'تعذر تحميل القيد المحاسبي: $e',
        ));
      }
    }
  }

  void _emitSingleEntrySuccess(Map<String, dynamic> entryMap, String title) {
    final cur = state;
    final base = cur is JournalEntryLoaded
        ? cur
        : JournalEntryLoaded(
            accounts: const [],
            journalEntries: const [],
            transactionDate: DateTime.now(),
            totalBalances: 0.0,
            totalAccountsCount: 0,
            totalEntriesCount: 0,
          );
    emit(base.copyWith(
      journalEntries: [entryMap],
      isSingleEntryLoading: false,
      singleEntryTitle: title,
      clearSingleEntryError: true,
    ));
  }

  void _computeStats(JournalEntryLoaded currentState) {
    final totalAccountsCount = currentState.accounts.length;

    double sum = 0.0;
    for (var acc in currentState.accounts) {
      if (acc.balance > 0) sum += acc.balance;
    }

    final distinctEntries = <String>{};
    for (var entry in currentState.journalEntries) {
      distinctEntries.add(entry['entryNum'].toString());
    }

    emit(currentState.copyWith(
      totalBalances: sum,
      totalAccountsCount: totalAccountsCount,
      totalEntriesCount: distinctEntries.length,
    ));
  }

  void _computeStatsForInitial(
      List<AccountModel> accounts, List<Map<String, dynamic>> entries) {
    double sum = 0.0;
    for (var acc in accounts) {
      if (acc.balance > 0) sum += acc.balance;
    }

    final distinctEntries = <String>{};
    for (var entry in entries) {
      distinctEntries.add(entry['entryNum'].toString());
    }

    final now = DateTime.now();
    emit(JournalEntryLoaded(
      accounts: accounts,
      journalEntries: entries,
      transactionDate: now,
      totalBalances: sum,
      totalAccountsCount: accounts.length,
      totalEntriesCount: distinctEntries.length,
    ));
  }

  // ── Autocomplete Search Helpers ──

  DateTime get transactionDate {
    final s = state;
    return s is JournalEntryLoaded ? s.transactionDate : DateTime.now();
  }

  String get historySearchQuery {
    final s = state;
    return s is JournalEntryLoaded ? s.historySearchQuery : '';
  }

  List<AccountModel> get accounts {
    final s = state;
    return s is JournalEntryLoaded ? s.accounts : [];
  }

  List<Map<String, dynamic>> get journalEntries {
    final s = state;
    return s is JournalEntryLoaded ? s.journalEntries : [];
  }

  void setTransactionDate(DateTime date) {
    final s = state;
    if (s is JournalEntryLoaded) {
      emit(s.copyWith(transactionDate: date));
    }
  }

  void setHistorySearchQuery(String query) {
    final s = state;
    if (s is JournalEntryLoaded) {
      emit(s.copyWith(historySearchQuery: query));
    }
  }

  void searchDebit(String query) {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return;

    if (query.trim().isEmpty) {
      emit(currentState.copyWith(debitResults: [], debitHighlightIdx: 0));
      return;
    }
    final q = query.trim().toLowerCase();
    final results = currentState.accounts
        .where((a) =>
            a.name.toLowerCase().contains(q) || a.code.contains(q))
        .toList();
    emit(currentState.copyWith(debitResults: results, debitHighlightIdx: 0));
  }

  void searchCredit(String query) {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return;

    if (query.trim().isEmpty) {
      emit(currentState.copyWith(creditResults: [], creditHighlightIdx: 0));
      return;
    }
    final q = query.trim().toLowerCase();
    final results = currentState.accounts
        .where((a) =>
            a.name.toLowerCase().contains(q) || a.code.contains(q))
        .toList();
    emit(currentState.copyWith(creditResults: results, creditHighlightIdx: 0));
  }

  List<AccountModel> getDebitResults(String query) {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return [];
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    return currentState.accounts
        .where((a) =>
            a.name.toLowerCase().contains(q) || a.code.contains(q))
        .toList();
  }

  List<AccountModel> getCreditResults(String query) {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return [];
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    return currentState.accounts
        .where((a) =>
            a.name.toLowerCase().contains(q) || a.code.contains(q))
        .toList();
  }

  void selectDebitAccount(AccountModel acc) {
    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      debitCtrl.text = '${acc.code} - ${acc.name}';
      debitFocusNode.unfocus();
      emit(currentState.copyWith(
        selectedDebitAccount: acc,
        debitResults: [],
        debitHighlightIdx: 0,
      ));
    }
  }

  void selectCreditAccount(AccountModel acc) {
    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      creditCtrl.text = '${acc.code} - ${acc.name}';
      creditFocusNode.unfocus();
      emit(currentState.copyWith(
        selectedCreditAccount: acc,
        creditResults: [],
        creditHighlightIdx: 0,
      ));
    }
  }

  void clearDebitSelection() {
    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      debitCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedDebitAccount: true,
        debitResults: [],
        debitHighlightIdx: 0,
      ));
    }
  }

  void clearCreditSelection() {
    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      creditCtrl.clear();
      emit(currentState.copyWith(
        clearSelectedCreditAccount: true,
        creditResults: [],
        creditHighlightIdx: 0,
      ));
    }
  }

  // ── Date Pickers ──

  Future<void> pickTransactionDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(transactionDate: picked));
    }
  }

  Future<void> pickHistoryFromDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyFromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyFromDate: picked));
      loadHistory();
    }
  }

  Future<void> pickHistoryToDate(BuildContext context) async {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentState.historyToDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      emit(currentState.copyWith(historyToDate: picked));
      loadHistory();
    }
  }

  void clearHistoryFilters() {
    final currentState = state;
    if (currentState is JournalEntryLoaded) {
      emit(currentState.copyWith(
        historySearchQuery: '',
        clearHistoryFromDate: true,
        clearHistoryToDate: true,
      ));
      loadHistory();
    }
  }

  // ── Save Journal Entry (Double-Entry) ──

  Future<bool> saveEntry() async {
    final currentState = state;
    if (currentState is! JournalEntryLoaded) return false;
    if (currentState.isSaving) return false;

    final amountText = amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      return false;
    }

    if (currentState.selectedDebitAccount == null) {
      return false;
    }

    if (currentState.selectedCreditAccount == null) {
      return false;
    }

    if (currentState.selectedDebitAccount!.id ==
        currentState.selectedCreditAccount!.id) {
      return false;
    }

    final creditAcc = currentState.selectedCreditAccount!;
    if (creditAcc.balance < amount) {
      return false;
    }

    emit(currentState.copyWith(isSaving: true));
    try {
      final dateStr =
          AppUtils.formatDateForDb(currentState.transactionDate);

      final description = notesCtrl.text.trim().isEmpty
          ? 'قيد تسوية يومية بين ${currentState.selectedDebitAccount!.name} و ${currentState.selectedCreditAccount!.name}'
          : notesCtrl.text.trim();

      // 2. Dispatch the Business Event to the Enterprise Posting Engine
      await _client.rpc('rpc_build_manual_journal', params: {
        'payload': {
          'date': dateStr,
          'amount': amount,
          'debit_account_id': currentState.selectedDebitAccount!.id!,
          'credit_account_id': currentState.selectedCreditAccount!.id!,
          'description': description,
        }
      });

      // Notify other cubits
      DataChangeEventBus.instance.notifyAccountsChanged();

      // Clear form
      amountCtrl.clear();
      notesCtrl.clear();
      clearDebitSelection();
      clearCreditSelection();

      final now2 = DateTime.now();
      emit(currentState.copyWith(
        isSaving: false,
        transactionDate: now2,
        clearSelectedDebitAccount: true,
        clearSelectedCreditAccount: true,
      ));

      // Reload lists and stats
      await loadAll();
      return true;
    } catch (e) {
      final updatedState = state;
      if (updatedState is JournalEntryLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
      return false;
    } finally {
      final updatedState = state;
      if (updatedState is JournalEntryLoaded) {
        emit(updatedState.copyWith(isSaving: false));
      }
    }
  }

  @override
  void onChange(Change<JournalEntryState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    _accountsSub.cancel();
    amountCtrl.dispose();
    notesCtrl.dispose();
    debitCtrl.dispose();
    creditCtrl.dispose();
    debitFocusNode.dispose();
    creditFocusNode.dispose();
    amountFocusNode.dispose();
    notesFocusNode.dispose();
    return super.close();
  }
}
