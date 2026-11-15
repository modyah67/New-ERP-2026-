// lib/features/journal_entry/journal_entry_pdf_service.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../core/constants.dart';
import '../../data/models/account_model.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/services/warehouse_transfer_journal_service.dart';
import 'journal_entry_preview_dialog.dart';

class JournalEntryPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null && _boldFont != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _font     = pw.Font.ttf(r);
      _boldFont = pw.Font.ttf(b);
    } catch (_) {
      try {
        final regularFile = File('assets/fonts/Cairo-Regular.ttf');
        final boldFile = File('assets/fonts/Cairo-Bold.ttf');
        if (regularFile.existsSync() && boldFile.existsSync()) {
          _font = pw.Font.ttf(regularFile.readAsBytesSync().buffer.asByteData());
          _boldFont = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } else {
          _font = await PdfGoogleFonts.cairoRegular();
          _boldFont = await PdfGoogleFonts.cairoBold();
        }
      } catch (_) {
        try {
          _font = await PdfGoogleFonts.cairoRegular();
          _boldFont = await PdfGoogleFonts.cairoBold();
        } catch (_) {
          _font = pw.Font.helvetica();
          _boldFont = pw.Font.helveticaBold();
        }
      }
    }
  }

  static const _dark    = PdfColor.fromInt(0xFF212121);
  static const _gray    = PdfColor.fromInt(0xFF757575);
  static const _lightBg = PdfColor.fromInt(0xFFF5F5F5);
  static const _border  = PdfColor.fromInt(0xFFBDBDBD);

  static pw.MemoryImage? _bgImage;

  static Future<pw.MemoryImage?> _getBgImage() async {
    if (_bgImage != null) return _bgImage;
    try {
      final bgData = await rootBundle.load('assets/images/statment.png');
      _bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
      return _bgImage;
    } catch (_) {
      try {
        final f = File('assets/images/statment.png');
        if (f.existsSync()) {
          _bgImage = pw.MemoryImage(f.readAsBytesSync());
          return _bgImage;
        }
      } catch (_) {}
    }
    return null;
  }

  // ── Print Full Accounting Tree ───────────────────────────────────────
  static Future<void> printTree(List<AccountModel> accounts) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildTreePdf(accounts, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'شجرة_الحسابات',
      format: PdfPageFormat.a4,
    );
  }

  // ── Print Grouped Journal Entries History ─────────────────────────────
  static Future<void> printHistory(List<Map<String, dynamic>> entries) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildHistoryPdf(entries, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'دفتر_القيود_اليومية',
      format: PdfPageFormat.a4.landscape,
    );
  }

  // ── Generate Single Voucher PDF Bytes ─────────────────────────────────
  static Future<Uint8List> generateSingleVoucherPdf(Map<String, dynamic> entry) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    return _buildSingleVoucherPdf(entry, settings);
  }

  // ── Show Interactive Print Preview Dialog ─────────────────────────────
  static Future<void> showPreviewDialog(BuildContext context, Map<String, dynamic> entry) {
    return JournalEntryPreviewDialog.show(context, entry);
  }

  // ── Print Single Voucher Receipt ──────────────────────────────────────
  static Future<void> printSingleVoucher(Map<String, dynamic> entry) async {
    final bytes = await generateSingleVoucherPdf(entry);
    final entryNum = (entry['entryNum'] ??
            entry['entry_number'] ??
            entry['entryNumber'] ??
            entry['id'] ??
            'voucher')
        .toString();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'سند_قيد_$entryNum',
      format: PdfPageFormat.a4.landscape,
    );
  }

  // ── PDF builders ──────────────────────────────────────────────────────

  static Future<Uint8List> _buildTreePdf(
      List<AccountModel> accounts, Map<String, String> settings) async {
    final pdf = pw.Document();
    final bgImage = await _getBgImage();
    
    // Sort accounts: roots first, depth recursive helper
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

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _font, bold: _boldFont),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(32),
          buildBackground: bgImage != null
              ? (context) => pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(bgImage, fit: pw.BoxFit.cover),
                  )
              : null,
        ),
        header: (context) => _buildHeader('تقرير شجرة الحسابات', settings),
        footer: (context) => _buildFooter(context),
        build: (context) {
          return [
            pw.SizedBox(height: 16),
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _border, width: 0.5),
                bottom: pw.BorderSide(color: _dark, width: 1),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2), // Code
                1: const pw.FlexColumnWidth(5), // Account Tree hierarchy representation
                2: const pw.FlexColumnWidth(2), // Type
                3: const pw.FlexColumnWidth(3), // Balance
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightBg),
                  children: [
                    _cellHeader('الكود'),
                    _cellHeader('اسم الحساب / التفريغ الشجري'),
                    _cellHeader('النوع'),
                    _cellHeader('الرصيد الحالي'),
                  ],
                ),
                // Data rows
                ...treeRows.map((row) {
                  final a = row['account'] as AccountModel;
                  final depth = row['depth'] as int;
                  final prefix = '   ' * depth + (depth > 0 ? '├─ ' : '');
                  
                  return pw.TableRow(
                    children: [
                      _cell(a.code),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: pw.Text('$prefix${a.name}', style: const pw.TextStyle(fontSize: 10)),
                      ),
                      _cell(_getTypeLabel(a.type)),
                      _cell(AppUtils.formatCurrency(a.balance), isBold: true),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> _buildHistoryPdf(
      List<Map<String, dynamic>> entries, Map<String, String> settings) async {
    final pdf = pw.Document();
    final bgImage = await _getBgImage();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _font, bold: _boldFont),
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          buildBackground: bgImage != null
              ? (context) => pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(bgImage, fit: pw.BoxFit.cover),
                  )
              : null,
        ),
        header: (context) => _buildHeader('دفتر قيود اليومية العامة', settings),
        footer: (context) => _buildFooter(context),
        build: (context) {
          return [
            pw.SizedBox(height: 10),
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _border, width: 0.5),
                bottom: pw.BorderSide(color: _dark, width: 1),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6), // Date
                1: const pw.FlexColumnWidth(1.2), // Num
                2: const pw.FlexColumnWidth(4.2), // Debit Account
                3: const pw.FlexColumnWidth(4.2), // Credit Account
                4: const pw.FlexColumnWidth(2.0), // Amount
                5: const pw.FlexColumnWidth(4.8), // Notes
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightBg),
                  children: [
                    _cellHeader('التاريخ', isCenter: true, fontSize: 9.0),
                    _cellHeader('رقم القيد', isCenter: true, fontSize: 9.0),
                    _cellHeader('الجانب المدين (من د/)', isCenter: true, fontSize: 9.0),
                    _cellHeader('الجانب الدائن (إلى د/)', isCenter: true, fontSize: 9.0),
                    _cellHeader('القيمة', isCenter: true, fontSize: 9.0),
                    _cellHeader('البيان / الملاحظات', isCenter: false, fontSize: 9.0),
                  ],
                ),
                // Data rows
                ...entries.map((entry) {
                  final debName = entry['debitName']?.toString() ?? '—';
                  final crdName = entry['creditName']?.toString() ?? '—';
                  final formattedDeb = debName.startsWith('من ') ? debName : 'من د/ $debName';
                  final formattedCrd = crdName.startsWith('إلى ') ? crdName : 'إلى د/ $crdName';

                  return pw.TableRow(
                    children: [
                      _cell(AppUtils.formatDate(DateTime.tryParse(entry['date']) ?? DateTime.now()), isCenter: true, fontSize: 8.5),
                      _cell(entry['entryNum'].toString(), isCenter: true, fontSize: 8.5),
                      _cell(formattedDeb, fontSize: 8.5),
                      _cell(formattedCrd, fontSize: 8.5),
                      _cell(AppUtils.formatCurrency(entry['amount']), isBold: true, isCenter: true, fontSize: 8.5),
                      _cell(entry['notes'] ?? '—', fontSize: 8.5),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> _buildSingleVoucherPdf(
      Map<String, dynamic> entry, Map<String, String> settings) async {
    final pdf = pw.Document();
    final bgImage = await _getBgImage();

    // Prepare voucher lines
    final rawLines = (entry['lines'] as List?) ?? [];
    final List<Map<String, dynamic>> voucherLines = [];

    if (rawLines.isNotEmpty) {
      for (var l in rawLines) {
        final isMap = l is Map;
        final name = isMap ? (l['account_name'] ?? 'حساب غير معروف') : (l.accountName ?? 'حساب غير معروف');
        final code = isMap ? (l['account_code'] ?? '') : (l.accountCode ?? '');
        final desc = isMap ? (l['description'] ?? '') : ((l as dynamic).description ?? '');
        double deb = 0;
        double crd = 0;
        if (isMap) {
          deb = (l['debit'] as num?)?.toDouble() ?? 0.0;
          crd = (l['credit'] as num?)?.toDouble() ?? 0.0;
        } else {
          if (l.type == 'debit') deb = l.amount;
          if (l.type == 'credit') crd = l.amount;
        }
        voucherLines.add({
          'name': name.toString(),
          'code': code.toString(),
          'debit': deb,
          'credit': crd,
          'desc': desc.toString(),
        });
      }
    }

    if (voucherLines.isEmpty) {
      final double amt = (entry['amount'] as num?)?.toDouble() ?? 0.0;
      if (entry['debitName'] != null) {
        voucherLines.add({
          'name': entry['debitName'].toString(),
          'code': (entry['debitCode'] ?? '').toString(),
          'debit': amt,
          'credit': 0.0,
          'desc': (entry['notes'] ?? '').toString(),
        });
      }
      if (entry['creditName'] != null) {
        voucherLines.add({
          'name': entry['creditName'].toString(),
          'code': (entry['creditCode'] ?? '').toString(),
          'debit': 0.0,
          'credit': amt,
          'desc': (entry['notes'] ?? '').toString(),
        });
      }
    }

    // Sort lines: Debits (من د/) first, then Credits (إلى د/)
    voucherLines.sort((a, b) {
      final double aDeb = a['debit'] as double;
      final double bDeb = b['debit'] as double;
      if (aDeb > 0 && bDeb == 0) return -1;
      if (aDeb == 0 && bDeb > 0) return 1;
      return 0;
    });

    double totalVoucherDebit = 0.0;
    double totalVoucherCredit = 0.0;
    for (var vl in voucherLines) {
      totalVoucherDebit += (vl['debit'] as double);
      totalVoucherCredit += (vl['credit'] as double);
    }

    final isBalanced = (totalVoucherDebit - totalVoucherCredit).abs() < 0.01;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _font, bold: _boldFont),
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
          buildBackground: bgImage != null
              ? (context) => pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(bgImage, fit: pw.BoxFit.cover),
                  )
              : null,
        ),
        header: (context) => _buildHeader('سند قيد اليومية العامة', settings),
        footer: (context) => _buildFooter(context),
        build: (context) {
          return [
            // Metadata strip bar
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const pw.EdgeInsets.only(top: 8, bottom: 12),
              decoration: pw.BoxDecoration(
                color: _lightBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: _border, width: 0.6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('رقم القيد المتسلسل: ',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gray)),
                      pw.Text('#${entry['entryNum'] ?? entry['entry_number'] ?? entry['entryNumber'] ?? entry['id'] ?? ''}',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _dark)),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('تاريخ القيد: ',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gray)),
                      pw.Text(
                        AppUtils.formatDate(DateTime.tryParse((entry['date'] ?? entry['entry_date'] ?? entry['created_at'] ?? '').toString()) ?? DateTime.now()),
                        style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _dark),
                      ),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('طبيعة القيد: ',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gray)),
                      pw.Text(
                        voucherLines.length > 2 ? 'قيد مركب (متعدد الأطراف)' : 'قيد بسيط (مزدوج)',
                        style: const pw.TextStyle(fontSize: 10, color: _dark),
                      ),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('حالة التوازن: ',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _gray)),
                      pw.Text(
                        isBalanced ? 'متوازن 100%' : 'فارق توازن',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: isBalanced
                              ? const PdfColor.fromInt(0xFF2E7D32)
                              : const PdfColor.fromInt(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Main Journal Lines Table
            pw.Table(
              border: pw.TableBorder.all(color: _border, width: 0.8),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2), // الطرف المحاسبي (من د/ / إلى د/)
                1: const pw.FlexColumnWidth(1.5), // كود الحساب
                2: const pw.FlexColumnWidth(5.0), // اسم الحساب
                3: const pw.FlexColumnWidth(2.2), // مدين
                4: const pw.FlexColumnWidth(2.2), // دائن
                5: const pw.FlexColumnWidth(5.5), // البيان / الشرح
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightBg),
                  children: [
                    _cellHeader('الطرف المحاسبي (من د/ / إلى د/)', isCenter: true, fontSize: 9.0),
                    _cellHeader('كود الحساب', isCenter: true, fontSize: 9.0),
                    _cellHeader('اسم الحساب / المخزن', isCenter: false, fontSize: 9.0),
                    _cellHeader('مدين', isCenter: true, fontSize: 9.0),
                    _cellHeader('دائن', isCenter: true, fontSize: 9.0),
                    _cellHeader('البيان / الشرح', isCenter: false, fontSize: 9.0),
                  ],
                ),
                ...voucherLines.map((vl) {
                  final double deb = vl['debit'] as double;
                  final double crd = vl['credit'] as double;
                  final bool isDeb = deb > 0;
                  final String sideLabel = isDeb ? 'من د/' : 'إلى د/';
                  final String rawName = vl['name'].toString();
                  final String prefix = isDeb ? 'من د/ ' : 'إلى د/ ';

                  final lineTransferCtx = WarehouseTransferJournalService.extractTransferContext(
                    entry: entry,
                    line: {'description': vl['desc']},
                  );
                  final targetWh = isDeb
                      ? lineTransferCtx.receivingWarehouse
                      : lineTransferCtx.sendingWarehouse;

                  final String formattedName = lineTransferCtx.isTransfer && targetWh != null
                      ? WarehouseTransferJournalService.formatTransferAccountName(
                          baseAccountName: rawName,
                          isDebit: isDeb,
                          context: lineTransferCtx,
                          includePrefix: true,
                        )
                      : (rawName.startsWith('من ') || rawName.startsWith('إلى ')
                          ? rawName
                          : '$prefix$rawName');

                  final String descText = vl['desc'].toString().isNotEmpty
                      ? vl['desc'].toString()
                      : (entry['notes']?.toString() ?? '—');

                  return pw.TableRow(
                    children: [
                      _cell(sideLabel, isCenter: true, isBold: true, fontSize: 9.0),
                      _cell(vl['code'].toString(), isCenter: true, fontSize: 9.0),
                      _cell(formattedName, fontSize: 9.0),
                      _cell(deb > 0 ? AppUtils.formatCurrency(deb) : '0.00', isCenter: true, isBold: isDeb, fontSize: 9.0),
                      _cell(crd > 0 ? AppUtils.formatCurrency(crd) : '0.00', isCenter: true, isBold: !isDeb, fontSize: 9.0),
                      _cell(descText, fontSize: 9.0),
                    ],
                  );
                }),
                // Total Balanced Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightBg),
                  children: [
                    _cell('الإجمالي', isCenter: true, isBold: true, fontSize: 9.0),
                    _cell('—', isCenter: true, fontSize: 9.0),
                    _cell('إجمالي أطراف القيد المتوازنة', isBold: true, fontSize: 9.0),
                    _cell(AppUtils.formatCurrency(totalVoucherDebit), isCenter: true, isBold: true, fontSize: 9.0),
                    _cell(AppUtils.formatCurrency(totalVoucherCredit), isCenter: true, isBold: true, fontSize: 9.0),
                    _cell(
                      isBalanced ? 'متوازن 100%' : 'فارق توازن',
                      isCenter: true,
                      isBold: true,
                      fontSize: 9.0,
                      color: isBalanced
                          ? const PdfColor.fromInt(0xFF2E7D32)
                          : const PdfColor.fromInt(0xFFC62828),
                    ),
                  ],
                ),
              ],
            ),
            // Notes Box (if present)
            if (((entry['notes'] ?? entry['description'])?.toString() ?? '').trim().isNotEmpty &&
                entry['notes'] != '—' &&
                entry['description'] != '—')
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 10),
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border, width: 0.5),
                  color: _lightBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('البيان / الوصف العام للقيد: ',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: _dark)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text((entry['notes'] ?? entry['description']).toString(),
                          style: const pw.TextStyle(fontSize: 9.5, color: _dark)),
                    ),
                  ],
                ),
              ),
            // Signatures block
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 28),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _signatureBox('إعداد المحاسب'),
                  _signatureBox('المراجعة والتدقيق'),
                  _signatureBox('المدير المالي'),
                  _signatureBox('الاعتماد والمصادقة'),
                ],
              ),
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  // ── Shared UI widgets ──────────────────────────────────────────────────

  static pw.Widget _buildHeader(String title, Map<String, String> settings) {
    final companyName = settings['company_name'] ?? settings['companyName'] ?? AppConstants.companyName;
    final resolvedCompanyName = (companyName.isEmpty || companyName.contains('أعمال المحاسبة'))
        ? 'فروتي فارمز - Fruity Farms'
        : companyName;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Right Section (RTL Start): Company Branding
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  resolvedCompanyName,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _dark),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'نظام الإدارة المالية والمحاسبية المتكامل',
                  style: const pw.TextStyle(fontSize: 9, color: _gray),
                ),
                if (settings['phone'] != null && settings['phone']!.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text('هاتف: ${settings['phone']}', style: const pw.TextStyle(fontSize: 8.5, color: _gray)),
                  ),
              ],
            ),
            // Center Section: Distinctive Document Title Badge
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 7),
              decoration: pw.BoxDecoration(
                color: _lightBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: _border, width: 0.8),
              ),
              child: pw.Text(
                title,
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _dark),
              ),
            ),
            // Left Section (RTL End): Official Document Metadata & Status
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFE8F5E9),
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'مستند رسمي معتمد',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF2E7D32),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'تاريخ الطباعة: ${AppUtils.formatDate(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8.5, color: _gray),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: _dark, thickness: 1.2),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: _border, thickness: 0.5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('تاريخ الطباعة: ${AppUtils.formatDate(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9, color: _gray)),
            pw.Text('صفحة ${context.pageNumber} من ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: _gray)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cellHeader(String label, {bool isCenter = false, double fontSize = 9.0}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: _dark),
        textAlign: isCenter ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool isCenter = false,
    bool isBold = false,
    double fontSize = 8.5,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _dark,
        ),
        textAlign: isCenter ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _signatureBox(String label) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: _dark)),
        pw.SizedBox(height: 36),
        pw.Container(width: 150, height: 1, color: _border),
      ],
    );
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
