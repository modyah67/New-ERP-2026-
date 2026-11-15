import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

/// Semantic card type for automatic visual contrast and styling.
enum SummaryCardType {
  /// Positive / Profit / Up-trend (Vibrant Emerald / Mint / Cyan)
  positive,

  /// Negative / Deficit / Cost (Crimson Rose / Coral Red)
  negative,

  /// Carried Forward / Baseline / Opening Balance (Warm Amber / Golden)
  warning,

  /// Informational / Operational (Sky Blue / Cerulean)
  info,

  /// Foreign Currencies (Royal Indigo / Sapphire Purple)
  currency,

  /// Neutral / Counts / Metadata (Slate Steel / Cool Grey)
  neutral,

  /// Primary Highlight (Glow Border & Subtle Gradient)
  primary,

  /// Automatically decides between positive and negative based on the value's sign.
  auto,
}

/// Data model representing a single summary card inside the [EnhancedSummaryBar].
class SummaryCardData {
  /// Unique identifier (used for customization persistence & live animations).
  final String id;

  /// Arabic label/title of the metric.
  final String title;

  /// Numeric value. If provided, triggers animated counter and semantic sign detection.
  final double? value;

  /// Formatted text override (if value is null or custom string representation is desired).
  final String? customFormattedValue;

  /// Currency code or symbol (e.g. 'EGP', 'USD', 'ج.م', '$').
  final String currency;

  /// Icon representing the metric visually.
  final IconData icon;

  /// Visual semantic classification.
  final SummaryCardType cardType;

  /// Custom color override (overrides cardType color if provided).
  final Color? customColor;

  /// Secondary subtitle or calculation note (e.g. "الإجمالي الدفتري: EGP 58,555.56").
  final String? subtitle;

  /// Comprehensive tooltip explanation of what the card means and how it is calculated.
  final String? tooltip;

  /// Whether this card is considered primary/essential (displayed with higher visual prominence).
  final bool isPrimary;

  /// Optional click callback (e.g. to filter, jump to details, or open drill-down).
  final VoidCallback? onTap;

  /// Optional companion widgets (such as foreign currency mini-pills).
  final List<Widget>? companionWidgets;

  const SummaryCardData({
    required this.id,
    required this.title,
    this.value,
    this.customFormattedValue,
    this.currency = 'EGP',
    required this.icon,
    this.cardType = SummaryCardType.auto,
    this.customColor,
    this.subtitle,
    this.tooltip,
    this.isPrimary = false,
    this.onTap,
    this.companionWidgets,
  });

  SummaryCardData copyWith({
    String? id,
    String? title,
    double? value,
    String? customFormattedValue,
    String? currency,
    IconData? icon,
    SummaryCardType? cardType,
    Color? customColor,
    String? subtitle,
    String? tooltip,
    bool? isPrimary,
    VoidCallback? onTap,
    List<Widget>? companionWidgets,
  }) {
    return SummaryCardData(
      id: id ?? this.id,
      title: title ?? this.title,
      value: value ?? this.value,
      customFormattedValue: customFormattedValue ?? this.customFormattedValue,
      currency: currency ?? this.currency,
      icon: icon ?? this.icon,
      cardType: cardType ?? this.cardType,
      customColor: customColor ?? this.customColor,
      subtitle: subtitle ?? this.subtitle,
      tooltip: tooltip ?? this.tooltip,
      isPrimary: isPrimary ?? this.isPrimary,
      onTap: onTap ?? this.onTap,
      companionWidgets: companionWidgets ?? this.companionWidgets,
    );
  }
}

/// A top-tier, responsive, customizable Summary Bar for ERP dashboard pages.
///
/// Features:
/// - Semantic color contrast (Green for profits/positive, Red for deficit/negative, Amber for opening, Indigo for FX).
/// - Rich Tooltip explanations on hover.
/// - Live Animated smooth counters on data updates.
/// - Built-in card customization dialog with persistent storage.
/// - Elegant multi-currency display without visual clutter.
class EnhancedSummaryBar extends StatefulWidget {
  /// Unique storage key for persisting visible/hidden card preferences.
  final String storageKey;

