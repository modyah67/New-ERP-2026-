import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/consolidated_statement_pdf_service.dart';
import '../../data/models/clearing_agent_model.dart';
import 'clearing_agent_cubit.dart';
import 'clearing_agent_state.dart';
import 'clearing_agent_form_dialog.dart';

class ClearingAgentsPage extends StatefulWidget {
  const ClearingAgentsPage({super.key});

  @override
  State<ClearingAgentsPage> createState() => _ClearingAgentsPageState();
}

class _ClearingAgentsPageState extends State<ClearingAgentsPage> {
  late final ClearingAgentCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ClearingAgentCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile),
              const SizedBox(height: 20),
              _buildSearchBar(isMobile),
              const SizedBox(height: 16),
              Expanded(child: _buildTable()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_shipping_outlined, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('المخلصين', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isMobile ? 22 : 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
                buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
                builder: (context, state) {
                  final count = state is ClearingAgentLoaded ? state.agents.length : 0;
                  return Text('$count مخلص', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                },
              ),
            ]),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined), tooltip: 'تحديث',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        const SizedBox(width: 4),
        BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
          buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
          builder: (context, state) {
            final agents = state is ClearingAgentLoaded ? state.agents : <ClearingAgentModel>[];
            if (agents.isEmpty) return const SizedBox.shrink();
            return Row(
              children: [
                // IconButton(
                //   icon: const Icon(Icons.print_outlined, color: Colors.white70),
                //   tooltip: 'طباعة كشف مجمع',
                //   onPressed: () => _printStatement(agents),
                // ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
                  tooltip: 'حفظ PDF',
                  onPressed: () => _savePdf(agents),
                ),
                const SizedBox(width: 4),
              ],
            );
          },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة مخلص'),
          onPressed: () async {
            await _cubit.prepareAddForm();
            _showFormDialog();
          },
        ),
        ],
      );
  }

  Widget _buildSearchBar(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: _cubit.onSearchChanged,
          decoration: InputDecoration(
            hintText: 'بحث بالاسم أو الكود...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
              buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
              builder: (context, state) {
                final query = state is ClearingAgentLoaded ? state.searchQuery : '';
                if (query.isEmpty) return const SizedBox.shrink();
                return IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cubit.onSearchChanged(''));
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTypeFilter(),
      ],
    );
  }

  Widget _buildTypeFilter() {
    return BlocBuilder<ClearingAgentCubit, ClearingAgentState>(
      buildWhen: (prev, curr) => curr is ClearingAgentLoaded,
      builder: (context, state) {
        final currentFilter = state is ClearingAgentLoaded ? state.typeFilter : 'all';
        return Row(
          children: [
            _buildFilterChip('الكل', 'all', currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip('بحري', 'بحري', currentFilter),
            const SizedBox(width: 8),
            _buildFilterChip('جوي', 'جوي', currentFilter),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value, String currentFilter) {
    final isSelected = currentFilter == value;
    return GestureDetector(
      onTap: () => _cubit.onTypeFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == 'all' ? Icons.filter_list : (value == 'بحري' ? Icons.sailing_outlined : Icons.flight_outlined),
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: BlocConsumer<ClearingAgentCubit, ClearingAgentState>(
            listener: (context, state) {
              if (state is ClearingAgentError) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
              }
            },
            builder: (context, state) {
              if (state is ClearingAgentLoading) return const Center(child: CircularProgressIndicator());
              if (state is ClearingAgentLoaded) {
                if (state.agents.isEmpty) return _buildEmptyState(state.searchQuery);
                return _buildDataTable(state);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(ClearingAgentLoaded state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth > 750 ? constraints.maxWidth : 750,
            ),
            child: Column(
              children: [
                _buildTableHeader(),
                const Divider(height: 1),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (!state.isFetchingMore && state.hasMore && scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                        _cubit.fetchMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      itemCount: state.agents.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (listContext, index) {
                        if (index == state.agents.length) {
                          return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
                        }
                        return _buildTableRow(listContext, state.agents[index], index);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _labelStyle = TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 13);

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(width: 36, child: Text('#', style: _labelStyle)),
          SizedBox(width: 100, child: Text('الكود', style: _labelStyle)),
          SizedBox(width: 140, child: Text('الاسم', style: _labelStyle)),
          SizedBox(width: 90, child: Text('النوع', style: _labelStyle)),
          SizedBox(width: 120, child: Text('الهاتف', style: _labelStyle)),
          SizedBox(width: 110, child: Text('الرصيد', style: _labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 90, child: Text('إجراءات', style: _labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext listContext, ClearingAgentModel agent, int index) {
    final isEven = index % 2 == 0;
    return Container(
      height: 55,
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text('${index + 1}', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
              child: Text(agent.code.isNotEmpty ? agent.code : '—', style: const TextStyle(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis),
            ),
          ),
          SizedBox(width: 140, child: Text(agent.name, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14), overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: agent.brokerType == 'بحري' ? Colors.blue.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(agent.brokerType, style: TextStyle(fontSize: 11, color: agent.brokerType == 'بحري' ? Colors.blue : Colors.orange, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
          ),
          SizedBox(width: 120, child: Text(agent.phone.isNotEmpty ? agent.phone : '—', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 110,
            child: Text(
              '${agent.balance < 0 ? '-' : ''}${agent.balance.abs().toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: agent.balance > 0 ? AppTheme.success : AppTheme.textSecondary, fontFamily: 'Cairo'),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 90,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(onTap: () => _showFormDialog(agent: agent), child: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(searchQuery.isEmpty ? 'لا يوجد مخلصين بعد' : 'لا توجد نتائج للبحث', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text(searchQuery.isEmpty ? 'اضغط "إضافة مخلص" لإضافة أول مخلص' : 'جرب كلمة بحث مختلفة', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مخلص'),
              onPressed: () async { await _cubit.prepareAddForm(); _showFormDialog(); },
            ),
          ],
        ],
      ),
    );
  }

  void _showFormDialog({ClearingAgentModel? agent}) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(value: _cubit, child: ClearingAgentFormDialog(agent: agent)),
    );
  }

  void _showDeleteConfirm(BuildContext context, ClearingAgentModel agent) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف "${agent.name}"؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () { Navigator.pop(dialogContext); _cubit.deleteAgent(agent); },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _printStatement(List<ClearingAgentModel> agents) async {
    final rows = agents.map((a) => <String, String>{
      'code': a.code,
      'name': a.name,
      'currency': a.currency,
      'balance': a.balance.toStringAsFixed(2),
    }).toList();
    final totalBalance = agents.fold<double>(0, (s, a) => s + a.balance);

    try {
      await ConsolidatedStatementPdfService.print(
        title: 'كشف حساب مجمع - المخلصين',
        rows: rows,
        totalBalance: totalBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _savePdf(List<ClearingAgentModel> agents) async {
    final rows = agents.map((a) => <String, String>{
      'code': a.code,
      'name': a.name,
      'currency': a.currency,
      'balance': a.balance.toStringAsFixed(2),
    }).toList();
    final totalBalance = agents.fold<double>(0, (s, a) => s + a.balance);

    try {
      final path = await ConsolidatedStatementPdfService.saveToFile(
        title: 'كشف حساب مجمع - المخلصين',
        rows: rows,
        totalBalance: totalBalance,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ في: $path'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
