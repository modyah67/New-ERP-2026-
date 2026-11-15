library;

/// ═══════════════════════════════════════════════════════════════════════════
/// Packing Order Cost Variance & Comparison Data Models
///
/// Strict Accounting Rules:
/// 1. Estimated / Planned: Entered during packing order creation or editing.
/// 2. Actual: Extracted ONLY from verifiable system documents (Inventory issues,
///    confirmed Journal Entries, Supplier Accruals, Debit Notes).
/// 3. If no verifiable document exists, actualCost = null ("غير متاح").
/// 4. Payments are settlements of liabilities, NOT expenses (Payment != Expense).
/// 5. Strictly Read-Only. No side-effects or journal postings.
/// ═══════════════════════════════════════════════════════════════════════════

/// State/Status of a cost item in variance comparison.
enum PackingCostStatus {
  /// تقديري فقط - لا يوجد مستند فعلي حتى الآن
  estimatedOnly,

  /// له تكلفة فعلية جزئية
  partiallyActual,

  /// مكتمل فعلياً - مثبت بمستند محاسبي أو مخزني
  fullyActual,

  /// لا يوجد مصدر فعلي - بند تقديري بدون مسار توثيق
  noActualSource,
}

extension PackingCostStatusExt on PackingCostStatus {
  String get labelAr {
    switch (this) {
      case PackingCostStatus.estimatedOnly:
        return 'تقديري فقط';
      case PackingCostStatus.partiallyActual:
        return 'فعلي جزئي';
      case PackingCostStatus.fullyActual:
        return 'مكتمل فعلياً';
      case PackingCostStatus.noActualSource:
        return 'لا يوجد مصدر فعلي';
    }
  }
}

/// Comparison row for a single cost item in the packing order.
class PackingCostItemComparison {
  /// Name of the cost item (e.g. 'محصول خام - برتقال صيفي', 'كرتون 5 كجم', 'عمالة تحميل')
  final String name;

  /// Category ('fruit', 'material', 'labor', 'logistics', 'other')
  final String category;

  /// التكلفة التقديرية / المخططة
  final double estimatedCost;

  /// التكلفة الفعلية المثبتة بمستند (null إذا لم يتوفر مصدر موثوق)
  final double? actualCost;

  /// الفرق = الفعلي - التقديري (null إذا كان الفعلي غير متاح)
  final double? variance;

  /// نسبة الانحراف = (الفرق / التقديري) * 100
  final double? variancePercent;

  /// حالة البند
  final PackingCostStatus status;

  /// وصف المستند أو الحركة الفعلية التي أثبتت التكلفة
  final String source;

  /// سبب عدم توفر التكلفة الفعلية (إذا كان actualCost == null)
  final String? reasonNotAvailable;

  /// معرّف القيد المحاسبي في journal_entries إن وُجد لفتح المستند الأصلي
  final dynamic journalEntryId;

  /// نوع المصدر المحاسبي ('packing_order', 'packing_debit_note', 'supplier_accrual', etc.)
  final String? sourceType;

  /// معرّف المصدر
  final String? sourceId;

  /// اسم المورد المرتبط (إن وُجد)
  final String? supplierName;

  /// كمية تقديرية
  final double? estimatedQuantity;

  /// كمية فعلية مصروفة
  final double? actualQuantity;

  /// سعر الوحدة التقديري
  final double? estimatedUnitPrice;

  /// سعر الوحدة الفعلي
  final double? actualUnitPrice;

  /// وحدة القياس (كجم، كرتونة، طرد، خدمة، إلخ)
  final String? unit;

  /// إشعار خصم مطبق على هذا البند
  final double? debitNoteDiscount;

  /// معرّف بند التكلفة الأصلي في جدول packing_order_cost_items (إن وُجد)
  final int? costItemId;

  const PackingCostItemComparison({
    required this.name,
    required this.category,
    required this.estimatedCost,
    this.actualCost,
    this.variance,
    this.variancePercent,
    required this.status,
    required this.source,
    this.reasonNotAvailable,
    this.journalEntryId,
    this.sourceType,
    this.sourceId,
    this.supplierName,
    this.estimatedQuantity,
    this.actualQuantity,
    this.estimatedUnitPrice,
    this.actualUnitPrice,
    this.unit,
    this.debitNoteDiscount,
    this.costItemId,
  });

