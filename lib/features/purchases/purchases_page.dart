// lib/features/purchases/purchases_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/item_model.dart';
import '../auth/auth_cubit.dart';
import 'purchase_cubit.dart';
import 'purchase_state.dart';
import 'purchase_pdf_service.dart';
import '../../data/dao/purchase_dao.dart';
import '../../data/models/station_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';

class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.read<PurchaseCubit>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_shipping_outlined,
                    color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('المشتريات', style: TextStyle(fontSize: isMobile ? 22 : 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo')),
                    BlocBuilder<PurchaseCubit, PurchaseState>(
                      builder: (context, state) {
                        final count = state is PurchaseLoaded ? state.purchases.length : 0;
                        return Text('$count عملية شراء', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold));
                      },
                    ),
                  ]),
                ),
              ),
              IconButton(icon: Icon(Icons.refresh_outlined, color: isDark ? Colors.white : Colors.black), tooltip: 'تحديث', onPressed: c.loadAll),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(isMobile ? 'جديد' : 'مشتريات جديدة', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                onPressed: () { c.prepareNewForm(); if (context.mounted) context.push('/purchases/new', extra: c); },
              ),
            ]),
            const SizedBox(height: 20),
            BlocBuilder<PurchaseCubit, PurchaseState>(
              builder: (context, state) {
                final loaded = state is PurchaseLoaded;
                final fromDate = loaded ? state.fromDate : null;
                final toDate = loaded ? state.toDate : null;
                final selectedProductId = loaded ? state.selectedProductId : null;
                final allItems = loaded ? state.allItems : <ItemModel>[];
                final selectedItem = selectedProductId != null
                    ? allItems.cast<ItemModel?>().firstWhere(
                        (i) => i?.id == selectedProductId,
                        orElse: () => null)
                    : null;
                final hasAnyFilter =
                    fromDate != null || toDate != null || selectedProductId != null;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: isMobile ? 200 : 300,
                        child: ClipRRect(borderRadius: BorderRadius.circular(24), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Container(
                          decoration: isDark ? AppTheme.glassCard() : BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'بحث بالرقم أو اسم المورد...',
                              hintStyle: TextStyle(
                                color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              prefixIcon: Icon(Icons.search, size: 20, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                              border: InputBorder.none,
                            ),
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                            onChanged: (v) => c.onSearchChanged(v),
                          ),
                        )))),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: isMobile ? 140 : 180,
                        child: InkWell(
                          onTap: () => _showProductPicker(context, c, allItems, selectedProductId),
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: selectedProductId != null
                                  ? AppTheme.primary.withValues(alpha: 0.12)
                                  : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedProductId != null
                                    ? AppTheme.primary.withValues(alpha: 0.4)
                                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                              ),
                            ),
                            child: Row(children: [
                              Icon(Icons.inventory_2_outlined, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  selectedItem != null
                                      ? '${selectedItem.code} - ${selectedItem.name}'
                                      : 'كل المنتجات',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selectedProductId != null
                                        ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                        : (isDark ? Colors.white : Colors.black),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 18, color: isDark ? AppTheme.textSecondary : Colors.black),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => c.pickFromDate(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(children: [
                                  Icon(Icons.calendar_today, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                  const SizedBox(width: 8),
                                  Text(
                                    fromDate == null
                                        ? 'من تاريخ'
                                        : AppUtils.formatDate(fromDate),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            VerticalDivider(width: 1, indent: 8, endIndent: 8, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                            InkWell(
                              onTap: () => c.pickToDate(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(children: [
                                  Icon(Icons.calendar_today, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                  const SizedBox(width: 8),
                                  Text(
                                    toDate == null
                                        ? 'إلى تاريخ'
                                        : AppUtils.formatDate(toDate),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                            if (hasAnyFilter) ...[
                              VerticalDivider(width: 1, indent: 8, endIndent: 8, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                              IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: AppTheme.danger),
                                onPressed: c.clearFilters,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: BlocBuilder<PurchaseCubit, PurchaseState>(
              builder: (context, state) {
                if (state is PurchaseLoading || state is PurchaseInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is PurchaseError) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 72, color: AppTheme.danger.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text('خطأ في تحميل البيانات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.danger, fontFamily: 'Cairo')),
                      const SizedBox(height: 8),
                      const Padding(
                        padding:  EdgeInsets.symmetric(horizontal: 32),
                        child:  Text('state.message', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontFamily: 'Cairo'), textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('إعادة المحاولة'),
                        onPressed: () => context.read<PurchaseCubit>().loadAll(reset: true),
                      ),
                    ],
                  ));
                }
                if (state is! PurchaseLoaded || state.purchases.isEmpty) {
                  return Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 72, color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.3) : const Color(0xFF94A3B8)),
                      const SizedBox(height: 16),
                      Text('لا توجد مشتريات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo')),
                    ],
                  ));
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: isDark
                          ? AppTheme.glassCard()
                          : BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                      child: Column(children: [
                        if (!isMobile)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFE2E8F0),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            child: Row(children: [
                              Expanded(flex: 2, child: Text('الرقم', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14))),
                              Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14))),
                              Expanded(flex: 3, child: Text('المورد', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14))),
                              Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                              SizedBox(width: 120, child: Text('إجراءات', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
                            ]),
                          ),
                        if (!isMobile) Divider(height: 1, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (ScrollNotification scrollInfo) {
                              if (!state.isLoading &&
                                  !state.isFetchingMore &&
                                  state.hasMore &&
                                  scrollInfo.metrics.pixels >=
                                      scrollInfo.metrics.maxScrollExtent - 200) {
                                c.fetchMore();
                              }
                              return false;
                            },
                            child: ListView.separated(
                              itemCount: state.purchases.length + (state.hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                              itemBuilder: (_, i) {
                                if (i == state.purchases.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                return isMobile
                                    ? _mobileCard(context, state.purchases[i])
                                    : _desktopRow(context, state.purchases[i], i);
                              },
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showProductPicker(
      BuildContext context, PurchaseCubit cubit, List<ItemModel> items, String? selectedId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxHeight: 420),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('اختر المنتج', style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Material(
                        color: selectedId == null ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: true,
                          title: Text('الكل', style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                          leading: Icon(Icons.clear_all, color: selectedId == null ? AppTheme.primary : (isDark ? AppTheme.textSecondary : Colors.black54), size: 20),
                          onTap: () {
                            Navigator.pop(dialogContext);
                            cubit.onProductFilterChanged(null);
                          },
                        ),
                      ),
                      Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                      ...items.map((item) => Material(
                        color: item.id == selectedId ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: true,
                          title: Text('${item.name} (${item.code})',
                              style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
                          leading: Icon(Icons.inventory_2_outlined, color: item.id == selectedId ? AppTheme.primary : (isDark ? AppTheme.textSecondary : Colors.black54), size: 20),
                          onTap: () {
                            Navigator.pop(dialogContext);
                            cubit.onProductFilterChanged(item.id);
                          },
                        ),
                      )),
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

  Widget _desktopRow(BuildContext context, PurchaseModel p, int i) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final even = i % 2 == 0;
    final isDraft = p.status != 'confirmed';
    final authState = context.read<AuthCubit>().state;
    final isAdmin = authState is AuthAuthenticated && authState.isAdmin;
    return Container(
      color: isDark
          ? (even ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05))
          : (even ? Colors.white : const Color(0xFFF8FAFC)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(flex: 2, child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(p.purchaseNumber.toString().padLeft(6, '0'),
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDraft
                    ? Colors.orange.withValues(alpha: isDark ? 0.2 : 0.15)
                    : (isDark ? AppTheme.success.withValues(alpha: 0.2) : const Color(0xFFDCFCE7)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDraft
                      ? (isDark ? Colors.orange : Colors.orange.shade700)
                      : (isDark ? AppTheme.success : const Color(0xFF16A34A)),
                ),
              ),
              child: Text(isDraft ? 'مسودة' : 'مؤكد',
                  style: TextStyle(
                    color: isDraft
                        ? (isDark ? Colors.orange : Colors.orange.shade900)
                        : (isDark ? AppTheme.success : const Color(0xFF15803D)),
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  )),
            ),
          ],
        )),
        Expanded(
          flex: 2,
          child: Text(
            AppUtils.formatDate(AppUtils.parseDate(p.purchaseDate)),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            p.supplierName ?? '—',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            '${AppUtils.formatNumber(p.netAmount)} ${p.currency}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (isDraft) ...[
            InkWell(
              onTap: () => _confirmPurchase(context, p),
              child: const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _editPurchase(context, p),
              child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
          ],
          if (!isDraft) ...[
            _buildJournalEntriesDropdown(context, p),
            const SizedBox(width: 12),
          ],
          InkWell(
            onTap: () => _viewPurchase(context, p),
            child: Icon(Icons.article_outlined, size: 18, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => _showDetails(context, p),
            child: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Colors.red),
          ),
        ]),
      ]),
    );
  }

  Widget _mobileCard(BuildContext context, PurchaseModel p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDraft = p.status != 'confirmed';
    final authState = context.read<AuthCubit>().state;
    final isAdmin = authState is AuthAuthenticated && authState.isAdmin;
    return InkWell(
      onTap: () => _showDetails(context, p),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(p.purchaseNumber.toString().padLeft(6, '0'),
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 14)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDraft
                    ? Colors.orange.withValues(alpha: isDark ? 0.2 : 0.15)
                    : (isDark ? AppTheme.success.withValues(alpha: 0.2) : const Color(0xFFDCFCE7)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDraft
                      ? (isDark ? Colors.orange : Colors.orange.shade700)
                      : (isDark ? AppTheme.success : const Color(0xFF16A34A)),
                ),
              ),
              child: Text(isDraft ? 'مسودة' : 'مؤكد',
                  style: TextStyle(
                    color: isDraft
                        ? (isDark ? Colors.orange : Colors.orange.shade900)
                        : (isDark ? AppTheme.success : const Color(0xFF15803D)),
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  )),
            ),
            const Spacer(),
            Text(AppUtils.formatDate(AppUtils.parseDate(p.purchaseDate)),
                style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: isDark ? AppTheme.textSecondary : Colors.black87),
            const SizedBox(width: 6),
            Expanded(child: Text(p.supplierName ?? '—',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                '${AppUtils.formatNumber(p.netAmount)} ${p.currency}',
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 15, color: isDark ? AppTheme.accent : Colors.black),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDraft) ...[
              InkWell(onTap: () => _confirmPurchase(context, p),
                  child: const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success)),
              const SizedBox(width: 12),
              InkWell(onTap: () => _editPurchase(context, p),
                  child: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary)),
              const SizedBox(width: 12),
            ],
            if (!isDraft) ...[
              _buildJournalEntriesDropdown(context, p),
              const SizedBox(width: 12),
            ],
            InkWell(onTap: () => _viewPurchase(context, p),
                child: Icon(Icons.list_alt_outlined, size: 18, color: isDark ? AppTheme.accent : Colors.black87)),
            const SizedBox(width: 12),
            InkWell(onTap: () => _showDetails(context, p),
                child: const Icon(Icons.receipt_long_outlined, size: 18, color: Colors.red)),
          ]),
        ]),
      ),
    );
  }

  void _confirmPurchase(BuildContext context, PurchaseModel p) {
    bool isLoading = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? AppTheme.surface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            title: Text('تأكيد المشتريات', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 16)),
            content: Text(
              'هل أنت متأكد من تأكيد فاتورة ${p.purchaseNumber}؟\nسيتم إضافة الأصناف للمخازن وتحديث رصيد المورد${(p.paidAmount > 0) ? ' وخصم المبلغ المدفوع من الخزينة/البنك' : ''}.',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
                child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  setDialogState(() => isLoading = true);
                  try {
                    await PurchaseDao().confirmPurchase(p.id!);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تأكيد المشتريات بنجاح'), backgroundColor: AppTheme.success),
                      );
                      context.read<PurchaseCubit>().loadAll(reset: true);
                    }
                  } catch (e) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('تأكيد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _cancelPurchase(BuildContext context, PurchaseModel p) {
    bool isLoading = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? AppTheme.surface : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            title: Text('إلغاء المشتريات', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 16)),
            content: Text(
              'هل أنت متأكد من إلغاء فاتورة ${p.purchaseNumber}؟\n'
              'سيتم عكس جميع التغييرات: الخزينة، رصيد المورد، المخزون، والقيود المحاسبية.',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
                child: Text('رجوع', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  setDialogState(() => isLoading = true);
                  try {
                    final result = await PurchaseDao().cancelPurchase(p.id!);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      final msg = result['message']?.toString() ?? 'تم إلغاء المشتريات بنجاح';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: AppTheme.warning),
                      );
                      context.read<PurchaseCubit>().loadAll(reset: true);
                    }
                  } catch (e) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('إلغاء الفاتورة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _viewPurchase(BuildContext context, PurchaseModel p) async {
    final c = context.read<PurchaseCubit>();
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    await c.prepareEditForm(int.parse(p.id!));
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      context.push('/purchases/view', extra: c);
    }
  }

  void _editPurchase(BuildContext context, PurchaseModel p) async {
    final c = context.read<PurchaseCubit>();
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    await c.prepareEditForm(int.parse(p.id!));
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      context.push('/purchases/new', extra: c);
    }
  }

  Future<void> _showEditPriceDialog(BuildContext context, PurchaseModel p) async {
    if (p.id == null) return;

    PurchaseModel fullPurchase = p;
    if (p.items.isEmpty) {
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      final fetched = await PurchaseDao().getById(int.parse(p.id!));
      if (fetched != null) fullPurchase = fetched;
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    final c = context.read<PurchaseCubit>();

    final priceControllers = <String, TextEditingController>{};
    for (final item in fullPurchase.items) {
      if (item.id != null) {
        priceControllers[item.id!] = TextEditingController(
          text: item.purchasePrice.toString(),
        );
      }
    }

    bool isSaving = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppTheme.surface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
              title: Text(
                'تعديل السعر - ${fullPurchase.purchaseNumber}',
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'العملة: ${fullPurchase.currency}',
                      style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ...fullPurchase.items.map((item) {
                      final ctrl = priceControllers[item.id];
                      if (ctrl == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.itemName} (${item.itemCode})',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'الكمية: ${AppUtils.formatNumber(item.quantity)}',
                              style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: ctrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              decoration: InputDecoration(
                                labelText: 'سعر الشراء للوحدة',
                                labelStyle: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                                filled: true,
                                fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                                ),
                                suffixText: fullPurchase.currency,
                                suffixStyle: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setState(() => isSaving = true);
                          try {
                            final dao = PurchaseDao();
                            for (final item in fullPurchase.items) {
                              final ctrl = priceControllers[item.id];
                              if (ctrl == null) continue;
                              final newPrice = double.tryParse(ctrl.text);
                              if (newPrice == null || newPrice < 0) continue;
                              if (newPrice == item.purchasePrice) continue;
                              await dao.editItemPrice(
                                itemId: item.id!,
                                purchaseId: p.id!,
                                newPrice: newPrice,
                              );
                            }
                            if (context.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم تعديل السعر بنجاح'),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                              c.loadAll(reset: true);
                            }
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('خطأ: $e'),
                                  backgroundColor: AppTheme.danger,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('حفظ السعر', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDetails(BuildContext context, PurchaseModel p) async {
    PurchaseModel fullPurchase = p;
    if (p.items.isEmpty && p.id != null) {
      showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
      final fetched = await PurchaseDao().getById(int.parse(p.id!));
      if (fetched != null) fullPurchase = fetched;
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    final stations = context.read<PurchaseCubit>().state is PurchaseLoaded 
        ? (context.read<PurchaseCubit>().state as PurchaseLoaded).stations 
        : [];

    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: isMobile ? screenW * 0.95 : 700, padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Text('تفاصيل المشتريات', style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo')), const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black), onPressed: () => Navigator.pop(dialogContext))]),
                Divider(height: 24, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                Row(
                  children: [
                    Expanded(child: _dr(context, 'رقم المشتريات', fullPurchase.purchaseNumber.toString().padLeft(6, '0'))),
                    Expanded(child: _dr(context, 'التاريخ', AppUtils.formatDate(AppUtils.parseDate(fullPurchase.purchaseDate)))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _dr(context, 'المورد', fullPurchase.supplierName ?? '—')),
                    Expanded(child: _dr(context, 'كود المورد', fullPurchase.supplierCode ?? '—')),
                  ],
                ),
                Divider(height: 24, color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                Row(
                  children: [
                    Expanded(child: _dr(context, 'الإجمالي', '${AppUtils.formatNumber(fullPurchase.totalAmount)} ${fullPurchase.currency}')),
                  ],
                ),
                if (fullPurchase.notes != null && fullPurchase.notes!.isNotEmpty) _dr(context, 'ملاحظات', fullPurchase.notes!),
                const SizedBox(height: 12),
                Text('الأصناف:', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 520,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: fullPurchase.items.map((item) {
                          final stationName = stations.firstWhere(
                            (s) => s.id == item.stationId?.toString(),
                            orElse: () => StationModel(code: '', name: 'غير محدد', createdAt: ''),
                          ).name;
                          return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: isDark ? AppTheme.border : const Color(0xFFE2E8F0))),
                          ),
                          child: Row(children: [
                            Expanded(flex: 3, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.itemName, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13, color: isDark ? Colors.white : Colors.black)),
                                Text('كود: ${item.itemCode}', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            )),
                            Expanded(flex: 2, child: Column(
                              children: [
                                Text('الكمية', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 10)),
                                Text(AppUtils.formatNumber(item.quantity), style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            )),
                            Expanded(flex: 2, child: Column(
                              children: [
                                Text('سعر الشراء', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 10)),
                                Text('${AppUtils.formatNumber(item.purchasePrice)} ${fullPurchase.currency}', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            )),
                            Expanded(flex: 2, child: Column(
                              children: [
                                Text('المخزن', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 10)),
                                Text(stationName, style: TextStyle(color: isDark ? AppTheme.accent : const Color(0xFF0284C7), fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            )),
                            Expanded(flex: 2, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('الإجمالي', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 10)),
                                Text('${AppUtils.formatNumber(item.totalPrice)} ${fullPurchase.currency}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black)),
                              ],
                            )),
                          ]),
                        );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    // OutlinedButton.icon(
                    //   icon: const Icon(Icons.book_outlined, size: 18),
                    //   label: const Text('عرض القيد المحاسبي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    //   style: OutlinedButton.styleFrom(
                    //     foregroundColor: AppTheme.accent,
                    //     side: const BorderSide(color: AppTheme.accent),
                    //   ),
                    //   onPressed: () {
                    //     Navigator.of(dialogContext).pop();
                    //     _showJournalEntry(context, fullPurchase);
                    //   },
                    // ),
                    _buildJournalEntriesDropdown(context, fullPurchase),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt),
                      label: const Text('حفظ PDF', style: TextStyle(fontFamily: 'Cairo')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        try {
                          await PurchasePdfService.saveToFile(dialogContext, fullPurchase);
                        } catch (e) {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text('خطأ: فشل حفظ الملف: $e'),
                                backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showJournalEntry(BuildContext context, PurchaseModel p) {
    JournalEntryNavigationService.openForPurchase(
      context,
      purchaseId: p.id,
      purchaseNumber: p.purchaseNumber,
      journalEntryId: p.journalEntryId,
    );
  }

  Widget _buildJournalEntriesDropdown(BuildContext context, PurchaseModel p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<String>(
      onSelected: (entryNumber) {
        JournalEntryNavigationService.openById(context, journalEntryId: entryNumber);
      },
      offset: const Offset(0, 30),
      color: isDark ? AppTheme.surface : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1)),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: PurchaseDao().getJournalEntriesForPurchase(p.id ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return Text('لا توجد قيود محاسبية',
                    style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black54, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('القيود المحاسبية (${entries.length})',
                      style: TextStyle(color: isDark ? AppTheme.accent : const Color(0xFF0369A1), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  ...entries.map((je) {
                    final entryNum = je['entry_number']?.toString() ?? '';
                    final date = je['entry_date']?.toString() ?? '';
                    final debit = (je['total_debit'] as num?)?.toDouble() ?? 0;
                    final cur = je['currency']?.toString() ?? 'EGP';
                    final srcType = je['source_type']?.toString() ?? '';
                    String typeLabel;
                    switch (srcType) {
                      case 'purchase_inventory': typeLabel = 'قيد المخزون'; break;
                      case 'purchase_payment': typeLabel = 'قيد السداد'; break;
                      case 'purchase_price_adjustment': typeLabel = 'تعديل السعر'; break;
                      default: typeLabel = srcType;
                    }
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        JournalEntryNavigationService.openById(context, journalEntryId: entryNum);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(30) : const Color(0xFFE2E8F0))),
                        ),
                        child: Row(children: [
                          Icon(
                            srcType == 'purchase_price_adjustment' ? Icons.price_change_outlined : Icons.book_outlined,
                            size: 14,
                            color: srcType == 'purchase_price_adjustment' ? AppTheme.warning : (isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('قيد #$entryNum — $typeLabel',
                                    style: TextStyle(color: isDark ? AppTheme.textPrimary : Colors.black, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                const SizedBox(height: 2),
                                Text('$date — ${debit.toStringAsFixed(2)} $cur',
                                    style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new, size: 12, color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                        ]),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.accent.withAlpha(15) : const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isDark ? AppTheme.accent.withAlpha(40) : const Color(0xFFBAE6FD)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, color: isDark ? AppTheme.accent : const Color(0xFF0369A1), size: 14),
            const SizedBox(width: 4),
            Text('عرض القيود',
                style: TextStyle(color: isDark ? AppTheme.accent : const Color(0xFF0369A1), fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: isDark ? AppTheme.accent : const Color(0xFF0369A1), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _dr(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 13), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
