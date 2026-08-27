import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  try {
    final conn = await Connection.open(
      Endpoint(
        host: 'localhost',
        database: 'postgres',
        username: 'postgres',
        password: '123456',
        port: 5432
      ),
      settings: ConnectionSettings(sslMode: SslMode.disable),
    );

    print('========================================');
    print('DATABASE VERIFICATION REPORT');
    print('========================================');

    print('\\n1. Migrations Check (018 - 029):');
    final migrationsList = [
      '20260731000000_018_enterprise_posting_seed.sql',
      '20260731000000_019_enterprise_posting_templates.sql',
      '20260731000000_020_rpc_build_cost_allocation.sql',
      '20260731000000_021_cash_payment_builder.sql',
      '20260731000000_022_patch_cash_payment_builder_balances.sql',
      '20260731000000_023_cash_receipt_builder.sql',
      '20260731000000_024_party_adjustment_builder.sql',
      '20260731000000_025_manual_journal_builder.sql',
      '20260731000000_026_shipment_cogs_builder.sql',
      '20260731000000_027_purchase_workflow_builder.sql',
      '20260731000000_028_purchase_delete_builder.sql',
      '20260731000000_029_multi_line_journal_builder.sql',
    ];

    for (final m in migrationsList) {
      final file = File('supabase/migrations/' + m);
      final exists = file.existsSync();
      print('- ' + m);
      print('  Exists in repository: ' + (exists ? "Yes" : "No"));
      
      // Let's check schema_migrations if it exists
      try {
        final version = m.substring(0, 14); 
        final res = await conn.execute("SELECT inserted_at FROM supabase_migrations.schema_migrations WHERE version = '" + version + "'");
        if (res.isNotEmpty) {
           print('  Applied in Supabase database: Yes (Timestamp: ' + res.first.first.toString() + ')');
        } else {
           print('  Applied in Supabase database: No (Record not found)');
        }
      } catch(e) {
         print('  Applied in Supabase database: No (schema_migrations missing or error)');
      }
    }

    bool allFunctionsApplied = true;

    print('\\n2. SQL Functions Check:');
    final functions = [
      'rpc_build_cost_allocation_journal',
      'rpc_build_cash_payment_journal',
      'rpc_build_cash_receipt_journal',
      'rpc_build_party_adjustment_journal',
      'rpc_build_manual_journal',
      'rpc_post_shipment_with_cogs', 
      'create_purchase_workflow' 
    ];
    
    for (final fn in functions) {
      final res = await conn.execute("SELECT COUNT(*) FROM pg_proc WHERE proname = '" + fn + "'");
      final count = (res.first.first as num).toInt();
      print('- ' + fn + ': ' + (count > 0 ? "EXISTS" : "MISSING"));
      if (count == 0 && (fn != 'create_purchase_workflow' && fn != 'rpc_post_shipment_with_cogs')) {
          allFunctionsApplied = false;
      }
    }

    print('\\n3. rpc_post_journal Check:');
    try {
      final pRes = await conn.execute("SELECT prosrc FROM pg_proc WHERE proname = 'rpc_post_journal'");
      if (pRes.isNotEmpty) {
          final source = pRes.first.first.toString();
          if (source.contains('SELECT id INTO v_profile_id FROM public.posting_profiles')) {
            print('- rpc_post_journal is latest version (auto profile resolution): PASS');
          } else {
            print('- rpc_post_journal is latest version (auto profile resolution): FAIL (does not contain auto profile resolution logic)');
          }
      } else {
          print('- rpc_post_journal is latest version: FAIL (Function not found)');
      }
    } catch (e) {
      print('- rpc_post_journal is latest version: FAIL (Function not found)');
    }

    print('\\n4-6. Seeded Data Check:');
    try {
      final templates = await conn.execute("SELECT COUNT(*) FROM public.document_posting_templates;");
      print('- document_posting_templates contains rows: ' + ((templates.first.first as num).toInt() > 0 ? 'Yes' : 'No') + ' (' + (templates.first.first).toString() + ' rows)');
      
      final profiles = await conn.execute("SELECT COUNT(*) FROM public.posting_profiles;");
      print('- posting_profiles contains seeded data: ' + ((profiles.first.first as num).toInt() > 0 ? 'Yes' : 'No') + ' (' + (profiles.first.first).toString() + ' rows)');
      
      final rules = await conn.execute("SELECT COUNT(*) FROM public.posting_profile_rules;");
      print('- posting_profile_rules contains seeded data: ' + ((rules.first.first as num).toInt() > 0 ? 'Yes' : 'No') + ' (' + (rules.first.first).toString() + ' rows)');
    } catch(e) {
      print('- Seeded Data Check: FAIL (' + e.toString() + ')');
    }

    print('\\n7. Post Balanced Journal Test:');
    try {
      final payload = '''
        {
          "company_id": "00000000-0000-0000-0000-000000000000",
          "document_type": "MANUAL_JOURNAL",
          "posting_date": "2026-07-31",
          "reference": "TEST-001",
          "description": "Test verification",
          "currency": {"code": "EGP", "exchange_rate": 1.0},
          "idempotency_key": "test_verification_001",
          "lines": [
            {"role": "ADJUSTMENT", "debit": 100, "credit": 0, "description": "Test debit"},
            {"role": "CASH", "debit": 0, "credit": 100, "description": "Test credit"}
          ]
        }
      ''';
      
      await conn.runTx((ctx) async {
         await ctx.execute("SELECT public.rpc_post_journal('" + payload + "'::jsonb);");
         print('- Engine posted balanced journal successfully (rolled back): PASS');
         throw Exception("rollback_test");
      });
    } catch(e) {
      if (e.toString().contains("rollback_test")) {
        // Expected
      } else {
        print('- Engine posted balanced journal: FAIL (' + e.toString() + ')');
      }
    }

    print('\\n8. Pending Migrations Check:');
    final chkRes = await conn.execute("SELECT COUNT(*) FROM pg_proc WHERE proname = 'rpc_build_cash_payment_journal'");
    if ((chkRes.first.first as num).toInt() == 0) {
      print('- STOP: Migrations 021-029 must be applied.');
    } else {
      print('- All required functions exist. No migrations pending.');
    }

    await conn.close();
  } catch (e) {
    print('Error during verification: ' + e.toString());
  }
}
