// lib/features/journal_entry/journal_entry_excel_service.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import '../../core/utils.dart';
import '../../data/models/account_model.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/transaction_model.dart';

class JournalEntryExcelService {
  
  // ── Export Chart of Accounts Tree to CSV ────────────────────────────
  static Future<void> exportAccountsTree(
    BuildContext context,
    List<AccountModel> accounts,
  ) async {
    List<Map<String, dynamic>> flattenTree(String? parentId, int depth) {
      final children = accounts.where((a) => a.parentId == parentId).toList();
      final list = <Map<String, dynamic>>[];
      for (final child in children) {
        list.add({'account': child, 'depth': depth});
        list.addAll(flattenTree(child.id, depth + 1));
      }
      return list;
    }
    
    final treeRows = flattenTree(null, 0);

    final List<List<dynamic>> rows = [
      ['كود الحساب', 'مستوى الشجرة', 'اسم الحساب', 'النوع', 'الرصيد الحالي'],
    ];

    for (final row in treeRows) {
      final a = row['account'] as AccountModel;
      final depth = row['depth'] as int;
      rows.add([
        a.code,
        'المستوى ${depth + 1}',
        '   ' * depth + a.name,
        _getTypeLabel(a.type),
        a.balance,
      ]);
    }

    await _exportCsv(context, 'شجرة_الحسابات', rows);
  }

  // ── Headers for Journal Entries ─────────────────────────────────────
  static const List<String> journalHeaders = [
    'تاريخ القيد',
    'رقم القيد',
    'الجانب المدين (المستلم)',
    'كود المدين',
    'عملة المدين',
    'مبلغ المدين',
    'مبلغ المدين بالمصري (ج.م)',
    'الجانب الدائن (المسحوب منه)',
    'كود الدائن',
    'عملة الدائن',
    'مبلغ الدائن',
    'مبلغ الدائن بالمصري (ج.م)',
    'عملة القيد',
    'إجمالي القيد بالعملة',
    'إجمالي القيد بالمصري (ج.م)',
    'البيان / الملاحظات',
  ];

