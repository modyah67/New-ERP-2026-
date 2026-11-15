// lib/features/suppliers/master_codes_directory_pdf_service.dart
// Professional Master Code Directory PDF Service (دليل الأكواد الشامل)
// Dynamically compiles all live system entities from Supabase / local DAOs

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/constants.dart';
import '../../core/ui_utils.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

/// Single entity entry within a code directory group
class MasterCodeEntry {
  final String code;
  final String name;
  final String? category;
  final String? notes;

  const MasterCodeEntry({
    required this.code,
    required this.name,
    this.category,
    this.notes,
  });
}

/// Category / Sub-center grouping in the financial directory
class MasterCodeGroup {
  final int groupId;
  final String groupName;
  final List<MasterCodeEntry> entries;

  const MasterCodeGroup({
    required this.groupId,
    required this.groupName,
    required this.entries,
  });
}

class MasterCodesDirectoryPdfService {
  MasterCodesDirectoryPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // COLOR PALETTE (Official Navy & Slate Financial Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static const _navyPrimary = PdfColor.fromInt(0xFF1E3A8A); // Deep Navy (#1E3A8A)
  static const _headerBg    = PdfColor.fromInt(0xFFD1D5DB); // Gray 300
  static const _cardBg      = PdfColor.fromInt(0xFFF8FAFC); // Slate 50
  static const _lightBg     = PdfColor.fromInt(0xFFF1F5F9); // Slate 100
  static const _borderColor = PdfColor.fromInt(0xFF64748B); // Slate 500
  static const _tableBorder = PdfColor.fromInt(0xFF475569); // Slate 600
  static const _darkText    = PdfColor.fromInt(0xFF0F172A); // Slate 900
  static const _mutedText   = PdfColor.fromInt(0xFF475569); // Slate 600
  static const _white       = PdfColors.white;

  // ──────────────────────────────────────────────────────────────────────────
  // FONT LOADER WITH CAIRO & NOTOSANS FALLBACK
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Font? _font;
  static pw.Font? _boldFont;
  static pw.Font? _fallbackFont;

  static Future<void> _loadFonts() async {
    if (_font != null && _boldFont != null) return;
    try {
      final r = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final b = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      _font = pw.Font.ttf(r);
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
        _font = await PdfGoogleFonts.cairoRegular();
        _boldFont = await PdfGoogleFonts.cairoBold();
      }
    }

