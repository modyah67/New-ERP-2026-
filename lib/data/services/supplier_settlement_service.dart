import '../models/supplier_model.dart';
import '../models/purchase_model.dart';

typedef Supplier = SupplierModel;
typedef PurchaseInvoice = PurchaseModel;

class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);

  @override
  String toString() => message;
}

enum ViewType {
  supplierStatement,
  treasury,
  ledger,
}

class SupplierSettlementService {
  static final SupplierSettlementService instance = SupplierSettlementService._();
  SupplierSettlementService._();

  static const String supplierAdvanceAccountCode = '2120';

  /// Validates that payment amount does not exceed the remaining amount on the invoice.
  void validateSupplierPayment({
    required PurchaseModel? invoice,
    required double paymentAmount,
  }) {
    if (invoice != null) {
      final bool isAdvance = invoice.purchaseNumber == '—' || invoice.totalAmount == 0.0;
      if (!isAdvance) {
        final remainingBeforePayment = invoice.remainingAmount;
        if (paymentAmount > remainingBeforePayment) {
          throw ValidationException(
            'قيمة السداد ($paymentAmount) أكبر من المبلغ المستحق ($remainingBeforePayment).'
          );
        }
      }
    }
  }

  String generatePlainDescription({
    required SupplierModel supplier,
    required PurchaseModel? invoice,
    required double paymentAmount,
    required String treasuryName,
    required ViewType viewType,
  }) {
    final String paymentStatus;
    if (invoice == null || invoice.purchaseNumber == '—' || invoice.totalAmount == 0.0) {
      paymentStatus = "دفعة مقدمة للمورد";
    } else {
      final remainingBefore = invoice.remainingAmount;
      if (paymentAmount < remainingBefore) {
        paymentStatus = "سداد جزئي";
      } else if (paymentAmount == remainingBefore) {
        paymentStatus = "سداد كامل";
      } else {
        paymentStatus = "سداد زائد للمورد";
      }
    }

    switch (viewType) {
      case ViewType.supplierStatement:
      case ViewType.treasury:
        if (paymentStatus == "دفعة مقدمة للمورد") {
          return "دفعة مقدمة للمورد (${supplier.name} - ${supplier.supplierCode})\n"
              "وسيلة السداد: $treasuryName";
        } else if (paymentStatus == "سداد كامل") {
          return "سداد كامل للمورد (${supplier.name} - ${supplier.supplierCode})";
        } else {
          return "$paymentStatus للمورد (${supplier.name} - ${supplier.supplierCode})\n"
              "مرتبط بفاتورة شراء رقم ${invoice?.purchaseNumber}\n"
              "وسيلة السداد: $treasuryName";
        }

      case ViewType.ledger:
        if (paymentStatus == "دفعة مقدمة للمورد") {
          return "قيد دفعة مقدمة للمورد (${supplier.name} - ${supplier.supplierCode})\n"
              "من ح/ دفعات مقدمة للموردين\n"
              "إلى ح/ $treasuryName";
        } else if (paymentStatus == "سداد كامل") {
          return "قيد سداد كامل للمورد (${supplier.name} - ${supplier.supplierCode})\n"
              "من ح/ الموردين\n"
              "إلى ح/ $treasuryName";
        } else {
          return "قيد $paymentStatus للمورد (${supplier.name} - ${supplier.supplierCode})\n"
              "فاتورة شراء رقم: ${invoice?.purchaseNumber}\n"
              "من ح/ الموردين\n"
              "إلى ح/ $treasuryName";
        }
    }
  }

  /// Returns the description formatted for display.
  /// Currently a pass-through since descriptions are already human-readable.
  String getDisplayDescription(String description, ViewType viewType) {
    return description;
  }

  // Kept for backward compatibility but returns plain description now to avoid crash on any call
  String generateSupplierPaymentDescription({
    required Supplier supplier,
    required PurchaseInvoice invoice,
    required double paymentAmount,
    required double invoiceTotal,
    required String treasuryName,
    required ViewType viewType,
  }) {
    return generatePlainDescription(
      supplier: supplier,
      invoice: invoice,
      paymentAmount: paymentAmount,
      treasuryName: treasuryName,
      viewType: viewType,
    );
  }
}
