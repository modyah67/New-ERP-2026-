library;

import 'package:flutter/material.dart';

/// Defines a single column in a reporting data grid.
///
/// Reports supply column configs. The framework uses them to render
/// headers, rows, sort, and format values.
@immutable
class ReportColumn {
  final String key;
  final String label;
  final String labelAr;
  final double? fixedWidth;
  final double? minWidth;
  final int flex;
  final bool sortable;
  final bool alignRight;
  final String? currency;

  const ReportColumn({
    required this.key,
    required this.label,
    required this.labelAr,
    this.fixedWidth,
    this.minWidth,
    this.flex = 1,
    this.sortable = false,
    this.alignRight = false,
    this.currency,
  });
}

/// A single metric displayed in a summary card.
@immutable
class MetricData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const MetricData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
}

/// An export action available in the toolbar.
@immutable
class ExportAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const ExportAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}
