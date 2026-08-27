import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/packing_recipe_model.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_cost_allocation_model.dart';
import '../../data/models/shipment_recipe_snapshot_model.dart';
import '../../data/dao/packing_recipe_dao.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/shipment_cost_allocation_dao.dart';
import '../../data/dao/shipment_recipe_snapshot_dao.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/services/journal_entry_navigation_service.dart';

class PackingOrderDetailsDialog extends StatefulWidget {
  final PackingOrderModel order;
  const PackingOrderDetailsDialog({super.key, required this.order});

  @override
  State<PackingOrderDetailsDialog> createState() =>
      _PackingOrderDetailsDialogState();
}

class _PackingOrderDetailsDialogState
    extends State<PackingOrderDetailsDialog> {
  final _recipeDao = PackingRecipeDao();
  final _exportDao = ExportShipmentDao();
  final _allocationDao = ShipmentCostAllocationDao();
  final _snapshotDao = ShipmentRecipeSnapshotDao();

  bool _loading = true;
  List<PackingRecipeModel> _recipes = [];
  ExportShipmentModel? _shipment;
  List<ShipmentCostAllocationModel> _allocations = [];
  List<ShipmentRecipeSnapshotModel> _snapshots = [];

  // Recipe section state
  bool _recipeLinked = false;
  bool _snapshotsExist = false;
  double _snapshotTotalCost = 0;
  bool _recipeDeleted = false;

  // Inline materials from notes (added directly in the form, not via recipe)
  List<Map<String, dynamic>> _noteMaterials = [];
  List<Map<String, dynamic>> _noteCostItems = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final order = widget.order;
    debugPrint('=== PackingOrderDetailsDialog ===');
    debugPrint('recipeId: ${order.recipeId}');
    debugPrint('notes: ${order.notes}');
    debugPrint('fruitTypeId: ${order.fruitTypeId}');
    debugPrint('exportShipmentId: ${order.exportShipmentId}');
    debugPrint('orderNumber: ${order.orderNumber}');
    try {
      // Direct recipe link from the packing order itself (most accurate)
      if (order.recipeId != null) {
        _recipes = await _recipeDao.getByRecipeId(order.recipeId!);
        if (_recipes.isEmpty) {
          _recipeDeleted = true; // recipe was deleted from DB
        }
      } else if (order.recipeName != null && order.recipeName!.isNotEmpty) {
        _recipes = await _recipeDao.getByRecipeName(order.recipeName!);
        if (_recipes.isNotEmpty) _recipeLinked = true;
      }
      if (order.exportShipmentId != null) {
        _shipment = await _exportDao.getById(order.exportShipmentId!);
        _allocations =
            await _allocationDao.getForShipment(int.parse(order.exportShipmentId!));
        _snapshots =
            await _snapshotDao.getByShipment(int.parse(order.exportShipmentId!));
      }
      // Parse inline materials from notes (added directly in form, not via recipe)
      if (order.notes != null && order.notes!.isNotEmpty) {
        try {
          final parsed = jsonDecode(order.notes!);
          if (parsed is Map) {
            final map = parsed as Map<String, dynamic>;
            if (map.containsKey('materials') && map['materials'] is List) {
              _noteMaterials = (map['materials'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
            if (map.containsKey('cost_items') && map['cost_items'] is List) {
              _noteCostItems = (map['cost_items'] as List)
                  .whereType<Map<String, dynamic>>()
                  .toList();
            }
          }
        } catch (_) {}
      }

      _recipeLinked = order.recipeId != null
          || _shipment?.packingRecipeId != null
          || _recipes.isNotEmpty
          || _noteMaterials.isNotEmpty;
      _snapshotsExist = _snapshots.isNotEmpty;
      _snapshotTotalCost =
          _snapshots.fold(0.0, (s, r) => s + r.totalCost);
    } catch (e, st) {
      debugPrint('❌ _loadData error: $e\n$st');
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
      case 'pending':
        return AppTheme.warning;
      case 'in_progress':
        return const Color(0xFF3B82F6);
      case 'completed':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      default:
        return AppTheme.primary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
      case 'pending':
        return 'مسودة';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مؤكد';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'A':
        return AppTheme.primary;
      case 'B':
        return AppTheme.warning;
      case 'C':
        return AppTheme.danger;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: const Color(0xCC05192D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Column(children: [
              _buildHeader(order),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(children: [
                      const SizedBox(height: 8),
                      _buildSectionTitle('ملخص الإنتاج'),
                      _buildProductionSummary(order),
                      if (order.lines.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _buildSectionTitle('المنتجات والتكاليف'),
                        _buildProductsLines(order),
                      ],
                      if (order.journalEntryId != null) ...[
                        const SizedBox(height: 12),
                        _buildSectionTitle('القيد المحاسبي'),
                        _buildJournalLink(order),
                      ],
                      const SizedBox(height: 12),
                      _buildSectionTitle('وصفة التعبئة'),
                      _buildRecipeSection(order),
                      const SizedBox(height: 12),
                      _buildSectionTitle('التكاليف'),
                      _buildCostSummary(order),
                      const SizedBox(height: 12),
                      if (_shipment != null) ...[
                        _buildSectionTitle('الشحنة المرتبطة'),
                        _buildExportLink(),
                        const SizedBox(height: 12),
                      ],
                      _buildSectionTitle('ملاحظات'),
                      if (order.notes != null && order.notes!.isNotEmpty)
                        _buildNotes(order.notes!)
                      else
                        _buildEmptyNotes(),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PackingOrderModel order) {
    final statusColor = _statusColor(order.status);
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 12,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(60)),
        ),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.checklist_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              order.orderNumber,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: const Icon(
                Icons.close,
                color: AppTheme.textSecondary,
                size: 18,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _buildBadge(order.grade, _gradeColor(order.grade)),
          const Spacer(),
          if (order.createdAt != null)
            Text(
              '${order.createdAt!.year}/${order.createdAt!.month.toString().padLeft(2, '0')}/${order.createdAt!.day.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontFamily: 'Cairo',
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _glassCard(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x2805192D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withAlpha(60)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildProductionSummary(PackingOrderModel order) {
    return _glassCard(
      Column(children: [
        _infoRow('عدد الكراتين', '${order.cartonCount}'),
        if (order.soldCartons > 0) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _infoRow('تباع', '${order.soldCartons} كرتونة', valueColor: AppTheme.success),
          _infoRow('المتبقي', '${order.remainingCartons} كرتونة'),
        ],
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow(
          'الوزن الصافي',
          '${order.totalNetWeight.toStringAsFixed(1)} كجم',
          sub: '${order.netWeightPerCarton.toStringAsFixed(1)} كجم/كرتونة',
        ),
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow(
          'الوزن الإجمالي',
          '${order.totalGrossWeight.toStringAsFixed(1)} كجم',
          sub: '${order.grossWeightPerCarton.toStringAsFixed(1)} كجم/كرتونة',
        ),
        if (order.productName != null) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _infoRow('المنتج', order.productName!),
        ],
        if (order.supplierName != null) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _infoRow('المورد', order.supplierName!),
        ],
        if (order.packedAt != null) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _infoRow(
            'تاريخ التعبئة',
            '${order.packedAt!.year}/${order.packedAt!.month.toString().padLeft(2, '0')}/${order.packedAt!.day.toString().padLeft(2, '0')}',
          ),
        ],
      ]),
    );
  }

  Widget _buildProductsLines(PackingOrderModel order) {
    final snapshot = order.costSnapshot;
    return Column(
      children: [
        for (int i = 0; i < order.lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _glassCard(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${i + 1}',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.lines[i].productName.isNotEmpty
                        ? order.lines[i].productName
                        : 'منتج #${i + 1}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                if (order.lines[i].finalCost > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${order.lines[i].finalCost.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              _infoRow('الكراتين', '${order.lines[i].cartonCount}'),
              _infoRow('الوزن الصافي', '${order.lines[i].totalNetWeight.toStringAsFixed(1)} كجم'),
              const Divider(height: 12, color: AppTheme.divider),
              _infoRow('تكلفة الخام', '${order.lines[i].rawMaterialCost.toStringAsFixed(2)} ج.م'),
              if (order.lines[i].specificPackagingCost > 0)
                _infoRow('تعبئة مخصصة', '${order.lines[i].specificPackagingCost.toStringAsFixed(2)} ج.م'),
              if (order.lines[i].allocatedSharedPackaging > 0)
                _infoRow('تعبئة مشتركة', '${order.lines[i].allocatedSharedPackaging.toStringAsFixed(2)} ج.م'),
              if (order.lines[i].allocatedCostItems > 0)
                _infoRow('مصاريف محملة', '${order.lines[i].allocatedCostItems.toStringAsFixed(2)} ج.م'),
              const Divider(height: 12, color: AppTheme.divider),
              _infoRow(
                'تكلفة الوحدة (للكجم)',
                '${order.lines[i].finalUnitCost.toStringAsFixed(2)} ج.م/كجم',
                valueColor: AppTheme.accent,
              ),
            ]),
          ),
        ],
        if (snapshot != null) ...[
          const SizedBox(height: 8),
          _buildCostSnapshotSection(snapshot),
        ],
      ],
    );
  }

  Widget _buildCostSnapshotSection(dynamic snapshot) {
    Map<String, dynamic> snapMap;
    if (snapshot is Map<String, dynamic>) {
      snapMap = snapshot;
    } else if (snapshot is String) {
      try {
        snapMap = jsonDecode(snapshot) as Map<String, dynamic>;
      } catch (_) {
        return const SizedBox.shrink();
      }
    } else {
      return const SizedBox.shrink();
    }

    final calculatedAt = snapMap['calculated_at']?.toString() ?? '';
    final method = snapMap['allocation_method']?.toString() ?? '';

    return _glassCard(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.camera_alt, color: AppTheme.info, size: 16),
          const SizedBox(width: 6),
          const Text('لقطة التكلفة (Cost Snapshot)',
              style: TextStyle(
                  color: AppTheme.info,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
          const Spacer(),
          if (calculatedAt.isNotEmpty)
            Text(calculatedAt.substring(0, calculatedAt.length > 10 ? 10 : calculatedAt.length),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
        ]),
        if (method.isNotEmpty) ...[
          const SizedBox(height: 4),
          _infoRow('طريقة التوزيع', method),
        ],
      ]),
    );
  }

  Widget _buildJournalLink(PackingOrderModel order) {
    return _glassCard(
      Column(
        children: [
          _infoRow('رقم القيد', '${order.journalEntryId}'),
          if (order.reversalJournalEntryId != null)
            _infoRow(
              'قيد العكس',
              '${order.reversalJournalEntryId}',
              valueColor: AppTheme.danger,
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final journalEntryId = order.journalEntryId;
                final packingOrderId = order.id;
                debugPrint('═══════════════════════════════════════════');
                debugPrint('PackingOrderDetails: عرض القيد المحاسبي');
                debugPrint('  PackingOrder ID = $packingOrderId');
                debugPrint('  Stored JournalEntry ID = $journalEntryId');
                debugPrint('═══════════════════════════════════════════');

                String searchKey = journalEntryId ?? '';
                if (journalEntryId != null && journalEntryId.isNotEmpty) {
                  try {
                    final parsedId = int.tryParse(journalEntryId) ?? 0;
                    final jeRes = await Supabase.instance.client
                        .from('journal_entries')
                        .select('id, entry_number')
                        .eq('id', parsedId)
                        .maybeSingle();
                    if (jeRes == null && packingOrderId != null) {
                      debugPrint('  ⚠️ JE #$journalEntryId not found, searching by source_id=$packingOrderId');
                      final fallback = await Supabase.instance.client
                          .from('journal_entries')
                          .select('id, entry_number')
                          .eq('source_type', 'packing_order')
                          .eq('source_id', packingOrderId)
                          .order('id', ascending: false)
                          .maybeSingle();
                      if (fallback != null) {
                        searchKey = fallback['id'].toString();
                        debugPrint('  ✅ Found JE by source_id: id=${fallback['id']}, entry_number=${fallback['entry_number']}');
                      }
                    } else if (jeRes != null) {
                      debugPrint('  ✅ JE #$journalEntryId exists: entry_number=${jeRes['entry_number']}');
                    }
                  } catch (e) {
                    debugPrint('  ⚠️ JE lookup error: $e');
                  }
                }

                debugPrint('  Search Key Used = "$searchKey"');
                debugPrint('═══════════════════════════════════════════');

                Navigator.of(context).pop();
                if (searchKey.isNotEmpty) {
                  JournalEntryNavigationService.openById(
                    context,
                    journalEntryId: searchKey,
                  );
                }
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('عرض القيد في دفتر اليومية',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeSection(PackingOrderModel order) {
    if (_recipeDeleted) {
      return _buildDeletedRecipeCard();
    }

    if (!_recipeLinked && !_snapshotsExist && _recipes.isEmpty) {
      return _buildMissingRecipeCard();
    }

    final String title;
    final Color statusColor;
    final IconData statusIcon;
    final bool linkActive = _shipment?.packingRecipeId != null;

    if (order.recipeId != null) {
      title = 'مرتبطة';
      statusColor = AppTheme.success;
      statusIcon = Icons.check_circle;
    } else if (linkActive) {
      title = 'مرتبطة';
      statusColor = AppTheme.success;
      statusIcon = Icons.check_circle;
    } else if (_snapshotsExist) {
      title = 'مرتبطة (Snapshot)';
      statusColor = AppTheme.success;
      statusIcon = Icons.check_circle;
    } else if (_noteMaterials.isNotEmpty) {
      title = 'مواد مباشرة';
      statusColor = AppTheme.primary;
      statusIcon = Icons.inventory_2;
    } else if (_recipes.isNotEmpty) {
      title = 'وصفات متاحة (غير مرتبطة)';
      statusColor = AppTheme.warning;
      statusIcon = Icons.info_outline;
    } else {
      title = 'مفقودة';
      statusColor = AppTheme.danger;
      statusIcon = Icons.cancel;
    }

    final displaySnapshots = _snapshots;
    final displayRecipes = _recipes;
    final totalCartons = order.cartonCount;

    final snapshotRecipeName = displaySnapshots.isNotEmpty
        ? displaySnapshots.first.recipeName
        : order.recipeName;
    final snapshotVersion = displaySnapshots.isNotEmpty
        ? displaySnapshots.first.recipeVersion
        : order.recipeVersion;
    final snapshotCreated = displaySnapshots.isNotEmpty
        ? displaySnapshots.first.createdAt
        : null;

    return _glassCard(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(statusIcon, color: statusColor, size: 18),
          const SizedBox(width: 6),
          Text(title,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
          if (_shipment?.packingRecipeId != null || order.recipeId != null) ...[
            const Spacer(),
            _buildOpenRecipeButton(),
          ],
        ]),
        if (snapshotRecipeName != null) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _infoRow('اسم الوصفة', snapshotRecipeName),
          if (order.recipeId != null)
            _infoRow('معرف الوصفة', '${order.recipeId}')
          else if (_shipment?.packingRecipeId != null)
            _infoRow('معرف الوصفة', '${_shipment!.packingRecipeId}'),
          if (snapshotVersion != null)
            _infoRow('الإصدار', '$snapshotVersion'),
          if (snapshotCreated != null)
            _infoRow(
              'تاريخ الإنشاء',
              '${snapshotCreated.year}/${snapshotCreated.month.toString().padLeft(2, '0')}/${snapshotCreated.day.toString().padLeft(2, '0')}',
            ),
        ],
        if (_noteMaterials.isNotEmpty) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _buildNoteMaterialsTable(),
        ] else if (displaySnapshots.isNotEmpty) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _buildRecipeMaterialsTable(displaySnapshots, totalCartons),
        ] else if (displayRecipes.isNotEmpty) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _buildRecipeMaterialsSimple(displayRecipes, totalCartons),
        ],
        if (_noteCostItems.isNotEmpty) ...[
          const Divider(height: 16, color: AppTheme.divider),
          _buildNoteCostItemsSection(),
        ],
      ]),
    );
  }

  Widget _buildRecipeMaterialsTable(
      List<ShipmentRecipeSnapshotModel> snapshots, int cartonCount) {
    return Column(children: [
     const Row(children: [
        Expanded(
            flex: 3,
            child: Text('المادة',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
        Expanded(
            flex: 2,
            child: Text('لكل كرتونة',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
        Expanded(
            flex: 2,
            child: Text('المطلوب',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
        Expanded(
            flex: 2,
            child: Text('التكلفة',
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
      ]),
      const SizedBox(height: 4),
      ...snapshots.map((s) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text(s.materialName ?? '—',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontFamily: 'Cairo'))),
              Expanded(
                  flex: 2,
                  child: Text(
                      '${s.quantityPerCarton.toStringAsFixed(2)} ${s.unit ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Cairo'))),
              Expanded(
                  flex: 2,
                  child: Text(
                      '${s.totalQuantity.toStringAsFixed(1)} ${s.unit ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontFamily: 'Cairo'))),
              Expanded(
                  flex: 2,
                  child: Text(
                      s.totalCost > 0
                          ? '${s.totalCost.toStringAsFixed(2)} ج.م'
                          : '—',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: s.totalCost > 0
                              ? AppTheme.success
                              : AppTheme.textMuted,
                          fontSize: 12,
                          fontFamily: 'Cairo'))),
            ]),
          )),
      const Divider(height: 12, color: AppTheme.divider),
      _infoRow('إجمالي تكلفة الخامات',
          '${_snapshotTotalCost.toStringAsFixed(2)} ج.م'),
    ]);
  }

  Widget _buildRecipeMaterialsSimple(
      List<PackingRecipeModel> recipes, int cartonCount) {
    return Column(children: [
      const Row(children: [
        Expanded(
            flex: 3,
            child: Text('المادة',
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
        Expanded(
            flex: 2,
            child: Text('لكل كرتونة',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
        Expanded(
            flex: 2,
            child: Text('الإجمالي',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Cairo'))),
      ]),
      const SizedBox(height: 4),
      ...recipes.map((r) {
        final totalQty = r.quantityPerCarton * cartonCount;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(
                flex: 3,
                child: Text(r.rawMaterialName ?? '—',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontFamily: 'Cairo'))),
            Expanded(
                flex: 2,
                child: Text(
                    '${r.quantityPerCarton.toStringAsFixed(2)} ${r.unit}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontFamily: 'Cairo'))),
            Expanded(
                flex: 2,
                child: Text('${totalQty.toStringAsFixed(1)} ${r.unit}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontFamily: 'Cairo'))),
          ]),
        );
      }),
    ]);
  }

  Widget _buildNoteMaterialsTable() {
    final totalCost = _noteMaterials.fold<double>(
        0.0, (sum, m) => sum + ((m['total'] as num?)?.toDouble() ?? 0.0));
    return Column(children: [
      const Row(children: [
        Expanded(flex: 3, child: Text('المادة',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'))),
        Expanded(flex: 2, child: Text('الكمية',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'))),
        Expanded(flex: 2, child: Text('التكلفة',
            textAlign: TextAlign.end,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'))),
      ]),
      const SizedBox(height: 4),
      ..._noteMaterials.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(flex: 3, child: Text(m['product_name'] ?? '—',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 2, child: Text(
                  '${(m['used_qty'] as num?)?.toStringAsFixed(1) ?? '0'} وحدة',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 2, child: Text(
                  '${(m['total'] as num?)?.toStringAsFixed(2) ?? '0'} ج.م',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
            ]),
          )),
      if (_noteMaterials.length > 1) ...[
        const Divider(height: 12, color: AppTheme.divider),
        _infoRow('إجمالي الخامات', '${totalCost.toStringAsFixed(2)} ج.م'),
      ],
    ]);
  }

  Widget _buildNoteCostItemsSection() {
    final totalCost = _noteCostItems.fold<double>(
        0.0, (sum, c) => sum + ((c['total'] as num?)?.toDouble() ?? 0.0));
    return Column(children: [
      const Row(children: [
        Expanded(flex: 3, child: Text('البند',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'))),
        Expanded(flex: 2, child: Text('التكلفة',
            textAlign: TextAlign.end,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo'))),
      ]),
      const SizedBox(height: 4),
      ..._noteCostItems.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(flex: 3, child: Text(c['name'] ?? '—',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
              Expanded(flex: 2, child: Text(
                  '${(c['total'] as num?)?.toStringAsFixed(2) ?? '0'} ج.م',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontFamily: 'Cairo'))),
            ]),
          )),
      if (_noteCostItems.length > 1) ...[
        const Divider(height: 12, color: AppTheme.divider),
        _infoRow('إجمالي بنود التكلفة', '${totalCost.toStringAsFixed(2)} ج.م'),
      ],
    ]);
  }

  Widget _buildMissingRecipeCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.danger.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.danger.withAlpha(60)),
          ),
          child: const Row(children: [
             Icon(Icons.cancel, color: AppTheme.danger, size: 20),
             SizedBox(width: 10),
            Expanded(
              child: Text(
                'لا توجد وصفة تعبئة مرتبطة بهذا الأمر',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildDeletedRecipeCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.warning.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.warning.withAlpha(60)),
          ),
          child: const Row(children: [
            const Icon(Icons.warning_amber, color: AppTheme.warning, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'الوصفة المرتبطة بهذا الأمر تم حذفها',
                style: const TextStyle(
                  color: AppTheme.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildOpenRecipeButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        context.push('/packing/recipes');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withAlpha(60)),
        ),
        child: const Text(
          'فتح الوصفة',
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildCostSummary(PackingOrderModel order) {
    final cur = order.displayCurrency;
    final rate = order.displayExchangeRate;
    final toDisplay = (double baseVal) {
      if (cur == 'EGP') return baseVal.toStringAsFixed(2);
      return CurrencyConversionService.instance.fromBase(baseVal, cur, rate).toStringAsFixed(2);
    };
    final suffix = ' $cur';

    return _glassCard(
      Column(children: [
        _infoRow('تكلفة التعبئة/كرتونة', '${toDisplay(order.totalPackingCost > 0 && order.cartonCount > 0 ? order.totalPackingCost / order.cartonCount : 0)}$suffix'),
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow('إجمالي تكلفة التعبئة', '${order.totalPackingCost.toStringAsFixed(2)}$suffix'),
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow('تكلفة الفاكهة الموزعة', '${toDisplay(order.fruitCostBase > 0 ? order.fruitCostBase : order.fruitCostAllocated)}$suffix'),
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow('تكلفة الخامات الفعلية', '${toDisplay(order.materialCostBase > 0 ? order.materialCostBase : order.actualMaterialCost)}$suffix'),
        const Divider(height: 16, color: AppTheme.divider),
        _infoRow('الإجمالي بالعملة الأصلية', '${order.totalPackingCost.toStringAsFixed(2)} $cur'),
      ]),
    );
  }

  Widget _buildExportLink() {
    return _glassCard(
      Column(children: [
        Row(children: [
          Expanded(
            child: Text(
              _shipment!.shipmentNo,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              context.push('/exports/costing/${_shipment!.id.toString()}');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(60)),
              ),
              child: const Text(
                'عرض الشحنة',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Text(
            'جهة التوزيع: ',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
          Expanded(
            child: Text(
              _shipment!.customerName ?? '—',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ]),
        if (_allocations.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 8),
          ...(_allocations.take(3).map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Text(
                    'توزيع تكلفة #${a.finishedProductId}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${a.allocatedAmount.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ]),
              ))),
        ],
      ]),
    );
  }



  Widget _buildEmptyNotes() {
    return _glassCard(
      const Row(children: [
        Icon(Icons.info_outline, color: AppTheme.textMuted, size: 16),
        const SizedBox(width: 8),
        const Text(
          'لا توجد ملاحظات',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
            fontFamily: 'Cairo',
          ),
        ),
      ]),
    );
  }

  Widget _buildNotes(String notes) {
    // Try to parse as JSON (stored production data from the form page)
    try {
      final parsed = jsonDecode(notes);
      if (parsed is Map) {
        final map = parsed as Map<String, dynamic>;
        final children = <Widget>[];

        if (map.containsKey('waste_weight_kg')) {
          children.add(_infoRow('وزن الهالك',
              '${(map['waste_weight_kg'] as num).toStringAsFixed(1)} كجم'));
        }
        if (map.containsKey('grade_a_kg')) {
          children.add(_infoRow(
              'درجة A', '${(map['grade_a_kg'] as num).toStringAsFixed(1)} كجم'));
        }
        if (map.containsKey('grade_b_kg')) {
          children.add(_infoRow(
              'درجة B', '${(map['grade_b_kg'] as num).toStringAsFixed(1)} كجم'));
        }
        if (map.containsKey('grade_c_kg')) {
          children.add(_infoRow(
              'درجة C', '${(map['grade_c_kg'] as num).toStringAsFixed(1)} كجم'));
        }
        if (map.containsKey('materials') && map['materials'] is List) {
          final mats = map['materials'] as List;
          if (mats.isNotEmpty) {
            final matsText = mats.map((m) {
              final name = m is Map ? m['raw_material_name'] ?? m['name'] ?? '—' : '$m';
              return '  • $name';
            }).join('\n');
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'الخامات:\n$matsText',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ));
          }
        }
        if (map.containsKey('cost_items') && map['cost_items'] is List) {
          final items = map['cost_items'] as List;
          if (items.isNotEmpty) {
            final itemsText = items.map((c) {
              final name = c is Map ? c['cost_item_name'] ?? '—' : '$c';
              final cost = c is Map ? '${(c['cost'] as num?)?.toStringAsFixed(2) ?? ''} ج.م' : '';
              return '  • $name${cost.isNotEmpty ? ' — $cost' : ''}';
            }).join('\n');
            children.add(Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'بنود التكلفة:\n$itemsText',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
            ));
          }
        }
        if (map.containsKey('station_snapshot') && map['station_snapshot'] is Map) {
          final snap = map['station_snapshot'] as Map<String, dynamic>;
          final sp = snap['station_product'] as Map<String, dynamic>?;
          final batches = snap['batches'] as List?;
          if (sp != null && sp['product_name'] != null) {
            children.add(_infoRow('المنتج', sp['product_name'] as String));
          }
          if (batches != null && batches.isNotEmpty) {
            for (final b in batches) {
              if (b is Map) {
                if (b['supplier_name'] != null && '${b['supplier_name']}'.isNotEmpty) {
                  children.add(_infoRow('المورد', '${b['supplier_name']}'));
                }
                if (b['quantity'] != null) {
                  children.add(_infoRow('الكمية', '${(b['quantity'] as num).toStringAsFixed(1)} كجم'));
                }
              }
            }
          }
        }

        if (children.isNotEmpty) {
          return _glassCard(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ));
        }

        // JSON but no known fields — show key list instead of raw dump
        final keys = map.keys.join('، ');
        return _glassCard(
          Text(
            'بيانات إضافية: $keys',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontFamily: 'Cairo',
            ),
          ),
        );
      }
    } catch (_) {
      // Not JSON — treat as plain text
    }

    return _glassCard(
      Text(
        notes,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 13,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {String? sub, Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            fontFamily: 'Cairo',
          ),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
              ),
            ),
            if (sub != null)
              Text(
                sub,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontFamily: 'Cairo',
                ),
              ),
          ],
        ),
      ],
    );
  }
}
