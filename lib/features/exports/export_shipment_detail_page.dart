import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_recipe_snapshot_model.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/shipment_recipe_snapshot_dao.dart';
import '../../data/services/recipe_snapshot_service.dart';
import 'export_shipment_cubit.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'commercial_invoice_pdf_service.dart';
import 'packing_list_pdf_service.dart';
import 'shipment_cost_breakdown_page.dart';
import 'preparation_center_invoice_screen.dart';
import 'shipment_invoice_preview_page.dart';
import 'export_shipment_return_page.dart';

class ExportShipmentDetailPage extends StatefulWidget {
  const ExportShipmentDetailPage({super.key});

  @override
  State<ExportShipmentDetailPage> createState() => _ExportShipmentDetailPageState();
}

class _ExportShipmentDetailPageState extends State<ExportShipmentDetailPage> {
  bool _isDocLoading = false;
  List<ShipmentRecipeSnapshotModel> _recipeSnapshots = [];
  bool _snapshotsLoaded = false;
  double _snapshotTotalCost = 0;
  final _exportDao = ExportShipmentDao();

  String _statusLabel(String status) {
    switch (status) {
      case 'draft': return 'مسودة';
      case 'booked': return 'محجوزة';
      case 'loaded': return 'محملة';
      case 'sailed': return 'أبحرت';
      case 'arrived': return 'وصلت';
      case 'completed': return 'مكتملة';
      case 'returned_from_airport': return 'عائدة من المطار';
      case 'cancelled': return 'ملغاة';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft': return AppTheme.textSecondary;
      case 'booked': return const Color(0xFF3B82F6);
      case 'loaded': return AppTheme.warning;
      case 'sailed': return const Color(0xFF22D3EE);
      case 'arrived': return const Color(0xFF8B5CF6);
      case 'completed': return AppTheme.success;
      case 'returned_from_airport': return const Color(0xFFEA580C);
      case 'cancelled': return AppTheme.danger;
      default: return AppTheme.primary;
    }
  }

