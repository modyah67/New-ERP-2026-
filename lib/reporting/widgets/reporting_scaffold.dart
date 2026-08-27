library;

import 'package:flutter/material.dart';
import '../models/reporting_models.dart';
import 'reporting_page_header.dart';
import 'reporting_summary_cards.dart';
import 'reporting_validation_panel.dart';
import 'reporting_toolbar.dart';
import 'reporting_data_grid.dart';
import 'reporting_loading_overlay.dart';

/// The main reporting page scaffold.
///
/// Reports provide configuration + data. This widget handles layout composition.
/// Every report page becomes: `Scaffold(body: ReportingScaffold(...))`
class ReportingScaffold extends StatelessWidget {
  // ── Header ──
  final IconData headerIcon;
  final String headerTitle;
  final int? headerCount;
  final String? headerCountLabel;
  final List<Widget> headerActions;

  // ── Filter ──
  final Widget? filterBar;

  // ── Summary ──
  final List<MetricData>? metrics;

  // ── Validation ──
  final bool? isBalanced;
  final double? totalDebit;
  final double? totalCredit;
  final double? difference;
  final dynamic validationResult;
  final String? debitLabel;
  final String? creditLabel;
  final String? differenceLabel;
  final bool showStatusBadge;

  // ── Toolbar ──
  final VoidCallback onRefresh;
  final VoidCallback onFullscreen;
  final List<ExportAction> exportActions;

  // ── Data Grid ──
  final List<ReportColumn> columns;
  final List<ReportingRowData> rows;
  final CellRenderer cellRenderer;
  final WidgetCellRenderer? widgetCellRenderer;
  final String? sortColumn;
  final bool sortAscending;
  final Function(String)? onSort;
  final Function(String)? onRowTap;
  final Function(String)? onExpandToggle;
  final Set<String> expandedIds;
  final Map<String, int> depthMap;
  final bool showHierarchy;
  final Widget? gridFooter;
  final Widget? emptyState;

  // ── Refresh overlay ──
  final bool isRefreshing;
  final Color? backgroundColor;

  const ReportingScaffold({
    super.key,
    // Header
    this.headerIcon = Icons.balance_outlined,
    required this.headerTitle,
    this.headerCount,
    this.headerCountLabel,
    this.headerActions = const [],
    // Filter
    this.filterBar,
    // Summary
    this.metrics,
    // Validation
    this.isBalanced,
    this.totalDebit,
    this.totalCredit,
    this.difference,
    this.validationResult,
    this.debitLabel,
    this.creditLabel,
    this.differenceLabel,
    this.showStatusBadge = true,
    // Toolbar
    required this.onRefresh,
    required this.onFullscreen,
    this.exportActions = const [],
    // DataGrid
    this.columns = const [],
    this.rows = const [],
    required this.cellRenderer,
    this.widgetCellRenderer,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
    this.onExpandToggle,
    this.expandedIds = const {},
    this.depthMap = const {},
    this.showHierarchy = false,
    this.gridFooter,
    this.emptyState,
    // Refresh overlay
    this.isRefreshing = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? Colors.transparent,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                ReportingPageHeader(
                  icon: headerIcon,
                  title: headerTitle,
                  count: headerCount,
                  countLabel: headerCountLabel,
                  actions: headerActions,
                ),
                const SizedBox(height: 20),

                // ── Filter ──
                if (filterBar != null) ...[
                  filterBar!,
                  const SizedBox(height: 16),
                ],

                // ── Summary, Validation & Toolbar ──
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (metrics != null && metrics!.isNotEmpty) ...[
                        ReportingSummaryCards(metrics: metrics!),
                        const SizedBox(width: 12),
                      ],
                      if (isBalanced != null &&
                          totalDebit != null &&
                          totalCredit != null &&
                          difference != null) ...[
                        ReportingValidationPanel(
                          isBalanced: isBalanced!,
                          totalDebit: totalDebit!,
                          totalCredit: totalCredit!,
                          difference: difference!,
                          validationResult: validationResult,
                          debitLabel: debitLabel,
                          creditLabel: creditLabel,
                          differenceLabel: differenceLabel,
                          showStatusBadge: showStatusBadge,
                        ),
                        const SizedBox(width: 12),
                      ],
                      ReportingToolbar(
                        onRefresh: onRefresh,
                        onFullscreen: onFullscreen,
                        exportActions: exportActions,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Data Grid ──
                Expanded(
                  child: rows.isEmpty && emptyState != null
                      ? emptyState!
                      : ReportingDataGrid(
                          columns: columns,
                          rows: rows,
                          cellRenderer: cellRenderer,
                          widgetCellRenderer: widgetCellRenderer,
                          sortColumn: sortColumn,
                          sortAscending: sortAscending,
                          onSort: onSort,
                          onRowTap: onRowTap,
                          onExpandToggle: onExpandToggle,
                          expandedIds: expandedIds,
                          depthMap: depthMap,
                          showHierarchy: showHierarchy,
                          footer: gridFooter,
                        ),
                ),
              ],
            ),
          ),
          // ── Refresh Overlay ──
          ReportingLoadingOverlay(isVisible: isRefreshing),
        ],
      ),
    );
  }
}
