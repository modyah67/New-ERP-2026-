import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/services/journal_entry_navigation_service.dart';

/// Modal dialog / bottom sheet that displays all actual journal entries
/// linked to a shipment's profitability and costs with full line breakdown.
class ShipmentJournalEntriesDialog extends StatefulWidget {
  final String shipmentNo;
  final List<Map<String, dynamic>> entries;
  final bool isLoading;

  const ShipmentJournalEntriesDialog({
    super.key,
    required this.shipmentNo,
    required this.entries,
    this.isLoading = false,
  });

  /// Shows this dialog as an adaptive modal (Dialog on desktop, BottomSheet on mobile).
  static Future<void> show(
    BuildContext context, {
    required String shipmentNo,
    required Future<List<Map<String, dynamic>>> entriesFuture,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: entriesFuture,
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final entries = snapshot.data ?? [];
            return ShipmentJournalEntriesDialog(
              shipmentNo: shipmentNo,
              entries: entries,
              isLoading: isLoading,
            );
          },
        );
      },
    );
  }

  @override
  State<ShipmentJournalEntriesDialog> createState() =>
      _ShipmentJournalEntriesDialogState();
}

class _ShipmentJournalEntriesDialogState
    extends State<ShipmentJournalEntriesDialog> {
  String _selectedFilter = 'all'; // 'all', 'costs', 'commercial'
  final Set<int> _expandedEntries = {};

  @override
  void initState() {
    super.initState();
    // Expand all entries by default for immediate clarity
    for (final e in widget.entries) {
      final id = e['journal_entry_id'] as int?;
      if (id != null) _expandedEntries.add(id);
    }
  }

  @override
  void didUpdateWidget(covariant ShipmentJournalEntriesDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.length != widget.entries.length) {
      for (final e in widget.entries) {
        final id = e['journal_entry_id'] as int?;
        if (id != null) _expandedEntries.add(id);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredEntries {
    if (_selectedFilter == 'costs') {
      return widget.entries.where((e) => e['is_cost_entry'] == true).toList();
    } else if (_selectedFilter == 'commercial') {
      return widget.entries
          .where((e) =>
              e['category'] == 'commercial' ||
              (e['is_cost_entry'] == false &&
                  e['category'] != 'return' &&
                  e['is_return_entry'] != true))
          .toList();
    } else if (_selectedFilter == 'returns') {
      return widget.entries
          .where((e) => e['category'] == 'return' || e['is_return_entry'] == true)
          .toList();
    }
    return widget.entries;
  }

  double get _totalCostDebits {
    return widget.entries
        .where((e) => e['is_cost_entry'] == true)
        .fold(0.0, (sum, e) => sum + ((e['total_debit'] as num?)?.toDouble() ?? 0.0));
  }

  double get _totalCommercialDebits {
    return widget.entries
        .where((e) => e['is_cost_entry'] == false)
        .fold(0.0, (sum, e) => sum + ((e['total_debit'] as num?)?.toDouble() ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final dialogWidth = isMobile
        ? MediaQuery.of(context).size.width * 0.95
        : MediaQuery.of(context).size.width * 0.85;
    final dialogHeight = MediaQuery.of(context).size.height * 0.90;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 24,
          vertical: 24,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: dialogWidth.clamp(320, 1100),
              height: dialogHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF07182B).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildHeader(context),
                  _buildSummaryBar(isMobile),
                  _buildFilterBar(),
                  Expanded(
                    child: widget.isLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppTheme.primary),
                          )
                        : _buildEntriesList(isMobile),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D243F),
        border: Border(
          bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'قيود ربحية وتكاليف الشحنة [${widget.shipmentNo}]',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'استعراض القيود المحاسبية الفعلية في دفتر اليومية العام والأستاذ المساعد',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 22),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(bool isMobile) {
    final costEntriesCount =
        widget.entries.where((e) => e['is_cost_entry'] == true).length;
    final commercialCount = widget.entries
        .where((e) =>
            e['category'] == 'commercial' ||
            (e['is_cost_entry'] == false &&
                e['category'] != 'return' &&
                e['is_return_entry'] != true))
        .length;
    final returnCount = widget.entries
        .where((e) => e['category'] == 'return' || e['is_return_entry'] == true)
        .length;
    final returnDebits = widget.entries
        .where((e) => e['category'] == 'return' || e['is_return_entry'] == true)
        .fold(0.0, (sum, e) => sum + ((e['total_debit'] as num?)?.toDouble() ?? 0.0));
    final allBalanced =
        widget.entries.isNotEmpty && widget.entries.every((e) => e['is_balanced'] == true);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2642),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _summaryBadge(
            icon: Icons.receipt_long,
            label: 'إجمالي القيود',
            value: '${widget.entries.length}',
            color: AppTheme.primary,
          ),
          _summaryBadge(
            icon: Icons.inventory_2_outlined,
            label: 'قيود التكاليف الفعلية',
            value: '$costEntriesCount قيد (${_formatNum(_totalCostDebits)} ج.م)',
            color: const Color(0xFFF59E0B),
          ),
          _summaryBadge(
            icon: Icons.trending_up,
            label: 'قيود الشحنة والإيرادات',
            value: '$commercialCount قيد (${_formatNum(_totalCommercialDebits)} ج.م)',
            color: const Color(0xFF10B981),
          ),
          if (returnCount > 0)
            _summaryBadge(
              icon: Icons.assignment_return_outlined,
              label: 'قيود المرتجع والإلغاء',
              value: '$returnCount قيد (${_formatNum(returnDebits)} ج.م)',
              color: const Color(0xFFEA580C),
            ),
          if (widget.entries.isNotEmpty)
            _summaryBadge(
              icon: allBalanced ? Icons.check_circle : Icons.warning_amber_rounded,
              label: 'حالة الاتزان المحاسبي',
              value: allBalanced ? 'متزنة 100%' : 'تتطلب مراجعة',
              color: allBalanced ? const Color(0xFF10B981) : AppTheme.danger,
            ),
        ],
      ),
    );
  }

  Widget _summaryBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'Cairo',
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final costCount = widget.entries.where((e) => e['is_cost_entry'] == true).length;
    final commCount = widget.entries
        .where((e) =>
            e['category'] == 'commercial' ||
            (e['is_cost_entry'] == false &&
                e['category'] != 'return' &&
                e['is_return_entry'] != true))
        .length;
    final returnCount = widget.entries
        .where((e) => e['category'] == 'return' || e['is_return_entry'] == true)
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _filterChip(
            key: 'all',
            label: 'جميع القيود (${widget.entries.length})',
            isSelected: _selectedFilter == 'all',
          ),
          const SizedBox(width: 8),
          _filterChip(
            key: 'costs',
            label: 'قيود التكاليف الفعلية ($costCount)',
            isSelected: _selectedFilter == 'costs',
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 8),
          _filterChip(
            key: 'commercial',
            label: 'قيود الشحنة والإيراد ($commCount)',
            isSelected: _selectedFilter == 'commercial',
            color: const Color(0xFF10B981),
          ),
          if (returnCount > 0) ...[
            const SizedBox(width: 8),
            _filterChip(
              key: 'returns',
              label: 'قيود المرتجع والإلغاء ($returnCount)',
              isSelected: _selectedFilter == 'returns',
              color: const Color(0xFFEA580C),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String key,
    required String label,
    required bool isSelected,
    Color? color,
  }) {
    final activeColor = color ?? AppTheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : AppTheme.glassBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 11.5,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildEntriesList(bool isMobile) {
    final entries = _filteredEntries;

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 52, color: AppTheme.textMuted.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              Text(
                widget.entries.isEmpty
                    ? 'لا توجد قيود محاسبية مرتبطة بهذه الشحنة حتى الآن.'
                    : 'لا توجد قيود محاسبية مسجلة في هذا التصنيف',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.entries.isEmpty
                    ? 'عرض القيود لا ينشئ قيودًا محاسبية. احفظ تكاليف الشحنة أو رحّل أمر التعبئة أولاً.'
                    : 'تأكد من اختيار التبويب المناسب لعرض القيود المطلوبة.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildEntryCard(entries[index], isMobile);
      },
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, bool isMobile) {
    final jeId = entry['journal_entry_id'] as int?;
    final isExpanded = jeId != null && _expandedEntries.contains(jeId);
    final isReturn = entry['category'] == 'return' || entry['is_return_entry'] == true;
    final isCost = entry['is_cost_entry'] == true && !isReturn;
    final isBalanced = entry['is_balanced'] == true;
    final lines = (entry['lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final themeColor = isReturn
        ? const Color(0xFFEA580C)
        : (isCost ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F36),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (jeId == null) return;
              setState(() {
                if (isExpanded) {
                  _expandedEntries.remove(jeId);
                } else {
                  _expandedEntries.add(jeId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Entry Number Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: themeColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          entry['entry_number']?.toString() ?? '#$jeId',
                          style: TextStyle(
                            color: themeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Category Label Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry['category_label']?.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Date
                      Text(
                        entry['entry_date']?.toString() ?? '',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontFamily: 'Cairo',
                        ),
                      ),

                      const Spacer(),

                      // Status Badge (مرحّل)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          entry['status']?.toString() ?? 'مرحّل',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Balance Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? AppTheme.primary.withValues(alpha: 0.15)
                              : AppTheme.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBalanced ? 'متزن ✓' : 'غير متزن ⚠',
                          style: TextStyle(
                            color: isBalanced ? AppTheme.primary : AppTheme.danger,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Expand Icon
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Entry Description & Total Amount
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry['description']?.toString() ?? '',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_formatNum((entry['total_debit'] as num?)?.toDouble() ?? 0)} ${entry['currency'] ?? 'EGP'}',
                            style: TextStyle(
                              color: themeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            isCost ? 'ضمن تكاليف الشحنة' : 'إيرادات تجارية',
                            style: TextStyle(
                              color: isCost ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                              fontSize: 9.5,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded Lines Table
          if (isExpanded) ...[
            const Divider(color: AppTheme.glassBorder, height: 1),
            Container(
              color: const Color(0xFF061423),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  _buildLinesHeader(isMobile),
                  const Divider(color: Colors.white12, height: 8),
                  ...lines.map((l) => _buildLineRow(l, isMobile)),
                  const Divider(color: Colors.white12, height: 12),
                  _buildLinesFooter(entry, isMobile),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 14, color: AppTheme.primary),
                        label: const Text(
                          'عرض في دفتر اليومية العام',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        onPressed: () {
                          JournalEntryNavigationService.openById(
                            context,
                            journalEntryId: jeId,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLinesHeader(bool isMobile) {
    return Row(
      children: [
        const Expanded(
          flex: 4,
          child: Text('الحساب واسم الدليل',
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
        ),
        const SizedBox(
          width: 70,
          child: Text('الكود',
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
        ),
        const SizedBox(
          width: 85,
          child: Text('مدين',
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
        ),
        const SizedBox(
          width: 85,
          child: Text('دائن',
              textAlign: TextAlign.end,
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
        ),
        const SizedBox(
          width: 45,
          child: Text('العملة',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
        ),
        if (!isMobile)
          const Expanded(
            flex: 2,
            child: Text('مركز التكلفة',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 10.5, fontFamily: 'Cairo')),
          ),
      ],
    );
  }

  Widget _buildLineRow(Map<String, dynamic> line, bool isMobile) {
    final debit = (line['debit'] as num?)?.toDouble() ?? 0.0;
    final credit = (line['credit'] as num?)?.toDouble() ?? 0.0;
    final hasDebit = debit > 0;
    final hasCredit = credit > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              line['account_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              line['account_code']?.toString() ?? '',
              style: const TextStyle(
                color: AppTheme.warning,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 85,
            child: Text(
              hasDebit ? _formatNum(debit) : '—',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: hasDebit ? const Color(0xFF10B981) : AppTheme.textMuted,
                fontWeight: hasDebit ? FontWeight.bold : FontWeight.normal,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 85,
            child: Text(
              hasCredit ? _formatNum(credit) : '—',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: hasCredit ? const Color(0xFFEF4444) : AppTheme.textMuted,
                fontWeight: hasCredit ? FontWeight.bold : FontWeight.normal,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              line['currency']?.toString() ?? 'EGP',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 10,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          if (!isMobile)
            Expanded(
              flex: 2,
              child: Text(
                line['cost_center_id']?.toString() ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinesFooter(Map<String, dynamic> entry, bool isMobile) {
    final totDebit = (entry['total_debit'] as num?)?.toDouble() ?? 0.0;
    final totCredit = (entry['total_credit'] as num?)?.toDouble() ?? 0.0;
    final isBalanced = entry['is_balanced'] == true;

    return Row(
      children: [
        const Expanded(
          flex: 4,
          child: Text('الإجمالي وحالة الاتزان',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
        ),
        SizedBox(
          width: 70,
          child: Text(isBalanced ? 'متزن ✓' : 'غير متزن ⚠',
              style: TextStyle(
                  color: isBalanced ? const Color(0xFF10B981) : AppTheme.danger,
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                  fontFamily: 'Cairo')),
        ),
        SizedBox(
          width: 85,
          child: Text(
            _formatNum(totDebit),
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(
          width: 85,
          child: Text(
            _formatNum(totCredit),
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            entry['currency']?.toString() ?? 'EGP',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'Cairo',
            ),
          ),
        ),
        if (!isMobile) const Expanded(flex: 2, child: SizedBox()),
      ],
    );
  }

  static String _formatNum(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}
