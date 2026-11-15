import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/models/shareholder_model.dart';
import 'shareholders_cubit.dart';
import 'shareholders_state.dart';
import 'shareholders_export_service.dart';

class ShareholdersPage extends StatelessWidget {
  const ShareholdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ShareholdersCubit()..loadAll(),
      child: const _ShareholdersView(),
    );
  }
}

class _ShareholdersView extends StatefulWidget {
  const _ShareholdersView();

  @override
  State<_ShareholdersView> createState() => _ShareholdersViewState();
}

class _ShareholdersViewState extends State<_ShareholdersView> {
  late final ScrollController _horizontalScrollController;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final pad = w < 400 ? 12.0 : w < 700 ? 16.0 : w < 1024 ? 20.0 : 24.0;
          final titleSize = w < 400 ? 18.0 : w < 700 ? 20.0 : w < 1024 ? 22.0 : 24.0;

          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(w, titleSize),
                SizedBox(height: pad),
                Expanded(
                  child: BlocConsumer<ShareholdersCubit, ShareholdersState>(
                    listener: (context, state) {
                      if (state is ShareholdersError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(state.message), backgroundColor: AppTheme.danger),
                        );
                      }
                    },
                    builder: (context, state) {
                      if (state is ShareholdersLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state is ShareholdersLoaded) {
                        return _buildContent(state, w, h, pad);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(double w, double titleSize) {
    final iconSize = w < 400 ? 22.0 : 28.0;
    final isDark = ThemeCubit.isCurrentDark;
    final primaryColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    final titleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.people_outline, color: primaryColor, size: iconSize),
        const SizedBox(width: 10),
        Text('المساهمين',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo')),
      ],
    );

    final actionsWidget = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ExportIconButton(
          onTap: () {
            final state = context.read<ShareholdersCubit>().state;
            if (state is ShareholdersLoaded) {
              ShareholdersExportService.exportShareholdersToExcel(state.shareholders);
            }
          },
          label: 'Excel',
          icon: Icons.grid_on,
          color: const Color(0xFF00D4AA),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => _showAddShareholderSheet(context),
          icon: const Icon(Icons.add, color: Colors.white, size: 18),
          label: const Text('إضافة مساهم',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );

    if (w < 480) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleWidget,
          const SizedBox(height: 12),
          actionsWidget,
        ],
      );
    }

    return Row(
      children: [
        titleWidget,
        const Spacer(),
        actionsWidget,
      ],
    );
  }

  Widget _buildContent(ShareholdersLoaded state, double w, double h, double pad) {
    if (state.shareholders.isEmpty) {
      return Center(
        child: Text('لا يوجد مساهمين',
            style: TextStyle(fontSize: w < 400 ? 13 : 16, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
      );
    }

    final headerFontSize = w < 400 ? 10.0 : w < 700 ? 11.0 : 12.0;
    final cellFontSize = w < 400 ? 10.0 : w < 700 ? 11.0 : 12.0;
    final cellVerticalPad = w < 400 ? 8.0 : 12.0;

    final isDark = ThemeCubit.isCurrentDark;
    final labelColor = isDark ? AppTheme.textSecondary : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.glassBorder : AppTheme.lightBorder),
        boxShadow: isDark ? null : [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = constraints.maxWidth > 720 ? constraints.maxWidth : 720.0;
          return Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: constraints.maxWidth < 720,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: minWidth,
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text('الكود', style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 3, child: Text('الاسم', style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 3, child: Text('جنية', textAlign: TextAlign.center, style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 3, child: Text('دولار', textAlign: TextAlign.center, style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 3, child: Text('يورو', textAlign: TextAlign.center, style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 3, child: Text('استرليني', textAlign: TextAlign.center, style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          Expanded(flex: 1, child: Text('تعديل', textAlign: TextAlign.center, style: TextStyle(color: labelColor, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: state.shareholders.length,
                        separatorBuilder: (_, __) => Divider(color: isDark ? AppTheme.divider : AppTheme.lightBorder, height: 1),
                        itemBuilder: (ctx, index) {
                          final s = state.shareholders[index];
                          final isEven = index % 2 == 0;
                          return Container(
                            color: isEven
                                ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.transparent)
                                : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
                            padding: EdgeInsets.symmetric(horizontal: pad, vertical: cellVerticalPad),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (isDark ? AppTheme.accent : AppTheme.lightAccent).withValues(alpha: isDark ? 0.08 : 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        s.code,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isDark ? AppTheme.accent : Colors.black,
                                          fontFamily: 'Cairo',
                                          fontSize: cellFontSize,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: cellFontSize + 1,
                                    ),
                                  ),
                                ),
                                Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceEgp, s.totalDepositsEgp, s.totalWithdrawalsEgp, cellFontSize)),
                                Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceUsd, s.totalDepositsUsd, s.totalWithdrawalsUsd, cellFontSize)),
                                Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceEur, s.totalDepositsEur, s.totalWithdrawalsEur, cellFontSize)),
                                Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceGbp, s.totalDepositsGbp, s.totalWithdrawalsGbp, cellFontSize)),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: IconButton(
                                      icon: Icon(Icons.edit_outlined, color: isDark ? AppTheme.primary : AppTheme.lightPrimary, size: 20),
                                      onPressed: () => _showEditInitialBalanceDialog(context, s),
                                      tooltip: 'تعديل الرصيد الافتتاحي (جنية)',
                                    ),
                                  ),
                                ),
                              ],
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
        },
      ),
    );
  }

  Widget _buildCurrencyStats(double balance, double deposits, double withdrawals, double fontSize) {
    final isDark = ThemeCubit.isCurrentDark;
    final labelSize = fontSize - 1;

    final balanceColor = balance > 0
        ? (isDark ? AppTheme.success : const Color(0xFF15803D))
        : (balance < 0 ? (isDark ? AppTheme.danger : const Color(0xFFB91C1C)) : (isDark ? AppTheme.textSecondary : Colors.black));
    final depositColor = isDark ? AppTheme.success : const Color(0xFF0284C7);
    final withdrawalColor = isDark ? AppTheme.danger : const Color(0xFFDC2626);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'الرصيد: ${AppUtils.formatNumber(balance)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: balanceColor,
            fontWeight: FontWeight.w900,
            fontFamily: 'Cairo',
            fontSize: fontSize,
          ),
        ),
        Text(
          'إيداع: ${AppUtils.formatNumber(deposits)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: depositColor,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: labelSize,
          ),
        ),
        Text(
          'صرف: ${AppUtils.formatNumber(withdrawals)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: withdrawalColor,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: labelSize,
          ),
        ),
      ],
    );
  }

  void _showAddShareholderSheet(BuildContext context) async {
    final cubit = context.read<ShareholdersCubit>();
    final nameCtrl = TextEditingController();
    final egpCtrl = TextEditingController();
    final usdCtrl = TextEditingController();
    final eurCtrl = TextEditingController();
    final gbpCtrl = TextEditingController();
    String newCode = await ShareholderDao().generateNextCode();
    final codeCtrl = TextEditingController(text: newCode.replaceAll('SH-', ''));

    String initialBalanceDirectionEgp = 'CREDIT';
    String initialBalanceDirectionUsd = 'CREDIT';
    String initialBalanceDirectionEur = 'CREDIT';
    String initialBalanceDirectionGbp = 'CREDIT';

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = ThemeCubit.isCurrentDark;
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
          color: isDark ? const Color(0xFF0A1630) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إضافة مساهم',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo')),
                const SizedBox(height: 16),

                TextField(
                  controller: codeCtrl,
                  enabled: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  decoration: InputDecoration(
                    labelText: 'الكود',
                    hintText: ShareholderModel.codeHint,
                    labelStyle: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    floatingLabelStyle: TextStyle(
                      color: isDark ? AppTheme.primary : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    hintStyle: TextStyle(
                      color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    filled: true,
                    fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.primary : Colors.black, width: 2.0)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  decoration: InputDecoration(
                    labelText: 'الاسم',
                    labelStyle: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    floatingLabelStyle: TextStyle(
                      color: isDark ? AppTheme.primary : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    hintStyle: TextStyle(
                      color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    filled: true,
                    fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.primary : Colors.black, width: 2.0)),
                  ),
                ),
                const SizedBox(height: 12),

                _CurrencyInputRow(
                  label: 'الرصيد المبدئي (جنية)',
                  controller: egpCtrl,
                  direction: initialBalanceDirectionEgp,
                  onDirectionChanged: (val) => setState(() => initialBalanceDirectionEgp = val),
                ),
                const SizedBox(height: 12),
                _CurrencyInputRow(
                  label: 'الرصيد المبدئي (دولار)',
                  controller: usdCtrl,
                  direction: initialBalanceDirectionUsd,
                  onDirectionChanged: (val) => setState(() => initialBalanceDirectionUsd = val),
                ),
                const SizedBox(height: 12),
                _CurrencyInputRow(
                  label: 'الرصيد المبدئي (يورو)',
                  controller: eurCtrl,
                  direction: initialBalanceDirectionEur,
                  onDirectionChanged: (val) => setState(() => initialBalanceDirectionEur = val),
                ),
                const SizedBox(height: 12),
                _CurrencyInputRow(
                  label: 'الرصيد المبدئي (استرليني)',
                  controller: gbpCtrl,
                  direction: initialBalanceDirectionGbp,
                  onDirectionChanged: (val) => setState(() => initialBalanceDirectionGbp = val),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final code = codeCtrl.text.trim();
                      final name = nameCtrl.text.trim();
                      final egp = double.tryParse(egpCtrl.text.trim()) ?? 0.0;
                      final usd = double.tryParse(usdCtrl.text.trim()) ?? 0.0;
                      final eur = double.tryParse(eurCtrl.text.trim()) ?? 0.0;
                      final gbp = double.tryParse(gbpCtrl.text.trim()) ?? 0.0;

                      if (code.isEmpty || name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكود والاسم مطلوبان', style: TextStyle(fontFamily: 'Cairo'))));
                        return;
                      }

                      // ── Form Validation Guard: Strict Numerical Boundary Check ──
                      final codeErr = ShareholderModel.validateShareholderCode(code);
                      if (codeErr != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(codeErr, style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }

                      // ── Collision Check Guard ──
                      final exists = await ShareholderDao().checkCodeExists(code);
                      if (exists) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('كود المساهم ($code) مستخدم بالفعل، يرجى اختيار كود آخر',
                                style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                        return;
                      }

                      final shareholder = ShareholderModel(
                        code: code,
                        name: name,
                        initialBalanceEgp: egp,
                        currentBalanceEgp: egp,
                        initialBalanceUsd: usd,
                        currentBalanceUsd: usd,
                        initialBalanceEur: eur,
                        currentBalanceEur: eur,
                        initialBalanceGbp: gbp,
                        currentBalanceGbp: gbp,
                        initialBalanceDirectionEgp: initialBalanceDirectionEgp,
                        initialBalanceDirectionUsd: initialBalanceDirectionUsd,
                        initialBalanceDirectionEur: initialBalanceDirectionEur,
                        initialBalanceDirectionGbp: initialBalanceDirectionGbp,
                        createdAt: DateTime.now().toIso8601String(),
                      );

                      if (!sheetContext.mounted) return;
                      cubit.addShareholder(shareholder);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('حفظ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          ),
            ));
          }
        );
      },
    );
  }

  void _showEditInitialBalanceDialog(BuildContext context, ShareholderModel shareholder) {
    final cubit = context.read<ShareholdersCubit>();
    
    final egpCtrl = TextEditingController(text: shareholder.initialBalanceEgp.toString());
    final usdCtrl = TextEditingController(text: shareholder.initialBalanceUsd.toString());
    final eurCtrl = TextEditingController(text: shareholder.initialBalanceEur.toString());
    final gbpCtrl = TextEditingController(text: shareholder.initialBalanceGbp.toString());
    
    String egpDir = shareholder.initialBalanceDirectionEgp;
    String usdDir = shareholder.initialBalanceDirectionUsd;
    String eurDir = shareholder.initialBalanceDirectionEur;
    String gbpDir = shareholder.initialBalanceDirectionGbp;

    final isDark = ThemeCubit.isCurrentDark;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppTheme.surface : Colors.white,
              title: Text('تعديل الرصيد الافتتاحي - ${shareholder.name}', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CurrencyInputRow(
                        label: 'EGP',
                        controller: egpCtrl,
                        direction: egpDir,
                        onDirectionChanged: (val) => setState(() => egpDir = val),
                      ),
                      const SizedBox(height: 16),
                      _CurrencyInputRow(
                        label: 'USD',
                        controller: usdCtrl,
                        direction: usdDir,
                        onDirectionChanged: (val) => setState(() => usdDir = val),
                      ),
                      const SizedBox(height: 16),
                      _CurrencyInputRow(
                        label: 'EUR',
                        controller: eurCtrl,
                        direction: eurDir,
                        onDirectionChanged: (val) => setState(() => eurDir = val),
                      ),
                      const SizedBox(height: 16),
                      _CurrencyInputRow(
                        label: 'GBP',
                        controller: gbpCtrl,
                        direction: gbpDir,
                        onDirectionChanged: (val) => setState(() => gbpDir = val),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('إلغاء', style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black, fontWeight: isDark ? FontWeight.normal : FontWeight.bold, fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () {
                    cubit.updateInitialBalance(
                      id: shareholder.id!,
                      egpBal: double.tryParse(egpCtrl.text.trim()) ?? 0.0,
                      egpDir: egpDir,
                      usdBal: double.tryParse(usdCtrl.text.trim()) ?? 0.0,
                      usdDir: usdDir,
                      eurBal: double.tryParse(eurCtrl.text.trim()) ?? 0.0,
                      eurDir: eurDir,
                      gbpBal: double.tryParse(gbpCtrl.text.trim()) ?? 0.0,
                      gbpDir: gbpDir,
                    );
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('حفظ', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }
}

class _CurrencyInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String direction;
  final ValueChanged<String> onDirectionChanged;

  const _CurrencyInputRow({
    required this.label,
    required this.controller,
    required this.direction,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeCubit.isCurrentDark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
            ],
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              floatingLabelStyle: TextStyle(
                color: isDark ? AppTheme.primary : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              hintStyle: TextStyle(
                color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              filled: true,
              fillColor: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFF94A3B8))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.primary : Colors.black, width: 2.0)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: Container(
            height: 56, // Match text field height
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.transparent : const Color(0xFF94A3B8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => onDirectionChanged('CREDIT'),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: direction == 'CREDIT'
                            ? (isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFE0F2FE))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: direction == 'CREDIT' && !isDark
                            ? Border.all(color: const Color(0xFF0284C7), width: 1.5)
                            : null,
                      ),
                      child: FittedBox(
                        child: Text(
                          'دائن',
                          style: TextStyle(
                            color: direction == 'CREDIT'
                                ? (isDark ? AppTheme.primary : const Color(0xFF0369A1))
                                : (isDark ? AppTheme.textMuted : Colors.black),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onDirectionChanged('DEBIT'),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: direction == 'DEBIT'
                            ? (isDark ? Colors.redAccent.withValues(alpha: 0.2) : const Color(0xFFFEE2E2))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: direction == 'DEBIT' && !isDark
                            ? Border.all(color: const Color(0xFFDC2626), width: 1.5)
                            : null,
                      ),
                      child: FittedBox(
                        child: Text(
                          'مدين',
                          style: TextStyle(
                            color: direction == 'DEBIT'
                                ? Colors.redAccent
                                : (isDark ? AppTheme.textMuted : Colors.black),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ExportIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color color;

  const _ExportIconButton({
    required this.onTap,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }
}
