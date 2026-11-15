import 'package:supabase/supabase.dart';
import '../lib/supabase_options.dart';

void main() async {
  print('======================================================================');
  print('  FRUITY FARMS ERP — ROOT 2 (LIABILITIES & EQUITY) LIVE SYNC');
  print('======================================================================');

  final c = SupabaseClient(
    SupabaseOptions.url,
    SupabaseOptions.anonKey,
  );

  print('1. Connecting to Supabase and authenticating...');
  final authRes = await c.auth.signInWithPassword(
    email: 'mahmoud@gmail.com',
    password: '123456',
  );
  print('✓ Authenticated as: ${authRes.user?.email} (${authRes.user?.id})');

  // Resolve company_id from existing accounts
  final sampleAcc = await c.from('accounts').select('company_id').not('company_id', 'is', null).limit(1).maybeSingle();
  final companyId = sampleAcc?['company_id'] ?? 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';
  print('✓ Active company_id: $companyId');

  // The 51 Target Accounts
  final targetAccounts = [
    // Level 1 (1)
    {'code': '2', 'name': 'Liabilities & Equity', 'ar': 'الخصوم', 'type': 'liability', 'parent': null, 'level': 1, 'leaf': false},

    // Level 2 (3)
    {'code': '21', 'name': 'Current Liabilities', 'ar': 'الخصوم المتداوله', 'type': 'liability', 'parent': '2', 'level': 2, 'leaf': false},
    {'code': '22', 'name': 'Long-Term Liabilities', 'ar': 'الإلتزامات طويله الأجل', 'type': 'liability', 'parent': '2', 'level': 2, 'leaf': false},
    {'code': '23', 'name': 'Capital & Equity', 'ar': 'راس المال وحقوق الملكيه', 'type': 'equity', 'parent': '2', 'level': 2, 'leaf': false},

    // Level 3 under 21 (3)
    {'code': '211', 'name': 'Suppliers & Notes Payable', 'ar': 'الموردين واوراق الدفع', 'type': 'liability', 'parent': '21', 'level': 3, 'leaf': false},
    {'code': '212', 'name': 'Liabilities to Government Entities', 'ar': 'التزامات لجهات حكوميه', 'type': 'liability', 'parent': '21', 'level': 3, 'leaf': false},
    {'code': '213', 'name': 'Other Credit Balances', 'ar': 'أرصده دائنه أخرى', 'type': 'liability', 'parent': '21', 'level': 3, 'leaf': false},

    // Level 4 under 211 (2)
    {'code': '2111', 'name': 'Suppliers Control', 'ar': 'الموردين', 'type': 'liability', 'parent': '211', 'level': 4, 'leaf': false},
    {'code': '2112', 'name': 'Notes Payable Control', 'ar': 'اوراق الدفع', 'type': 'liability', 'parent': '211', 'level': 4, 'leaf': false},

    // Level 5 under 2111 (3)
    {'code': '21111', 'name': 'Crop Purchase Suppliers Sub-ledger', 'ar': 'موردين محاصيل فرعي', 'type': 'liability', 'parent': '2111', 'level': 5, 'leaf': true},
    {'code': '21112', 'name': 'Local Packaging Material Suppliers', 'ar': 'موردين محليين مواد تعبئه', 'type': 'liability', 'parent': '2111', 'level': 5, 'leaf': true},
    {'code': '21113', 'name': 'Crop Purchase Suppliers', 'ar': 'موردين مشتريات محاصيل', 'type': 'liability', 'parent': '2111', 'level': 5, 'leaf': true},

    // Level 5 under 2112 (1)
    {'code': '21121', 'name': 'Notes Payable - CIB', 'ar': 'اوراق دفع البنك التجارى الدولى CIB', 'type': 'liability', 'parent': '2112', 'level': 5, 'leaf': true},

    // Level 4 under 212 (2)
    {'code': '2121', 'name': 'Taxes Control', 'ar': 'الضرائب', 'type': 'liability', 'parent': '212', 'level': 4, 'leaf': false},
    {'code': '2122', 'name': 'Social Insurance & Labor Office Control', 'ar': 'هيئه التامينات الإجتماعيه ومكتب العمل', 'type': 'liability', 'parent': '212', 'level': 4, 'leaf': false},

    // Level 5 under 2121 (6)
    {'code': '21211', 'name': 'Payroll Tax', 'ar': 'ضريبه كسب العمل', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},
    {'code': '21212', 'name': 'Withholding Tax', 'ar': 'ضريبه الخصم من الغير - الخصم والاضافه', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},
    {'code': '21213', 'name': 'VAT - Sales Tax', 'ar': 'ضريبه القيمه المضافه - المبيعات', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},
    {'code': '21214', 'name': 'Corporate Income Tax', 'ar': 'ضريبه الدخل', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},
    {'code': '21215', 'name': 'Stamp Duty Tax', 'ar': 'ضريبه الدمغه', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},
    {'code': '21216', 'name': 'Prior Years Taxes', 'ar': 'ضريبه سنوات سابقه', 'type': 'liability', 'parent': '2121', 'level': 5, 'leaf': true},

    // Level 5 under 2122 (2)
    {'code': '21221', 'name': 'Social Insurance Authority', 'ar': 'هيئه التامينات الإجتماعيه', 'type': 'liability', 'parent': '2122', 'level': 5, 'leaf': true},
    {'code': '21222', 'name': 'Labor Office', 'ar': 'مكتب العمل', 'type': 'liability', 'parent': '2122', 'level': 5, 'leaf': true},

    // Level 4 under 213 (1)
    {'code': '2131', 'name': 'Other Credit Balances Control', 'ar': 'أرصده دائنه أخرى', 'type': 'liability', 'parent': '213', 'level': 4, 'leaf': false},

    // Level 5 under 2131 (2)
    {'code': '21311', 'name': 'Accrued Expenses - Salaries', 'ar': 'مصروفات مستحقه - مرتبات', 'type': 'liability', 'parent': '2131', 'level': 5, 'leaf': true},
    {'code': '21312', 'name': 'Third Party Deposits', 'ar': 'تأمينات لصالح الغير', 'type': 'liability', 'parent': '2131', 'level': 5, 'leaf': true},

    // Level 3 under 22 (1)
    {'code': '221', 'name': 'Long Term Liabilities', 'ar': 'إلتزامات طويله الأجل', 'type': 'liability', 'parent': '22', 'level': 3, 'leaf': false},

    // Level 4 under 221 (2)
    {'code': '2211', 'name': 'Long Term Liabilities - Taxes', 'ar': 'التزمات طويله الأجل ضرائب', 'type': 'liability', 'parent': '221', 'level': 4, 'leaf': false},
    {'code': '2212', 'name': 'Accumulated Depreciation Control', 'ar': 'مجمع الإهلاك', 'type': 'liability', 'parent': '221', 'level': 4, 'leaf': false},

    // Level 5 under 2211 (1)
    {'code': '22111', 'name': 'Deferred Taxes', 'ar': 'ضرائب مؤجله', 'type': 'liability', 'parent': '2211', 'level': 5, 'leaf': true},

    // Level 5 under 2212 (6)
    {'code': '22121', 'name': 'Acc. Depr. - Land Improvements', 'ar': 'مجمع اهلاك أصول ثابته اراضي', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},
    {'code': '22122', 'name': 'Acc. Depr. - Buildings', 'ar': 'مجمع اهلاك أصول ثابته مباني', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},
    {'code': '22123', 'name': 'Acc. Depr. - Furniture & Office Equipment', 'ar': 'مجمع اهلاك أصول ثابته أثاث ومعدات مكتبيه', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},
    {'code': '22124', 'name': 'Acc. Depr. - Computers & IT', 'ar': 'مجمع اهلاك أصول ثابته اجهزه كمبيوتر', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},
    {'code': '22125', 'name': 'Acc. Depr. - Passenger Vehicles', 'ar': 'مجمع اهلاك أصول ثابته سيارات ملاكي', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},
    {'code': '22126', 'name': 'Acc. Depr. - Produce Transport Vehicles', 'ar': 'مجمع اهلاك أصول ثابته وسائل نقل المحاصيل', 'type': 'liability', 'parent': '2212', 'level': 5, 'leaf': true},

    // Level 3 under 23 (5)
    {'code': '231', 'name': 'Paid-in Capital Group', 'ar': 'رأس المال', 'type': 'equity', 'parent': '23', 'level': 3, 'leaf': false},
    {'code': '232', 'name': 'Shareholders Current Accounts Group', 'ar': 'جارى مساهمين', 'type': 'equity', 'parent': '23', 'level': 3, 'leaf': false},
    {'code': '233', 'name': 'Legal Reserve Group', 'ar': 'إحتياطي قانونى', 'type': 'equity', 'parent': '23', 'level': 3, 'leaf': false},
    {'code': '234', 'name': 'Retained Earnings Group', 'ar': 'أرباح \\ خسائر مرحله', 'type': 'equity', 'parent': '23', 'level': 3, 'leaf': false},
    {'code': '235', 'name': 'Current Year Profit / Loss Group', 'ar': 'أرباح \\ خسائر العام الحالى', 'type': 'equity', 'parent': '23', 'level': 3, 'leaf': false},

    // Level 4 under 231 (1)
    {'code': '2311', 'name': 'Paid-in Capital Control', 'ar': 'رأس المال', 'type': 'equity', 'parent': '231', 'level': 4, 'leaf': false},

    // Level 5 under 2311 (2)
    {'code': '23111', 'name': 'Issued Capital', 'ar': 'رأس المال المصدر', 'type': 'equity', 'parent': '2311', 'level': 5, 'leaf': true},
    {'code': '23112', 'name': 'Capital Increase', 'ar': 'زياده راس المال', 'type': 'equity', 'parent': '2311', 'level': 5, 'leaf': true},

    // Level 4 under 232 (1)
    {'code': '2321', 'name': 'Shareholders Current Accounts Control', 'ar': 'جارى مساهمين', 'type': 'equity', 'parent': '232', 'level': 4, 'leaf': false},

    // Level 5 under 2321 (3)
    {'code': '23211', 'name': 'Shareholder - Emad', 'ar': 'جارى أ / عماد', 'type': 'equity', 'parent': '2321', 'level': 5, 'leaf': true},
    {'code': '23212', 'name': 'Shareholder - Abdel Batin', 'ar': 'جارى أ / عبدالباطن', 'type': 'equity', 'parent': '2321', 'level': 5, 'leaf': true},
    {'code': '23213', 'name': 'Shareholder - Eslam', 'ar': 'جارى أ / اسلام', 'type': 'equity', 'parent': '2321', 'level': 5, 'leaf': true},

    // Level 4 under 233 (1)
    {'code': '2331', 'name': 'Legal Reserve Control', 'ar': 'إحتياطي قانونى', 'type': 'equity', 'parent': '233', 'level': 4, 'leaf': false},

    // Level 5 under 2331 (1)
    {'code': '23311', 'name': 'Legal Reserve', 'ar': 'إحتياطى قانونى', 'type': 'equity', 'parent': '2331', 'level': 5, 'leaf': true},

    // Level 4 under 234 (1)
    {'code': '2341', 'name': 'Retained Earnings Control', 'ar': 'أرباح \\ خسائر مرحله', 'type': 'equity', 'parent': '234', 'level': 4, 'leaf': false},

    // Level 5 under 2341 (1)
    {'code': '23411', 'name': 'Retained Earnings', 'ar': 'أرباح \\ خسائر مرحله', 'type': 'equity', 'parent': '2341', 'level': 5, 'leaf': true},

    // Level 4 under 235 (1)
    {'code': '2351', 'name': 'Current Year Profit / Loss Control', 'ar': 'أرباح \\ خسائر العام الحالى', 'type': 'equity', 'parent': '235', 'level': 4, 'leaf': false},

    // Level 5 under 2351 (1)
    {'code': '23511', 'name': 'Current Year Profit / Loss', 'ar': 'أرباح \\ خسائر العام الحالى', 'type': 'equity', 'parent': '2351', 'level': 5, 'leaf': true},
  ];

  final targetCodes = targetAccounts.map((a) => a['code'] as String).toSet();
  print('✓ Total target accounts: ${targetAccounts.length}');

  // 2. Archive legacy Root 2 accounts
  print('\n2. Archiving legacy Root 2 accounts not in the 51-account specification...');
  final existingAccounts = await c.from('accounts')
      .select('id, account_code, name, account_name, is_active')
      .like('account_code', '2%');

  int archivedCount = 0;
  for (var acc in existingAccounts) {
    final code = acc['account_code'] as String?;
    if (code != null && !targetCodes.contains(code)) {
      await c.from('accounts').update({
        'is_active': false,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', acc['id']);
      print('  Archived legacy account: $code | ${acc['account_name'] ?? acc['name']}');
      archivedCount++;
    }
  }
  print('✓ Archived $archivedCount legacy accounts.');

  // 3. Upsert target 51 accounts
  print('\n3. Upserting the 51 standard accounts...');
  final Map<String, int> codeToId = {};
  
  // Refresh existing accounts map
  final currentAccounts = await c.from('accounts')
      .select('id, account_code')
      .like('account_code', '2%');
  for (var acc in currentAccounts) {
    final code = acc['account_code'] as String?;
    if (code != null) {
      codeToId[code] = acc['id'] as int;
    }
  }

  int updatedCount = 0;
  int insertedCount = 0;

  for (final acc in targetAccounts) {
    final code = acc['code'] as String;
    final name = acc['name'] as String;
    final ar = acc['ar'] as String;
    final type = acc['type'] as String;
    final level = acc['level'] as int;
    final isLeaf = acc['leaf'] as bool;
    final sortOrder = int.tryParse(code) ?? 0;

    if (codeToId.containsKey(code)) {
      final existingId = codeToId[code]!;
      await c.from('accounts').update({
        'name': name,
        'account_name': ar,
        'account_type': type,
        'normal_balance': 'Credit',
        'level': level,
        'is_leaf': isLeaf,
        'allow_posting': isLeaf,
        'is_active': true,
        'deleted_at': null,
        'sort_order': sortOrder,
        'display_order': sortOrder,
      }).eq('id', existingId);
      updatedCount++;
    } else {
      final res = await c.from('accounts').insert({
        'account_code': code,
        'name': name,
        'account_name': ar,
        'account_type': type,
        'normal_balance': 'Credit',
        'level': level,
        'is_leaf': isLeaf,
        'allow_posting': isLeaf,
        'is_system': true,
        'is_active': true,
        'sort_order': sortOrder,
        'display_order': sortOrder,
        'company_id': companyId,
      }).select('id').single();
      final newId = res['id'] as int;
      codeToId[code] = newId;
      insertedCount++;
    }
  }
  print('✓ Upsert complete: $updatedCount updated, $insertedCount newly created.');

  // 4. Wire Parents
  print('\n4. Wiring parent-child relationships...');
  for (final acc in targetAccounts) {
    final code = acc['code'] as String;
    final parentCode = acc['parent'] as String?;
    final id = codeToId[code]!;
    final parentId = parentCode != null ? codeToId[parentCode] : null;

    await c.from('accounts').update({
      'parent_id': parentId,
    }).eq('id', id);
  }
  print('✓ Parent-child wiring complete.');

  // 5. Re-link Shareholders
  print('\n5. Re-linking shareholders in database to new accounts...');
  final emadAccId = codeToId['23211'];
  final abdelbatinAccId = codeToId['23212'];
  final eslamAccId = codeToId['23213'];

  if (emadAccId != null) {
    await c.from('shareholders').update({'account_id': emadAccId}).ilike('name', '%عماد%');
    print('  Linked عماد -> 23211 ($emadAccId)');
  }
  if (abdelbatinAccId != null) {
    await c.from('shareholders').update({'account_id': abdelbatinAccId}).ilike('name', '%عبدالباطن%');
    print('  Linked عبدالباطن -> 23212 ($abdelbatinAccId)');
  }
  if (eslamAccId != null) {
    await c.from('shareholders').update({'account_id': eslamAccId}).ilike('name', '%إسلام%');
    await c.from('shareholders').update({'account_id': eslamAccId}).ilike('name', '%اسلام%');
    print('  Linked اسلام -> 23213 ($eslamAccId)');
  }

  // 6. Rebuild recursive paths and depths
  print('\n6. Computing recursive path_codes, path_ids, and levels...');
  final allAccRaw = await c.from('accounts').select('id, account_code, parent_id');
  final allAccList = List<Map<String, dynamic>>.from(allAccRaw as List);
  final accById = {for (var a in allAccList) a['id'] as int: a};

  String getPathCodes(int id) {
    final a = accById[id];
    if (a == null) return id.toString();
    final pId = a['parent_id'] as int?;
    final code = (a['account_code'] ?? '').toString();
    if (pId == null || !accById.containsKey(pId)) return code;
    return '${getPathCodes(pId)}/$code';
  }

  String getPathIds(int id) {
    final a = accById[id];
    if (a == null) return id.toString();
    final pId = a['parent_id'] as int?;
    if (pId == null || !accById.containsKey(pId)) return id.toString();
    return '${getPathIds(pId)}/$id';
  }

  int getDepth(int id) {
    final a = accById[id];
    if (a == null) return 1;
    final pId = a['parent_id'] as int?;
    if (pId == null || !accById.containsKey(pId)) return 1;
    return getDepth(pId) + 1;
  }

  for (final acc in targetAccounts) {
    final code = acc['code'] as String;
    final id = codeToId[code]!;
    final pCodes = getPathCodes(id);
    final pIds = getPathIds(id);
    final depth = getDepth(id);

    await c.from('accounts').update({
      'path_codes': pCodes,
      'path_ids': pIds,
      'level': depth,
    }).eq('id', id);
  }
  print('✓ Paths and levels computed successfully.');

  // 7. Audit & Verification
  print('\n======================================================================');
  print('  AUDIT & VERIFICATION');
  print('======================================================================');
  final activeRoot2 = await c.from('accounts')
      .select('id, account_code, name, account_name, level, parent_id, is_leaf, allow_posting, path_codes')
      .like('account_code', '2%')
      .eq('is_active', true)
      .order('account_code');

  print('Total active accounts under Root 2: ${activeRoot2.length}');

  bool allMatched = true;
  for (final target in targetAccounts) {
    final code = target['code'] as String;
    final found = activeRoot2.firstWhere((a) => a['account_code'] == code, orElse: () => {});
    if (found.isEmpty) {
      print('❌ Missing account: $code');
      allMatched = false;
      continue;
    }
    if (found['level'] != target['level']) {
      print('❌ Level mismatch for $code: expected ${target['level']}, got ${found['level']}');
      allMatched = false;
    }
    if (found['is_leaf'] != target['leaf']) {
      print('❌ Leaf mismatch for $code: expected ${target['leaf']}, got ${found['is_leaf']}');
      allMatched = false;
    }
  }

  if (allMatched) {
    print('✅ ALL 51 ACCOUNTS PERFECTLY MATCHED IN LIVE DATABASE!');
  } else {
    print('⚠️ Some accounts did not match verification criteria.');
  }

  print('\nTree preview:');
  for (var a in activeRoot2) {
    final indent = '  ' * ((a['level'] as int) - 1);
    print('$indent${a['account_code']} | ${a['account_name']} (L${a['level']}, leaf: ${a['is_leaf']}, path: ${a['path_codes']})');
  }
}
