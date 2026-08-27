// lib/features/journal_entry/journal_entry_pdf_service.dart

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils.dart';
import '../../data/models/account_model.dart';
import '../../data/dao/settings_dao.dart';

class JournalEntryPdfService {
  static pw.Font? _font;
  static pw.Font? _boldFont;

  static Future<void> _loadFonts() async {
    if (_font != null) return;
    final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    _font     = pw.Font.ttf(r);
    _boldFont = pw.Font.ttf(b);
  }

  static const _dark    = PdfColor.fromInt(0xFF212121);
  static const _gray    = PdfColor.fromInt(0xFF757575);
  static const _lightBg = PdfColor.fromInt(0xFFF5F5F5);
  static const _border  = PdfColor.fromInt(0xFFBDBDBD);

  static pw.MemoryImage? _bgImage;

  static Future<pw.MemoryImage> _getBgImage() async {
    if (_bgImage != null) return _bgImage!;
    final bgData = await rootBundle.load('assets/images/statment.png');
    _bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    return _bgImage!;
  }

  // ── Print Full Accounting Tree ───────────────────────────────────────
  static Future<void> printTree(List<AccountModel> accounts) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildTreePdf(accounts, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'شجرة_الحسابات',
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
    );
  }

  // ── Print Single Voucher Receipt ──────────────────────────────────────
  static Future<void> printSingleVoucher(Map<String, dynamic> entry) async {
    await _loadFonts();
    final settings = await SettingsDao().getAllSettings();
    final bytes = await _buildSingleVoucherPdf(entry, settings);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'سند_قيد_${entry['entryNum']}',
    );
  }

  // ── PDF builders ──────────────────────────────────────────────────────

  static Future<Uint8List> _buildTreePdf(
      List<AccountModel> accounts, Map<String, String> settings) async {
    final pdf = pw.Document();
    final bgImage = await _getBgImage();
    
    // Sort accounts: roots first, depth recursive helper
    List<Map<String, dynamic>> flattenTree(int? parentId, int depth) {
      final children = accounts.where((a) => a.parentId == parentId).toList();
      final list = <Map<String, dynamic>>[];
      for (final child in children) {
        list.add({'account': child, 'depth': depth});
        list.addAll(flattenTree(int.tryParse(child.id ?? ''), depth + 1));
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
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
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
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(32),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        header: (context) => _buildHeader('دفتر قيود اليومية', settings),
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
                0: const pw.FlexColumnWidth(1.5), // Date
                1: const pw.FlexColumnWidth(1),   // Code/Num
                2: const pw.FlexColumnWidth(3),   // Debit Account
                3: const pw.FlexColumnWidth(3),   // Credit Account
                4: const pw.FlexColumnWidth(2),   // Amount
                5: const pw.FlexColumnWidth(4.5), // Notes
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _lightBg),
                  children: [
                    _cellHeader('التاريخ'),
                    _cellHeader('رقم القيد'),
                    _cellHeader('الجانب المدين (المستلم)'),
                    _cellHeader('الجانب الدائن (المسحوب منه)'),
                    _cellHeader('القيمة'),
                    _cellHeader('البيان / الملاحظات'),
                  ],
                ),
                // Data rows
                ...entries.map((entry) {
                  return pw.TableRow(
                    children: [
                      _cell(AppUtils.formatDate(DateTime.tryParse(entry['date']) ?? DateTime.now())),
                      _cell(entry['entryNum'].toString()),
                      _cell(entry['debitName']),
                      _cell(entry['creditName']),
                      _cell(AppUtils.formatCurrency(entry['amount']), isBold: true),
                      _cell(entry['notes'] ?? '—'),
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

    pdf.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: _font, bold: _boldFont),
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.all(40),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(bgImage, fit: pw.BoxFit.cover),
          ),
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildHeader('سند قيد اليومية (يومية عامة)', settings),
              pw.SizedBox(height: 32),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('رقم القيد المتسلسل:  #${entry['entryNum']}',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('تاريخ القيد:  ${AppUtils.formatDate(DateTime.tryParse(entry['date']) ?? DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Table(
                border: pw.TableBorder.all(color: _border, width: 0.8),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(5),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _lightBg),
                    children: [
                      _cellHeader('الحساب', isCenter: true),
                      _cellHeader('اسم الحساب بالكامل', isCenter: true),
                      _cellHeader('مدين (Debit)', isCenter: true),
                      _cellHeader('دائن (Credit)', isCenter: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell(entry['debitCode'] ?? '—', isCenter: true),
                      _cell(entry['debitName'] ?? '—'),
                      _cell(AppUtils.formatCurrency(entry['amount']), isCenter: true, isBold: true),
                      _cell('0.00', isCenter: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell(entry['creditCode'] ?? '—', isCenter: true),
                      _cell(entry['creditName'] ?? '—'),
                      _cell('0.00', isCenter: true),
                      _cell(AppUtils.formatCurrency(entry['amount']), isCenter: true, isBold: true),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border, width: 0.5),
                  color: _lightBg,
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('البيان / الوصف: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Text(entry['notes'] ?? '—', style: const pw.TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _signatureBox('إعداد المحاسب'),
                  _signatureBox('المدير المالي'),
                  _signatureBox('الاعتماد والمراجعة'),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  // ── Shared UI widgets ──────────────────────────────────────────────────

  static pw.Widget _buildHeader(String title, Map<String, String> settings) {
    final companyName = settings['companyName'] ?? 'مؤسسة أعمال المحاسبة';
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _dark)),
                if (settings['phone'] != null)
                  pw.Text('هاتف: ${settings['phone']}', style: const pw.TextStyle(fontSize: 9, color: _gray)),
              ],
            ),
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _dark)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: _dark, thickness: 1),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
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

  static pw.Widget _cellHeader(String label, {bool isCenter = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        textAlign: isCenter ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _cell(String text, {bool isCenter = false, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: isCenter ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }

  static pw.Widget _signatureBox(String label) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 48),
        pw.Container(width: 120, height: 1, color: _border),
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
