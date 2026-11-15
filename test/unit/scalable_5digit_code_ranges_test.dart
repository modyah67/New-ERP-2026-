import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/core/constants/entity_code_ranges.dart';
import 'package:accounting_system/data/models/customer_model.dart';
import 'package:accounting_system/data/models/clearing_agent_model.dart';
import 'package:accounting_system/data/models/shareholder_model.dart';
import 'package:accounting_system/data/models/supplier_model.dart';
import 'package:accounting_system/data/models/transport_supplier_model.dart';
import 'package:accounting_system/data/models/station_model.dart';
import 'package:accounting_system/data/models/shipping_company_model.dart';

void main() {
  group('Scalable 5-Digit Code Ranges - Global Catalog & Boundary Verification', () {
    test('Catalog contains all 12 designated entity categories', () {
      const categories = AppEntityCodeRanges.allRanges;
      expect(categories.length, 12);

      expect(AppEntityCodeRanges.customerRange.minCode, 12000);
      expect(AppEntityCodeRanges.customerRange.maxCode, 19999);
      expect(AppEntityCodeRanges.customerRange.capacity, 8000);

      expect(AppEntityCodeRanges.maritimeClearingRange.minCode, 20000);
      expect(AppEntityCodeRanges.maritimeClearingRange.maxCode, 24999);
      expect(AppEntityCodeRanges.maritimeClearingRange.capacity, 5000);

      expect(AppEntityCodeRanges.airClearingRange.minCode, 25000);
      expect(AppEntityCodeRanges.airClearingRange.maxCode, 29999);
      expect(AppEntityCodeRanges.airClearingRange.capacity, 5000);

      expect(AppEntityCodeRanges.shareholderRange.minCode, 30000);
      expect(AppEntityCodeRanges.shareholderRange.maxCode, 39999);
      expect(AppEntityCodeRanges.shareholderRange.capacity, 10000);

      expect(AppEntityCodeRanges.deductionsSupplierRange.minCode, 40000);
      expect(AppEntityCodeRanges.deductionsSupplierRange.maxCode, 49999);
      expect(AppEntityCodeRanges.deductionsSupplierRange.capacity, 10000);

      expect(AppEntityCodeRanges.cropSupplierRange.minCode, 50000);
      expect(AppEntityCodeRanges.cropSupplierRange.maxCode, 59999);
      expect(AppEntityCodeRanges.cropSupplierRange.capacity, 10000);

      expect(AppEntityCodeRanges.transportSupplierRange.minCode, 60000);
      expect(AppEntityCodeRanges.transportSupplierRange.maxCode, 69999);
      expect(AppEntityCodeRanges.transportSupplierRange.capacity, 10000);

      expect(AppEntityCodeRanges.packagingSupplierRange.minCode, 70000);
      expect(AppEntityCodeRanges.packagingSupplierRange.maxCode, 74999);
      expect(AppEntityCodeRanges.packagingSupplierRange.capacity, 5000);

      expect(AppEntityCodeRanges.sharedSupplierRange.minCode, 75000);
      expect(AppEntityCodeRanges.sharedSupplierRange.maxCode, 79999);
      expect(AppEntityCodeRanges.sharedSupplierRange.capacity, 5000);

      expect(AppEntityCodeRanges.warehouseStationRange.minCode, 80000);
      expect(AppEntityCodeRanges.warehouseStationRange.maxCode, 84999);
      expect(AppEntityCodeRanges.warehouseStationRange.capacity, 5000);

      expect(AppEntityCodeRanges.stationRange.minCode, 85000);
      expect(AppEntityCodeRanges.stationRange.maxCode, 89999);
      expect(AppEntityCodeRanges.stationRange.capacity, 5000);

      expect(AppEntityCodeRanges.shippingCompanyRange.minCode, 90000);
      expect(AppEntityCodeRanges.shippingCompanyRange.maxCode, 99999);
      expect(AppEntityCodeRanges.shippingCompanyRange.capacity, 10000);
    });

    test('Zero overlap / absolute separation across all 10 categories', () {
      const list = AppEntityCodeRanges.allRanges;
      for (int i = 0; i < list.length; i++) {
        for (int j = i + 1; j < list.length; j++) {
          final a = list[i];
          final b = list[j];
          final overlap = a.overlapsWith(b);
          expect(overlap, isFalse,
              reason: 'Range ${a.label} (${a.minCode}-${a.maxCode}) must not overlap with ${b.label} (${b.minCode}-${b.maxCode})');
        }
      }
    });

    test('findRangeForCode correctly identifies categories or returns null', () {
      expect(AppEntityCodeRanges.findRangeForCode(12000)?.categoryKey, 'customer');
      expect(AppEntityCodeRanges.findRangeForCode(19999)?.categoryKey, 'customer');
      expect(AppEntityCodeRanges.findRangeForCode(20000)?.categoryKey, 'maritime_clearing');
      expect(AppEntityCodeRanges.findRangeForCode(24999)?.categoryKey, 'maritime_clearing');
      expect(AppEntityCodeRanges.findRangeForCode(25000)?.categoryKey, 'air_clearing');
      expect(AppEntityCodeRanges.findRangeForCode(29999)?.categoryKey, 'air_clearing');
      expect(AppEntityCodeRanges.findRangeForCode(30000)?.categoryKey, 'shareholder');
      expect(AppEntityCodeRanges.findRangeForCode(39999)?.categoryKey, 'shareholder');
      expect(AppEntityCodeRanges.findRangeForCode(50000)?.categoryKey, 'crop');
      expect(AppEntityCodeRanges.findRangeForCode(59999)?.categoryKey, 'crop');
      expect(AppEntityCodeRanges.findRangeForCode(60000)?.categoryKey, 'transport');
      expect(AppEntityCodeRanges.findRangeForCode(69999)?.categoryKey, 'transport');
      expect(AppEntityCodeRanges.findRangeForCode(70000)?.categoryKey, 'packaging');
      expect(AppEntityCodeRanges.findRangeForCode(74999)?.categoryKey, 'packaging');
      expect(AppEntityCodeRanges.findRangeForCode(75000)?.categoryKey, 'shared');
      expect(AppEntityCodeRanges.findRangeForCode(79999)?.categoryKey, 'shared');
      expect(AppEntityCodeRanges.findRangeForCode(80000)?.categoryKey, 'sub_warehouse');
      expect(AppEntityCodeRanges.findRangeForCode(84999)?.categoryKey, 'sub_warehouse');
      expect(AppEntityCodeRanges.findRangeForCode(85000)?.categoryKey, 'station');
      expect(AppEntityCodeRanges.findRangeForCode(89999)?.categoryKey, 'station');
      expect(AppEntityCodeRanges.findRangeForCode(90000)?.categoryKey, 'shipping');
      expect(AppEntityCodeRanges.findRangeForCode(99999)?.categoryKey, 'shipping');

      expect(AppEntityCodeRanges.findRangeForCode(45000)?.categoryKey, 'deduction');
      expect(AppEntityCodeRanges.findRangeForCode(11999), isNull);
      expect(AppEntityCodeRanges.findRangeForCode(100000), isNull);
    });
  });

  group('Category-Specific Model Validation Guards', () {
    test('1. Customer Validation (12000 to 19999)', () {
      expect(CustomerModel.validateCustomerCode('12000'), isNull);
      expect(CustomerModel.validateCustomerCode('15500'), isNull);
      expect(CustomerModel.validateCustomerCode('19999'), isNull);

      expect(CustomerModel.validateCustomerCode('11999'), isNotNull);
      expect(CustomerModel.validateCustomerCode('20000'), isNotNull);
      expect(CustomerModel.validateCustomerCode(''), isNotNull);
      expect(CustomerModel.validateCustomerCode('not_num'), isNotNull);
    });

    test('2. Maritime Customs Clearance Validation (20000 to 24999)', () {
      expect(ClearingAgentModel.validateClearingAgentCode('20000', 'بحري'), isNull);
      expect(ClearingAgentModel.validateClearingAgentCode('22500', 'بحري'), isNull);
      expect(ClearingAgentModel.validateClearingAgentCode('24999', 'بحري'), isNull);

      // Must reject outside sea bounds
      expect(ClearingAgentModel.validateClearingAgentCode('19999', 'بحري'), isNotNull);
      expect(ClearingAgentModel.validateClearingAgentCode('25000', 'بحري'), isNotNull);
    });

    test('3. Air Customs Clearance Validation (25000 to 29999)', () {
      expect(ClearingAgentModel.validateClearingAgentCode('25000', 'جوي'), isNull);
      expect(ClearingAgentModel.validateClearingAgentCode('27500', 'جوي'), isNull);
      expect(ClearingAgentModel.validateClearingAgentCode('29999', 'جوي'), isNull);

      // Must reject outside air bounds
      expect(ClearingAgentModel.validateClearingAgentCode('24999', 'جوي'), isNotNull);
      expect(ClearingAgentModel.validateClearingAgentCode('30000', 'جوي'), isNotNull);
    });

    test('4. Shareholders Validation (30000 to 39999)', () {
      expect(ShareholderModel.validateShareholderCode('30000'), isNull);
      expect(ShareholderModel.validateShareholderCode('35000'), isNull);
      expect(ShareholderModel.validateShareholderCode('39999'), isNull);

      expect(ShareholderModel.validateShareholderCode('29999'), isNotNull);
      expect(ShareholderModel.validateShareholderCode('40000'), isNotNull);
    });

    test('5. Crop Suppliers Validation (50000 to 59999)', () {
      expect(SupplierModel.validateSupplierCode('50000', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('55000', 'crop'), isNull);
      expect(SupplierModel.validateSupplierCode('59999', 'crop'), isNull);

      expect(SupplierModel.validateSupplierCode('49999', 'crop'), isNotNull);
      expect(SupplierModel.validateSupplierCode('60000', 'crop'), isNotNull);
    });

    test('6. Transport Suppliers Validation (60000 to 69999)', () {
      expect(TransportSupplierModel.validateTransportCode('60000'), isNull);
      expect(TransportSupplierModel.validateTransportCode('65000'), isNull);
      expect(TransportSupplierModel.validateTransportCode('69999'), isNull);

      expect(TransportSupplierModel.validateTransportCode('59999'), isNotNull);
      expect(TransportSupplierModel.validateTransportCode('70000'), isNotNull);
    });

    test('7. Packaging Suppliers Validation (70000 to 74999)', () {
      expect(SupplierModel.validateSupplierCode('70000', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('72500', 'packaging'), isNull);
      expect(SupplierModel.validateSupplierCode('74999', 'packaging'), isNull);

      expect(SupplierModel.validateSupplierCode('69999', 'packaging'), isNotNull);
      expect(SupplierModel.validateSupplierCode('75000', 'packaging'), isNotNull);
    });

    test('8. Shared Suppliers Validation (75000 to 79999)', () {
      expect(SupplierModel.validateSupplierCode('75000', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('77500', 'shared'), isNull);
      expect(SupplierModel.validateSupplierCode('79999', 'shared'), isNull);

      expect(SupplierModel.validateSupplierCode('74999', 'shared'), isNotNull);
      expect(SupplierModel.validateSupplierCode('80000', 'shared'), isNotNull);
    });

    test('9. Stations (Sub-warehouses) Validation (80000 to 84999)', () {
      expect(StationModel.validateStationCode('80000'), isNull);
      expect(StationModel.validateStationCode('82500'), isNull);
      expect(StationModel.validateStationCode('84999'), isNull);

      expect(StationModel.validateStationCode('79999'), isNotNull);
      expect(StationModel.validateStationCode('85000'), isNotNull);
      expect(StationModel.validateStationCode('90000'), isNotNull);
    });

    test('9b. Station Suppliers Validation (85000 to 89999)', () {
      expect(SupplierModel.validateSupplierCode('85000', 'station'), isNull);
      expect(SupplierModel.validateSupplierCode('87500', 'station'), isNull);
      expect(SupplierModel.validateSupplierCode('89999', 'station'), isNull);

      expect(SupplierModel.validateSupplierCode('84999', 'station'), isNotNull);
      expect(SupplierModel.validateSupplierCode('90000', 'station'), isNotNull);
    });

    test('10. Shipping Companies Validation (90000 to 99999)', () {
      expect(ShippingCompanyModel.validateShippingCompanyCode('90000'), isNull);
      expect(ShippingCompanyModel.validateShippingCompanyCode('95000'), isNull);
      expect(ShippingCompanyModel.validateShippingCompanyCode('99999'), isNull);

      expect(ShippingCompanyModel.validateShippingCompanyCode('89999'), isNotNull);
      expect(ShippingCompanyModel.validateShippingCompanyCode('100000'), isNotNull);
    });

    test('11. Deductions Suppliers Validation (40000 to 49999)', () {
      expect(SupplierModel.validateSupplierCode('40000', 'deduction'), isNull);
      expect(SupplierModel.validateSupplierCode('45000', 'deduction'), isNull);
      expect(SupplierModel.validateSupplierCode('49999', 'deduction'), isNull);

      expect(SupplierModel.validateSupplierCode('39999', 'deduction'), isNotNull);
      expect(SupplierModel.validateSupplierCode('50000', 'deduction'), isNotNull);
    });
  });
}