  /// List of cards to be displayed in the bar.
  final List<SummaryCardData> cards;

  /// Optional leading widget (e.g., section badge, quick filter, or title).
  final Widget? leading;

  /// Optional trailing widget (e.g., action buttons or status indicators).
  final Widget? trailing;

  /// Whether to show the customization settings button.
  final bool showCustomizeButton;

  /// Padding around the bar.
  final EdgeInsetsGeometry padding;

  const EnhancedSummaryBar({
    super.key,
    required this.storageKey,
    required this.cards,
    this.leading,
    this.trailing,
    this.showCustomizeButton = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  State<EnhancedSummaryBar> createState() => _EnhancedSummaryBarState();
}

class _EnhancedSummaryBarState extends State<EnhancedSummaryBar> {
  Set<String> _hiddenCardIds = {};

  @override
  void initState() {
    super.initState();
    _loadVisibilityPreferences();
  }

  @override
  void didUpdateWidget(covariant EnhancedSummaryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageKey != widget.storageKey) {
      _loadVisibilityPreferences();
    }
  }

  String get _prefsKey => 'enhanced_summary_bar_hidden_${widget.storageKey}';

  Future<void> _loadVisibilityPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey);
      if (list != null) {
        if (mounted) {
          setState(() {
            _hiddenCardIds = list.toSet();
          });
          return;
        }
      }
    } catch (e) {
      // Fallback for desktop when SharedPreferences plugin is unavailable
      try {
        final file = File('.summary_bar_prefs_${widget.storageKey}.json');
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final decoded = (jsonDecode(content) as List).cast<String>();
          if (mounted) {
            setState(() {
              _hiddenCardIds = decoded.toSet();
            });
            return;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _saveVisibilityPreferences(Set<String> hiddenIds) async {
    setState(() => _hiddenCardIds = hiddenIds);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, hiddenIds.toList());
    } catch (e) {
      try {
        final file = File('.summary_bar_prefs_${widget.storageKey}.json');
        await file.writeAsString(jsonEncode(hiddenIds.toList()));
      } catch (_) {}
    }
  }

  void _openCustomizationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SummaryBarCustomizeDialog(
        allCards: widget.cards,
        initiallyHiddenIds: _hiddenCardIds,
        onSave: (newHidden) => _saveVisibilityPreferences(newHidden),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter visible cards based on user customization
    final visibleCards = widget.cards.where((c) => !_hiddenCardIds.contains(c.id)).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF041936) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppTheme.primary.withValues(alpha: 0.25)
                : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;

          // Action button to customize cards
          final customizeBtn = widget.showCustomizeButton
              ? Tooltip(
                  message: 'تخصيص الكروت الظاهرة في شريط الملخصات',
                  preferBelow: false,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F2B48) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.white,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openCustomizationDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 15,
                              color: isDark ? AppTheme.cyan : const Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'تخصيص',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppTheme.cyan : const Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink();

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.leading != null || widget.showCustomizeButton)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (widget.leading != null) widget.leading!,
                      customizeBtn,
                    ],
                  ),
                if (widget.leading != null || widget.showCustomizeButton)
                  const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: visibleCards.map((c) => _SummaryCardWidget(card: c)).toList(),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(height: 8),
                  Center(child: widget.trailing!),
                ],
              ],
            );
          }

          // Full Desktop / Wide Layout
          return Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < visibleCards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        _SummaryCardWidget(card: visibleCards[i]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.trailing != null) ...[
                widget.trailing!,
                const SizedBox(width: 8),
              ],
              customizeBtn,
            ],
          );
        },
      ),
    );
  }
}

/// Single summary card widget with hover effects, semantic styling, and tooltips.
class _SummaryCardWidget extends StatefulWidget {
  final SummaryCardData card;

  const _SummaryCardWidget({required this.card});