    try {
      _fallbackFont = await PdfGoogleFonts.notoSansRegular();
    } catch (_) {
      _fallbackFont = pw.Font.courier();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LIVE DATABASE QUERY & COMPILATION
  // ──────────────────────────────────────────────────────────────────────────
  /// Queries all live database records from Supabase DAOs and compiles them into
  /// the official 9 financial categories in the exact architectural order.
  static Future<List<MasterCodeGroup>> compileDirectory() async {
    final List<MasterCodeEntry> cropSuppliers = [];
    final List<MasterCodeEntry> transportList = [];
    final List<MasterCodeEntry> packagingSuppliers = [];
    final List<MasterCodeEntry> sharedSuppliers = [];
    final List<MasterCodeEntry> stationList = [];
    final List<MasterCodeEntry> stationSuppliers = [];
    final List<MasterCodeEntry> deductionSuppliers = [];
    final List<MasterCodeEntry> clearingList = [];
    final List<MasterCodeEntry> shippingList = [];

    try {
      // 1. Fetch live suppliers (Crop, Packaging, Shared, Station, Deduction)
      final suppliers = await SupplierDao().getAll(limit: 1000);
      for (final s in suppliers) {
        final code = s.supplierCode.trim();
        final name = s.name.trim();
        if (name.isEmpty) continue;

        final type = s.supplierType.trim().toLowerCase();
        final codeNum = int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

        if (type == 'deduction' || (codeNum >= 40000 && codeNum <= 49999) || (codeNum >= 400 && codeNum <= 499)) {
          deductionSuppliers.add(MasterCodeEntry(
            code: code.isNotEmpty ? code : '—',
            name: name,
            category: 'تخصيمات ورسوم',
          ));
        } else if (type == 'station' || (codeNum >= 85000 && codeNum <= 89999) || (codeNum >= 850 && codeNum <= 899)) {
          stationSuppliers.add(MasterCodeEntry(
            code: code.isNotEmpty ? code : '—',
            name: name,
            category: 'خدمات محطات',
          ));
        } else if (type == 'shared' || (codeNum >= 75000 && codeNum <= 79999) || (codeNum >= 750 && codeNum <= 799)) {
          sharedSuppliers.add(MasterCodeEntry(
            code: code.isNotEmpty ? code : '—',
            name: name,
            category: 'مشترك (محاصيل وتعبئة)',
          ));
        } else if (type == 'packaging' || type == 'sticker' || (codeNum >= 70000 && codeNum <= 74999) || (codeNum >= 701 && codeNum <= 749)) {
          packagingSuppliers.add(MasterCodeEntry(
            code: code.isNotEmpty ? code : '—',
            name: name,
            category: 'مواد تعبئة وتغليف',
          ));
        } else {
          cropSuppliers.add(MasterCodeEntry(
            code: code.isNotEmpty ? code : '—',
            name: name,
            category: 'محاصيل زراعية',
          ));
        }
      }
    } catch (_) {}

    try {
      // 2. Fetch live transport contractors (60000 - 69999)
      final transportSuppliers = await TransportSupplierDao().getAll(limit: 1000);
      for (final t in transportSuppliers) {
        final code = t.code.trim();
        final name = t.name.trim();
        if (name.isEmpty) continue;
        transportList.add(MasterCodeEntry(
          code: code.isNotEmpty ? code : '—',
          name: name,
          category: 'نقل وشحن بري',
        ));
      }
    } catch (_) {}

    try {
      // 3. Fetch live packing stations (80000 - 89999)
      final stations = await StationDao().getAll(limit: 1000);
      for (final st in stations) {
        final code = st.code.trim();
        final name = st.name.trim();
        if (name.isEmpty) continue;
        stationList.add(MasterCodeEntry(
          code: code.isNotEmpty ? code : '—',
          name: name,
          category: 'محطات فرز وتعبئة',
        ));
      }
    } catch (_) {}

    try {
      // 4. Fetch live clearing agents (Customs Clearing Agents - Sea / Air)
      final clearingAgents = await ClearingAgentDao().getAll(limit: 1000);
      for (final ca in clearingAgents) {
        final code = ca.code.trim();
        final name = ca.name.trim();
        if (name.isEmpty) continue;
        final brokerType = ca.brokerType.trim();
        final typeSuffix = brokerType.isNotEmpty ? ' ($brokerType)' : '';
        clearingList.add(MasterCodeEntry(
          code: code.isNotEmpty ? code : '—',
          name: '$name$typeSuffix',
          category: brokerType.isNotEmpty ? 'تخليص $brokerType' : 'تخليص جمركي',
        ));
      }
    } catch (_) {}

    try {
      // 5. Fetch live shipping companies (90000+)
      final shippingCompanies = await ShippingCompanyDao().getAll(limit: 1000);
      for (final sh in shippingCompanies) {
        final code = sh.code.trim();
        final name = sh.name.trim();
        if (name.isEmpty) continue;
        shippingList.add(MasterCodeEntry(
          code: code.isNotEmpty ? code : '—',
          name: name,
          category: 'شحن دولي',
        ));
      }
    } catch (_) {}

    // Sort entries within each group by code (numerically if possible, else alphabetically)
    void sortEntries(List<MasterCodeEntry> list) {
      list.sort((a, b) {
        final aNum = int.tryParse(a.code.replaceAll(RegExp(r'[^0-9]'), ''));
        final bNum = int.tryParse(b.code.replaceAll(RegExp(r'[^0-9]'), ''));
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.code.compareTo(b.code);
      });
    }

    sortEntries(cropSuppliers);
    sortEntries(transportList);
    sortEntries(packagingSuppliers);
    sortEntries(sharedSuppliers);
    sortEntries(stationList);
    sortEntries(stationSuppliers);
    sortEntries(deductionSuppliers);
    sortEntries(clearingList);
    sortEntries(shippingList);

    return [
      MasterCodeGroup(
        groupId: 50,
        groupName: 'موردين المحاصيل\n(50000 - 59999)',
        entries: cropSuppliers,
      ),
      MasterCodeGroup(
        groupId: 60,
        groupName: 'موردين النقل ومقاولي الشحن\n(60000 - 69999)',
        entries: transportList,
      ),
      MasterCodeGroup(
        groupId: 70,
        groupName: 'موردين مواد التعبئة والتغليف\n(70000 - 74999)',
        entries: packagingSuppliers,
      ),
      MasterCodeGroup(
        groupId: 75,
        groupName: 'الموردين المشتركين (محاصيل وتعبئة)\n(75000 - 79999)',
        entries: sharedSuppliers,
      ),
      MasterCodeGroup(
        groupId: 80,
        groupName: 'المحطات\n(80000 - 89999)',
        entries: stationList,
      ),
      MasterCodeGroup(
        groupId: 85,
        groupName: 'موردي المحطات\n(85000 - 89999)',
        entries: stationSuppliers,
      ),
      MasterCodeGroup(
        groupId: 40,
        groupName: 'موردي التخصيمات\n(40000 - 49999)',
        entries: deductionSuppliers,
      ),
      MasterCodeGroup(
        groupId: 20,
        groupName: 'المخلصين\n(بحري / جوي)',
        entries: clearingList,
      ),
      MasterCodeGroup(
        groupId: 90,
        groupName: 'شركات الشحن\n(90000+)',
        entries: shippingList,
      ),
    ];
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC ENTRY POINTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates the raw PDF bytes using live database records
  static Future<Uint8List> generatePdfBytes({
    List<MasterCodeGroup>? groups,
    Map<String, String>? settings,
  }) async {
    await _loadFonts();
    final resolvedGroups = groups ?? await compileDirectory();
    final resolvedSettings = settings ?? await () async {
      try {
        return await SettingsDao().getAllSettings();
      } catch (_) {
        return <String, String>{};
      }
    }();

    return _build(
      groups: resolvedGroups,
      settings: resolvedSettings,
    );
  }

  /// Generates and opens the standard system print dialog
  static Future<void> generateAndPrint(BuildContext context, {List<MasterCodeGroup>? groups}) async {
    final bytes = await generatePdfBytes(groups: groups);
    final docTitle = 'دليل_الأكواد_الشامل_الموردين_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: docTitle,
      format: PdfPageFormat.a4,
    );
  }

  /// Saves the Master Code Directory PDF directly to user's export storage
  static Future<File> saveToFile(BuildContext context, {List<MasterCodeGroup>? groups}) async {
    final bytes = await generatePdfBytes(groups: groups);
    final dir = await FileHelper.getExportDirectory();
    final fileName = 'دليل_الأكواد_الشامل_الموردين_${DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now())}';
    final path = '${dir.path}/$fileName.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes);
    if (context.mounted) {
      UIUtils.showSuccessSnackbar(context, 'تم حفظ دليل الأكواد الشامل بنجاح في:\n$path');
    }
    return file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDER
  // ──────────────────────────────────────────────────────────────────────────
  static Future<Uint8List> _build({
    required List<MasterCodeGroup> groups,
    required Map<String, String> settings,
  }) async {
    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: _font!,
      bold: _boldFont!,
      fontFallback: _fallbackFont != null ? [_fallbackFont!] : [],
    );

    final companyName = settings['company_name'] ?? AppConstants.companyName;

    final pageTheme = pw.PageTheme(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.portrait,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 22),
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        header: (context) => _buildDocumentHeader(companyName),
        footer: (context) => _buildDocumentFooter(context),
        build: (context) => [
          pw.SizedBox(height: 10),
          // Master Directory Table
          _buildMasterTable(groups),
          pw.SizedBox(height: 14),
          // Audit & Department Signatures
          _buildAuditSignatures(),
        ],
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER COMPONENT (MIRRORING mmmmالموردين.pdf)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildDocumentHeader(String companyName) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left Credential Header (Fruity Farms Company / Financial Department / Suppliers)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Fruity Farms Company',
                style: pw.TextStyle(font: _boldFont, fontSize: 10.0, color: _navyPrimary),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'Financial Department',
                style: pw.TextStyle(font: _font, fontSize: 9.0, color: _darkText),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'Suppliers Directory',
                style: pw.TextStyle(font: _font, fontSize: 9.0, color: _darkText),
              ),
            ],
          ),

          // Center Box (أكواد الموردين 2026)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: pw.BoxDecoration(
              color: _headerBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: _borderColor, width: 1.0),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  'أكواد الموردين والجهات المعتمدة',
                  style: pw.TextStyle(
                    font: _boldFont,
                    fontSize: 11.5,
                    color: _darkText,
                  ),
                ),
                pw.Text(
                  'دليل الأكواد الشامل',
                  style: pw.TextStyle(
                    font: _font,
                    fontSize: 7.5,
                    color: _mutedText,
                  ),
                ),
              ],
            ),
          ),

          // Right Credential Info
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(font: _boldFont, fontSize: 10.0, color: _navyPrimary),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                'الإدارة المالية والحسابات',
                style: pw.TextStyle(font: _font, fontSize: 8.0, color: _mutedText),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                DateFormat('yyyy-MM-dd').format(DateTime.now()),
                style: pw.TextStyle(font: _font, fontSize: 8.0, color: _mutedText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MASTER TABLE COMPONENT
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildMasterTable(List<MasterCodeGroup> groups) {
    return pw.Column(
      children: [
        // Top Global Column Header
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _headerBg,
            border: pw.Border.all(color: _tableBorder, width: 0.8),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              pw.Container(
                width: 125,
                child: pw.Center(
                  child: pw.Text(
                    'الفئات والمراكز الفرعية',
                    style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _darkText),
                  ),
                ),
              ),
              pw.Container(width: 0.8, height: 16, color: _tableBorder),
              pw.Container(
                width: 32,
                child: pw.Center(
                  child: pw.Text(
                    'م',
                    style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _darkText),
                  ),
                ),
              ),
              pw.Container(width: 0.8, height: 16, color: _tableBorder),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                  child: pw.Text(
                    'الموردين / اسم الجهة',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _darkText),
                  ),
                ),
              ),
              pw.Container(width: 0.8, height: 16, color: _tableBorder),
              pw.Container(
                width: 65,
                child: pw.Center(
                  child: pw.Text(
                    'Codes',
                    style: pw.TextStyle(font: _boldFont, fontSize: 8.5, color: _darkText),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Group Containers
        ...groups.map((group) => _buildGroupBlock(group)),
      ],
    );
  }

  static pw.Widget _buildGroupBlock(MasterCodeGroup group) {
    final entries = group.entries;

    if (entries.isEmpty) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 3),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _tableBorder, width: 0.8),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _buildSidebar(group.groupId, group.groupName),
            pw.Container(width: 0.8, height: 26, color: _tableBorder),
            pw.Expanded(
              child: pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Text(
                    'لا توجد جهات مسجلة في هذا القسم حالياً',
                    style: pw.TextStyle(font: _font, fontSize: 8.0, color: _mutedText),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 3),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _tableBorder, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Sub-Center Left / RTL Sidebar (المراكز الفرعية)
          _buildSidebar(group.groupId, group.groupName),

          // Divider
          pw.Container(width: 0.8, color: _tableBorder),

          // Entries List
          pw.Expanded(
            child: pw.Column(
              children: entries.asMap().entries.map((item) {
                final idx = item.key + 1;
                final entry = item.value;
                final isLast = idx == entries.length;

                return pw.Container(
                  decoration: pw.BoxDecoration(
                    color: item.key % 2 == 0 ? _white : _cardBg,
                    border: isLast
                        ? null
                        : const pw.Border(
                            bottom: pw.BorderSide(color: _borderColor, width: 0.4),
                          ),
                  ),
                  child: pw.Row(
                    children: [
                      // Sequence number (#)
                      pw.Container(
                        width: 32,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
                        child: pw.Center(
                          child: pw.Text(
                            '$idx',
                            style: pw.TextStyle(font: _font, fontSize: 7.5, color: _mutedText),
                          ),
                        ),
                      ),
                      pw.Container(width: 0.8, height: 14, color: _borderColor),

                      // Entity Name (الموردين)
                      pw.Expanded(
                        child: pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2.2),
                          child: pw.Text(
                            entry.name,
                            style: pw.TextStyle(font: _font, fontSize: 7.5, color: _darkText),
                            maxLines: 1,
                          ),
                        ),
                      ),
                      pw.Container(width: 0.8, height: 14, color: _borderColor),

                      // Code (Codes)
                      pw.Container(
                        width: 65,
                        padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
                        child: pw.Center(
                          child: pw.Text(
                            entry.code,
                            style: pw.TextStyle(
                              font: _boldFont,
                              fontSize: 8.0,
                              color: _navyPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSidebar(int groupId, String groupName) {
    return pw.Container(
      width: 125,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 18,
            height: 18,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _tableBorder, width: 0.6),
              color: _white,
            ),
            child: pw.Center(
              child: pw.Text(
                '$groupId',
                style: pw.TextStyle(font: _boldFont, fontSize: 7.0, color: _navyPrimary),
              ),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Text(
              groupName,
              style: pw.TextStyle(font: _boldFont, fontSize: 7.0, color: _navyPrimary),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AUDIT & SIGNATURES BLOCK
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildAuditSignatures() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _lightBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _borderColor, width: 0.6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSignatureSlot('رئيس قسم الحسابات العامة'),
          _buildSignatureSlot('مراجع الحسابات والرقابة المالية'),
          _buildSignatureSlot('الإدارة المالية والاعتماد'),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureSlot(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(font: _boldFont, fontSize: 7.5, color: _navyPrimary),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          width: 120,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _borderColor, width: 0.7, style: pw.BorderStyle.dashed),
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'التوقيع: ...........................',
          style: pw.TextStyle(font: _font, fontSize: 6.0, color: _mutedText),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER COMPONENT
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildDocumentFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Fruity Farms ERP — نظام إدارة وتكويد الموردين الموحد',
            style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: _font, fontSize: 6.5, color: _mutedText),
          ),
        ],
      ),
    );
  }
}
