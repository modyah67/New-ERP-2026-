import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import 'supplier_statement_cubit.dart';
import 'supplier_statement_state.dart';
import 'supplier_statement_pdf_service.dart';
import '../../data/models/statement_row_model.dart';
import '../../data/models/supplier_model.dart';

class SupplierStatementPage extends StatefulWidget {
  final String? initialSupplierId;
  const SupplierStatementPage({super.key, this.initialSupplierId});

  @override
  State<SupplierStatementPage> createState() => _SupplierStatementPageState();
}

class _SupplierStatementPageState extends State<SupplierStatementPage> {
  String _selectedCategoryFilter = 'all';
  bool _filterInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialSupplierId != null) {
        context
            .read<SupplierStatementCubit>()
            .init(initialSupplierId: widget.initialSupplierId);
      } else {
        context.read<SupplierStatementCubit>().refreshSuppliers();
      }
    });
  }

  void _checkAutoSelectFilter(SupplierStatementLoaded state) {
    if (!_filterInitialized && state.selectedSupplier != null) {
      final s = state.selectedSupplier!;
      final code =
          int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final type = s.supplierType.toLowerCase().trim();
      if (type == 'station' || (code >= 85000 && code <= 89999)) {
        _selectedCategoryFilter = 'station';
      } else if (type == 'deduction' ||
          type == 'deductions' ||
          (code >= 40000 && code <= 49999)) {
        _selectedCategoryFilter = 'deduction';
      } else if (type == 'packaging' ||
          type == 'sticker' ||
          type.contains('تعبئ') ||
          type.contains('pack') ||
          (code >= 70000 && code <= 74999) ||
          (code >= 700 && code <= 749)) {
        _selectedCategoryFilter = 'packaging';
      } else if (type == 'transport' || (code >= 60000 && code <= 69999)) {
        _selectedCategoryFilter = 'transport';
      } else if (type == 'crop' || (code >= 50000 && code <= 59999)) {
        _selectedCategoryFilter = 'crop';
      }
      _filterInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupplierStatementCubit, SupplierStatementState>(
      builder: (context, state) {
        if (state is! SupplierStatementLoaded) return const SizedBox();
        _checkAutoSelectFilter(state);
        return Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, state),
                const SizedBox(height: 20),
                _buildFilterBar(context, state),
                const SizedBox(height: 16),
                Expanded(child: _buildContent(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<SupplierModel> _getFilteredSuppliers(List<SupplierModel> suppliers) {
    if (_selectedCategoryFilter == 'all') return suppliers;
    return suppliers.where((s) {
      final code = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final type = s.supplierType.toLowerCase().trim();
      if (_selectedCategoryFilter == 'station') {
        return type == 'station' || (code >= 85000 && code <= 89999);
      } else if (_selectedCategoryFilter == 'deduction') {
        return type == 'deduction' || type == 'deductions' || (code >= 40000 && code <= 49999);
      } else if (_selectedCategoryFilter == 'packaging') {
        return type == 'packaging' ||
            type == 'sticker' ||
            type.contains('تعبئ') ||
            type.contains('pack') ||
            s.categories.any((c) =>
                c.toLowerCase().contains('pack') || c.contains('تعبئ')) ||
            (code >= 70000 && code <= 74999) ||
            (code >= 700 && code <= 749);
      } else if (_selectedCategoryFilter == 'transport') {
        return type == 'transport' || (code >= 60000 && code <= 69999);
      } else if (_selectedCategoryFilter == 'crop') {
        return type == 'crop' || (code >= 50000 && code <= 59999);
      }
      return true;
    }).toList();
  }

  Widget _buildCategoryFilterChips(
      BuildContext context, SupplierStatementLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filters = [
      {'key': 'all', 'label': 'جميع الموردين', 'icon': Icons.groups_rounded, 'color': AppTheme.primary},
      {'key': 'station', 'label': 'موردي المحطات 🏭', 'icon': Icons.factory_rounded, 'color': const Color(0xFFF59E0B)},
      {'key': 'deduction', 'label': 'موردي التخصيمات 📋', 'icon': Icons.fact_check_rounded, 'color': const Color(0xFF8B5CF6)},
      {'key': 'packaging', 'label': 'موردي مواد التعبئة 📦', 'icon': Icons.inventory_2_rounded, 'color': const Color(0xFFEC4899)},
      {'key': 'transport', 'label': 'موردي النقل 🚛', 'icon': Icons.local_shipping_rounded, 'color': const Color(0xFF06B6D4)},
      {'key': 'crop', 'label': 'موردي المحاصيل 🌾', 'icon': Icons.agriculture_rounded, 'color': const Color(0xFF10B981)},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final key = f['key'] as String;
          final label = f['label'] as String;
          final color = f['color'] as Color;
          final isSelected = _selectedCategoryFilter == key;

          return Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: FilterChip(
              selected: isSelected,
              showCheckmark: false,
              avatar: isSelected ? null : Icon(f['icon'] as IconData, size: 16, color: isDark ? Colors.white70 : color),
              label: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              selectedColor: color,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
              side: BorderSide(
                color: isSelected ? color : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                width: isSelected ? 1.5 : 1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (selected) {
                setState(() {
                  _selectedCategoryFilter = key;
                  if (state.selectedSupplier != null && key != 'all') {
                    final filtered = _getFilteredSuppliers(state.suppliers);
                    if (!filtered.any((s) => s.id == state.selectedSupplier!.id)) {
                      context.read<SupplierStatementCubit>().selectSupplier(null);
                    }
                  }
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SupplierStatementLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_shipping_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('كشف حساب مورد',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                fontFamily: 'Cairo')),
                        Text('اختر مورداً وفترة زمنية لعرض الحركات',
                            style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    tooltip: 'إعادة تعيين',
                    onPressed: () =>
                        context.read<SupplierStatementCubit>().reset(),
                  ),
                ],
              ),
              if (state.statementRows.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon:
                            const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('طباعة'),
                        onPressed: () => _printStatement(context, state),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('حفظ PDF'),
                        onPressed: () => _savePdf(context, state),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_shipping_outlined,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كشف حساب مورد',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo')),
                Text('اختر مورداً وفترة زمنية لعرض الحركات',
                    style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 13)),
              ],
            ),
            const Spacer(),
            if (state.statementRows.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('طباعة'),
                    onPressed: () => _printStatement(context, state),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('حفظ PDF'),
                    onPressed: () => _savePdf(context, state),
                  ),
                ],
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'إعادة تعيين',
              onPressed: () => context.read<SupplierStatementCubit>().reset(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(BuildContext context, SupplierStatementLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Category Filter Chips (e.g. موردي المحطات 🏭)
                _buildCategoryFilterChips(context, state),
                const SizedBox(height: 14),

                // 2. Search Autocomplete + Dates + Submit
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 700;
                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSupplierAutocomplete(context, state, double.infinity, isDark),
                          const SizedBox(height: 12),
                          _buildDateColumn(
                              context,
                              'من تاريخ',
                              state.fromDate,
                              () => context.read<SupplierStatementCubit>().pickFromDate(context),
                              double.infinity,
                              isDark),
                          const SizedBox(height: 12),
                          _buildDateColumn(
                              context,
                              'إلى تاريخ',
                              state.toDate,
                              () => context.read<SupplierStatementCubit>().pickToDate(context),
                              double.infinity,
                              isDark),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('عرض الكشف',
                                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => context.read<SupplierStatementCubit>().loadStatement(),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            flex: 3,
                            child: _buildSupplierAutocomplete(context, state, 0, isDark)),
                        const SizedBox(width: 16),
                        Expanded(
                            flex: 2,
                            child: _buildDateColumn(
                                context,
                                'من تاريخ',
                                state.fromDate,
                                () => context.read<SupplierStatementCubit>().pickFromDate(context),
                                0,
                                isDark)),
                        const SizedBox(width: 16),
                        Expanded(
                            flex: 2,
                            child: _buildDateColumn(
                                context,
                                'إلى تاريخ',
                                state.toDate,
                                () => context.read<SupplierStatementCubit>().pickToDate(context),
                                0,
                                isDark)),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('عرض الكشف',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => context.read<SupplierStatementCubit>().loadStatement(),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierAutocomplete(
      BuildContext context, SupplierStatementLoaded state, double width, bool isDark) {
    final filteredSuppliers = _getFilteredSuppliers(state.suppliers);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('المورد',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, constraints) {
          return Autocomplete<SupplierModel>(
            key: ValueKey('autocomplete_$_selectedCategoryFilter'),
            displayStringForOption: (s) => '${s.supplierCode} - ${s.name}',
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return filteredSuppliers;
              final q = textEditingValue.text.toLowerCase();
              return filteredSuppliers.where((s) =>
                  s.name.toLowerCase().contains(q) ||
                  s.supplierCode.toLowerCase().contains(q));
            },
            onSelected: (s) =>
                context.read<SupplierStatementCubit>().selectSupplier(s),
            fieldViewBuilder:
                (context, textEditingController, focusNode, onFieldSubmitted) {
              textEditingController.addListener(() {
                if (textEditingController.text.isEmpty) {
                  context.read<SupplierStatementCubit>().selectSupplier(null);
                }
              });
              if (state.selectedSupplier != null &&
                  textEditingController.text.isEmpty) {
                textEditingController.text =
                    '${state.selectedSupplier!.supplierCode} - ${state.selectedSupplier!.name}';
              }
              final hintText = _selectedCategoryFilter == 'station'
                  ? 'ابحث في موردي المحطات (85xxx)...'
                  : _selectedCategoryFilter == 'packaging'
                      ? 'ابحث في موردي مواد التعبئة (70xxx)...'
                      : _selectedCategoryFilter == 'deduction'
                          ? 'ابحث في موردي التخصيمات (40xxx)...'
                          : _selectedCategoryFilter == 'transport'
                              ? 'ابحث في موردي النقل (60xxx)...'
                              : _selectedCategoryFilter == 'crop'
                                  ? 'ابحث في موردي المحاصيل (50xxx)...'
                                  : 'ابحث بالكود أو الاسم...';
              final icon = _selectedCategoryFilter == 'station'
                  ? Icons.factory_rounded
                  : _selectedCategoryFilter == 'packaging'
                      ? Icons.inventory_2_rounded
                      : _selectedCategoryFilter == 'deduction'
                          ? Icons.fact_check_rounded
                          : _selectedCategoryFilter == 'transport'
                              ? Icons.local_shipping_rounded
                              : _selectedCategoryFilter == 'crop'
                                  ? Icons.agriculture_rounded
                                  : Icons.local_shipping_outlined;
              return TextFormField(
                controller: textEditingController,
                focusNode: focusNode,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
                onFieldSubmitted: (String value) {
                  onFieldSubmitted();
                },
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    icon,
                    size: 18,
                    color: isDark ? AppTheme.accent : const Color(0xFF0F172A),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: isDark ? AppTheme.glassBorder : const Color(0xFF94A3B8),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: state.selectedSupplier != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            textEditingController.clear();
                            context
                                .read<SupplierStatementCubit>()
                                .selectSupplier(null);
                          },
                        )
                      : const Icon(Icons.arrow_drop_down),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                      ),
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        final codeNum = int.tryParse(option.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                        final isStation = option.supplierType == 'station' || (codeNum >= 85000 && codeNum <= 89999);
                        final isDeduction = option.supplierType == 'deduction' || option.supplierType == 'deductions' || (codeNum >= 40000 && codeNum <= 49999);
                        final isPackaging = option.supplierType == 'packaging' ||
                            option.supplierType == 'sticker' ||
                            option.supplierType.toLowerCase().contains('تعبئ') ||
                            option.supplierType.toLowerCase().contains('pack') ||
                            option.categories.any((c) =>
                                c.toLowerCase().contains('pack') || c.contains('تعبئ')) ||
                            (codeNum >= 70000 && codeNum <= 74999) ||
                            (codeNum >= 700 && codeNum <= 749);
                        final isTransport = option.supplierType == 'transport' || (codeNum >= 60000 && codeNum <= 69999);
                        final isCrop = option.supplierType == 'crop' || (codeNum >= 50000 && codeNum <= 59999);

                        final typeLabel = isStation
                            ? 'مورد محطة 🏭'
                            : isDeduction
                                ? 'مورد تخصيمات 📋'
                                : isPackaging
                                    ? 'مورد مواد تعبئة 📦'
                                    : isTransport
                                        ? 'مورد نقل 🚛'
                                        : isCrop
                                            ? 'مورد محاصيل 🌾'
                                            : 'مورد عام';
                        final badgeColor = isStation
                            ? const Color(0xFFF59E0B)
                            : isDeduction
                                ? const Color(0xFF8B5CF6)
                                : isPackaging
                                    ? const Color(0xFFEC4899)
                                    : isTransport
                                        ? const Color(0xFF06B6D4)
                                        : isCrop
                                            ? const Color(0xFF10B981)
                                            : AppTheme.primary;

                        return Builder(builder: (context) {
                          final bool isHighlighted =
                              AutocompleteHighlightedOption.of(context) == index;
                          return Material(
                            color: isHighlighted
                                ? (isDark ? Colors.white12 : const Color(0xFFF1F5F9))
                                : Colors.transparent,
                            child: ListTile(
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isStation
                                      ? Icons.factory_rounded
                                      : isDeduction
                                          ? Icons.fact_check_rounded
                                          : isPackaging
                                              ? Icons.inventory_2_rounded
                                              : isTransport
                                                  ? Icons.local_shipping_rounded
                                                  : isCrop
                                                      ? Icons.agriculture_rounded
                                                      : Icons.local_shipping_outlined,
                                  size: 18,
                                  color: badgeColor,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      option.name,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      typeLabel,
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'كود: ${option.supplierCode}',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              onTap: () => onSelected(option),
                            ),
                          );
                        });
                      },
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }

  Widget _buildDateColumn(BuildContext context, String label, DateTime? value,
      VoidCallback onTap, double width, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        _datePicker(value: value, hint: 'اختر التاريخ', onTap: onTap, isDark: isDark),
      ],
    );
  }

  Widget _datePicker(
      {required DateTime? value,
      required String hint,
      required VoidCallback onTap,
      required bool isDark}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8), width: 1.2),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: isDark ? Colors.white70 : Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? AppUtils.formatDate(value) : hint,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, SupplierStatementLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (state.selectedSupplier == null) {
      return _buildPlaceholder(
        icon: Icons.local_shipping_outlined,
        title: 'اختر مورداً',
        subtitle: 'اختر المورد وحدد الفترة الزمنية ثم اضغط "عرض الكشف"',
        isDark: isDark,
      );
    }
    if (state.statementRows.isEmpty) {
      return _buildPlaceholder(
        icon: Icons.receipt_long_outlined,
        title: 'لا توجد حركات',
        subtitle: 'لا توجد معاملات في الفترة المحددة',
        isDark: isDark,
      );
    }
    return Column(
      children: [
        _buildSummaryCards(state, isDark),
        const SizedBox(height: 16),
        Expanded(child: _buildTable(state, isDark)),
      ],
    );
  }

  Widget _buildSummaryCards(SupplierStatementLoaded state, bool isDark) {
    final balance = state.finalBalance;
    final balColor = balance < 0
        ? (isDark ? AppTheme.danger : const Color(0xFFDC2626))
        : (isDark ? AppTheme.success : const Color(0xFF16A34A));
    final currency = state.selectedSupplier?.currency ?? 'EGP';
    final cards = [
      _summaryCard(
          label: 'إجمالي عليه',
          value: AppUtils.formatCurrency(state.totalDebit, currency),
          color: isDark ? AppTheme.success : const Color(0xFF047857),
          icon: Icons.arrow_downward,
          isDark: isDark),
      _summaryCard(
          label: 'إجمالي له',
          value: AppUtils.formatCurrency(state.totalCredit, currency),
          color: isDark ? AppTheme.danger : const Color(0xFFB91C1C),
          icon: Icons.arrow_upward,
          isDark: isDark),
      _summaryCard(
        label: balance > 0
            ? 'الرصيد النهائي (له)'
            : balance < 0
                ? 'الرصيد النهائي (عليه)'
                : 'الرصيد النهائي (متوازن)',
        value: AppUtils.formatCurrency(balance.abs(), currency),
        color: balColor,
        icon: Icons.account_balance_outlined,
        isBold: true,
        isDark: isDark,
      ),
      _summaryCard(
          label: 'عدد الحركات',
          value: state.statementRows.length.toString(),
          color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
          icon: Icons.format_list_numbered,
          isDark: isDark),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map((c) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: c,
                    ))
                .toList(),
          );
        }
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard(
      {required String label,
      required String value,
      required Color color,
      required IconData icon,
      required bool isDark,
      bool isBold = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 13.5)),
                      const SizedBox(height: 4),
                      Text(value,
                          style: TextStyle(
                              fontSize: isBold ? 16 : 14.5,
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontFamily: 'Cairo')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const double _colRef = 160;
  static const double _colDate = 130;
  static const double _colAccount = 150;
  static const double _colDesc = 280;
  static const double _colQty = 50;
  static const double _colVolume = 70;
  static const double _colPrice = 80;
  static const double _colForeign = 150;
  static const double _colDebit = 100;
  static const double _colCredit = 100;
  static const double _colBalance = 110;
  static const double _colHPad = 24;
  static const double _tableWidth = _colRef +
      _colDate +
      _colAccount +
      _colDesc +
      _colQty +
      _colVolume +
      _colPrice +
      _colForeign +
      _colDebit +
      _colCredit +
      _colBalance +
      _colHPad;

  Widget _buildTable(SupplierStatementLoaded state, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final minWidth = constraints.maxWidth > _tableWidth
                        ? constraints.maxWidth
                        : _tableWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: minWidth,
                        child: Column(
                          children: [
                            _buildTableHeader(isDark),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView.separated(
                                itemCount: state.statementRows.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (context, index) => _buildTableRow(
                                    state.statementRows[index],
                                    index,
                                    state.selectedSupplier?.currency ?? 'EGP',
                                    isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    final headerStyle = TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo',
        fontSize: 13.5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
      child: Row(
        children: [
          SizedBox(
              width: _colRef,
              child: Text('رقم الفاتورة أو المعاملة', style: headerStyle)),
          SizedBox(
              width: _colDate,
              child: Text('التاريخ', style: headerStyle)),
          SizedBox(
              width: _colAccount,
              child: Text('اسم الحساب', style: headerStyle)),
          Expanded(
              flex: _colDesc.toInt(),
              child: Text('البيان', style: headerStyle, overflow: TextOverflow.ellipsis)),
          SizedBox(
              width: _colQty,
              child: Text('العدد', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colVolume,
              child: Text('الكمية', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colPrice,
              child: Text('السعر', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colForeign,
              child: Text('المبلغ بالعملة الأجنبية', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colDebit,
              child: Text('منه (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colCredit,
              child: Text('له (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: _colBalance,
              child: Text('الرصيد (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(StatementRow row, int index, String currency, bool isDark) {
    final isEven = index % 2 == 0;
    final balColor = row.balance < 0
        ? (isDark ? AppTheme.danger : const Color(0xFFDC2626))
        : (isDark ? AppTheme.success : const Color(0xFF16A34A));

    return Container(
      color: isDark
          ? (isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05))
          : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
              width: _colRef,
              child: Text(row.transactionNumber,
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          SizedBox(
              width: _colDate,
              child: Text(AppUtils.formatDate(AppUtils.parseDate(row.date)),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13.5))),
          SizedBox(
              width: _colAccount,
              child: Text(row.accountName,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13.5),
                  overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: _colDesc.toInt(),
              child: Tooltip(
                message: row.description,
                waitDuration: const Duration(milliseconds: 350),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    row.description,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      height: 1.35,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 4,
                    softWrap: true,
                  ),
                ),
              )),
          SizedBox(
            width: _colQty,
            child: Text(
                row.piecesCount > 0
                    ? AppUtils.formatNumber(row.piecesCount)
                    : '—',
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colVolume,
            child: Text(
                row.quantity > 0 ? AppUtils.formatNumber(row.quantity) : '—',
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colPrice,
            child: Text(
                row.unitPrice > 0
                    ? AppUtils.formatCurrency(row.unitPrice, currency)
                    : '—',
                style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colForeign,
            child: Text(
              row.isForeignCurrency ? row.foreignDisplay : '—',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: _colDebit,
            child: Text(
                row.debit > 0
                    ? AppUtils.formatCurrency(row.debit, 'EGP')
                    : '—',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: row.debit > 0
                        ? (isDark ? AppTheme.success : const Color(0xFF047857))
                        : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colCredit,
            child: Text(
                row.credit > 0
                    ? AppUtils.formatCurrency(row.credit, 'EGP')
                    : '—',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: row.credit > 0
                        ? (isDark ? AppTheme.danger : const Color(0xFFB91C1C))
                        : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ),
          SizedBox(
            width: _colBalance,
            child: Column(
              children: [
                Text(AppUtils.formatCurrency(row.balance, 'EGP'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: balColor,
                        fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
                Text(
                    row.balance > 0
                        ? 'له'
                        : row.balance < 0
                            ? 'عليه'
                            : 'متوازن',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: balColor,
                        fontFamily: 'Cairo'),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(
      {required IconData icon,
      required String title,
      required String subtitle,
      required bool isDark}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 72, color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.3) : const Color(0xFF94A3B8)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _printStatement(
      BuildContext context, SupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await SupplierStatementPdfService.generateAndPrint(
        supplier: supplier,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل إنشاء PDF: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _savePdf(
      BuildContext context, SupplierStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    try {
      await SupplierStatementPdfService.saveToFile(
        context,
        supplier: supplier,
        rows: state.statementRows,
        totalDebit: state.totalDebit,
        totalCredit: state.totalCredit,
        finalBalance: state.finalBalance,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل حفظ الملف: $e'),
            backgroundColor: AppTheme.danger),
      );
    }
  }
}
