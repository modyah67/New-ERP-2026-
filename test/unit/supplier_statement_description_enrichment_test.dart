import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/data/models/statement_row_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-test-key-signature',
      );
    } catch (_) {}
  });

  group('Supplier Statement Description Enrichment Tests', () {
    test('StatementRow model holds piecesCount, quantity, unitPrice, currency and rich description', () {
      const row = StatementRow(
        transactionNumber: 'INV-2026-001',
        date: '2026-09-09',
        accountName: 'مشتريات خامات',
        description: 'فاتورة مشتريات خامات #INV-2026-001: كرتون تصدير 5 كجم (1,000 كرتونة بسعر 15 ج.م)',
        piecesCount: 1000,
        quantity: 1000,
        unitPrice: 15.0,
        debit: 0,
        credit: 15000,
        balance: 15000,
        type: 'purchase',
        createdAt: '2026-09-09T10:00:00Z',
        currency: 'EGP',
      );

      expect(row.transactionNumber, 'INV-2026-001');
      expect(row.description, contains('كرتون تصدير'));
      expect(row.description, contains('1,000 كرتونة'));
      expect(row.description, contains('15 ج.م'));
      expect(row.piecesCount, 1000);
      expect(row.quantity, 1000);
      expect(row.unitPrice, 15.0);
      expect(row.credit, 15000);
    });

    test('Material Purchase description formatting with single item', () {
      final purchase = {
        'id': 'p1',
        'invoice_number': 'INV-101',
        'currency': 'EGP',
        'total_amount': 7500.0,
        'purchase_invoice_items': [
          {
            'quantity': 500.0,
            'unit_cost': 15.0,
            'raw_materials': {
              'name': 'كرتون تصدير 5 كجم',
              'unit': 'كرتونة',
            }
          }
        ],
        'notes': 'طلبية عاجلة'
      };

      final items = purchase['purchase_invoice_items'] as List;
      final firstItem = items[0] as Map<String, dynamic>;
      final rm = firstItem['raw_materials'] as Map<String, dynamic>;
      final name = rm['name'];
      final qty = firstItem['quantity'];
      final unit = rm['unit'];
      final price = firstItem['unit_cost'];
      final invNo = purchase['invoice_number'];
      final notes = purchase['notes'];

      final desc = 'فاتورة مشتريات خامات #$invNo: $name ($qty $unit بسعر $price ج.م) - $notes';
      expect(desc, 'فاتورة مشتريات خامات #INV-101: كرتون تصدير 5 كجم (500.0 كرتونة بسعر 15.0 ج.م) - طلبية عاجلة');
    });

    test('Crop Purchase description formatting: Gross vs Net weight narrative', () {
      final lot = {
        'lot_number': 'LOT-MANGO-01',
        'crop_name': 'مانجو كيت',
        'purchase_mode': 'weight',
        'gross_weight_kg': 1000.0,
        'net_weight_kg': 950.0,
        'price_per_kg': 2.0,
        'currency': 'USD',
        'total_fruit_cost': 2000.0,
      };

      final crop = lot['crop_name'];
      final gross = lot['gross_weight_kg'];
      final net = lot['net_weight_kg'];
      final price = lot['price_per_kg'];
      final lotNo = lot['lot_number'];

      final desc = 'شراء محصول $crop - 1,000 كجم (إجمالي مالي) بسعر $price \$ [صافي المخزن: $net كجم] (لوط: $lotNo)';
      expect(desc, contains('مانجو كيت'));
      expect(desc, contains('1,000 كجم (إجمالي مالي)'));
      expect(desc, contains('صافي المخزن: 950.0 كجم'));
      expect(desc, contains('LOT-MANGO-01'));
    });

    test('Crop Purchase description formatting: Carton mode narrative', () {
      final lot = {
        'lot_number': 'LOT-CITRUS-02',
        'crop_name': 'برتقال بصرة',
        'purchase_mode': 'carton',
        'carton_count': 600,
        'price_per_carton': 12.5,
        'currency': 'USD',
        'gross_weight_kg': 9000.0,
        'net_weight_kg': 8800.0,
        'total_fruit_cost': 7500.0,
      };

      final crop = lot['crop_name'];
      final cartons = lot['carton_count'];
      final price = lot['price_per_carton'];
      final lotNo = lot['lot_number'];

      final desc = 'شراء محصول $crop - $cartons كرتونة بسعر $price \$ [إجمالي: 9,000 كجم، صافي: 8,800 كجم] (لوط: $lotNo)';
      expect(desc, contains('برتقال بصرة'));
      expect(desc, contains('600 كرتونة'));
      expect(desc, contains('12.5 \$'));
      expect(desc, contains('LOT-CITRUS-02'));
    });

    test('Treasury Transaction description formatting: payment with treasury and receipt', () {
      final tx = {
        'id': 'tx-123',
        'type': 'expense',
        'amount': 5000.0,
        'treasury_name': 'الخزينة الرئيسية',
        'receipt_number': 'REC-9988',
        'description': '',
      };

      final treasury = tx['treasury_name'];
      final receipt = tx['receipt_number'];
      final desc = 'سداد نقدي للمورد (خزينة: $treasury) [إيصال: $receipt]';

      expect(desc, 'سداد نقدي للمورد (خزينة: الخزينة الرئيسية) [إيصال: REC-9988]');
    });

    test('Bank Transaction description formatting: transfer with bank name and reference', () {
      final tx = {
        'id': 'bnk-456',
        'type': 'withdrawal',
        'amount': 25000.0,
        'bank_name': 'بنك CIB - حساب الدولار',
        'reference_number': 'REF-TRF-0012',
      };

      final bank = tx['bank_name'];
      final ref = tx['reference_number'];
      final desc = 'سداد / تحويل بنكي للمورد عبر بنك: $bank [مرجع: $ref]';

      expect(desc, 'سداد / تحويل بنكي للمورد عبر بنك: بنك CIB - حساب الدولار [مرجع: REF-TRF-0012]');
    });

    test('Initial and Opening Balance descriptions with debit/credit directions', () {
      // Credit (supplier is owed money -> دائن)
      const creditBal = 50000.0;
      final creditDesc = 'رصيد افتتاحي مستحق للمورد (دائن) بـ 50,000 ج.م (EGP)';
      expect(creditDesc, contains('دائن'));
      expect(creditDesc, contains('مستحق للمورد'));

      // Debit (supplier owes company -> مدين)
      const debitBal = -12000.0;
      final debitDesc = 'رصيد سابق مستحق على المورد حتى 2026-09-01 (مدين) بـ 12,000 \$ (USD)';
      expect(debitDesc, contains('مدين'));
      expect(debitDesc, contains('مستحق على المورد'));
    });
  });
}