  bool get hasActualCost => actualCost != null;

  /// هل يتبع هذا البند مورد محطة؟
  bool get isStation =>
      category == 'station' ||
      category == 'station_supplier' ||
      sourceType == 'station_supplier_accrual' ||
      name.contains('محطة');

  /// هل يتبع هذا البند مورد تخصيمات؟
  bool get isDeduction =>
      category == 'deduction' ||
      category == 'deductions' ||
      sourceType == 'supplier_accrual' ||
      name.contains('تخصيم');

  /// هل هذا البند تكلفة فعلية فقط بدون تقدير مسبق (مثل بنود النقل والشحن)؟
  bool get isActualOnly =>
      !isStation &&
      !isDeduction &&
      (category == 'transport' ||
          category == 'logistics' ||
          name.contains('نقل') ||
          name.contains('شحن'));

  /// هل التكلفة الفعلية أعلى من التقديرية؟
  bool get isOverBudget => !isActualOnly && variance != null && variance! > 0.001;

  /// هل التكلفة الفعلية أقل من التقديرية؟
  bool get isUnderBudget => !isActualOnly && variance != null && variance! < -0.001;

  /// هل التكلفة الفعلية مساوية للتقديرية؟
  bool get isOnBudget => isActualOnly || (variance != null && variance!.abs() <= 0.001);
}

/// Consolidated variance report for an entire packing order.
class PackingCostVarianceReport {
  /// إجمالي التكلفة التقديرية
  final double totalEstimatedCost;

  /// إجمالي التكلفة الفعلية المتاحة (فقط للبنود التي لها مصدر فعلي مثبت)
  final double totalActualCost;

  /// إجمالي التكلفة التقديرية المقابلة للبنود الفعلية المتاحة فقط
  /// (لمقارنة عادلة وموضوعية تمنع تشويه الانحراف بسبب البنود التي لم تصرف بعد)
  final double totalEstimatedForAvailableActual;

  /// إجمالي الانحراف = إجمالي الفعلي - إجمالي التقديري المقابل
  final double totalVariance;

  /// نسبة الانحراف الإجمالية = (إجمالي الانحراف / إجمالي التقديري المقابل) * 100
  final double? variancePercent;

  /// اتجاه الانحراف: 'higher' (أعلى من المتوقع), 'lower' (أقل من المتوقع), 'equal' (متطابق), 'none' (غير محدد)
  final String direction;

  /// نسبة التغطية الفعلية = (عدد أو قيمة البنود الفعلية / إجمالي التقديري) * 100
  final double actualCoveragePercent;

  /// هل أمر التعبئة مؤكد ومرحل محاسبياً؟
  final bool isOrderConfirmed;

  /// حالة أمر التعبئة
  final String orderStatus;

  /// رقم أمر التعبئة
  final String orderNumber;

  /// معرّف القيد المحاسبي الرئيسي لأمر التعبئة
  final dynamic mainJournalEntryId;

  /// قائمة البنود المقارنة بالتفصيل
  final List<PackingCostItemComparison> items;

  /// إجمالي مبالغ إشعارات الخصم المطبقة
  final double totalDebitNotesApplied;

  const PackingCostVarianceReport({
    required this.totalEstimatedCost,
    required this.totalActualCost,
    required this.totalEstimatedForAvailableActual,
    required this.totalVariance,
    this.variancePercent,
    required this.direction,
    required this.actualCoveragePercent,
    required this.isOrderConfirmed,
    required this.orderStatus,
    required this.orderNumber,
    this.mainJournalEntryId,
    required this.items,
    this.totalDebitNotesApplied = 0.0,
  });

  /// عدد البنود التي لها تكلفة فعلية مثبتة
  int get actualItemsCount => items.where((i) => i.hasActualCost).length;

  /// إجمالي عدد البنود
  int get totalItemsCount => items.length;

  /// هل جميع البنود لها تكلفة فعلية؟
  bool get isFullyCovered => actualCoveragePercent >= 99.9;
}
