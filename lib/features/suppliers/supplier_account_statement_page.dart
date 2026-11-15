import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/language_dialog.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/statement_pdf_service.dart';
import '../../core/statement_excel_service.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/statement_row_model.dart';
import 'supplier_account_statement_cubit.dart';
import 'supplier_account_statement_state.dart';

class SupplierAccountStatementPage extends StatefulWidget {
  final String? initialSupplierId;
  const SupplierAccountStatementPage({super.key, this.initialSupplierId});

  @override
  State<SupplierAccountStatementPage> createState() =>
      _SupplierAccountStatementPageState();
}

class _SupplierAccountStatementPageState
    extends State<SupplierAccountStatementPage> {
  String _selectedCategoryFilter = 'all';
  bool _filterInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSupplierId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context
            .read<SupplierAccountStatementCubit>()
            .init(initialSupplierId: widget.initialSupplierId);
      });
    }
  }

  void _checkAutoSelectFilter(SupplierAccountStatementLoaded state) {
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

  List<SupplierModel> _getFilteredSuppliers(List<SupplierModel> suppliers) {
    if (_selectedCategoryFilter == 'all') return suppliers;
    return suppliers.where((s) {
      final code =
          int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final type = s.supplierType.toLowerCase().trim();
      if (_selectedCategoryFilter == 'station') {
        return type == 'station' || (code >= 85000 && code <= 89999);
      } else if (_selectedCategoryFilter == 'deduction') {
        return type == 'deduction' ||
            type == 'deductions' ||
            (code >= 40000 && code <= 49999);
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
      BuildContext context, SupplierAccountStatementLoaded state) {
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
                      : (isDark ? Colors.white70 : Colors.black),
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
                      context.read<SupplierAccountStatementCubit>().selectSupplier(null);
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

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SupplierAccountStatementCubit,
        SupplierAccountStatementState>(
      builder: (context, state) {
        if (state is SupplierAccountStatementError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppTheme.danger),
                const SizedBox(height: 16),
                Text(state.message,
                    style: const TextStyle(
                        color: AppTheme.danger,
                        fontFamily: 'Cairo',
                        fontSize: 14),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      context.read<SupplierAccountStatementCubit>().init(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }
        if (state is! SupplierAccountStatementLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        _checkAutoSelectFilter(state);
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 700;
              final content = Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, state),
                    const SizedBox(height: 16),
                    _buildFilterBar(context, state),
                    const SizedBox(height: 16),
                    if (isMobile)
                      _buildContent(context, state)
                    else
                      Expanded(child: _buildContent(context, state)),
                  ],
                ),
              );
              if (isMobile) {
                return SingleChildScrollView(
                    child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: content,
                ));
              }
              return content;
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, SupplierAccountStatementLoaded state) {
    final hasData =
        state.selectedSupplier != null && state.statementRows.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: isDark ? AppTheme.textPrimary : Colors.black,
      fontFamily: 'Cairo',
    );

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
                    child: const Icon(Icons.receipt_long_outlined,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('كشف حساب الموردين',
                        style: titleStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    tooltip: 'إعادة تعيين',
                    onPressed: () =>
                        context.read<SupplierAccountStatementCubit>().reset(),
                  ),
                ],
              ),
              if (hasData) ...[
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
                      OutlinedButton.icon(
                        icon: const Icon(Icons.table_chart_outlined, size: 18),
                        label: const Text('حفظ Excel'),
                        onPressed: () => _saveExcel(context, state),
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
              child: const Icon(Icons.receipt_long_outlined,
                  color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Text('كشف حساب الموردين', style: titleStyle),
            const Spacer(),
            if (hasData) ...[
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('حفظ Excel'),
                onPressed: () => _saveExcel(context, state),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'إعادة تعيين',
              onPressed: () =>
                  context.read<SupplierAccountStatementCubit>().reset(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(
      BuildContext context, SupplierAccountStatementLoaded state) {
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
                _buildCategoryFilterChips(context, state),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 700;
                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSupplierAutocomplete(
                              context, state, double.infinity),
                          const SizedBox(height: 12),
                          _buildCurrencyFilter(context, state),
                          const SizedBox(height: 12),
                          _buildDateColumn(
                              context,
                              'من تاريخ',
                              state.fromDate,
                              () => context
                                  .read<SupplierAccountStatementCubit>()
                                  .pickFromDate(context),
                              double.infinity),
                          const SizedBox(height: 12),
                          _buildDateColumn(
                              context,
                              'إلى تاريخ',
                              state.toDate,
                              () => context
                                  .read<SupplierAccountStatementCubit>()
                                  .pickToDate(context),
                              double.infinity),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('عرض الكشف',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => context
                                  .read<SupplierAccountStatementCubit>()
                                  .loadStatement(),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child:
                                _buildSupplierAutocomplete(context, state, 0)),
                        const SizedBox(width: 12),
                        Expanded(
                            flex: 2,
                            child: _buildCurrencyFilter(context, state)),
                        const SizedBox(width: 12),
                        Expanded(
                            flex: 2,
                            child: _buildDateColumn(
                                context,
                                'من تاريخ',
                                state.fromDate,
                                () => context
                                    .read<SupplierAccountStatementCubit>()
                                    .pickFromDate(context),
                                0)),
                        const SizedBox(width: 12),
                        Expanded(
                            flex: 2,
                            child: _buildDateColumn(
                                context,
                                'إلى تاريخ',
                                state.toDate,
                                () => context
                                    .read<SupplierAccountStatementCubit>()
                                    .pickToDate(context),
                                0)),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.search, size: 18),
                            label: const Text('عرض الكشف',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => context
                                .read<SupplierAccountStatementCubit>()
                                .loadStatement(),
                          ),
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

  Widget _buildSupplierAutocomplete(BuildContext context,
      SupplierAccountStatementLoaded state, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('المورد',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return Autocomplete<SupplierModel>(
              key: ValueKey('autocomplete_$_selectedCategoryFilter'),
              displayStringForOption: (s) => '${s.supplierCode} - ${s.name}',
              optionsBuilder: (textEditingValue) {
                final filtered = _getFilteredSuppliers(state.suppliers);
                if (textEditingValue.text.isEmpty) return filtered;
                final q = textEditingValue.text.toLowerCase();
                return filtered.where((s) =>
                    s.name.toLowerCase().contains(q) ||
                    s.supplierCode.toLowerCase().contains(q));
              },
              onSelected: (s) => context
                  .read<SupplierAccountStatementCubit>()
                  .selectSupplier(s),
              fieldViewBuilder: (context, textEditingController, focusNode,
                  onFieldSubmitted) {
                textEditingController.addListener(() {
                  if (textEditingController.text.isEmpty) {
                    context
                        .read<SupplierAccountStatementCubit>()
                        .selectSupplier(null);
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
                                    : Icons.business_outlined;
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 14,
                  ),
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                        icon,
                        size: 18,
                        color: isDark ? AppTheme.textSecondary : Colors.black),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: state.selectedSupplier != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              textEditingController.clear();
                              context
                                  .read<SupplierAccountStatementCubit>()
                                  .selectSupplier(null);
                            },
                          )
                        : Icon(Icons.arrow_drop_down,
                            color: isDark ? AppTheme.textSecondary : Colors.black),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final optionsList = options.toList();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    color: isDark ? const Color(0xFF0A1E38) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: constraints.maxWidth,
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0A1E38) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : const Color(0xFFCBD5E1)),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: optionsList.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? Colors.white10
                              : const Color(0xFFF1F5F9),
                        ),
                        itemBuilder: (context, index) {
                          final option = optionsList[index];
                          final codeNum = int.tryParse(option.supplierCode
                                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0;
                          final isStation = option.supplierType == 'station' ||
                              (codeNum >= 85000 && codeNum <= 89999);
                          final isDeduction = option.supplierType ==
                                  'deduction' ||
                              option.supplierType == 'deductions' ||
                              (codeNum >= 40000 && codeNum <= 49999);
                          final isPackaging = option.supplierType ==
                                  'packaging' ||
                              option.supplierType == 'sticker' ||
                              option.supplierType.toLowerCase().contains('تعبئ') ||
                              option.supplierType.toLowerCase().contains('pack') ||
                              option.categories.any((c) =>
                                  c.toLowerCase().contains('pack') || c.contains('تعبئ')) ||
                              (codeNum >= 70000 && codeNum <= 74999) ||
                              (codeNum >= 700 && codeNum <= 749);
                          final isTransport = option.supplierType == 'transport' ||
                              (codeNum >= 60000 && codeNum <= 69999);
                          final isCrop = option.supplierType == 'crop' ||
                              (codeNum >= 50000 && codeNum <= 59999);

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

                          return ListTile(
                            leading: Container(
                              width: 32,
                              height: 32,
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
                                                    : Icons.business_outlined,
                                size: 16,
                                color: badgeColor,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option.name,
                                    style: TextStyle(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
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
                                      fontSize: 10,
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
                                fontSize: 12.5,
                              ),
                            ),
                            dense: true,
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCurrencyFilter(
      BuildContext context, SupplierAccountStatementLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCurrency = state.selectedCurrency ?? 'ALL';
    final items = state.availableCurrencies.isNotEmpty
        ? state.availableCurrencies
        : const ['ALL', 'EGP'];
    final effectiveValue =
        items.contains(currentCurrency) ? currentCurrency : items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('عملة الكشف',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? const Color(0xFFBDBDBD) : const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(8),
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: effectiveValue,
              isExpanded: true,
              dropdownColor: isDark ? AppTheme.surface : Colors.white,
              icon: Icon(Icons.keyboard_arrow_down,
                  color: isDark ? AppTheme.textSecondary : Colors.black, size: 20),
              items: items.map((cur) {
                return DropdownMenuItem<String>(
                  value: cur,
                  child: Row(
                    children: [
                      Icon(
                        cur == 'ALL'
                            ? Icons.all_inclusive
                            : Icons.monetization_on_outlined,
                        size: 16,
                        color:
                            cur == 'ALL' ? AppTheme.info : (isDark ? AppTheme.warning : const Color(0xFFD97706)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getCurrencyFilterLabel(cur),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newCur) {
                if (newCur != null) {
                  context
                      .read<SupplierAccountStatementCubit>()
                      .selectCurrency(newCur);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  String _getCurrencyFilterLabel(String code) {
    switch (code) {
      case 'ALL':
        return 'الكل (جميع العملات)';
      case 'EGP':
        return 'جنيه مصري (EGP - ج.م)';
      case 'USD':
        return 'دولار أمريكي (USD - \$)';
      case 'EUR':
        return 'يورو (EUR - €)';
      case 'GBP':
        return 'جنيه إسترليني (GBP - £)';
      case 'SAR':
        return 'ريال سعودي (SAR - ر.س)';
      case 'AED':
        return 'درهم إماراتي (AED - د.إ)';
      case 'KWD':
        return 'دينار كويتي (KWD - د.ك)';
      case 'QAR':
        return 'ريال قطري (QAR - ر.ق)';
      case 'TRY':
        return 'ليرة تركية (TRY - ₺)';
      case 'CNY':
        return 'يوان صيني (CNY - ¥)';
      default:
        final sym = SupplierModel.getCurrencySymbol(code);
        return '$code ($sym)';
    }
  }

  Widget _buildDateColumn(BuildContext context, String label, DateTime? value,
      VoidCallback onTap, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 14)),
        const SizedBox(height: 6),
        _buildDateField(
            context: context, value: value, hint: label, onTap: onTap),
      ],
    );
  }

  Widget _buildDateField(
      {required BuildContext context,
      required DateTime? value,
      required String hint,
      required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? const Color(0xFFBDBDBD) : const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: isDark ? AppTheme.textSecondary : Colors.black),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? AppUtils.formatDate(value) : hint,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: value != null
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, SupplierAccountStatementLoaded state) {
    if (state.selectedSupplier == null) {
      return _buildPlaceholder(
          icon: Icons.business_outlined,
          title: 'اختر مورداً',
          subtitle: 'اختر المورد وحدد الفترة الزمنية ثم اضغط "عرض الكشف"');
    }
    if (state.statementRows.isEmpty) {
      return _buildPlaceholder(
          icon: Icons.receipt_long_outlined,
          title: 'لا توجد حركات',
          subtitle: 'لا توجد معاملات في الفترة المحددة');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isScrollable =
            !constraints.hasBoundedHeight || constraints.maxHeight > 800;
        final tableWidget = _buildTable(state);
        return Column(
          mainAxisSize: isScrollable ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _buildSummaryCards(state),
            const SizedBox(height: 16),
            if (state.fromDate != null && (state.openingBalance != 0 || (state.selectedCurrency != 'ALL' && (state.openingBalancesByCurrency[state.selectedCurrency] ?? 0) != 0)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(
                  builder: (ctx) {
                    final isFiltered = state.selectedCurrency != null && state.selectedCurrency != 'ALL';
                    final cur = state.selectedCurrency ?? 'ALL';
                    final opBal = isFiltered ? (state.openingBalancesByCurrency[cur] ?? 0.0) : state.openingBalance;
                    final isNeg = opBal < 0;
                    final noteColor = isNeg ? AppTheme.danger : AppTheme.info;
                    final supplier = state.selectedSupplier;
                    final hasMulti = supplier != null && supplier.hasMultiCurrencyInitialBalance;
                    final absVal = AppUtils.formatNumber(opBal.abs());
                    final currSym = (supplier?.currency == 'MULTI')
                        ? 'ج.م'
                        : SupplierModel.getCurrencySymbol(supplier?.currency ?? 'EGP');
                    final balDisplay = state.formattedOpeningBalances.isNotEmpty
                        ? state.formattedOpeningBalances
                        : (hasMulti ? supplier.formattedInitialBalance : '$absVal $currSym');
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: noteColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: noteColor.withAlpha(60)),
                      ),
                      child: RichText(
                        textDirection: TextDirection.rtl,
                        text: TextSpan(
                          style: TextStyle(
                              color: noteColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'Cairo'),
                          children: [
                            const TextSpan(text: 'ملحوظة: الرصيد السابق = '),
                            if (isNeg && !hasMulti && !isFiltered)
                              const TextSpan(
                                  text: '- ',
                                  style: TextStyle(fontSize: 18)),
                            TextSpan(text: balDisplay),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (isScrollable)
              SizedBox(height: 400, child: tableWidget)
            else
              Expanded(child: tableWidget),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(SupplierAccountStatementLoaded state) {
    final isFiltered = state.selectedCurrency != null && state.selectedCurrency != 'ALL';
    final cur = state.selectedCurrency ?? 'ALL';

    final balance = state.finalBalance;
    final balColor = balance > 0
        ? AppTheme.success
        : balance < 0
            ? AppTheme.danger
            : AppTheme.textSecondary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final supplier = state.selectedSupplier;
        final hasMulti = state.finalBalancesByCurrency.length > 1 || (supplier != null && supplier.supportsMultiCurrency);

        final String debitVal;
        final String? debitSub;
        final String creditVal;
        final String? creditSub;
        final String finalVal;
        final String? finalSub;

        if (isFiltered) {
          final nativeDebit = state.totalDebitsByCurrency[cur] ?? 0.0;
          final nativeCredit = state.totalCreditsByCurrency[cur] ?? 0.0;
          final nativeFinal = state.finalBalancesByCurrency[cur] ?? 0.0;

          debitVal = _formatCurrency(nativeDebit, currency: cur);
          debitSub = cur != 'EGP' ? 'ما يعادل: ${_formatCurrency(state.totalDebit, currency: 'EGP')}' : null;

          creditVal = _formatCurrency(nativeCredit, currency: cur);
          creditSub = cur != 'EGP' ? 'ما يعادل: ${_formatCurrency(state.totalCredit, currency: 'EGP')}' : null;

          finalVal = _formatCurrency(nativeFinal.abs(), currency: cur);
          finalSub = cur != 'EGP' ? 'ما يعادل: ${_formatCurrency(balance.abs(), currency: 'EGP')}' : null;
        } else {
          debitVal = _formatCurrency(state.totalDebit, currency: 'EGP');
          debitSub = null;

          creditVal = _formatCurrency(state.totalCredit, currency: 'EGP');
          creditSub = null;

          finalVal = _formatCurrency(balance.abs(), currency: 'EGP');
          finalSub = (hasMulti && state.formattedFinalBalances.isNotEmpty)
              ? 'الرصيد بالعملات: ${state.formattedFinalBalances}'
              : null;
        }

        final cards = [
          _summaryCard(
              label: 'إجمالي عليه',
              value: debitVal,
              subtitle: debitSub,
              color: AppTheme.danger,
              icon: Icons.arrow_upward,
              compact: isMobile),
          _summaryCard(
              label: 'إجمالي له',
              value: creditVal,
              subtitle: creditSub,
              color: AppTheme.success,
              icon: Icons.arrow_downward,
              compact: isMobile),
          _summaryCard(
            label: balance > 0
                ? 'الرصيد النهائي (له)'
                : balance < 0
                    ? 'الرصيد النهائي (عليه)'
                    : 'الرصيد النهائي (متوازن)',
            value: finalVal,
            subtitle: finalSub,
            color: balColor,
            icon: Icons.account_balance_outlined,
            isBold: true,
            compact: isMobile,
          ),
          _summaryCard(
              label: 'عدد الحركات',
              value: state.statementRows.length.toString(),
              color: AppTheme.primary,
              icon: Icons.format_list_numbered,
              compact: isMobile),
        ];
        if (isMobile) {
          return SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => SizedBox(width: 160, child: cards[i]),
            ),
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
      bool isBold = false,
      bool compact = false,
      String? subtitle}) {
    final pad = compact ? 8.0 : 16.0;
    final iconSize = compact ? 32.0 : 40.0;
    final iconInner = compact ? 16.0 : 20.0;
    final fontSize = compact ? 11.0 : 13.0;
    final valSize = compact ? 12.0 : (isBold ? 15.0 : 14.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: isDark ? 0.1 : 0.18),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: isDark ? color : (color == AppTheme.primary ? const Color(0xFF0284C7) : color), size: iconInner),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: fontSize)),
                      SizedBox(height: compact ? 2 : 4),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: valSize,
                              fontWeight: FontWeight.w900,
                              color: isDark ? color : Colors.black,
                              fontFamily: 'Cairo')),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: compact ? 9.0 : 10.5,
                                color: isDark ? color.withValues(alpha: 0.85) : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ],
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

  static const double _colRef = 150;
  static const double _colDate = 120;
  static const double _colAccount = 140;
  static const double _colDesc = 300;
  static const double _colForeign = 160;
  static const double _colDebit = 115;
  static const double _colCredit = 115;
  static const double _colBalance = 135;
  static const double _colNotes = 90;
  static const double _colHPad = 24;
  static const double _tableWidth = _colRef +
      _colDate +
      _colAccount +
      _colDesc +
      _colForeign +
      _colDebit +
      _colCredit +
      _colBalance +
      _colNotes +
      _colHPad;

  Widget _buildTable(SupplierAccountStatementLoaded state) {
    final curr = state.selectedSupplier?.currency ?? 'EGP';
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
                            _buildTableHeader(),
                            const Divider(height: 1),
                            Expanded(
                              child: ListView.separated(
                                itemCount: state.statementRows.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, indent: 16, endIndent: 16),
                                itemBuilder: (context, index) => _buildTableRow(
                                    context,
                                    state.statementRows[index],
                                    state.rowNotes,
                                    curr,
                                    supplier: state.selectedSupplier),
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

  Widget _buildTableHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerStyle = TextStyle(
        color: isDark ? AppTheme.textSecondary : Colors.black,
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo',
        fontSize: 14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: isDark ? const Color(0x1A00E5FF) : const Color(0x120284C7),
      child: Row(
        children: [
          SizedBox(width: _colRef, child: Text('رقم المرجع', style: headerStyle)),
          SizedBox(width: _colDate, child: Text('التاريخ', style: headerStyle)),
          SizedBox(width: _colAccount, child: Text('نوع الحساب', style: headerStyle)),
          Expanded(flex: _colDesc.toInt(), child: Text('البيان', style: headerStyle, overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colForeign, child: Text('المبلغ بالعملة الأجنبية', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: _colDebit, child: Text('المدين (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: _colCredit, child: Text('الدائن (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: _colBalance, child: Text('الرصيد (ج.م)', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: _colNotes, child: Text('ملاحظات', style: headerStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, StatementRow row,
      Map<String, String> rowNotes, String currency,
      {SupplierModel? supplier}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balColor = row.balance > 0
        ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
        : row.balance < 0
            ? (isDark ? AppTheme.danger : const Color(0xFFDC2626))
            : (isDark ? AppTheme.textSecondary : Colors.black54);

    return Container(
      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
              width: _colRef,
              child: Text(row.transactionNumber,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13))),
          SizedBox(
              width: _colDate,
              child: Text(_formatDateDisplay(row.date),
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 14))),
          SizedBox(
              width: _colAccount,
              child: Text(row.accountName,
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                  overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: _colDesc.toInt(),
              child: Tooltip(
                message: row.description,
                waitDuration: const Duration(milliseconds: 300),
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
                    softWrap: true,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )),
          SizedBox(
            width: _colForeign,
            child: Text(
              row.isForeignCurrency ? row.foreignDisplay : '—',
              style: TextStyle(
                fontSize: 12,
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
                  ? _formatCurrency(row.debit, currency: 'EGP')
                  : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: row.debit > 0
                    ? (isDark ? AppTheme.danger : const Color(0xFFDC2626))
                    : (isDark ? AppTheme.textSecondary : Colors.black54),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: _colCredit,
            child: Text(
              row.credit > 0
                  ? _formatCurrency(row.credit, currency: 'EGP')
                  : '—',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: row.credit > 0
                    ? (isDark ? AppTheme.success : const Color(0xFF16A34A))
                    : (isDark ? AppTheme.textSecondary : Colors.black54),
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: _colBalance,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatCurrency(row.balance.abs(), currency: 'EGP'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: balColor,
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
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
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          SizedBox(
            width: _colNotes,
            child: GestureDetector(
              onTap: () => _showNoteDialog(context, row.transactionNumber),
              child: (rowNotes[row.transactionNumber] ?? '').isNotEmpty
                  ? Text(rowNotes[row.transactionNumber]!,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                          fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2)
                  : Icon(Icons.edit_note_rounded,
                      size: 18, color: isDark ? AppTheme.textMuted.withAlpha(120) : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 72, color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.3) : const Color(0xFF64748B)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textSecondary : Colors.black,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 13)),
        ],
      ),
    );
  }

  String _formatCurrency(double amount, {String currency = 'EGP'}) {
    if (currency == 'MULTI') {
      return '${AppUtils.formatNumber(amount)} ج.م';
    }
    return SupplierModel.formatCurrency(amount, currency);
  }

  String _formatDateDisplay(String dateStr) {
    if (dateStr.isEmpty || dateStr == '—') return '—';
    if (dateStr.contains('/')) return dateStr;
    try {
      return AppUtils.formatDate(AppUtils.parseDate(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _printStatement(
      BuildContext context, SupplierAccountStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      final isFiltered = state.selectedCurrency != null && state.selectedCurrency != 'ALL';
      final cur = state.selectedCurrency ?? 'ALL';
      final effectiveCurrency = isFiltered ? cur : supplier.currency;
      final effectiveDebit = isFiltered ? (state.totalDebitsByCurrency[cur] ?? state.totalDebit) : state.totalDebit;
      final effectiveCredit = isFiltered ? (state.totalCreditsByCurrency[cur] ?? state.totalCredit) : state.totalCredit;
      final effectiveFinal = isFiltered ? (state.finalBalancesByCurrency[cur] ?? state.finalBalance) : state.finalBalance;

      String? obNote;
      if (state.fromDate != null && (state.openingBalance != 0 || (isFiltered && (state.openingBalancesByCurrency[cur] ?? 0) != 0))) {
        final hasMulti = supplier.hasMultiCurrencyInitialBalance;
        final currSym = supplier.currency == 'MULTI'
            ? 'ج.م'
            : SupplierModel.getCurrencySymbol(supplier.currency);
        final balStr = state.formattedOpeningBalances.isNotEmpty
            ? state.formattedOpeningBalances
            : (hasMulti
                ? supplier.formattedInitialBalance
                : '${AppUtils.formatNumber(state.openingBalance)} $currSym');
        obNote = locale == 'en'
            ? 'Note: Previous Balance = $balStr'
            : 'ملحوظة: الرصيد السابق = $balStr';
      }
      await StatementPdfService.printPdf(
        title: 'كشف حساب الموردين',
        vendorName: supplier.name,
        vendorCode: supplier.supplierCode,
        currency: effectiveCurrency,
        rows: state.statementRows,
        totalDebit: effectiveDebit,
        totalCredit: effectiveCredit,
        finalBalance: effectiveFinal,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل إنشاء PDF: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _savePdf(
      BuildContext context, SupplierAccountStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      final isFiltered = state.selectedCurrency != null && state.selectedCurrency != 'ALL';
      final cur = state.selectedCurrency ?? 'ALL';
      final effectiveCurrency = isFiltered ? cur : supplier.currency;
      final effectiveDebit = isFiltered ? (state.totalDebitsByCurrency[cur] ?? state.totalDebit) : state.totalDebit;
      final effectiveCredit = isFiltered ? (state.totalCreditsByCurrency[cur] ?? state.totalCredit) : state.totalCredit;
      final effectiveFinal = isFiltered ? (state.finalBalancesByCurrency[cur] ?? state.finalBalance) : state.finalBalance;

      String? obNote;
      if (state.fromDate != null && (state.openingBalance != 0 || (isFiltered && (state.openingBalancesByCurrency[cur] ?? 0) != 0))) {
        final hasMulti = supplier.hasMultiCurrencyInitialBalance;
        final currSym = supplier.currency == 'MULTI'
            ? 'ج.م'
            : SupplierModel.getCurrencySymbol(supplier.currency);
        final balStr = state.formattedOpeningBalances.isNotEmpty
            ? state.formattedOpeningBalances
            : (hasMulti
                ? supplier.formattedInitialBalance
                : '${AppUtils.formatNumber(state.openingBalance)} $currSym');
        obNote = locale == 'en'
            ? 'Note: Previous Balance = $balStr'
            : 'ملحوظة: الرصيد السابق = $balStr';
      }
      final path = await StatementPdfService.saveToFile(
        title: 'كشف حساب الموردين',
        vendorName: supplier.name,
        vendorCode: supplier.supplierCode,
        currency: effectiveCurrency,
        rows: state.statementRows,
        totalDebit: effectiveDebit,
        totalCredit: effectiveCredit,
        finalBalance: effectiveFinal,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم الحفظ في: $path'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الملف: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _saveExcel(
      BuildContext context, SupplierAccountStatementLoaded state) async {
    final supplier = state.selectedSupplier;
    if (supplier == null) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null) return;
    try {
      final isFiltered = state.selectedCurrency != null && state.selectedCurrency != 'ALL';
      final cur = state.selectedCurrency ?? 'ALL';
      final effectiveCurrency = isFiltered ? cur : supplier.currency;
      final effectiveDebit = isFiltered ? (state.totalDebitsByCurrency[cur] ?? state.totalDebit) : state.totalDebit;
      final effectiveCredit = isFiltered ? (state.totalCreditsByCurrency[cur] ?? state.totalCredit) : state.totalCredit;
      final effectiveFinal = isFiltered ? (state.finalBalancesByCurrency[cur] ?? state.finalBalance) : state.finalBalance;

      String? obNote;
      if (state.fromDate != null && (state.openingBalance != 0 || (isFiltered && (state.openingBalancesByCurrency[cur] ?? 0) != 0))) {
        final currSym = supplier.currency == 'MULTI'
            ? 'ج.م'
            : SupplierModel.getCurrencySymbol(supplier.currency);
        final balStr = state.formattedOpeningBalances.isNotEmpty
            ? state.formattedOpeningBalances
            : '${AppUtils.formatNumber(state.openingBalance)} $currSym';
        obNote = locale == 'en'
            ? 'Note: Previous Balance = $balStr'
            : 'ملحوظة: الرصيد السابق = $balStr';
      }
      final path = await StatementExcelService.saveToFile(
        title: 'كشف حساب الموردين',
        vendorName: supplier.name,
        vendorCode: supplier.supplierCode,
        currency: effectiveCurrency,
        rows: state.statementRows,
        totalDebit: effectiveDebit,
        totalCredit: effectiveCredit,
        finalBalance: effectiveFinal,
        fromDate: state.fromDate,
        toDate: state.toDate,
        statementNumber: state.statementNumber,
        locale: locale,
        notes: state.rowNotes,
        openingBalanceNote: obNote,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تم الحفظ في: $path'),
              backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الملف: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }


  void _showNoteDialog(BuildContext context, String transactionNumber) {
    final loadedState = context.read<SupplierAccountStatementCubit>().state;
    final currentNote = (loadedState is SupplierAccountStatementLoaded)
        ? (loadedState.rowNotes[transactionNumber] ?? '')
        : '';
    final controller = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('ملاحظة',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'أضف ملاحظة...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          if (currentNote.isNotEmpty)
            TextButton(
              onPressed: () {
                context
                    .read<SupplierAccountStatementCubit>()
                    .setRowNote(transactionNumber, '');
                Navigator.pop(ctx);
              },
              child: const Text('حذف',
                  style:
                      TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            onPressed: () {
              context
                  .read<SupplierAccountStatementCubit>()
                  .setRowNote(transactionNumber, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}
