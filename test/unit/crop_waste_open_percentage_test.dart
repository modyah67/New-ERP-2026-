import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  group('Open Crop Waste Percentage Calculation Tests', () {
    test('1. Arbitrary decimal waste percentage calculation (e.g. 1.5%, 3.2%, 10%)', () {
      final ctrl = TextEditingController(text: '1.5');
      double getWastePercent() =>
          double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0.0;

      double effectiveWeight = 1000.0; // 1000 kg
      double totalPurchaseCost = 25000.0; // 25,000 EGP (25 EGP/kg)

      // 1.5% waste
      double wastePercent = getWastePercent();
      expect(wastePercent, 1.5);

      double wasteWeight = effectiveWeight * (wastePercent / 100.0);
      expect(wasteWeight, 15.0); // 15 kg

      double wasteCost = totalPurchaseCost * (wastePercent / 100.0);
      expect(wasteCost, 375.0); // 375 EGP

      double availableWeight = effectiveWeight - wasteWeight;
      expect(availableWeight, 985.0); // 985 kg

      // Change to 3.2%
      ctrl.text = '3.2';
      wastePercent = getWastePercent();
      expect(wastePercent, 3.2);

      wasteWeight = effectiveWeight * (wastePercent / 100.0);
      expect(wasteWeight, 32.0); // 32 kg

      wasteCost = totalPurchaseCost * (wastePercent / 100.0);
      expect(wasteCost, 800.0); // 800 EGP

      availableWeight = effectiveWeight - wasteWeight;
      expect(availableWeight, 968.0); // 968 kg

      // Change to 10%
      ctrl.text = '10';
      wastePercent = getWastePercent();
      expect(wastePercent, 10.0);

      wasteWeight = effectiveWeight * (wastePercent / 100.0);
      expect(wasteWeight, 100.0); // 100 kg

      wasteCost = totalPurchaseCost * (wastePercent / 100.0);
      expect(wasteCost, 2500.0); // 2,500 EGP

      availableWeight = effectiveWeight - wasteWeight;
      expect(availableWeight, 900.0); // 900 kg
    });

    test('2. Empty or 0 waste percentage results in 0 waste', () {
      final ctrl = TextEditingController(text: '');
      double getWastePercent() =>
          double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0.0;

      double effectiveWeight = 500.0;
      double totalPurchaseCost = 10000.0;

      expect(getWastePercent(), 0.0);
      double wasteWeight = effectiveWeight * (getWastePercent() / 100.0);
      expect(wasteWeight, 0.0);
      double wasteCost = totalPurchaseCost * (getWastePercent() / 100.0);
      expect(wasteCost, 0.0);
    });
  });
}

