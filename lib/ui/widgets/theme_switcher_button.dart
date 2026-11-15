// lib/ui/widgets/theme_switcher_button.dart
// ─────────────────────────────────────────────
// Interactive Theme Switcher Button (Dark / Light)
// with micro-animations, glowing accents, and tooltips.
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme_cubit.dart';

class ThemeSwitcherButton extends StatelessWidget {
  final bool showLabel;
  final bool isCompact;

  const ThemeSwitcherButton({
    super.key,
    this.showLabel = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeMode>(
      builder: (context, themeMode) {
        final isDark = themeMode == ThemeMode.dark;
        final tooltipMsg = isDark ? 'التبديل إلى الوضع النهاري' : 'التبديل إلى الوضع الليلي';

        return Tooltip(
          message: tooltipMsg,
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                context.read<ThemeCubit>().toggleTheme();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: EdgeInsets.symmetric(
                  horizontal: showLabel ? 12 : 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x1AFFFFFF)
                      : const Color(0x0F0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                  boxShadow: [
                    if (isDark)
                      BoxShadow(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      )
                    else
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.10),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) {
                        return RotationTransition(
                          turns: anim,
                          child: ScaleTransition(scale: anim, child: child),
                        );
                      },
                      child: isDark
                          ? const Icon(
                              Icons.wb_sunny_rounded,
                              key: ValueKey('sun_icon'),
                              color: Color(0xFFFBBF24),
                              size: 20,
                            )
                          : const Icon(
                              Icons.dark_mode_rounded,
                              key: ValueKey('moon_icon'),
                              color: Color(0xFF0284C7),
                              size: 20,
                            ),
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      Text(
                        isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