  @override
  State<_SummaryCardWidget> createState() => _SummaryCardWidgetState();
}

class _SummaryCardWidgetState extends State<_SummaryCardWidget> {
  bool _isHovered = false;

  Color _resolveColor(BuildContext context) {
    if (widget.card.customColor != null) {
      return widget.card.customColor!;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (widget.card.cardType) {
      case SummaryCardType.positive:
        return const Color(0xFF10B981); // Emerald
      case SummaryCardType.negative:
        return const Color(0xFFF43F5E); // Rose Red
      case SummaryCardType.warning:
        return const Color(0xFFF59E0B); // Amber / Gold
      case SummaryCardType.info:
        return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7); // Sky Blue
      case SummaryCardType.currency:
        return isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5); // Indigo
      case SummaryCardType.neutral:
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569); // Slate Steel
      case SummaryCardType.primary:
        return AppTheme.primary;
      case SummaryCardType.auto:
        final v = widget.card.value ?? 0.0;
        if (v > 0) {
          return const Color(0xFF10B981);
        } else if (v < 0) {
          return const Color(0xFFF43F5E);
        }
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _resolveColor(context);
    final isPrimary = widget.card.isPrimary;

    Widget cardContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.card.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isPrimary ? 12 : 10,
          vertical: isPrimary ? 7 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: _isHovered
                ? (isDark ? 0.22 : 0.16)
                : (isDark ? (isPrimary ? 0.16 : 0.10) : (isPrimary ? 0.12 : 0.07)),
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(
              alpha: _isHovered
                  ? (isDark ? 0.70 : 0.60)
                  : (isDark ? (isPrimary ? 0.45 : 0.28) : (isPrimary ? 0.40 : 0.22)),
            ),
            width: isPrimary ? 1.4 : 1.0,
          ),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: isDark ? 0.3 : 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon Pill
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.20 : 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.card.icon,
                size: isPrimary ? 15 : 13,
                color: color,
              ),
            ),
            const SizedBox(width: 7),

            // Text & Live Number
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.card.title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isPrimary ? 11.5 : 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                    if (widget.card.subtitle != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        widget.card.subtitle!,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white54 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),

                // Animated Numeric Value / Formatted Value
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.card.value != null)
                      LiveAnimatedCounter(
                        value: widget.card.value!,
                        currency: widget.card.currency,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: isPrimary ? 13.5 : 12.0,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      )
                    else if (widget.card.customFormattedValue != null)
                      Text(
                        widget.card.customFormattedValue!,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: isPrimary ? 13.5 : 12.0,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Companion widgets (such as foreign currency pills)
            if (widget.card.companionWidgets != null &&
                widget.card.companionWidgets!.isNotEmpty) ...[
              const SizedBox(width: 6),
              ...widget.card.companionWidgets!,
            ],
          ],
        ),
      ),
    );

    if (widget.card.onTap != null) {
      cardContent = GestureDetector(
        onTap: widget.card.onTap,
        child: cardContent,
      );
    }

    if (widget.card.tooltip != null && widget.card.tooltip!.isNotEmpty) {
      return Tooltip(
        message: widget.card.tooltip!,
        preferBelow: false,
        verticalOffset: 24,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF071E3D) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.45 : 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          height: 1.4,
        ),
        child: cardContent,
      );
    }

    return cardContent;
  }
}

/// A smoothly animated counter for live metric updates.
///
/// Smoothly transitions from the previous value to the new value over 400ms
/// without sudden jumps or visual flicker.
class LiveAnimatedCounter extends StatefulWidget {
  final double value;
  final String currency;
  final TextStyle? style;
  final int fractionDigits;

  const LiveAnimatedCounter({
    super.key,
    required this.value,
    this.currency = 'EGP',
    this.style,
    this.fractionDigits = 2,
  });

  @override
  State<LiveAnimatedCounter> createState() => _LiveAnimatedCounterState();
}

