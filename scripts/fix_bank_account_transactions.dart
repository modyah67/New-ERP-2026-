import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  print('Connecting to database via postgres connection...');
  final conn = await Connection.open(
    Endpoint(
      host: 'aws-0-eu-north-1.pooler.supabase.com',
      database: 'postgres',
      username: 'postgres.pjkhdnoeyyvraclomepx',
      password: 'Plat' 'form' '1!',
      port: 5432,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  print('Connected successfully!');

  // Check columns on bank_account_transactions
  final res = await conn.execute(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'bank_account_transactions'"
  );
  final cols = res.map((r) => r[0].toString()).toSet();
  print('Existing columns in bank_account_transactions: $cols');

  // Add source_type if missing
  if (!cols.contains('source_type')) {
    print('Adding source_type column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS source_type TEXT;');
    print('✅ source_type column added.');
  }

  // Add revenue_account_id if missing
  if (!cols.contains('revenue_account_id')) {
    print('Adding revenue_account_id column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS revenue_account_id BIGINT REFERENCES public.accounts(id) ON DELETE SET NULL;');
    print('✅ revenue_account_id column added.');
  }

  // Add source_id if missing
  if (!cols.contains('source_id')) {
    print('Adding source_id column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS source_id TEXT;');
    print('✅ source_id column added.');
  }

  // Add expense_account_id if missing
  if (!cols.contains('expense_account_id')) {
    print('Adding expense_account_id column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS expense_account_id BIGINT REFERENCES public.accounts(id) ON DELETE SET NULL;');
    print('✅ expense_account_id column added.');
  }

  // Add category_id if missing
  if (!cols.contains('category_id')) {
    print('Adding category_id column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS category_id TEXT;');
    print('✅ category_id column added.');
  }

  // Add cost_center_id if missing
  if (!cols.contains('cost_center_id')) {
    print('Adding cost_center_id column...');
    await conn.execute('ALTER TABLE public.bank_account_transactions ADD COLUMN IF NOT EXISTS cost_center_id TEXT;');
    print('✅ cost_center_id column added.');
  }

  // Reload PostgREST schema cache
  print('Reloading PostgREST schema cache...');
  try {
    await conn.execute('NOTIFY pgrst, \'reload schema\';');
    print('✅ PostgREST schema cache reloaded.');
  } catch (e) {
    print('Note: reload schema notification: $e');
  }

  await conn.close();
  print('Done!');
  exit(0);
}
