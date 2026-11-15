import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SidebarNavItem {
  final IconData icon;
  final String label;
  final String? routePath;
  final bool adminOnly;
  final int? badgeCount;
  final Color? badgeColor;
  final List<SidebarNavItem>? children;

  const SidebarNavItem({
    required this.icon,
    required this.label,
    this.routePath,
    this.adminOnly = false,
    this.badgeCount,
    this.badgeColor,
    this.children,
  });
}

class ExpandableSidebar extends StatefulWidget {
  final List<SidebarNavItem> items;
  final String currentRoute;
  final bool collapsed;
  final bool isGlass;
  final bool isDrawer;
  final VoidCallback? onToggleCollapse;
  final Widget? headerLeading;
  final String? headerTitle;
  final String? headerSubtitle;
  final Widget? userSection;

  const ExpandableSidebar({
    super.key,
    required this.items,
    required this.currentRoute,
    this.collapsed = false,
    this.isGlass = false,
    this.isDrawer = false,
    this.onToggleCollapse,
    this.headerLeading,
    this.headerTitle,
    this.headerSubtitle,
    this.userSection,
  });

  @override
  State<ExpandableSidebar> createState() => _ExpandableSidebarState();
}

class _ExpandableSidebarState extends State<ExpandableSidebar> {
  static const _cyan = Color(0xFF3FD4E8);
  static const _glassBg = Color(0x0DFFFFFF);
  static const _glassBorder = Color(0x1AFFFFFF);

  final Set<String> _expandedGroups = {};

  void _toggleGroup(String label) {
    setState(() {
      if (_expandedGroups.contains(label)) {
        _expandedGroups.remove(label);
      } else {
        _expandedGroups.add(label);
      }
    });
  }

  void _openOverlay() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullScreenOverlay(
          items: widget.items,
          currentRoute: widget.currentRoute,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildSidebarPanel();
  }

  Widget _buildSidebarPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCollapsed = widget.collapsed;
    final w = isCollapsed ? 80.0 : 280.0;
    final glass = widget.isGlass;