  // ── Fetch all journal entries from database for export/backup ────────
  static Future<List<Map<String, dynamic>>> fetchAllEntries() async {
    final client = Supabase.instance.client;
    List rows = [];
    try {
      final res = await client.rpc('rpc_get_journal_history', params: {
        'p_limit': 10000,
      });
      rows = res as List;
    } catch (_) {
      try {
        final res = await client
            .from('v_journal_entry_lines')
            .select('*')
            .order('transaction_date', ascending: true)
            .order('id', ascending: true);
        rows = res as List;
      } catch (_) {}
    }

    final txList = rows.map((r) => TransactionModel.fromMap(Map<String, dynamic>.from(r as Map))).toList();
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

      final debitNames = debitLegs.map((d) => d.accountName ?? 'حساب غير معروف').toSet().join('، ');
      final creditNames = creditLegs.map((c) => c.accountName ?? 'حساب غير معروف').toSet().join('، ');
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

      final notes = txs.map((t) => t.description).where((d) => d.trim().isNotEmpty).toSet().join(' | ');

      entriesList.add({
        'id': entryId,
        'entryNum': entryNum,
        'date': firstTx.transactionDate.isNotEmpty ? firstTx.transactionDate : firstTx.createdAt,
        'amount': totalAmount,
        'currency': primaryCurrency,
        'totalBaseAmount': totalBaseAmount,
        'debitName': debitNames.isNotEmpty ? debitNames : (debitLeg.accountName ?? 'حساب غير معروف'),
        'debitCode': debitCodes.isNotEmpty ? debitCodes : (debitLeg.accountCode ?? ''),
        'debitCurrency': debitCurrencies.isNotEmpty ? debitCurrencies : 'EGP',
        'debitAmount': debitLegs.fold<double>(0.0, (sum, t) => sum + t.amount),
        'debitBaseAmount': debitBaseAmount,
        'creditName': creditNames.isNotEmpty ? creditNames : (creditLeg?.accountName ?? 'حساب غير معروف'),
        'creditCode': creditCodes.isNotEmpty ? creditCodes : (creditLeg?.accountCode ?? ''),
        'creditCurrency': creditCurrencies.isNotEmpty ? creditCurrencies : 'EGP',
        'creditAmount': creditLegs.fold<double>(0.0, (sum, t) => sum + t.amount),
        'creditBaseAmount': creditBaseAmount,
        'notes': notes.isNotEmpty ? notes : firstTx.description,
        'lines': txs,
      });
    });

    return entriesList;
  }

  // ── Generate 16-column Rows for Journal Entries ──────────────────────
  static List<List<dynamic>> generateJournalRows(List<Map<String, dynamic>> entries) {
    final List<List<dynamic>> rows = [
      List<dynamic>.from(journalHeaders),
    ];

    List<dynamic> buildCsvRow({
      required String date,
      required String entryNum,
      required List<dynamic> debitLines,
      required List<dynamic> creditLines,
      String? defaultNotes,
    }) {
      final debNames = <String>[];
      final debCodes = <String>[];
      final debCurrs = <String>{};
      double debAmt = 0.0;
      double debBase = 0.0;

      for (final d in debitLines) {
        final isMap = d is Map;
        final name = isMap ? d['account_name']?.toString() : (d as TransactionModel).accountName;
        final code = isMap ? d['account_code']?.toString() : (d as TransactionModel).accountCode;
        final curr = isMap ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
        final amt = isMap
            ? ((d['amount'] as num?)?.toDouble() ?? (d['debit'] as num?)?.toDouble() ?? 0.0)
            : (d as TransactionModel).amount;
        final base = isMap
            ? ((d['amount_in_base_currency'] as num?)?.toDouble() ?? (curr == 'EGP' ? amt : amt))
            : ((d as TransactionModel).amountInBaseCurrency ?? (curr == 'EGP' ? amt : amt));

        if (name != null && name.isNotEmpty) debNames.add(name);
        if (code != null && code.isNotEmpty) debCodes.add(code);
        debCurrs.add(curr);
        debAmt += amt;
        debBase += base;
      }

      final crdNames = <String>[];
      final crdCodes = <String>[];
      final crdCurrs = <String>{};
      double crdAmt = 0.0;
      double crdBase = 0.0;

      for (final c in creditLines) {
        final isMap = c is Map;
        final name = isMap ? c['account_name']?.toString() : (c as TransactionModel).accountName;
        final code = isMap ? c['account_code']?.toString() : (c as TransactionModel).accountCode;
        final curr = isMap ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
        final amt = isMap
            ? ((c['amount'] as num?)?.toDouble() ?? (c['credit'] as num?)?.toDouble() ?? 0.0)
            : (c as TransactionModel).amount;
        final base = isMap
            ? ((c['amount_in_base_currency'] as num?)?.toDouble() ?? (curr == 'EGP' ? amt : amt))
            : ((c as TransactionModel).amountInBaseCurrency ?? (curr == 'EGP' ? amt : amt));

        if (name != null && name.isNotEmpty) crdNames.add(name);
        if (code != null && code.isNotEmpty) crdCodes.add(code);
        crdCurrs.add(curr);
        crdAmt += amt;
        crdBase += base;
      }

      // Determine primary currency and total amount
      final allLines = [...debitLines, ...creditLines];
      final foreignDebits = debitLines.where((d) {
        final curr = d is Map ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
        return curr != 'EGP';
      }).toList();
      final foreignCredits = creditLines.where((c) {
        final curr = c is Map ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
        return curr != 'EGP';
      }).toList();

      String primaryCurr = 'EGP';
      double totalAmt = 0.0;
      double totalBaseAmt = 0.0;

      if (foreignDebits.isNotEmpty) {
        final firstD = foreignDebits.first;
        primaryCurr = firstD is Map ? (firstD['currency']?.toString() ?? 'USD') : ((firstD as TransactionModel).currency ?? 'USD');
        totalAmt = foreignDebits.fold<double>(0.0, (sum, d) {
          final isMap = d is Map;
          final curr = isMap ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
          if (curr != primaryCurr) return sum;
          final a = isMap ? ((d['amount'] as num?)?.toDouble() ?? (d['debit'] as num?)?.toDouble() ?? 0.0) : (d as TransactionModel).amount;
          return sum + a;
        });
        totalBaseAmt = foreignDebits.fold<double>(0.0, (sum, d) {
          final isMap = d is Map;
          final curr = isMap ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
          if (curr != primaryCurr) return sum;
          final b = isMap ? ((d['amount_in_base_currency'] as num?)?.toDouble() ?? 0.0) : ((d as TransactionModel).amountInBaseCurrency ?? 0.0);
          return sum + b;
        });
      } else if (foreignCredits.isNotEmpty) {
        final firstC = foreignCredits.first;
        primaryCurr = firstC is Map ? (firstC['currency']?.toString() ?? 'USD') : ((firstC as TransactionModel).currency ?? 'USD');
        totalAmt = foreignCredits.fold<double>(0.0, (sum, c) {
          final isMap = c is Map;
          final curr = isMap ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
          if (curr != primaryCurr) return sum;
          final a = isMap ? ((c['amount'] as num?)?.toDouble() ?? (c['credit'] as num?)?.toDouble() ?? 0.0) : (c as TransactionModel).amount;
          return sum + a;
        });
        totalBaseAmt = foreignCredits.fold<double>(0.0, (sum, c) {
          final isMap = c is Map;
          final curr = isMap ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
          if (curr != primaryCurr) return sum;
          final b = isMap ? ((c['amount_in_base_currency'] as num?)?.toDouble() ?? 0.0) : ((c as TransactionModel).amountInBaseCurrency ?? 0.0);
          return sum + b;
        });
      } else {
        primaryCurr = 'EGP';
        totalAmt = debAmt > 0 ? debAmt : crdAmt;
        totalBaseAmt = debBase > 0 ? debBase : crdBase;
      }

      if (totalBaseAmt <= 0) {
        totalBaseAmt = debBase > 0 ? debBase : (crdBase > 0 ? crdBase : totalAmt);
      }

      final notesList = allLines.map((l) {
        final isMap = l is Map;
        return isMap ? l['description']?.toString() ?? '' : (l as TransactionModel).description;
      }).where((d) => d.trim().isNotEmpty).toSet().toList();

      final notesStr = notesList.isNotEmpty ? notesList.join(' | ') : (defaultNotes ?? '—');

      return [
        AppUtils.formatDate(DateTime.tryParse(date) ?? DateTime.now()),
        entryNum,
        debNames.isNotEmpty ? debNames.toSet().join('، ') : '—',
        debCodes.isNotEmpty ? debCodes.toSet().join('، ') : '—',
        debCurrs.isNotEmpty ? debCurrs.join('، ') : 'EGP',
        AppUtils.roundDouble(debAmt, places: 2),
        AppUtils.roundDouble(debBase, places: 2),
        crdNames.isNotEmpty ? crdNames.toSet().join('، ') : '—',
        crdCodes.isNotEmpty ? crdCodes.toSet().join('، ') : '—',
        crdCurrs.isNotEmpty ? crdCurrs.join('، ') : 'EGP',
        AppUtils.roundDouble(crdAmt, places: 2),
        AppUtils.roundDouble(crdBase, places: 2),
        primaryCurr,
        AppUtils.roundDouble(totalAmt, places: 2),
        AppUtils.roundDouble(totalBaseAmt, places: 2),
        notesStr,
      ];
    }

    List<dynamic> buildSingleLineRow({
      required String date,
      required String entryNum,
      required dynamic line,
      required double totalEntryAmt,
      required double totalEntryBaseAmt,
      required String primaryCurr,
    }) {
      final isMap = line is Map;
      final type = isMap ? line['type']?.toString() : (line as TransactionModel).type;
      final isDebit = type == 'debit';
      final name = isMap ? (line['account_name']?.toString() ?? '—') : ((line as TransactionModel).accountName ?? '—');
      final code = isMap ? (line['account_code']?.toString() ?? '—') : ((line as TransactionModel).accountCode ?? '—');
      final curr = isMap ? (line['currency']?.toString() ?? 'EGP') : ((line as TransactionModel).currency ?? 'EGP');
      final amt = isMap
          ? ((line['amount'] as num?)?.toDouble() ?? (line['debit'] as num?)?.toDouble() ?? (line['credit'] as num?)?.toDouble() ?? 0.0)
          : (line as TransactionModel).amount;
      final base = isMap
          ? ((line['amount_in_base_currency'] as num?)?.toDouble() ?? (curr == 'EGP' ? amt : amt))
          : ((line as TransactionModel).amountInBaseCurrency ?? (curr == 'EGP' ? amt : amt));
      final desc = isMap ? (line['description']?.toString() ?? '') : ((line as TransactionModel).description);

      if (isDebit) {
        return [
          AppUtils.formatDate(DateTime.tryParse(date) ?? DateTime.now()),
          entryNum,
          name,
          code,
          curr,
          AppUtils.roundDouble(amt, places: 2),
          AppUtils.roundDouble(base, places: 2),
          '—',
          '—',
          '—',
          0.00,
          0.00,
          primaryCurr,
          AppUtils.roundDouble(totalEntryAmt, places: 2),
          AppUtils.roundDouble(totalEntryBaseAmt, places: 2),
          desc.isNotEmpty ? desc : '—',
        ];
      } else {
        return [
          AppUtils.formatDate(DateTime.tryParse(date) ?? DateTime.now()),
          entryNum,
          '—',
          '—',
          '—',
          0.00,
          0.00,
          name,
          code,
          curr,
          AppUtils.roundDouble(amt, places: 2),
          AppUtils.roundDouble(base, places: 2),
          primaryCurr,
          AppUtils.roundDouble(totalEntryAmt, places: 2),
          AppUtils.roundDouble(totalEntryBaseAmt, places: 2),
          desc.isNotEmpty ? desc : '—',
        ];
      }
    }

    for (final entry in entries) {
      final lines = (entry['lines'] as List?) ?? [];
      final date = entry['date']?.toString() ?? '';
      final entryNum = entry['entryNum']?.toString() ?? '';
      final defaultNotes = entry['notes']?.toString();

      if (lines.isEmpty) {
        // Fallback for simple map without lines
        rows.add([
          AppUtils.formatDate(DateTime.tryParse(date) ?? DateTime.now()),
          entryNum,
          entry['debitName']?.toString() ?? '—',
          entry['debitCode']?.toString() ?? '—',
          entry['debitCurrency']?.toString() ?? 'EGP',
          AppUtils.roundDouble((entry['debitAmount'] as num?)?.toDouble() ?? (entry['amount'] as num?)?.toDouble() ?? 0.0, places: 2),
          AppUtils.roundDouble((entry['debitBaseAmount'] as num?)?.toDouble() ?? (entry['totalBaseAmount'] as num?)?.toDouble() ?? 0.0, places: 2),
          entry['creditName']?.toString() ?? '—',
          entry['creditCode']?.toString() ?? '—',
          entry['creditCurrency']?.toString() ?? 'EGP',
          AppUtils.roundDouble((entry['creditAmount'] as num?)?.toDouble() ?? (entry['amount'] as num?)?.toDouble() ?? 0.0, places: 2),
          AppUtils.roundDouble((entry['creditBaseAmount'] as num?)?.toDouble() ?? (entry['totalBaseAmount'] as num?)?.toDouble() ?? 0.0, places: 2),
          entry['currency']?.toString() ?? 'EGP',
          AppUtils.roundDouble((entry['amount'] as num?)?.toDouble() ?? 0.0, places: 2),
          AppUtils.roundDouble((entry['totalBaseAmount'] as num?)?.toDouble() ?? (entry['amount'] as num?)?.toDouble() ?? 0.0, places: 2),
          defaultNotes ?? '—',
        ]);
        continue;
      }

      final debitLines = <dynamic>[];
      final creditLines = <dynamic>[];

      for (final line in lines) {
        final isMap = line is Map;
        final type = isMap ? line['type']?.toString() : (line as TransactionModel).type;
        if (type == 'debit') {
          debitLines.add(line);
        } else {
          creditLines.add(line);
        }
      }

      // Check if entry has compound distinct balanced currency groups (e.g. Export Shipment USD Sales + EGP COGS)
      final foreignDebits = debitLines.where((d) {
        final curr = d is Map ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
        return curr != 'EGP';
      }).toList();
      final foreignCredits = creditLines.where((c) {
        final curr = c is Map ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
        return curr != 'EGP';
      }).toList();
      final egpDebits = debitLines.where((d) {
        final curr = d is Map ? (d['currency']?.toString() ?? 'EGP') : ((d as TransactionModel).currency ?? 'EGP');
        return curr == 'EGP';
      }).toList();
      final egpCredits = creditLines.where((c) {
        final curr = c is Map ? (c['currency']?.toString() ?? 'EGP') : ((c as TransactionModel).currency ?? 'EGP');
        return curr == 'EGP';
      }).toList();

      // Case 1: Simple 1-debit, 1-credit entry
      if (debitLines.length == 1 && creditLines.length == 1) {
        rows.add(buildCsvRow(
          date: date,
          entryNum: entryNum,
          debitLines: debitLines,
          creditLines: creditLines,
          defaultNotes: defaultNotes,
        ));
      }
      // Case 2: Multi-currency 2-pair compound entry (e.g. EXP-00007 with 1 USD pair and 1 EGP pair)
      else if (foreignDebits.length == 1 && foreignCredits.length == 1 && egpDebits.length == 1 && egpCredits.length == 1) {
        rows.add(buildCsvRow(
          date: date,
          entryNum: entryNum,
          debitLines: foreignDebits,
          creditLines: foreignCredits,
          defaultNotes: defaultNotes,
        ));
        rows.add(buildCsvRow(
          date: date,
          entryNum: entryNum,
          debitLines: egpDebits,
          creditLines: egpCredits,
          defaultNotes: defaultNotes,
        ));
      }
      // Case 3: Multi-leg compound entry (e.g. Packing Orders PK-... with 2 debits and 5 credits, or custom multi-line entries)
      else {
        final primaryCurr = entry['currency']?.toString() ?? (foreignDebits.isNotEmpty ? (foreignDebits.first is Map ? foreignDebits.first['currency']?.toString() : (foreignDebits.first as TransactionModel).currency) ?? 'USD' : 'EGP');
        final totalEntryAmt = (entry['amount'] as num?)?.toDouble() ?? debitLines.fold<double>(0.0, (s, d) => s + (d is Map ? ((d['amount'] ?? d['debit']) as num?)?.toDouble() ?? 0.0 : (d as TransactionModel).amount));
        final totalEntryBaseAmt = (entry['totalBaseAmount'] as num?)?.toDouble() ?? (entry['amount'] as num?)?.toDouble() ?? totalEntryAmt;

        for (final d in debitLines) {
          rows.add(buildSingleLineRow(
            date: date,
            entryNum: entryNum,
            line: d,
            totalEntryAmt: totalEntryAmt,
            totalEntryBaseAmt: totalEntryBaseAmt,
            primaryCurr: primaryCurr,
          ));
        }
        for (final c in creditLines) {
          rows.add(buildSingleLineRow(
            date: date,
            entryNum: entryNum,
            line: c,
            totalEntryAmt: totalEntryAmt,
            totalEntryBaseAmt: totalEntryBaseAmt,
            primaryCurr: primaryCurr,
          ));
        }
      }
    }

    return rows;
  }

  // ── Export Journal Entries History to CSV ───────────────────────────
  static Future<void> exportJournalEntries(
    BuildContext context,
    List<Map<String, dynamic>> entries,
  ) async {
    final rows = generateJournalRows(entries);
    await _exportCsv(context, 'دفتر_قيود_اليومية', rows);
  }

  // ── Shared CSV Saver with UTF-8 BOM ───────────────────────────────
  static Future<void> _exportCsv(
    BuildContext context,
    String filename,
    List<List<dynamic>> rows,
  ) async {
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory == null) return;

      final String fileName = '${filename}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final String savePath = p.join(selectedDirectory, fileName);

      final String csvData = csv.encode(rows);
      
      final List<int> bom = [0xEF, 0xBB, 0xBF]; 
      
      final File file = File(savePath);
      final raf = file.openSync(mode: FileMode.write);
      raf.writeFromSync(bom);
      raf.writeStringSync(csvData);
      raf.closeSync();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف بنجاح في:\n$savePath'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تصدير الملف: $e'),
            backgroundColor: const Color(0xFFFFEBEE),
          ),
        );
      }
    }
  }

  static String _getTypeLabel(String type) {
    switch (type) {
      case 'asset':     return 'أصول';
      case 'liability': return 'خصوم';
      case 'equity':    return 'حقوق ملكية';
      case 'revenue':   return 'إيرادات';
      case 'expense':   return 'مصروفات';
      default:          return type;
    }
  }
}
