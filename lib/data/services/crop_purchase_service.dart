import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/crop_purchase_dao.dart';
import '../dao/fruit_type_dao.dart';
import '../models/fruit_type_model.dart';
import '../models/crop_purchase_model.dart';

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
}
