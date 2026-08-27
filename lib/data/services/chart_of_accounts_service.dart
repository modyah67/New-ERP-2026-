import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChartOfAccountsService {
  final _client = Supabase.instance.client;

  static const defaultAccounts = [
    {'account_code': '1000', 'name': 'Cash', 'account_name': 'الصندوق', 'account_type': 'asset'},
    {'account_code': '1010', 'name': 'Bank', 'account_name': 'البنك', 'account_type': 'asset'},
    {'account_code': '1020', 'name': 'Accounts Receivable', 'account_name': 'العملاء (مدينون)', 'account_type': 'asset'},
    {'account_code': '1030', 'name': 'Produce Inventory', 'account_name': 'مخزون المحاصيل', 'account_type': 'asset'},
    {'account_code': '1031', 'name': 'Finished Goods Inventory', 'account_name': 'مخزون الإنتاج التام', 'account_type': 'asset'},
    {'account_code': '1040', 'name': 'Packaging Materials Inventory', 'account_name': 'مخزون مواد التعبئة والتغليف', 'account_type': 'asset'},
    {'account_code': '1050', 'name': 'Export Expenses', 'account_name': 'مصروفات التصدير', 'account_type': 'expense'},
    {'account_code': '2000', 'name': 'Accounts Payable', 'account_name': 'الموردون (دائنون)', 'account_type': 'liability'},
    {'account_code': '2100', 'name': 'Other Current Liabilities', 'account_name': 'الخصوم المتداولة الأخرى', 'account_type': 'liability'},
    {'account_code': '2106', 'name': 'Packaging Waste Intermediary', 'account_name': 'وسيط هالك مواد التعبئة', 'account_type': 'liability'},
    {'account_code': '2107', 'name': 'Produce Waste Intermediary', 'account_name': 'وسيط هالك المحاصيل', 'account_type': 'liability'},
    {'account_code': '2120', 'name': 'Supplier Advances', 'account_name': 'دفعات مقدمة للموردين', 'account_type': 'asset'},
    {'account_code': '3000', 'name': 'Owner Equity', 'account_name': 'رأس مال المالك', 'account_type': 'equity'},
    {'account_code': '3001', 'name': 'Owner Equity - EGP', 'account_name': 'رأس مال المالك - ج.م', 'account_type': 'equity'},
    {'account_code': '3002', 'name': 'Owner Equity - USD', 'account_name': 'رأس مال المالك - دولار', 'account_type': 'equity'},
    {'account_code': '3003', 'name': 'Owner Equity - EUR', 'account_name': 'رأس مال المالك - يورو', 'account_type': 'equity'},
    {'account_code': '3004', 'name': 'Owner Equity - GBP', 'account_name': 'رأس مال المالك - جنيه إسترليني', 'account_type': 'equity'},
    {'account_code': '3900', 'name': 'Opening Balance Equity', 'account_name': 'الأرصدة الافتتاحية', 'account_type': 'equity'},
    {'account_code': '3901', 'name': 'Opening Balance Equity - EGP', 'account_name': 'الأرصدة الافتتاحية - ج.م', 'account_type': 'equity'},
    {'account_code': '3902', 'name': 'Opening Balance Equity - USD', 'account_name': 'الأرصدة الافتتاحية - دولار', 'account_type': 'equity'},
    {'account_code': '3903', 'name': 'Opening Balance Equity - EUR', 'account_name': 'الأرصدة الافتتاحية - يورو', 'account_type': 'equity'},
    {'account_code': '3904', 'name': 'Opening Balance Equity - GBP', 'account_name': 'الأرصدة الافتتاحية - إسترليني', 'account_type': 'equity'},
    {'account_code': '4000', 'name': 'Sales Revenue', 'account_name': 'إيرادات المبيعات', 'account_type': 'revenue'},
    {'account_code': '4200', 'name': 'Export Revenue', 'account_name': 'إيرادات التصدير', 'account_type': 'revenue'},
    {'account_code': '5000', 'name': 'Cost of Goods Sold', 'account_name': 'تكلفة البضاعة المباعة', 'account_type': 'expense'},
    {'account_code': '51101', 'name': 'General Expenses', 'account_name': 'مصروفات عامة', 'account_type': 'expense'},
    {'account_code': '51102', 'name': 'Produce Waste & Spoilage', 'account_name': 'هالك وفاقد المحاصيل', 'account_type': 'expense'},
    {'account_code': '51103', 'name': 'Produce Sorting & Grading', 'account_name': 'تسوية وفرز المحاصيل', 'account_type': 'expense'},
    {'account_code': '51104', 'name': 'Packaging Materials Waste', 'account_name': 'هالك وفاقد مواد التعبئة والتغليف', 'account_type': 'expense'},
    {'account_code': '6000', 'name': 'Expenses', 'account_name': 'المصروفات', 'account_type': 'expense'},
    {'account_code': '7000', 'name': 'Purchase Account', 'account_name': 'حساب المشتريات', 'account_type': 'expense'},
  ];

  /// Ensure all required accounts exist; skip if already present.
  Future<void> ensureDefaultAccounts() async {
    for (final acc in defaultAccounts) {
      try {
        final exists = await _client
            .from('accounts')
            .select('id')
            .eq('account_code', acc['account_code'] as String)
            .limit(1);
        if ((exists as List).isEmpty) {
          await _client.from('accounts').insert({
            'account_code': acc['account_code'],
            'name': acc['name'],
            'account_name': acc['account_name'],
            'type': acc['account_type'],
          });
          debugPrint('ChartOfAccounts: created account ${acc['account_code']} — ${acc['account_name']}');
        }
      } catch (e) {
        debugPrint('ChartOfAccounts: error seeding ${acc['account_code']}: $e');
      }
    }
  }

  /// Ensure the supplier advance account (2120) exists, creating it if it doesn't.
  Future<void> ensureSupplierAdvanceAccount() async {
    try {
      final exists = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '2120')
          .limit(1);
      if ((exists as List).isEmpty) {
        await _client.from('accounts').insert({
          'account_code': '2120',
          'name': 'Supplier Advances',
          'account_name': 'دفعات مقدمة للموردين',
          'type': 'asset',
        });
        debugPrint('ChartOfAccounts: created Supplier Advances account (2120)');
      }
    } catch (e) {
      debugPrint('ChartOfAccounts: error ensuring 2120: $e');
      rethrow;
    }
  }

  /// Get account ID by code. Returns null if not found.
  Future<int?> getAccountId(String code) async {
    try {
      final data = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', code)
          .maybeSingle();
      if (data == null) return null;
      final raw = data['id'];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  /// Get all accounts.
  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final data = await _client
        .from('accounts')
        .select('id, account_code, name, account_name, account_type, balance, is_active')
        .order('account_code', ascending: true);
    return (data as List).cast<Map<String, dynamic>>();
  }
}