    Widget panel = Container(
      decoration: BoxDecoration(
        color: glass
            ? (isDark ? _glassBg : Colors.white.withValues(alpha: 0.85))
            : (isDark ? const Color(0xFF041E42) : Colors.white),
        border: Border(
          left: BorderSide(
            color: isDark ? _glassBorder : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(isCollapsed),
          const SizedBox(height: 8),
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GestureDetector(
                onTap: _openOverlay,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _cyan.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _cyan.withAlpha(40), width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded,
                          color: _cyan.withAlpha(200), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'عرض الكل',
                        style: TextStyle(
                          color: _cyan.withAlpha(220),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.open_in_full,
                          color: _cyan.withAlpha(150), size: 14),
                    ],
                  ),
                ),
              ),
            ),
          if (!isCollapsed) const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: isCollapsed
                  ? const EdgeInsets.symmetric(horizontal: 8)
                  : const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.items.length,
              itemBuilder: (context, index) =>
                  _buildItem(widget.items[index], isCollapsed),
            ),
          ),
          if (widget.userSection != null) ...[
            Divider(
              color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFE2E8F0),
              height: 1,
            ),
            widget.userSection!,
          ],
        ],
      ),
    );

    if (glass) {
      panel = ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: panel,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: w,
      child: panel,
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required bool isDark,
    double size = 22,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          hoverColor: isDark
              ? Colors.white.withAlpha(20)
              : Colors.black.withAlpha(15),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withAlpha(15)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(35)
                    : const Color(0xFF0F172A),
                width: 1.5,
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withAlpha(15),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: isDark ? Colors.white : Colors.black,
                size: size,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCollapsed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.isDrawer) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Row(
          children: [
            widget.headerLeading ??
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _cyan.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cyan.withAlpha(40)),
                  ),
                  child: const Icon(Icons.spa, color: _cyan, size: 24),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.headerTitle != null)
                    _shadowText(
                      widget.headerTitle!,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  if (widget.headerSubtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.headerSubtitle!,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withAlpha(120)
                            : const Color(0xFF64748B),
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _buildToggleButton(
              icon: Icons.close_rounded,
              tooltip: 'إغلاق القائمة',
              onPressed: widget.onToggleCollapse ?? () => Navigator.of(context).pop(),
              isDark: isDark,
              size: 20,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: isCollapsed
          ? const EdgeInsets.fromLTRB(0, 20, 0, 12)
          : const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: isCollapsed
          ? Column(
              children: [
                widget.headerLeading ??
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _cyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cyan.withAlpha(40)),
                      ),
                      child: const Icon(Icons.spa, color: _cyan, size: 22),
                    ),
                const SizedBox(height: 12),
                _buildToggleButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'توسيع القائمة',
                  onPressed: widget.onToggleCollapse,
                  isDark: isDark,
                ),
              ],
            )
          : Row(
              children: [
                widget.headerLeading ??
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _cyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _cyan.withAlpha(40)),
                      ),
                      child: const Icon(Icons.spa, color: _cyan, size: 24),
                    ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.headerTitle != null)
                        _shadowText(
                          widget.headerTitle!,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      if (widget.headerSubtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.headerSubtitle!,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withAlpha(120)
                                : const Color(0xFF64748B),
                            fontSize: 11,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildToggleButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'طي القائمة',
                  onPressed: widget.onToggleCollapse,
                  isDark: isDark,
                ),
              ],
            ),
    );
  }

  Widget _buildItem(SidebarNavItem item, bool isCollapsed) {
    if (item.children != null && item.children!.isNotEmpty) {
      final isGroupExpanded = _expandedGroups.contains(item.label);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupTile(item, isCollapsed, isGroupExpanded),
          if (!isCollapsed && isGroupExpanded)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Column(
                children: item.children!
                    .map((child) => _buildNavTile(child, isCollapsed, isSubItem: true))
                    .toList(),
              ),
            ),
        ],
      );
    } else {
      return _buildNavTile(item, isCollapsed, isSubItem: false);
    }
  }

  Widget _buildGroupTile(SidebarNavItem item, bool isCollapsed, bool isExpanded) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? _cyan : const Color(0xFF0284C7);
    final iconWidget = Icon(item.icon, size: 22, color: activeColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: isCollapsed ? item.label : '',
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (isCollapsed) {
                widget.onToggleCollapse?.call();
                if (!isExpanded) {
                  _toggleGroup(item.label);
                }
              } else {
                _toggleGroup(item.label);
              }
            },
            hoverColor: isDark ? Colors.white.withAlpha(10) : const Color(0x0A0F172A),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isCollapsed ? 64 : null,
              padding: isCollapsed
                  ? const EdgeInsets.symmetric(vertical: 14)
                  : const EdgeInsets.fromLTRB(14, 13, 16, 13),
              decoration: BoxDecoration(
                color: isExpanded && !isCollapsed
                    ? (isDark ? Colors.white.withAlpha(8) : const Color(0x0A0F172A))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: isCollapsed
                  ? Center(child: iconWidget)
                  : Row(
                      children: [
                        iconWidget,
                        const SizedBox(width: 14),
                        Expanded(
                          child: _shadowText(
                            item.label,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          size: 18,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile(SidebarNavItem item, bool isCollapsed, {bool isSubItem = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = widget.currentRoute == item.routePath;
    final activeColor = isDark ? _cyan : const Color(0xFF0284C7);
    final iconWidget = Icon(item.icon, size: isSubItem ? 18 : 22, color: activeColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Tooltip(
        message: isCollapsed ? item.label : '',
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (widget.isDrawer || (Scaffold.maybeOf(context)?.isDrawerOpen ?? false)) {
                Navigator.of(context).pop();
              }
              if (item.routePath != null) {
                context.go(item.routePath!);
              }
            },
            hoverColor: isDark ? Colors.white.withAlpha(10) : const Color(0x0A0F172A),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isCollapsed ? 64 : null,
              padding: isCollapsed
                  ? const EdgeInsets.symmetric(vertical: 14)
                  : EdgeInsets.fromLTRB(14, isSubItem ? 10 : 13, 16, isSubItem ? 10 : 13),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? Colors.white.withAlpha(12) : const Color(0xFF0284C7).withValues(alpha: 0.10))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border(
                        right: BorderSide(color: activeColor, width: 3),
                      )
                    : null,
              ),
              child: isCollapsed
                  ? Center(child: iconWidget)
                  : Row(
                      children: [
                        iconWidget,
                        const SizedBox(width: 14),
                        Expanded(
                          child: _shadowText(
                            item.label,
                            fontSize: isSubItem ? 14 : 15,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),
                        if (item.badgeCount != null && item.badgeCount! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: (item.badgeColor ?? _cyan).withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.badgeCount}',
                              style: TextStyle(
                                color: item.badgeColor ?? _cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shadowText(
    String text, {
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF0F172A),
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: 'Cairo',
        shadows: isDark
            ? const [
                Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
              ]
            : null,
      ),
    );
  }
}

class _FullScreenOverlay extends StatelessWidget {
  final List<SidebarNavItem> items;
  final String currentRoute;

  static const _cyan = Color(0xFF3FD4E8);
  static const _glassBg = Color(0x0DFFFFFF);
  static const _glassBorder = Color(0x1AFFFFFF);
  static const _cardBorder = Color(0x26FFFFFF);
  static const _cardBg = Color(0x14FFFFFF);

  const _FullScreenOverlay({
    required this.items,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    final list = <SidebarNavItem>[];
    void flatten(List<SidebarNavItem> itemsList) {
      for (var item in itemsList) {
        if (item.children != null && item.children!.isNotEmpty) {
          flatten(item.children!);
        } else {
          list.add(item);
        }
      }
    }
    flatten(items);
    final flatItems = list;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Blur backdrop
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withAlpha(120)),
            ),
            // Grid content
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 48,
                  maxHeight: MediaQuery.of(context).size.height - 48,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _glassBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _glassBorder, width: 1),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _shadowText(
                                'القائمة الرئيسية',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              const Spacer(),
                              Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => Navigator.of(context).pop(),
                                  hoverColor: Colors.white.withAlpha(15),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(10),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: Colors.white.withAlpha(15)),
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white70, size: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth;
                                final cols = w > 1400
                                    ? 6
                                    : w > 1100
                                        ? 5
                                        : w > 900
                                            ? 4
                                            : w > 600
                                                ? 3
                                                : 2;

                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.1,
                                  ),
                                  itemCount: flatItems.length,
                                  itemBuilder: (context, index) {
                                    return _buildGridCard(
                                        context, flatItems[index]);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context, SidebarNavItem item) {
    final isSelected = currentRoute == item.routePath;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).pop();
          if (item.routePath != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                Navigator.of(context).pop();
              }
              context.go(item.routePath!);
            });
          }
        },
        hoverColor: Colors.white.withAlpha(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? _cyan.withAlpha(12) : _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _cyan.withAlpha(60) : _cardBorder,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _cyan.withAlpha(isSelected ? 25 : 12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _cyan.withAlpha(isSelected ? 40 : 20)),
                    ),
                    child: Icon(item.icon, color: _cyan, size: 24),
                  ),
                  if (item.badgeCount != null && item.badgeCount! > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: item.badgeColor ?? _cyan,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${item.badgeCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _shadowText(
                item.label,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _shadowText(
    String text, {
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w600,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: 'Cairo',
        shadows: const [
          Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}
