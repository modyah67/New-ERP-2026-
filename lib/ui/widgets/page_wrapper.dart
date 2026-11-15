// lib/ui/widgets/page_wrapper.dart
// ─────────────────────────────────────────────
// Premium dark glassmorphism page layout
// ─────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class PageWrapper extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> actions;
  final Widget child;

  const PageWrapper({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actions = const [],
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 850;

    return Stack(
      children: [
        Container(
          decoration: AppTheme.getBackgroundGradientFor(context),
        ),
        if (isDark)
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 12 : 24,
            isMobile ? 64 : 24,
            isMobile ? 12 : 24,
            isMobile ? 12 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 18,
                      vertical: isMobile ? 10 : 18,
                    ),
                    decoration: AppTheme.getGlassCardFor(context),
                    child: (isMobile && actions.isNotEmpty) || (actions.isNotEmpty && screenW < 1000)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  _buildIcon(isMobile),
                                  SizedBox(width: isMobile ? 10 : 16),
                                  Expanded(
                                    child: _buildTitle(context, isMobile),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                alignment: WrapAlignment.end,
                                children: actions,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              _buildIcon(isMobile),
                              SizedBox(width: isMobile ? 10 : 16),
                              Expanded(
                                child: _buildTitle(context, isMobile),
                              ),
                              if (actions.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: actions,
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 12 : 20),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIcon(bool isMobile) {
    return Container(
      width: isMobile ? 38 : 48,
      height: isMobile ? 38 : 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: isMobile ? 20 : 24),
    );
  }

  Widget _buildTitle(BuildContext context, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(
              fontSize: isMobile ? 17 : 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.getTextPrimary(context),
              fontFamily: 'Cairo',
            ),
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: isMobile ? 11 : 13,
              fontFamily: 'Cairo',
            ),
          ),
      ],
    );
  }
}
