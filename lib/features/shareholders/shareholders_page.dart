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

    if (w < 700) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.people_outline, color: AppTheme.primary, size: iconSize),
              const SizedBox(width: 10),
              Expanded(
                child: Text('المساهمين',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () => _showAddShareholderSheet(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('إضافة مساهم',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ExportIconButton(
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
              ),
              const SizedBox(width: 8),
              // Expanded(
              //   child: _ExportIconButton(
              //     onTap: () {
              //       final state = context.read<ShareholdersCubit>().state;
              //       if (state is ShareholdersLoaded) {
              //         ShareholdersExportService.exportShareholdersToPdf(state.shareholders);
              //       }
              //     },
              //     label: 'PDF',
              //     icon: Icons.picture_as_pdf,
              //     color: const Color(0xFFFF4757),
              //   ),
              // ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(Icons.people_outline, color: AppTheme.primary, size: iconSize),
        const SizedBox(width: 12),
        Expanded(
          child: Text('المساهمين',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 12),
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
        const SizedBox(width: 8),
        // _ExportIconButton(
        //   onTap: () {
        //     final state = context.read<ShareholdersCubit>().state;
        //     if (state is ShareholdersLoaded) {
        //       ShareholdersExportService.exportShareholdersToPdf(state.shareholders);
        //     }
        //   },
        //   label: 'PDF',
        //   icon: Icons.picture_as_pdf,
        //   color: const Color(0xFFFF4757),
        // ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: () => _showAddShareholderSheet(context),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('إضافة مساهم',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = constraints.maxWidth > 900 ? constraints.maxWidth : 900.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: minWidth,
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('الكود', style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('الاسم', style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('جنية', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('دولار', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('يورو', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('استرليني', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: headerFontSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 1, child: Text('', textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: state.shareholders.length,
                      separatorBuilder: (_, __) => const Divider(color: AppTheme.divider, height: 1),
                      itemBuilder: (ctx, index) {
                        final s = state.shareholders[index];
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: pad, vertical: cellVerticalPad),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(s.code, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: cellFontSize))),
                              Expanded(flex: 3, child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: cellFontSize))),
                              Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceEgp, s.totalDepositsEgp, s.totalWithdrawalsEgp, cellFontSize)),
                              Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceUsd, s.totalDepositsUsd, s.totalWithdrawalsUsd, cellFontSize)),
                              Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceEur, s.totalDepositsEur, s.totalWithdrawalsEur, cellFontSize)),
                              Expanded(flex: 3, child: _buildCurrencyStats(s.currentBalanceGbp, s.totalDepositsGbp, s.totalWithdrawalsGbp, cellFontSize)),
                              Expanded(
                                flex: 1, 
                                child: IconButton(
                                  icon: const Icon(Icons.edit, color: AppTheme.primary, size: 20),
                                  onPressed: () => _showEditInitialBalanceDialog(context, s),
                                  tooltip: 'تعديل الرصيد الافتتاحي (جنية)',
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
          );
        },
      ),
    );
  }

  Widget _buildCurrencyStats(double balance, double deposits, double withdrawals, double fontSize) {
    final labelSize = fontSize - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('الرصيد: ${AppUtils.formatNumber(balance)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: balance != 0 ? AppTheme.success : AppTheme.textSecondary, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: fontSize)),
        Text('إيداع: ${AppUtils.formatNumber(deposits)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.success, fontFamily: 'Cairo', fontSize: labelSize)),
        Text('صرف: ${AppUtils.formatNumber(withdrawals)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo', fontSize: labelSize)),
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
        return StatefulBuilder(
          builder: (context, setState) {
            return Material(
          color: const Color(0xFF0A1630),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('إضافة مساهم',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                const SizedBox(height: 16),

                TextField(
                  controller: codeCtrl,
                  enabled: true,
                  style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'الكود',
                    labelStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'الاسم',
                    labelStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                    onPressed: () {
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
    final usdCtrl = TextEditingController(text: (shareholder.initialBalanceUsd ?? 0.0).toString());
    final eurCtrl = TextEditingController(text: (shareholder.initialBalanceEur ?? 0.0).toString());
    final gbpCtrl = TextEditingController(text: (shareholder.initialBalanceGbp ?? 0.0).toString());
    
    String egpDir = shareholder.initialBalanceDirectionEgp;
    String usdDir = shareholder.initialBalanceDirectionUsd ?? 'CREDIT';
    String eurDir = shareholder.initialBalanceDirectionEur ?? 'CREDIT';
    String gbpDir = shareholder.initialBalanceDirectionGbp ?? 'CREDIT';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text('تعديل الرصيد الافتتاحي - ${shareholder.name}', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
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
                  child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
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
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: Container(
            height: 56, // Match text field height
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
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
                        color: direction == 'CREDIT' ? AppTheme.primary.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FittedBox(child: Text('دائن', style: TextStyle(color: direction == 'CREDIT' ? AppTheme.primary : AppTheme.textMuted, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
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
                        color: direction == 'DEBIT' ? Colors.redAccent.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: FittedBox(child: Text('مدين', style: TextStyle(color: direction == 'DEBIT' ? Colors.redAccent : AppTheme.textMuted, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
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