  String _transportLabel(String mode) {
    switch (mode) {
      case 'sea': return 'بحري';
      case 'air': return 'جوي';
      case 'land': return 'بري';
      default: return mode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: 800,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              decoration: BoxDecoration(
                color: AppTheme.background.withAlpha(245),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: BlocBuilder<ExportShipmentCubit, ExportShipmentState>(
                builder: (context, state) {
                  if (state is ExportShipmentLoading) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  if (state is ExportShipmentDetailLoaded) {
                    return _buildDetail(state.shipment);
                  }
                  if (state is ExportShipmentError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                          const SizedBox(height: 12),
                          Text(state.message, style: const TextStyle(color: AppTheme.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
                        ],
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(ExportShipmentModel s) {
    final color = _statusColor(s.status);
    return Column(
      children: [
        _buildHeader(s, color),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusTimeline(s.status),
                const SizedBox(height: 20),
                if (s.status == 'returned_from_airport') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEA580C).withAlpha(70)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.keyboard_return_rounded, color: Color(0xFFEA580C), size: 24),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'تم تسجيل رجوع هذه الشحنة بالكامل من المطار وفك ارتباطها بأمر التعبئة وتسوية الهالك ورد السليم للمخزون.',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildInfoCard('معلومات أساسية', [
                  _row('رقم الشحنة', s.shipmentNo),
                  _row('العميل', s.customerName ?? '—'),
                  _row('كود العميل', s.customerCode ?? '—'),
                  _row('جهة الاتصال', s.contactPerson ?? '—'),
                  _row('تاريخ الشحن', s.shipmentDate != null ? AppUtils.formatDate(s.shipmentDate!) : '—'),
                ]),
                const SizedBox(height: 16),
                _buildInfoCard('بيانات الشحن', [
                  _row('البلد', s.country ?? '—'),
                  _row('عنوان الوجهة', s.destinationAddress ?? '—'),
                  _row('وسيلة النقل', _transportLabel(s.transportMode)),
                  _row('رقم الحاوية', s.containerNo ?? '—'),
                  _row('رقم بوالص الشحن', s.blNumber ?? '—'),
                  _row('اسم السفينة', s.vesselName ?? '—'),
                  _row('شركة الشحن', s.shippingCompany ?? '—'),
                  _row('رقم مسجل البيانات', s.dataLoggerNo ?? '—'),
                ]),
                const SizedBox(height: 16),
                _buildInfoCard('الموانئ', [
                  _row('ميناء التحميل', s.portOfLoading ?? 'ميناء شرق بورسعيد'),
                  _row('ميناء الوصول', s.portOfDestination ?? '—'),
                ]),
                const SizedBox(height: 16),
                _buildInfoCard('الوزن والكراتين', [
                  _row('عدد المنصات', s.palletsCount.toString()),
                  _row('عدد الكراتين', s.cartonsCount.toString()),
                  _row('الوزن الصافي', '${s.netWeight} kg'),
                  _row('الوزن الإجمالي', '${s.grossWeight} kg'),
                ]),
                const SizedBox(height: 16),
                _buildInfoCard('الشروط التجارية', [
                  _row('Incoterm', s.incoterm ?? '—'),
                  _row('العملة', s.currency ?? '—'),
                  _row('شروط الدفع', s.paymentTerms ?? '—'),
                  _row('الشروط والأحكام', s.termsConditions ?? '—'),
                ]),
                if (s.internalNotes != null && s.internalNotes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildInfoCard('ملاحظات', [
                    _row('ملاحظات داخلية', s.internalNotes!),
                  ]),
                ],
                const SizedBox(height: 16),
                _buildActions(s),
                const SizedBox(height: 16),
                _buildDocumentsSection(s),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ExportShipmentModel s, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50)))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.flight_outlined, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UIUtils.shipmentNoText(s.shipmentNo, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                const SizedBox(height: 2),
                Text(s.customerName ?? s.country ?? '—', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withAlpha(50))),
            child: Text(_statusLabel(s.status), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0x3805192D), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.glassBorder)),
              child: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final stages = ['draft', 'booked', 'loaded', 'sailed', 'arrived', 'completed'];
    final currentIdx = stages.indexOf(status);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تتبع الشحنة', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: stages.map((stage) {
                    final idx = stages.indexOf(stage);
                    final isCompleted = currentIdx >= idx;
                    final isCurrent = currentIdx == idx;
                    final stageColor = isCompleted ? AppTheme.success : AppTheme.textSecondary;
                    final stageLabels = ['مسودة', 'محجوزة', 'محملة', 'أبحرت', 'وصلت', 'مكتملة'];
                    return Row(
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: isCompleted ? AppTheme.success.withAlpha(30) : const Color(0x1AFFFFFF),
                                shape: BoxShape.circle,
                                border: Border.all(color: isCompleted ? AppTheme.success : AppTheme.glassBorder, width: isCurrent ? 2 : 1),
                              ),
                              child: Icon(
                                isCompleted ? Icons.check : Icons.circle_outlined,
                                color: stageColor, size: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(stageLabels[idx], style: TextStyle(color: stageColor, fontSize: 10, fontFamily: 'Cairo')),
                          ],
                        ),
                        if (idx < stages.length - 1)
                          Container(
                            width: 40, height: 2,
                            color: isCompleted ? AppTheme.success.withAlpha(80) : AppTheme.glassBorder.withAlpha(40),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> rows) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 3, height: 16, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ],
              ),
              const SizedBox(height: 12),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ExportShipmentModel s) {
    final statusActions = <String, List<String>>{
      'draft': ['booked', 'cancelled'],
      'booked': ['loaded', 'cancelled'],
      'loaded': ['sailed'],
      'sailed': ['arrived'],
      'arrived': ['completed'],
    };
    final nextStatuses = statusActions[s.status] ?? [];
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الإجراءات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (nextStatuses.isNotEmpty)
                    ...nextStatuses.map((ns) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _actionBtn(
                        ns == 'cancelled' ? 'إلغاء الشحنة' : 'تحديث إلى ${_statusLabel(ns)}',
                        ns == 'cancelled' ? AppTheme.danger : AppTheme.primary,
                        ns == 'cancelled'
                            ? () => _confirmCancel(s)
                            : () => context.read<ExportShipmentCubit>().updateStatus(s.id!, ns),
                      ),
                    )),
                  _actionBtn('تعديل', AppTheme.warning, () {
                    context.read<ExportShipmentCubit>().loadForm(s.id);
                    Navigator.pop(context);
                    context.push('/exports/edit', extra: {'shipment': s});
                  }),
                  const SizedBox(width: 8),
                  if (s.isConfirmed && s.status != 'returned_from_airport' && s.status != 'cancelled') ...[
                    _actionBtn('تسجيل رجوع من المطار', const Color(0xFFEA580C), () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExportShipmentReturnPage(
                            shipmentId: s.id,
                            initialShipment: s,
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),
                  ],
                  _actionBtn('حذف', AppTheme.danger, () => _confirmDelete(s)),
                  if (s.isConfirmed || s.status == 'returned_from_airport' || s.status == 'returned') ...[
                    const SizedBox(width: 8),
                    _buildJournalEntriesDropdown(s),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withAlpha(50))),
        child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      ),
    );
  }

  Widget _buildJournalEntriesDropdown(ExportShipmentModel s) {
    return PopupMenuButton<String>(
      onSelected: (entryNumber) {
        JournalEntryNavigationService.openById(context, journalEntryId: entryNumber);
      },
      offset: const Offset(0, 30),
      constraints: const BoxConstraints(minWidth: 290, maxWidth: 360),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.glassBorder.withAlpha(40)),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _exportDao.getJournalEntriesForShipment(s.id ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return const Text('لا توجد قيود محاسبية',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('القيود المحاسبية (${entries.length})',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  ...entries.map((je) {
                    final entryNum = je['entry_number']?.toString() ?? '';
                    final date = je['entry_date']?.toString() ?? '';
                    final debit = (je['total_debit'] as num?)?.toDouble() ?? 0;
                    final cur = je['currency']?.toString() ?? 'EGP';
                    final srcType = je['source_type']?.toString() ?? '';
                    final cat = je['category']?.toString() ?? '';
                    final isReturn = je['is_return_entry'] == true ||
                        srcType == 'export_return' ||
                        srcType == 'export_shipment_return' ||
                        cat == 'return';

                    String typeLabel;
                    IconData iconData;
                    Color iconColor;

                    if (isReturn) {
                      typeLabel = 'قيد إلغاء / مرتجع الشحنة';
                      iconData = Icons.assignment_return_outlined;
                      iconColor = const Color(0xFFEA580C);
                    } else {
                      switch (srcType) {
                        case 'export_shipment':
                          typeLabel = 'قيد البيع';
                          iconData = Icons.receipt_long_outlined;
                          iconColor = AppTheme.cyan;
                          break;
                        case 'export_discount':
                          typeLabel = 'قيد الخصم';
                          iconData = Icons.discount_outlined;
                          iconColor = AppTheme.warning;
                          break;
                        case 'customer_treasury_deposit':
                        case 'bank_deposit':
                        case 'customer_bank_deposit':
                        case 'export_payment':
                          typeLabel = 'قيد السداد';
                          iconData = Icons.payment_outlined;
                          iconColor = AppTheme.success;
                          break;
                        case 'customer_treasury_withdrawal':
                          typeLabel = 'قيـد اسـترداد السـداد';
                          iconData = Icons.replay_outlined;
                          iconColor = AppTheme.danger;
                          break;
                        case 'packing_order':
                          typeLabel = 'قيد أمر التعبئة';
                          iconData = Icons.inventory_2_outlined;
                          iconColor = AppTheme.primary;
                          break;
                        case 'packing_debit_note':
                          typeLabel = 'خصم مورد تعبئة';
                          iconData = Icons.money_off_outlined;
                          iconColor = AppTheme.warning;
                          break;
                        case 'shipment_cost_accrual':
                          typeLabel = 'استحقاق تكلفة شحنة';
                          iconData = Icons.pending_actions_outlined;
                          iconColor = const Color(0xFF8B5CF6);
                          break;
                        case 'shipment_cost_paid':
                          typeLabel = 'سداد تكلفة شحنة';
                          iconData = Icons.paid_outlined;
                          iconColor = AppTheme.success;
                          break;
                        default:
                          typeLabel = je['category_label']?.toString() ?? srcType;
                          iconData = Icons.article_outlined;
                          iconColor = AppTheme.textSecondary;
                      }
                    }

                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        JournalEntryNavigationService.openById(context, journalEntryId: entryNum);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isReturn ? const Color(0xFFEA580C).withAlpha(15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
                        ),
                        child: Row(children: [
                          Icon(iconData, size: 14, color: iconColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('قيد #$entryNum — $typeLabel',
                                          style: TextStyle(
                                            color: isReturn ? const Color(0xFFEA580C) : AppTheme.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Cairo',
                                          )),
                                    ),
                                    if (isReturn)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEA580C).withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('مرتجع', style: TextStyle(color: Color(0xFFEA580C), fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('$date — ${debit.toStringAsFixed(2)} $cur',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          const Icon(Icons.open_in_new, size: 12, color: AppTheme.textMuted),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accent.withAlpha(80)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, color: AppTheme.accent, size: 14),
            SizedBox(width: 4),
            Text(
              'عرض القيود',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(ExportShipmentModel s) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('المستندات', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _docBtn('🧾  Commercial Invoice', AppTheme.primary, !_isDocLoading, () => _openCommercialInvoice(s)),
                    const SizedBox(width: 8),
                    _docBtn('📦  Packing List', const Color(0xFF22D3EE), !_isDocLoading, () => _openPackingList(s)),
                    const SizedBox(width: 8),
                    _docBtn('📑  فاتورة الشحنة', AppTheme.emerald, !_isDocLoading, () => _openShipmentInvoice(s)),
                    const SizedBox(width: 8),
                    _docBtn('🏭  مركز التحضير', const Color(0xFFF57C00), !_isDocLoading, () => _openPrepCenterInvoice(s)),
                    const SizedBox(width: 8),
                    _docBtn('💰  مركز التسعير', const Color(0xFF8B5CF6), !_isDocLoading, () => _openCosting(s)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSnapshotSection(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docBtn(String label, Color color, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? color : color.withAlpha(80),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildSnapshotSection(ExportShipmentModel s) {
    if (s.packingRecipeId == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warning.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withAlpha(40)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('لا توجد وصفة تعبئة مرتبطة بهذه الشحنة. قم بربط وصفة أولاً.',
                  style: TextStyle(color: AppTheme.warning, fontSize: 12, fontFamily: 'Cairo')),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<ShipmentRecipeSnapshotModel>>(
      future: _snapshotsLoaded ? null : ShipmentRecipeSnapshotDao().getByShipment(int.parse(s.id!)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 20, child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final snapshots = snapshot.data ?? _recipeSnapshots;

        if (snapshots.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withAlpha(40)),
            ),
            child: Row(
              children: [
                Icon(Icons.camera_alt_outlined, color: AppTheme.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠️ لا توجد Snapshot وصفة لهذه الشحنة بعد',
                          style: TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      const SizedBox(height: 4),
                      Text('سيتم إنشاء Snapshot تلقائياً عند حفظ الشحنة. يمكنك إنشاؤه يدوياً الآن.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo')),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    try {
                      await RecipeSnapshotService().createSnapshot(int.parse(s.id!));
                      if (!mounted) return;
                      setState(() => _snapshotsLoaded = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ تم إنشاء Snapshot الوصفة'), backgroundColor: AppTheme.success),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('⚠️ فشل إنشاء Snapshot: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warning.withAlpha(50)),
                    ),
                    child: Text('إنشاء Snapshot',
                        style: TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  ),
                ),
              ],
            ),
          );
        }

        final totalCost = snapshots.fold(0.0, (s, r) => s + r.totalCost);
        final recipeName = snapshots.first.recipeName ?? 'وصفة التعبئة';
        final createdAt = snapshots.first.createdAt;
        final createdDateStr = createdAt != null ? AppUtils.formatDate(createdAt) : '—';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الوصفة المستخدمة: $recipeName',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo')),
                  const SizedBox(height: 2),
                  Text('${snapshots.length} مادة | إصدار ${snapshots.first.recipeVersion} | $createdDateStr',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'Cairo')),
                  const SizedBox(height: 2),
                  Text('التكلفة: ${AppUtils.formatNumber(totalCost)} ${AppUtils.currencySymbol(s.currencyCode)}',
                      style: TextStyle(color: AppTheme.success, fontSize: 10, fontFamily: 'Cairo')),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showRecipeSnapshotDialog(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(50)),
                ),
                child: const Text('عرض Snapshot',
                    style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmRecreateSnapshot(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warning.withAlpha(50)),
                ),
                child: Text('إعادة إنشاء',
                    style: TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _openCommercialInvoice(ExportShipmentModel s) async {
    if (_isDocLoading) return;
    setState(() => _isDocLoading = true);
    try {
      final items = await ExportShipmentItemDao().getByShipmentId(s.id!);
      if (context.mounted) {
        await CommercialInvoicePdfService.previewCommercialInvoice(
          context: context,
          shipment: s,
          items: items,
        );
      }
    } catch (_) {}
    if (context.mounted) setState(() => _isDocLoading = false);
  }

  void _openPackingList(ExportShipmentModel s) async {
    if (_isDocLoading) return;
    setState(() => _isDocLoading = true);
    try {
      final items = await ExportShipmentItemDao().getByShipmentId(s.id!);
      if (context.mounted) {
        await PackingListPdfService.previewPackingList(
          context: context,
          shipment: s,
          items: items,
        );
      }
    } catch (_) {}
    if (context.mounted) setState(() => _isDocLoading = false);
  }

  Future<void> _loadRecipeSnapshots(ExportShipmentModel s) async {
    if (_snapshotsLoaded) return;
    try {
      final snapshots = await ShipmentRecipeSnapshotDao().getByShipment(int.parse(s.id!));
      if (!mounted) return;
      setState(() {
        _recipeSnapshots = snapshots;
        _snapshotsLoaded = true;
        _snapshotTotalCost = snapshots.fold(0.0, (sum, r) => sum + r.totalCost);
      });
    } catch (_) {}
  }

  Future<void> _showRecipeSnapshotDialog(ExportShipmentModel s) async {
    await _loadRecipeSnapshots(s);
    if (!mounted) return;
    if (_recipeSnapshots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد Snapshot وصفة لهذه الشحنة'), backgroundColor: AppTheme.warning),
      );
      return;
    }
    final recipeName = _recipeSnapshots.first.recipeName ?? '—';
    final grade = _recipeSnapshots.first.grade ?? '—';
    final version = _recipeSnapshots.first.recipeVersion;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xCC05192D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppTheme.glassBorder)),
          title: Row(children: [
            const Icon(Icons.receipt_long, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('$recipeName ($grade) — إصدار $version',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Cairo'))),
          ]),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إجمالي التكلفة: ${AppUtils.formatNumber(_snapshotTotalCost)} ${AppUtils.currencySymbol(s.currencyCode)}',
                      style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0x1AFFFFFF)),
                      border: TableBorder.all(color: AppTheme.glassBorder, width: 0.5),
                      columnSpacing: 12,
                      columns: const [
                        DataColumn(label: Text('المادة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataColumn(label: Text('الوحدة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataColumn(label: Text('لكل كرتونة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataColumn(label: Text('سعر الوحدة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataColumn(label: Text('الإجمالي', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataColumn(label: Text('التكلفة', style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                      ],
                      rows: _recipeSnapshots.map((r) => DataRow(cells: [
                        DataCell(Text(r.materialName ?? '—', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataCell(Text(r.unit ?? '—', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataCell(Text(r.quantityPerCarton.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataCell(Text('${r.unitCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataCell(Text('${r.totalQuantity.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
                        DataCell(Text('${r.totalCost.toStringAsFixed(2)} ${AppUtils.currencySymbol(s.currencyCode)}', style: const TextStyle(color: AppTheme.success, fontSize: 11, fontFamily: 'Cairo'))),
                      ])).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق', style: TextStyle(color: AppTheme.textSecondary))),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRecreateSnapshot(ExportShipmentModel s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('إعادة إنشاء Snapshot', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد؟ سيتم إعادة إنشاء Snapshot الوصفة للشحنة ${s.shipmentNo} بناءً على أحدث بيانات الوصفة.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await RecipeSnapshotService().createSnapshot(int.parse(s.id!));
      if (!mounted) return;
      setState(() => _snapshotsLoaded = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إعادة إنشاء Snapshot الوصفة'), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ فشل إعادة إنشاء Snapshot: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _openCosting(ExportShipmentModel s) {
    if (_isDocLoading) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentCostBreakdownPage(shipmentId: int.parse(s.id!)),
      ),
    );
  }

  void _openShipmentInvoice(ExportShipmentModel s) {
    if (_isDocLoading) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentInvoicePreviewPage(shipmentId: int.parse(s.id!)),
      ),
    );
  }

  void _openPrepCenterInvoice(ExportShipmentModel s) {
    if (_isDocLoading) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreparationCenterInvoiceScreen(shipmentId: int.parse(s.id!)),
      ),
    );
  }

  void _confirmDelete(ExportShipmentModel s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('حذف الشحنة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف الشحنة ${s.shipmentNo}؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ExportShipmentCubit>().delete(s.id!);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(ExportShipmentModel s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('إلغاء الشحنة', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من إلغاء الشحنة ${s.shipmentNo}؟',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.danger.withAlpha(50)),
              ),
              child: const Text(
                'سيتم عكس جميع القيود المحاسبية:\n'
                '• رصيد العميل\n'
                '• القيود في دفتر الأستاذ\n'
                '• القيود المحاسبية (القيد المزدوج)\n'
                '• حركة الخزنة',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ExportShipmentCubit>().cancelShipment(s.id!);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
  }
}
