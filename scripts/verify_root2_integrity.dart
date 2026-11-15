import 'dart:io';
import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  print('======================================================================');
  print('  ROOT 2 LIABILITIES & EQUITY — FINAL VERIFICATION AUDIT');
  print('======================================================================\n');

  final c = SupabaseClient(SupabaseOptions.url, SupabaseOptions.anonKey);
  await c.auth.signInWithPassword(email: 'mahmoud@gmail.com', password: '123456');

  final expectedAccounts = [
    // Level 1
    {'code': '2', 'ar': 'الخصوم', 'level': 1, 'leaf': false, 'parent': null},
    // Level 2
    {'code': '21', 'ar': 'الخصوم المتداوله', 'level': 2, 'leaf': false, 'parent': '2'},
    {'code': '22', 'ar': 'الإلتزامات طويله الأجل', 'level': 2, 'leaf': false, 'parent': '2'},
    {'code': '23', 'ar': 'راس المال وحقوق الملكيه', 'level': 2, 'leaf': false, 'parent': '2'},
    // Level 3 under 21
    {'code': '211', 'ar': 'الموردين واوراق الدفع', 'level': 3, 'leaf': false, 'parent': '21'},
    {'code': '212', 'ar': 'التزامات لجهات حكوميه', 'level': 3, 'leaf': false, 'parent': '21'},
    {'code': '213', 'ar': 'أرصده دائنه أخرى', 'level': 3, 'leaf': false, 'parent': '21'},
    // Level 4 under 211
    {'code': '2111', 'ar': 'الموردين', 'level': 4, 'leaf': false, 'parent': '211'},
    {'code': '2112', 'ar': 'اوراق الدفع', 'level': 4, 'leaf': false, 'parent': '211'},
    // Level 5 under 2111
    {'code': '21111', 'ar': 'موردين محليين نقل', 'level': 5, 'leaf': true, 'parent': '2111'},
    {'code': '21112', 'ar': 'موردين محليين مواد تعبئه', 'level': 5, 'leaf': true, 'parent': '2111'},
    {'code': '21113', 'ar': 'موردين مشتريات محاصيل', 'level': 5, 'leaf': true, 'parent': '2111'},
    // Level 5 under 2112
    {'code': '21121', 'ar': 'اوراق دفع البنك التجارى الدولى CIB', 'level': 5, 'leaf': true, 'parent': '2112'},
    // Level 4 under 212
    {'code': '2121', 'ar': 'الضرائب', 'level': 4, 'leaf': false, 'parent': '212'},
    {'code': '2122', 'ar': 'هيئه التامينات الإجتماعيه ومكتب العمل', 'level': 4, 'leaf': false, 'parent': '212'},
    // Level 5 under 2121
    {'code': '21211', 'ar': 'ضريبه كسب العمل', 'level': 5, 'leaf': true, 'parent': '2121'},
    {'code': '21212', 'ar': 'ضريبه الخصم من الغير - الخصم والاضافه', 'level': 5, 'leaf': true, 'parent': '2121'},
    {'code': '21213', 'ar': 'ضريبه القيمه المضافه - المبيعات', 'level': 5, 'leaf': true, 'parent': '2121'},
    {'code': '21214', 'ar': 'ضريبه الدخل', 'level': 5, 'leaf': true, 'parent': '2121'},
    {'code': '21215', 'ar': 'ضريبه الدمغه', 'level': 5, 'leaf': true, 'parent': '2121'},
    {'code': '21216', 'ar': 'ضريبه سنوات سابقه', 'level': 5, 'leaf': true, 'parent': '2121'},
    // Level 5 under 2122
    {'code': '21221', 'ar': 'هيئه التامينات الإجتماعيه', 'level': 5, 'leaf': true, 'parent': '2122'},
    {'code': '21222', 'ar': 'مكتب العمل', 'level': 5, 'leaf': true, 'parent': '2122'},
    // Level 4 under 213
    {'code': '2131', 'ar': 'أرصده دائنه أخرى', 'level': 4, 'leaf': false, 'parent': '213'},
    // Level 5 under 2131
    {'code': '21311', 'ar': 'مصروفات مستحقه - مرتبات', 'level': 5, 'leaf': true, 'parent': '2131'},
    {'code': '21312', 'ar': 'تأمينات لصالح الغير', 'level': 5, 'leaf': true, 'parent': '2131'},
    // Level 3 under 22
    {'code': '221', 'ar': 'إلتزامات طويله الأجل', 'level': 3, 'leaf': false, 'parent': '22'},
    // Level 4 under 221
    {'code': '2211', 'ar': 'التزمات طويله الأجل ضرائب', 'level': 4, 'leaf': false, 'parent': '221'},
    {'code': '2212', 'ar': 'مجمع الإهلاك', 'level': 4, 'leaf': false, 'parent': '221'},
    // Level 5 under 2211
    {'code': '22111', 'ar': 'ضرائب مؤجله', 'level': 5, 'leaf': true, 'parent': '2211'},
    // Level 5 under 2212
    {'code': '22121', 'ar': 'مجمع اهلاك أصول ثابته اراضي', 'level': 5, 'leaf': true, 'parent': '2212'},
    {'code': '22122', 'ar': 'مجمع اهلاك أصول ثابته مباني', 'level': 5, 'leaf': true, 'parent': '2212'},
    {'code': '22123', 'ar': 'مجمع اهلاك أصول ثابته أثاث ومعدات مكتبيه', 'level': 5, 'leaf': true, 'parent': '2212'},
    {'code': '22124', 'ar': 'مجمع اهلاك أصول ثابته اجهزه كمبيوتر', 'level': 5, 'leaf': true, 'parent': '2212'},
    {'code': '22125', 'ar': 'مجمع اهلاك أصول ثابته سيارات ملاكي', 'level': 5, 'leaf': true, 'parent': '2212'},
    {'code': '22126', 'ar': 'مجمع اهلاك أصول ثابته وسائل نقل المحاصيل', 'level': 5, 'leaf': true, 'parent': '2212'},
    // Level 3 under 23
    {'code': '231', 'ar': 'رأس المال', 'level': 3, 'leaf': false, 'parent': '23'},
    {'code': '232', 'ar': 'جارى مساهمين', 'level': 3, 'leaf': false, 'parent': '23'},
    {'code': '233', 'ar': 'إحتياطي قانونى', 'level': 3, 'leaf': false, 'parent': '23'},
    {'code': '234', 'ar': 'أرباح \\ خسائر مرحله', 'level': 3, 'leaf': false, 'parent': '23'},
    {'code': '235', 'ar': 'أرباح \\ خسائر العام الحالى', 'level': 3, 'leaf': false, 'parent': '23'},
    // Level 4 under 231
    {'code': '2311', 'ar': 'رأس المال', 'level': 4, 'leaf': false, 'parent': '231'},
    // Level 5 under 2311
    {'code': '23111', 'ar': 'رأس المال المصدر', 'level': 5, 'leaf': true, 'parent': '2311'},
    {'code': '23112', 'ar': 'زياده راس المال', 'level': 5, 'leaf': true, 'parent': '2311'},
    // Level 4 under 232
    {'code': '2321', 'ar': 'جارى مساهمين', 'level': 4, 'leaf': false, 'parent': '232'},
    // Level 5 under 2321
    {'code': '23211', 'ar': 'جارى أ / عماد', 'level': 5, 'leaf': true, 'parent': '2321'},
    {'code': '23212', 'ar': 'جارى أ / عبدالباطن', 'level': 5, 'leaf': true, 'parent': '2321'},
    {'code': '23213', 'ar': 'جارى أ / اسلام', 'level': 5, 'leaf': true, 'parent': '2321'},
    // Level 4 under 233
    {'code': '2331', 'ar': 'إحتياطي قانونى', 'level': 4, 'leaf': false, 'parent': '233'},
    // Level 5 under 2331
    {'code': '23311', 'ar': 'إحتياطى قانونى', 'level': 5, 'leaf': true, 'parent': '2331'},
    // Level 4 under 234
    {'code': '2341', 'ar': 'أرباح \\ خسائر مرحله', 'level': 4, 'leaf': false, 'parent': '234'},
    // Level 5 under 2341
    {'code': '23411', 'ar': 'أرباح \\ خسائر مرحله', 'level': 5, 'leaf': true, 'parent': '2341'},
    // Level 4 under 235
    {'code': '2351', 'ar': 'أرباح \\ خسائر العام الحالى', 'level': 4, 'leaf': false, 'parent': '235'},
    // Level 5 under 2351
    {'code': '23511', 'ar': 'أرباح \\ خسائر العام الحالى', 'level': 5, 'leaf': true, 'parent': '2351'},
  ];

  final activeAccountsRaw = await c.from('accounts')
      .select('id, account_code, account_name, name, level, parent_id, is_leaf, allow_posting, path_codes, is_active')
      .like('account_code', '2%')
      .eq('is_active', true)
      .order('account_code');

  final activeAccounts = List<Map<String, dynamic>>.from(activeAccountsRaw as List);
  final accByCode = {for (var a in activeAccounts) a['account_code'] as String: a};
  final accById = {for (var a in activeAccounts) a['id'] as int: a};

  print('Total Active Root 2 Accounts in DB: ${activeAccounts.length} (Expected: ${expectedAccounts.length})');

  int errors = 0;

  if (activeAccounts.length != expectedAccounts.length) {
    print('❌ Account count mismatch!');
    errors++;
  }

  for (final exp in expectedAccounts) {
    final code = exp['code'] as String;
    final expAr = exp['ar'] as String;
    final expLvl = exp['level'] as int;
    final expLeaf = exp['leaf'] as bool;
    final expParent = exp['parent'] as String?;

    final actual = accByCode[code];
    if (actual == null) {
      print('❌ Missing account: $code ($expAr)');
      errors++;
      continue;
    }

    if (actual['account_name'] != expAr) {
      print('❌ Arabic name mismatch for $code: expected "$expAr", got "${actual['account_name']}"');
      errors++;
    }

    if (actual['level'] != expLvl) {
      print('❌ Level mismatch for $code: expected $expLvl, got ${actual['level']}');
      errors++;
    }

    if (actual['is_leaf'] != expLeaf) {
      print('❌ is_leaf mismatch for $code: expected $expLeaf, got ${actual['is_leaf']}');
      errors++;
    }

    if (actual['allow_posting'] != expLeaf) {
      print('❌ allow_posting mismatch for $code: expected $expLeaf, got ${actual['allow_posting']}');
      errors++;
    }

    if (expParent != null) {
      final parentId = actual['parent_id'] as int?;
      final parentAcc = parentId != null ? accById[parentId] : null;
      final actualParentCode = parentAcc?['account_code'] as String?;
      if (actualParentCode != expParent) {
        print('❌ Parent mismatch for $code: expected parent $expParent, got $actualParentCode (id: $parentId)');
        errors++;
      }
    } else {
      if (actual['parent_id'] != null) {
        print('❌ Root account $code should have NULL parent, got ${actual['parent_id']}');
        errors++;
      }
    }
  }

  // Verify Shareholders
  print('\nVerifying Shareholders linkage:');
  final shareholders = await c.from('shareholders').select('id, name, account_id');
  for (var s in shareholders) {
    final name = s['name'] as String;
    final accId = s['account_id'] as int?;
    final acc = accId != null ? accById[accId] : null;
    print('  - Shareholder "$name" -> account_id: $accId (${acc?['account_code']} | ${acc?['account_name']})');
    if (acc == null) {
      print('  ❌ Shareholder $name has invalid account_id!');
      errors++;
    }
  }

  print('\n======================================================================');
  if (errors == 0) {
    print('🎉 100% PERFECT INTEGRITY! All 54 accounts verified with 0 errors.');
    exit(0);
  } else {
    print('❌ Found $errors errors during verification.');
    exit(1);
  }
}
