import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:accounting_system/supabase_options.dart';
import 'package:accounting_system/data/dao/supplier_dao.dart';
import 'package:accounting_system/data/dao/payment_dao.dart';

void main() {
  test('Audit Supplier 75000 Payment Recipient Lookup', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: SupabaseOptions.url,
      anonKey: SupabaseOptions.anonKey,
    );

    await Supabase.instance.client.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

    final dao = SupplierDao();
    print('Testing dao.search("75000")...');
    final res1 = await dao.search('75000');
    print('search("75000") result count: ${res1.length}');
    for (final s in res1) {
      print('  Found s: id=${s.id}, name=${s.name}, code=${s.supplierCode}, type=${s.supplierType}, cur=${s.currency}, isMulti=${s.isMultiCurrency}, outBal=${s.outstandingBalance}, curBals=${s.currentBalancesByCurrency}');
    }

    print('Testing dao.search("مورد مشترك")...');
    final res2 = await dao.search('مورد مشترك');
    print('search("مورد مشترك") result count: ${res2.length}');

    print('Testing dao.search("موردين مشتركين")...');
    final res3 = await dao.search('موردين مشتركين');
    print('search("موردين مشتركين") result count: ${res3.length}');

    print('Testing dao.search("مشترك")...');
    final res4 = await dao.search('مشترك');
    print('search("مشترك") result count: ${res4.length}');

    print('Testing dao.search("موردين المحاصيل")...');
    final res5 = await dao.search('موردين المحاصيل');
    print('search("موردين المحاصيل") result count: ${res5.length}');

    print('Testing dao.search("موردين مواد التعبئة والتغليف")...');
    final res6 = await dao.search('موردين مواد التعبئة والتغليف');
    print('search("موردين مواد التعبئة والتغليف") result count: ${res6.length}');

    print('Testing dao.search("موردين")...');
    final res7 = await dao.search('موردين');
    print('search("موردين") result count: ${res7.length}');

    print('Testing dao.search(" 75000 ")...');
    final res8 = await dao.search(' 75000 ');
    print('search(" 75000 ") result count: ${res8.length}');

    if (res1.isNotEmpty) {
      final s = res1.first;
      print('\nTesting PaymentDao().getUnpaidLiabilities("SUPPLIER", "${s.id}")...');
      try {
        final liabs = await PaymentDao().getUnpaidLiabilities('SUPPLIER', s.id!);
        print('Liabilities count: ${liabs.length}');
        for (final l in liabs) {
          print('  Liab: type=${l.liabilityType}, id=${l.liabilityId}, ref=${l.referenceNumber}, cur=${l.currency}, due=${l.dueAmount}');
        }
      } catch (e, st) {
        print('PaymentDao().getUnpaidLiabilities error: $e\n$st');
      }
    }
  });
}
