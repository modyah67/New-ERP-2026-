// lib/features/accounts/services/advanced_coa_pdf_service.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/models/account_model.dart';

/// Flattened representation of an account node for the PDF table adhering to strict 4-level hierarchy
class FlattenedCoaItem {
  final AccountModel account;
  final int level; // Strictly 1, 2, 3, or 4
  final int treeDepth; // Structural tree depth for connector lines & visual nesting
  final bool isSubAnalytic; // True if operational child node under Level 4 (e.g. named supplier, bank)
  final String formattedName;
  final String normalBalance;
  final String typeArabic;
  final bool isLastChild;
  final bool hasChildren;

  const FlattenedCoaItem({
    required this.account,
    required this.level,
    this.treeDepth = 1,
    this.isSubAnalytic = false,
    required this.formattedName,
    required this.normalBalance,
    required this.typeArabic,
    required this.isLastChild,
    required this.hasChildren,
  });
}

/// Advanced Engineered PDF Generation Service for the Chart of Accounts.
/// Strictly enforces the approved 4-Level hierarchical tree standard:
/// 1. Root / الجذور (5 roots)
/// 2. Groups / المجموعات (11 groups)
/// 3. Sub-groups / الحسابات الفرعية (32 sub-accounts)
/// 4. Analytic & Operational / الحسابات التحليلية والتشغيلية (99 accounts)
/// Operational sub-entities (specific banks, cash boxes, named suppliers, shareholders)
/// are mapped strictly under Level 4 as analytic child nodes without falsely incrementing
/// the level index to 5 or 6 in reports.
class AdvancedCoaPdfService {
  AdvancedCoaPdfService._();

  // ──────────────────────────────────────────────────────────────────────────
  // THEME COLORS (Professional Deep Navy #1A365D Accounting Theme)
  // ──────────────────────────────────────────────────────────────────────────
  static final _navyPrimary  = PdfColor.fromHex('#1A365D'); // Deep Navy #1A365D (Headers & Main Root)
  static final _navyLight    = PdfColor.fromHex('#2A4365'); // Navy Accent (Level 1 Root Banner)
  static final _slateLevel2  = PdfColor.fromHex('#EDF2F7'); // Slate/Cool Grey (Level 2 Major Group)
  static final _slateLevel3  = PdfColor.fromHex('#F7FAFC'); // Soft Tint (Level 3 Sub Group)
  static final _zebraBg      = PdfColor.fromHex('#F8FAFC'); // Clean Slate 50 (Level 4/5 Zebra)
  static final _textDark     = PdfColor.fromHex('#0F172A');
  static final _textMuted    = PdfColor.fromHex('#64748B');
  static final _borderColor  = PdfColor.fromHex('#CBD5E1');
  static final _borderLight  = PdfColor.fromHex('#E2E8F0');
  static final _accentColor  = PdfColor.fromHex('#0D9488'); // Teal 600
  static final _cardBg       = PdfColor.fromHex('#F8FAFC');