class _LiveAnimatedCounterState extends State<LiveAnimatedCounter> {
  final NumberFormat _formatter = NumberFormat('#,##0.00');

  String _format(double v) {
    if (widget.fractionDigits == 0) {
      return NumberFormat('#,##0').format(v);
    }
    return _formatter.format(v);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: widget.value, end: widget.value),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedVal, child) {
        final sign = animatedVal < 0 ? '-' : '';
        final absVal = animatedVal.abs();
        final textVal = _format(absVal);

        return Text(
          widget.currency.isNotEmpty
              ? '$sign${widget.currency} $textVal'
              : '$sign$textVal',
          style: widget.style,
        );
      },
    );
  }
}

/// Dialog allowing the user or admin to toggle visible/hidden cards in the summary bar.
class _SummaryBarCustomizeDialog extends StatefulWidget {
  final List<SummaryCardData> allCards;
  final Set<String> initiallyHiddenIds;
  final ValueChanged<Set<String>> onSave;

  const _SummaryBarCustomizeDialog({
    required this.allCards,
    required this.initiallyHiddenIds,
    required this.onSave,
  });

  @override
  State<_SummaryBarCustomizeDialog> createState() => _SummaryBarCustomizeDialogState();
}

class _SummaryBarCustomizeDialogState extends State<_SummaryBarCustomizeDialog> {
  late Set<String> _hiddenIds;

  @override
  void initState() {
    super.initState();
    _hiddenIds = Set<String>.from(widget.initiallyHiddenIds);
  }

  void _toggle(String id, bool isVisible) {
    setState(() {
      if (isVisible) {
        _hiddenIds.remove(id);
      } else {
        _hiddenIds.add(id);
      }
    });
  }

  void _showAll() {
    setState(() => _hiddenIds.clear());
  }

  void _resetDefault() {
    setState(() => _hiddenIds.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF041936) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تخصيص شريط الملخصات',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'حدد الكروت المالية والتشغيلية التي ترغب في إظهارها',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Quick Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _showAll,
                    icon: const Icon(Icons.select_all_rounded, size: 16),
                    label: const Text('إظهار الكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _resetDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('الافتراضي', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Cards List
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.allCards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final card = widget.allCards[index];
                    final isVisible = !_hiddenIds.contains(card.id);

                    return InkWell(
                      onTap: () => _toggle(card.id, !isVisible),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isVisible,
                              activeColor: AppTheme.primary,
                              onChanged: (val) => _toggle(card.id, val ?? true),
                            ),
                            const SizedBox(width: 8),
                            Icon(card.icon, size: 18, color: AppTheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.title,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (card.tooltip != null)
                                    Text(
                                      card.tooltip!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Bottom Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () {
                      widget.onSave(_hiddenIds);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'حفظ التفضيلات',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper component for elegant Foreign Currency Pill display.
class ForeignCurrencyChip extends StatelessWidget {
  final String currency;
  final double amount;
  final double? exchangeRate;
  final double? egpEquivalent;

  const ForeignCurrencyChip({
    super.key,
    required this.currency,
    required this.amount,
    this.exchangeRate,
    this.egpEquivalent,
  });

  String _symbol(String cur) {
    switch (cur.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      default:
        return cur;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sym = _symbol(currency);
    final fmt = NumberFormat('#,##0.00');

    final tooltipText = egpEquivalent != null && egpEquivalent! > 0
        ? '$currency $sym ${fmt.format(amount)} ≈ EGP ${fmt.format(egpEquivalent)}${exchangeRate != null ? " (سعر الصرف: ${exchangeRate!.toStringAsFixed(2)})" : ""}'
        : 'إجمالي العملة الأجنبية: $currency $sym ${fmt.format(amount)}';

    return Tooltip(
      message: tooltipText,
      preferBelow: false,
      textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B) : const Color(0xFF312E81),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.20 : 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.45 : 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sym,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF818CF8),
              ),
            ),
            const SizedBox(width: 3),
            Text(
              '$currency ${fmt.format(amount)}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
