import '../dao/crop_purchase_dao.dart';
import '../dao/fruit_type_dao.dart';
import '../models/fruit_type_model.dart';
import '../models/crop_purchase_model.dart';
import 'crop_purchase_calculation_service.dart';

class CropPurchaseService {
  final CropPurchaseDao _dao = CropPurchaseDao();
  final FruitTypeDao _fruitDao = FruitTypeDao();

  Future<List<CropPurchaseModel>> getAll({
    String? supplierId,
    String? fruitTypeId,
    int? year,
    int? month,
  }) {
    return _dao.getAll(
      supplierId: supplierId,
      fruitTypeId: fruitTypeId,
      year: year,
      month: month,
    );
  }

  Future<CropPurchaseModel?> getById(String id) {
    return _dao.getById(id);
  }

  Future<String> insert(CropPurchaseModel purchase) {
    return _dao.insert(purchase);
  }

  Future<void> update(CropPurchaseModel purchase) {
    return _dao.update(purchase);
  }

  Future<void> delete(String id) {
    return _dao.delete(id);
  }

  Future<String> generateReceiptNumber() {
    return _dao.generateReceiptNumber();
  }

  /// Get the latest purchase price for a specific fruit type
  Future<double?> getLatestPriceForFruit(String fruitTypeId) async {
    return _dao.getLatestPriceForFruit(fruitTypeId);
  }

  /// Get all fruit types with computed latest purchase prices
  Future<List<FruitTypeModel>> getFruitTypesWithPrices() async {
    return _fruitDao.getLatestPrices();
  }

  /// Get purchase statistics
  Future<Map<String, dynamic>> getStats() async {
    return _dao.getStats();
  }

  /// Calculate total financial liability amount credited to supplier
  double calculateTotal({
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
  }) {
    return CropPurchaseCalculationService.calculateTotalAmount(
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
    );
  }

  /// Build active formula description (e.g. 500.00 كجم (إجمالي) × 25.00 $ = 12,500.00 $)
  String buildFormula({
    required String purchaseMethod,
    int? cartonCount,
    double? pricePerCarton,
    double? grossWeightKg,
    double? netWeightKg,
    double? pricePerKg,
    required double totalAmount,
    required String currency,
  }) {
    return CropPurchaseCalculationService.buildFormulaDescription(
      purchaseMethod: purchaseMethod,
      cartonCount: cartonCount,
      pricePerCarton: pricePerCarton,
      grossWeightKg: grossWeightKg,
      netWeightKg: netWeightKg,
      pricePerKg: pricePerKg,
      totalAmount: totalAmount,
      currency: currency,
    );
  }
}