  // ──────────────────────────────────────────────────────────────────────────
  // FONT LOADER WITH ARABIC & FALLBACK SUPPORT
  // ──────────────────────────────────────────────────────────────────────────
  static Future<({pw.Font regular, pw.Font bold, pw.Font fallback})> _loadFonts() async {
    pw.Font regular;
    pw.Font bold;
    try {
      final regularData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      regular = pw.Font.ttf(regularData);
      bold = pw.Font.ttf(boldData);
    } catch (_) {
      try {
        final regularFile = File('assets/fonts/Cairo-Regular.ttf');
        final boldFile = File('assets/fonts/Cairo-Bold.ttf');
        if (regularFile.existsSync() && boldFile.existsSync()) {
          regular = pw.Font.ttf(regularFile.readAsBytesSync().buffer.asByteData());
          bold = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
        } else {
          regular = await PdfGoogleFonts.cairoRegular();
          bold = await PdfGoogleFonts.cairoBold();
        }
      } catch (_) {
        try {
          regular = await PdfGoogleFonts.cairoRegular();
          bold = await PdfGoogleFonts.cairoBold();
        } catch (_) {
          regular = pw.Font.helvetica();
          bold = pw.Font.helveticaBold();
        }
      }
    }

    pw.Font fallback;
    try {
      fallback = await PdfGoogleFonts.notoSansRegular();
    } catch (_) {
      fallback = pw.Font.courier();
    }

    return (regular: regular, bold: bold, fallback: fallback);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HIERARCHICAL TREE FLATTENER & PRE-ORDER TRAVERSAL ALGORITHM
  // ──────────────────────────────────────────────────────────────────────────
  /// Builds a true hierarchical tree structure and performs pre-order traversal
  /// (Parent -> Children -> Grandchildren) so that parent accounts are immediately
  /// followed by their direct sub-accounts and leaf nodes.
  /// Strictly orders roots according to the official 5-root sequence:
  /// 1. Assets / الأصول (Root 1)
  /// 2. Liabilities & Equity / الخصوم وحقوق الملكية (Root 2)
  /// 3. Expenses & Costs / المصروفات والتكاليف (Root 3)
  /// 4. Revenues / الإيرادات (Root 4)
  /// 5. System & Intermediary / الحسابات النظامية ووسيطة (Root 9)
  static List<FlattenedCoaItem> flattenTree(List<AccountModel> accounts) {
    if (accounts.isEmpty) return [];

    final idMap = <String, AccountModel>{};
    final codeMap = <String, AccountModel>{};

    for (final acc in accounts) {
      if (acc.id != null && acc.id!.trim().isNotEmpty) {
        idMap[acc.id!.trim()] = acc;
      }
      codeMap[acc.code.trim()] = acc;
    }

    /// Official 4-Level Standard Root Category Sequence:
    /// Priority 1: Assets / الأصول (1xxx)
    /// Priority 2: Liabilities & Equity / الخصوم وحقوق الملكية (2xxx)
    /// Priority 3: Expenses & Costs / المصروفات والتكاليف (3xxx, legacy 5xxx/6xxx/7xxx)
    /// Priority 4: Revenues / الإيرادات (4xxx)
    /// Priority 5: System & Intermediary / الحسابات النظامية ووسيطة (9xxx)
    int getCategoryPriority(AccountModel acc) {
      final code = acc.code.trim();
      final type = acc.type.trim().toLowerCase();

      // 1. Assets (الأصول) - Root 1
      if (code.startsWith('1')) return 1;

      // 2. Liabilities & Equity (الخصوم وحقوق الملكية) - Root 2
      if (code.startsWith('2')) return 2;

      // 3. Expenses & Costs (المصروفات والتكاليف) - Root 3 (and legacy 5, 6, 7)
      if (code.startsWith('3') || code.startsWith('5') || code.startsWith('6') || code.startsWith('7')) return 3;

      // 4. Revenues (الإيرادات) - Root 4
      if (code.startsWith('4')) return 4;

      // 5. System & Intermediary (الحسابات النظامية ووسيطة) - Root 9
      if (code.startsWith('9')) return 5;

      // Fallback by account type
      if (type == 'asset') return 1;
      if (type == 'liability' || type == 'equity') return 2;
      if (type == 'expense') return 3;
      if (type == 'revenue') return 4;
      if (type == 'system') return 5;

      return 99;
    }

    int compareAccountCodes(AccountModel a, AccountModel b) {
      final prioA = getCategoryPriority(a);
      final prioB = getCategoryPriority(b);
      if (prioA != prioB) {
        return prioA.compareTo(prioB);
      }

      final codeA = a.code.trim();
      final codeB = b.code.trim();

      // If one code is a prefix of the other:
      // The shorter parent prefix must precede its sub-accounts
      if (codeB.startsWith(codeA) && codeA.length < codeB.length) return -1;
      if (codeA.startsWith(codeB) && codeB.length < codeA.length) return 1;

      // Same code length: compare numeric values if both digits
      if (codeA.length == codeB.length) {
        final numA = int.tryParse(codeA);
        final numB = int.tryParse(codeB);
        if (numA != null && numB != null) {
          return numA.compareTo(numB);
        }
      }

      return codeA.compareTo(codeB);
    }

    // Helper to resolve an account's parent AccountModel
    AccountModel? resolveParent(AccountModel acc) {
      final code = acc.code.trim();
      final accPrio = getCategoryPriority(acc);

      // Explicit Major Root Nodes (Level 1)
      if (code == '1' || code == '2' || code == '3' || code == '4' ||
          code == '5' || code == '6' || code == '7' || code == '8' ||
          code == '9' || code == '9000') {
        return null;
      }

      // 1. Primary: Match explicit parentId
      final pid = acc.parentId?.trim();
      if (pid != null && pid.isNotEmpty) {
        AccountModel? candidate;
        if (idMap.containsKey(pid) && idMap[pid]!.code.trim() != code) {
          candidate = idMap[pid];
        } else if (codeMap.containsKey(pid) && pid != code) {
          candidate = codeMap[pid];
        }

        if (candidate != null) {
          final candPrio = getCategoryPriority(candidate);
          if (candPrio == accPrio) {
            return candidate;
          }
        }
      }

      // 2. Secondary: Hierarchical prefix matching by account code
      AccountModel? bestPrefixMatch;
      int bestMatchLength = 0;

      for (final otherCode in codeMap.keys) {
        if (otherCode == code) continue;
        if (code.startsWith(otherCode) && otherCode.length > bestMatchLength) {
          final candidate = codeMap[otherCode]!;
          final candPrio = getCategoryPriority(candidate);
          if (candPrio == accPrio) {
            bestMatchLength = otherCode.length;
            bestPrefixMatch = candidate;
          }
        }
      }

      if (bestPrefixMatch != null) {
        return bestPrefixMatch;
      }

      // 3. Fallback for standard 4-Level Chart of Accounts roots
      if (code.startsWith('1') && codeMap.containsKey('1')) return codeMap['1'];
      if (code.startsWith('2') && codeMap.containsKey('2')) return codeMap['2'];
      if (code.startsWith('3') && codeMap.containsKey('3')) return codeMap['3'];
      if (code.startsWith('5') || code.startsWith('6') || code.startsWith('7')) {
        if (codeMap.containsKey('3')) return codeMap['3'];
        if (codeMap.containsKey('5') && code.startsWith('5')) return codeMap['5'];
        if (codeMap.containsKey('6') && code.startsWith('6')) return codeMap['6'];
      }
      if (code.startsWith('4') && codeMap.containsKey('4')) return codeMap['4'];
      if (code.startsWith('9') && codeMap.containsKey('9')) return codeMap['9'];
      if (code.startsWith('9') && codeMap.containsKey('9000') && code != '9000') return codeMap['9000'];

      return null;
    }

    // Build tree hierarchy with cycle detection
    final childrenMap = <String, List<AccountModel>>{};
    final rootAccounts = <AccountModel>[];

    for (final acc in accounts) {
      final parent = resolveParent(acc);

      if (parent == null) {
        rootAccounts.add(acc);
      } else {
        // Cycle detection: trace up parent chain
        bool hasCycle = false;
        AccountModel? curr = parent;
        final visited = <String>{acc.code.trim()};

        while (curr != null) {
          final currCode = curr.code.trim();
          if (visited.contains(currCode)) {
            hasCycle = true;
            break;
          }
          visited.add(currCode);
          curr = resolveParent(curr);
        }

        if (hasCycle) {
          rootAccounts.add(acc);
        } else {
          final parentKey = parent.id?.trim().isNotEmpty == true
              ? parent.id!.trim()
              : parent.code.trim();
          childrenMap.putIfAbsent(parentKey, () => []).add(acc);
        }
      }
    }

    // Sort root accounts by standard financial accounting sequence (1->2->3->4->9)
    rootAccounts.sort(compareAccountCodes);

    // Sort all child lists by code
    for (final list in childrenMap.values) {
      list.sort(compareAccountCodes);
    }

    final result = <FlattenedCoaItem>[];

    int computeLevel(String code, int treeDepth) {
      final c = code.trim();
      if (c == '1' || c == '2' || c == '3' || c == '4' || c == '9' || c.length == 1) return 1;
      if (c.length == 2) return 2;
      if (c.length == 3) return 3;
      if (c.length == 4) return 4;
      return 5;
    }

    // Pre-order DFS Traversal: Parent -> Children -> Grandchildren
    void dfs(AccountModel current, int depth, bool isLast) {
      final currentKey = current.id?.trim().isNotEmpty == true
          ? current.id!.trim()
          : current.code.trim();

      final children = childrenMap[currentKey] ??
          childrenMap[current.code.trim()] ??
          <AccountModel>[];
      final hasChildren = children.isNotEmpty;

      final rawTitle = current.displayName.isNotEmpty
          ? current.displayName
          : current.name;

      final level = computeLevel(current.code, depth);
      final bool isSubAnalytic = depth > 4 || current.code.trim().length > 4;

      result.add(FlattenedCoaItem(
        account: current,
        level: level,
        treeDepth: depth,
        isSubAnalytic: isSubAnalytic,
        formattedName: rawTitle,
        normalBalance: _getNormalBalance(current.type, current.code),
        typeArabic: _getTypeArabic(current.type, current.code),
        isLastChild: isLast,
        hasChildren: hasChildren,
      ));

      for (int i = 0; i < children.length; i++) {
        final isChildLast = (i == children.length - 1);
        dfs(children[i], depth + 1, isChildLast);
      }
    }

    for (int i = 0; i < rootAccounts.length; i++) {
      final isRootLast = (i == rootAccounts.length - 1);
      dfs(rootAccounts[i], 1, isRootLast);
    }

    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CLASSIFICATION HELPERS
  // ──────────────────────────────────────────────────────────────────────────
  static String _getTypeArabic(String type, String code) {
    final c = code.trim();
    if (c.startsWith('1')) return 'أصول';
    if (c.startsWith('23')) return 'حقوق ملكية';
    if (c.startsWith('21') || c.startsWith('22')) return 'خصوم';
    if (c == '2') return 'خصوم وحقوق ملكية';
    if (c.startsWith('3') || c.startsWith('5') || c.startsWith('6') || c.startsWith('7')) return 'مصروفات وتكاليف';
    if (c.startsWith('4')) return 'إيرادات';
    if (c.startsWith('9')) return 'حسابات وسيطة';

    switch (type.toLowerCase()) {
      case 'asset':
        return 'أصول';
      case 'liability':
        return 'خصوم';
      case 'equity':
        return 'حقوق ملكية';
      case 'revenue':
        return 'إيرادات';
      case 'expense':
        return 'مصروفات وتكاليف';
      case 'system':
        return 'حسابات وسيطة';
      default:
        return type;
    }
  }

  static String _getNormalBalance(String type, String code) {
    final c = code.trim();
    if (c.startsWith('1') || c.startsWith('3') || c.startsWith('5') || c.startsWith('6')) {
      return 'مدين (Dr)';
    }
    if (c.startsWith('2') || c.startsWith('4')) {
      return 'دائن (Cr)';
    }
    if (c.startsWith('9')) {
      return 'وسيط / تسوية';
    }

    switch (type.toLowerCase()) {
      case 'asset':
      case 'expense':
        return 'مدين (Dr)';
      case 'liability':
      case 'equity':
      case 'revenue':
        return 'دائن (Cr)';
      case 'system':
        return 'وسيط / تسوية';
      default:
        return '-';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC ENTRY POINTS
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> printPdf(
    List<AccountModel> accounts, {
    String companyName = 'مزارع فروتي - Fruity Farms',
  }) async {
    final pdfBytes = await generatePdf(accounts, companyName: companyName);
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: 'شجرة_الحسابات_دليل_الحسابات_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> sharePdf(
    List<AccountModel> accounts, {
    String companyName = 'مزارع فروتي - Fruity Farms',
  }) async {
    final pdfBytes = await generatePdf(accounts, companyName: companyName);
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'Chart_of_Accounts_5Level_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<Uint8List> generatePdf(
    List<AccountModel> accounts, {
    String companyName = 'مزارع فروتي - Fruity Farms',
  }) async {
    final fonts = await _loadFonts();
    final flattened = flattenTree(accounts);

    // Compute Exact Metrics across the 4 approved levels
    final totalAccounts = flattened.length;
    int maxLevel = 1;
    int rootCount = 0;
    int groupCount = 0;
    int subGroupCount = 0;
    int analyticalCount = 0;
    int leafCount = 0;

    for (final item in flattened) {
      if (item.level > maxLevel) maxLevel = item.level;
      switch (item.level) {
        case 1:
          rootCount++;
          break;
        case 2:
          groupCount++;
          break;
        case 3:
          subGroupCount++;
          break;
        case 4:
          analyticalCount++;
          break;
        case 5:
        default:
          leafCount++;
          break;
      }
    }

    final printDate = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fonts.regular,
        bold: fonts.bold,
        fontFallback: [fonts.regular, fonts.bold, fonts.fallback],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        textDirection: pw.TextDirection.rtl,
        header: (context) => _buildPageHeader(
          companyName: companyName,
          printDate: printDate,
          totalAccounts: totalAccounts,
          maxLevel: maxLevel,
          rootCount: rootCount,
          groupCount: groupCount,
          subGroupCount: subGroupCount,
          analyticalCount: analyticalCount,
          leafCount: leafCount,
          fontBold: fonts.bold,
          fontRegular: fonts.regular,
          isFirstPage: context.pageNumber == 1,
        ),
        footer: (context) => _buildPageFooter(
          context: context,
          fontRegular: fonts.regular,
        ),
        build: (context) => [
          _buildAccountsTableWidget(
            items: flattened,
            fontBold: fonts.bold,
            fontRegular: fonts.regular,
            fontFallback: fonts.fallback,
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER WIDGET
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildPageHeader({
    required String companyName,
    required String printDate,
    required int totalAccounts,
    required int maxLevel,
    required int rootCount,
    required int groupCount,
    required int subGroupCount,
    required int analyticalCount,
    required int leafCount,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required bool isFirstPage,
  }) {
    if (!isFirstPage) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _borderColor, width: 0.7),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'دليل الحسابات الشامل (5 مستويات هرمية) - $companyName',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 8.5,
                color: _navyPrimary,
              ),
            ),
            pw.Text(
              'تاريخ الطباعة: $printDate',
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: fontRegular,
                fontSize: 7.5,
                color: _textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Top Branding & Title Row
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 15,
                      color: _navyPrimary,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'نظام إدارة الموارد والمحاسبة المالية (ERP System)',
                    textDirection: pw.TextDirection.rtl,
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 8.5,
                      color: _textMuted,
                    ),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _navyPrimary,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  boxShadow: [
                    pw.BoxShadow(
                      color: PdfColor.fromHex('#CBD5E1'),
                      blurRadius: 2,
                      offset: const PdfPoint(0, 1),
                    ),
                  ],
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'دليل الحسابات الشامل - 5 مستويات هرمية',
                      textDirection: pw.TextDirection.rtl,
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10.5,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Comprehensive Chart of Accounts (5-Level Standard)',
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: 6.5,
                        color: PdfColor.fromHex('#94A3B8'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 8),

          // Divider Bar
          pw.Container(
            height: 2,
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [_navyPrimary, _accentColor, _borderColor],
              ),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          ),

          pw.SizedBox(height: 8),

          // Summary Statistics Card (Strict 5-Level Standard)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: _cardBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              border: pw.Border.all(color: _borderColor, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('تاريخ الطباعة', printDate, fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('إجمالي الحسابات', '$totalAccounts حساب', fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('الجذور الرئيسية', '$rootCount جذور (L1)', fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('المجموعات الرئيسية', '$groupCount مجموعة (L2)', fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('المجموعات الفرعية', '$subGroupCount فرعي (L3)', fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('حسابات رقابية', '$analyticalCount رقابي (L4)', fontBold, fontRegular),
                _buildSummaryDivider(),
                _buildSummaryItem('حسابات ترحيل', '$leafCount ترحيل (L5)', fontBold, fontRegular),
              ],
            ),
          ),

          pw.SizedBox(height: 6),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(String title, String value, pw.Font fontBold, pw.Font fontRegular) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: _textMuted),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          value,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: _navyPrimary),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryDivider() {
    return pw.Container(height: 16, width: 0.5, color: _borderColor);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TABLE WIDGET (Strict 1-to-1 TableRow Mapping with Clean Border & No Overlap)
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildAccountsTableWidget({
    required List<FlattenedCoaItem> items,
    required pw.Font fontBold,
    required pw.Font fontRegular,
    required pw.Font fontFallback,
  }) {
    final rows = <pw.TableRow>[
      // Table Header Row
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: _navyPrimary,
          borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
        ),
        repeat: true,
        children: [
          _buildHeaderCell('الكود\nCode', fontBold, align: pw.TextAlign.center),
          _buildHeaderCell('المستوى\nLevel', fontBold, align: pw.TextAlign.center),
          _buildHeaderCell('اسم الحساب والمسار الهرمي\nAccount Name & Tree Hierarchy', fontBold, align: pw.TextAlign.right),
          _buildHeaderCell('التصنيف\nType', fontBold, align: pw.TextAlign.center),
          _buildHeaderCell('طبيعة الحساب\nNormal Balance', fontBold, align: pw.TextAlign.center),
        ],
      ),
    ];

    // Build exactly ONE TableRow per FlattenedCoaItem
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final level = item.level;

      PdfColor rowBg;
      PdfColor textColor;
      pw.Font currentFont;
      double fontSize;

      if (level == 1) {
        // Level 1 Root: Dark Navy Background, Bold White Text
        rowBg = _navyLight;
        textColor = PdfColors.white;
        currentFont = fontBold;
        fontSize = 8.5;
      } else if (level == 2) {
        // Level 2 Major Group: Slate Tint Background, Bold Dark Text
        rowBg = _slateLevel2;
        textColor = _navyPrimary;
        currentFont = fontBold;
        fontSize = 8.0;
      } else if (level == 3) {
        // Level 3 Sub-Group: Soft Grey/Slate Tint Background, Semi-Bold Text
        rowBg = _slateLevel3;
        textColor = _navyPrimary;
        currentFont = fontBold;
        fontSize = 7.5;
      } else {
        // Level 4 Analytical Leaf & Operational Sub-Accounts: Pure White / Light Zebra, Clean Dark Text
        rowBg = (i % 2 == 0) ? PdfColors.white : _zebraBg;
        textColor = _textDark;
        currentFont = fontRegular;
        fontSize = 7.2;
      }

      final borderSide = pw.BorderSide(
        color: level == 1
            ? _navyPrimary
            : (level == 2 ? _borderColor : (level == 3 ? _borderColor : _borderLight)),
        width: level <= 2 ? 0.6 : 0.35,
      );

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: rowBg,
            border: pw.Border(
              bottom: borderSide,
              left: borderSide,
              right: borderSide,
            ),
          ),
          children: [
            // 0: Code
            _buildDataCell(
              item.account.code,
              font: level <= 2 ? fontBold : (level == 3 ? fontBold : fontRegular),
              fontSize: fontSize,
              textColor: textColor,
              align: pw.TextAlign.center,
              fontFallback: fontFallback,
            ),
            // 1: Level Indicator Badge
            _buildLevelCell(
              level: level,
              fontBold: fontBold,
              isSubAnalytic: item.isSubAnalytic,
            ),
            // 2: Account Name with Visual RTL Indentation and Tree Connector
            _buildAccountNameCell(
              item: item,
              font: currentFont,
              fontSize: fontSize,
              textColor: textColor,
              fontFallback: fontFallback,
            ),
            // 3: Type (Arabic)
            _buildDataCell(
              item.typeArabic,
              font: level <= 2 ? fontBold : fontRegular,
              fontSize: fontSize * 0.95,
              textColor: textColor,
              align: pw.TextAlign.center,
              fontFallback: fontFallback,
            ),
            // 4: Normal Balance (Arabic)
            _buildDataCell(
              item.normalBalance,
              font: level <= 2 ? fontBold : fontRegular,
              fontSize: fontSize * 0.95,
              textColor: textColor,
              align: pw.TextAlign.center,
              fontFallback: fontFallback,
            ),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: {
        0: const pw.FixedColumnWidth(55), // Code
        1: const pw.FixedColumnWidth(62), // Level Badge
        2: const pw.FlexColumnWidth(4.5), // Account Name & Tree Structure
        3: const pw.FixedColumnWidth(60), // Type
        4: const pw.FixedColumnWidth(60), // Normal Balance
      },
      children: rows,
    );
  }

  static pw.Widget _buildHeaderCell(
    String text,
    pw.Font fontBold, {
    pw.TextAlign align = pw.TextAlign.right,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: 7.2,
          color: PdfColors.white,
          lineSpacing: 1.1,
        ),
      ),
    );
  }

  static pw.Widget _buildLevelCell({
    required int level,
    required pw.Font fontBold,
    bool isSubAnalytic = false,
  }) {
    PdfColor badgeBg;
    PdfColor badgeText;
    String label;

    if (isSubAnalytic) {
      badgeBg = PdfColor.fromHex('#DCFCE7');
      badgeText = PdfColor.fromHex('#15803D');
      label = 'مستوى 5 - ترحيل';
    } else {
      switch (level) {
        case 1:
          badgeBg = _navyPrimary;
          badgeText = PdfColors.white;
          label = 'مستوى 1 - رئيسي';
          break;
        case 2:
          badgeBg = _accentColor;
          badgeText = PdfColors.white;
          label = 'مستوى 2 - مجموعة';
          break;
        case 3:
          badgeBg = _slateLevel2;
          badgeText = _navyPrimary;
          label = 'مستوى 3 - فرعي';
          break;
        case 4:
          badgeBg = PdfColor.fromHex('#E0F2FE');
          badgeText = PdfColor.fromHex('#0369A1');
          label = 'مستوى 4 - تحليلي';
          break;
        case 5:
        default:
          badgeBg = PdfColor.fromHex('#DCFCE7');
          badgeText = PdfColor.fromHex('#15803D');
          label = 'مستوى 5 - ترحيل';
          break;
      }
    }

    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3.5, vertical: 1.5),
        decoration: pw.BoxDecoration(
          color: badgeBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        ),
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.rtl,
          style: pw.TextStyle(
            font: fontBold,
            fontSize: 5.6,
            color: badgeText,
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildAccountNameCell({
    required FlattenedCoaItem item,
    required pw.Font font,
    required double fontSize,
    required PdfColor textColor,
    required pw.Font fontFallback,
  }) {
    final level = item.level;
    // In Arabic RTL, right padding indents the text inward from the right border.
    // Operational sub-entities under Level 4 are visually indented as child nodes.
    final double indentRight = (level <= 1)
        ? 0.0
        : (level == 2)
            ? 13.0
            : (level == 3)
                ? 26.0
                : (item.isSubAnalytic ? 48.0 : 36.0);

    return pw.Padding(
      padding: pw.EdgeInsets.only(
        right: 6.0 + indentRight,
        left: 6.0,
        top: 3.5,
        bottom: 3.5,
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.max,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Visual Tree Connector / Marker
          if (level == 1) ...[
            pw.Container(
              width: 4,
              height: 11,
              margin: const pw.EdgeInsets.only(left: 6),
              decoration: pw.BoxDecoration(
                color: _accentColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
              ),
            ),
          ] else if (level == 2) ...[
            pw.Container(
              width: 5,
              height: 5,
              margin: const pw.EdgeInsets.only(left: 5),
              decoration: pw.BoxDecoration(
                color: _navyPrimary,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
              ),
            ),
          ] else if (level == 3) ...[
            pw.Container(
              width: 4,
              height: 4,
              margin: const pw.EdgeInsets.only(left: 5),
              decoration: pw.BoxDecoration(
                color: _accentColor,
                shape: pw.BoxShape.circle,
              ),
            ),
          ] else if (level == 4 && !item.isSubAnalytic) ...[
            // Level 4 Parent Analytical Node
            pw.Container(
              width: 9,
              height: 8,
              margin: const pw.EdgeInsets.only(left: 4),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    right: 1,
                    top: 0,
                    bottom: item.isLastChild ? 4 : 0,
                    child: pw.Container(width: 1, color: _borderColor),
                  ),
                  pw.Positioned(
                    right: 1,
                    top: 4,
                    child: pw.Container(width: 6, height: 1, color: _borderColor),
                  ),
                  pw.Positioned(
                    right: 6,
                    top: 3,
                    child: pw.Container(
                      width: 2.5,
                      height: 2.5,
                      decoration: pw.BoxDecoration(
                        color: _navyLight,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Level 4 Operational Sub-Entities (Child nodes nested under Level 4)
            pw.Container(
              width: 9,
              height: 8,
              margin: const pw.EdgeInsets.only(left: 4),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    right: 1,
                    top: 0,
                    bottom: item.isLastChild ? 4 : 0,
                    child: pw.Container(width: 1, color: _accentColor),
                  ),
                  pw.Positioned(
                    right: 1,
                    top: 4,
                    child: pw.Container(width: 6, height: 1, color: _accentColor),
                  ),
                  pw.Positioned(
                    right: 6,
                    top: 3,
                    child: pw.Container(
                      width: 2.5,
                      height: 2.5,
                      decoration: pw.BoxDecoration(
                        color: _accentColor,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          pw.Expanded(
            child: pw.Text(
              item.formattedName,
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                font: font,
                fontSize: fontSize,
                color: textColor,
                fontFallback: [fontFallback, pw.Font.courier(), pw.Font.helvetica()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDataCell(
    String text, {
    required pw.Font font,
    required double fontSize,
    required PdfColor textColor,
    required pw.TextAlign align,
    required pw.Font fontFallback,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          color: textColor,
          fontFallback: [fontFallback, pw.Font.courier(), pw.Font.helvetica()],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FOOTER WIDGET
  // ──────────────────────────────────────────────────────────────────────────
  static pw.Widget _buildPageFooter({
    required pw.Context context,
    required pw.Font fontRegular,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'نظام Fruity Farms ERP - دليل الحسابات المعتمد محاسبيا (سري وللاستخدام الداخلي)',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font: fontRegular,
              fontSize: 7,
              color: _textMuted,
            ),
          ),
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(
              font: fontRegular,
              fontSize: 7,
              color: _textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Official alias for ChartOfAccountsPdfService to support both naming conventions seamlessly
typedef ChartOfAccountsPdfService = AdvancedCoaPdfService;
