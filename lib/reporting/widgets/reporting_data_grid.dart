library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../models/reporting_models.dart';

/// A single data row for the grid, with hierarchy support.
@immutable
class ReportingRowData {
  final String id;
  final Map<String, dynamic> cells;
  final bool hasChildren;
  final bool isParent;

  const ReportingRowData({
    required this.id,
    required this.cells,
    this.hasChildren = false,
    this.isParent = false,
  });
}

/// Callback that returns the display value for a cell (plain text).
typedef CellRenderer = String Function(ReportingRowData row, ReportColumn column);

/// Callback that returns a custom widget for a cell (colored text, badges, etc.).
/// When provided, [CellRenderer] is used only as a fallback for plain text.
typedef WidgetCellRenderer = Widget Function(ReportingRowData row, ReportColumn column);

/// Enterprise data grid with sticky header, sortable columns,
/// hierarchy indent, expand/collapse arrows, and footer totals.
class ReportingDataGrid extends StatelessWidget {
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
  final Widget? footer;

  const ReportingDataGrid({
    super.key,
    required this.columns,
    required this.rows,
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
    this.footer,
  });

  double get _minGridWidth {
    double minWidth = 0;
    for (var col in columns) {
      if (col.fixedWidth != null) {
        minWidth += col.fixedWidth!;
      } else if (col.minWidth != null) {
        minWidth += col.minWidth!;
      } else {
        minWidth += col.flex * 120.0; // 120 pixels per flex unit minimum
      }
    }
    return minWidth + 32;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: AppTheme.glassCard().copyWith(
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minW = _minGridWidth;
            final gridWidth =
                constraints.maxWidth < minW ? minW : constraints.maxWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: gridWidth,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: rows.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                final depth = depthMap[row.id] ?? 0;
                                return _buildRow(row, depth, index);
                              },
                            ),
                    ),
                    if (footer != null) footer!,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        border: Border(
          bottom: BorderSide(color: AppTheme.border.withAlpha(80), width: 1.5),
        ),
      ),
      child: Row(
        children: [
          for (final col in columns) ...[
            if (col.fixedWidth != null)
              SizedBox(
                width: col.fixedWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _SortableHeader(
                    label: col.labelAr,
                    columnKey: col.key,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    sortable: col.sortable,
                    alignRight: col.alignRight,
                    onSort: onSort,
                  ),
                ),
              )
            else
              Expanded(
                flex: col.flex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _SortableHeader(
                    label: col.labelAr,
                    columnKey: col.key,
                    currentSort: sortColumn,
                    ascending: sortAscending,
                    sortable: col.sortable,
                    alignRight: col.alignRight,
                    onSort: onSort,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(ReportingRowData row, int depth, int index) {
    final indent = showHierarchy ? depth * 24.0 : 0.0;

    return RepaintBoundary(
      child: InkWell(
        onTap: onRowTap != null ? () => onRowTap!(row.id) : null,
        hoverColor: AppTheme.primary.withAlpha(15),
        child: Container(
          height: 56,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: index.isEven
                ? Colors.white.withAlpha(6)
                : Colors.white.withAlpha(12),
            border: Border(
              bottom: BorderSide(
                color: AppTheme.border.withAlpha(30),
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final col in columns) ...[
                if (col.fixedWidth != null)
                  SizedBox(
                    width: col.fixedWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          if (showHierarchy && col == columns.first) ...[
                            SizedBox(width: indent),
                            if (row.hasChildren)
                              GestureDetector(
                                onTap: onExpandToggle != null
                                    ? () => onExpandToggle!(row.id)
                                    : null,
                                child: Icon(
                                  expandedIds.contains(row.id)
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_right,
                                  size: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              )
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: _buildCellContent(row, col),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    flex: col.flex,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _buildCellContent(row, col),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCellContent(ReportingRowData row, ReportColumn col) {
    if (widgetCellRenderer != null) {
      return Container(
        alignment: col.alignRight
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: widgetCellRenderer!(row, col),
      );
    }

    final rawValue = cellRenderer(row, col);
    final isParentRow = row.isParent;
    final cleanValue = rawValue.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    Widget textWidget = Text(
      cleanValue,
      style: TextStyle(
        fontSize: 13,
        color: AppTheme.textPrimary,
        fontFamily: col.currency != null ? 'monospace' : 'Cairo',
        fontWeight: isParentRow ? FontWeight.w600 : FontWeight.normal,
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: col.alignRight ? TextAlign.end : TextAlign.start,
    );

    if (cleanValue.isNotEmpty) {
      textWidget = Tooltip(
        message: cleanValue,
        waitDuration: const Duration(milliseconds: 350),
        textStyle: const TextStyle(
          fontSize: 12,
          color: Colors.white,
          fontFamily: 'Cairo',
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border.withAlpha(100)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: textWidget,
      );
    }

    return Container(
      alignment: col.alignRight
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: textWidget,
    );
  }
}

class _SortableHeader extends StatelessWidget {
  final String label;
  final String columnKey;
  final String? currentSort;
  final bool ascending;
  final bool sortable;
  final bool alignRight;
  final Function(String)? onSort;

  const _SortableHeader({
    required this.label,
    required this.columnKey,
    this.currentSort,
    required this.ascending,
    this.sortable = false,
    this.alignRight = false,
    this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentSort == columnKey;
    final alignment = alignRight
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final mainAxisAlignment =
        alignRight ? MainAxisAlignment.end : MainAxisAlignment.start;

    if (!sortable) {
      return Container(
        alignment: alignment,
        child: Text(
          label,
          style: _headerStyle,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return GestureDetector(
      onTap: onSort != null ? () => onSort!(columnKey) : null,
      child: Container(
        alignment: alignment,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: mainAxisAlignment,
          children: [
            Flexible(
              child: Text(
                label,
                style: _headerStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: AppTheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    color: AppTheme.textPrimary,
  );
}
