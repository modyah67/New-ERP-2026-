import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(
    Endpoint(host: 'localhost', database: 'erp_staging', username: 'postgres', password: '123456', port: 5432),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  final companyId = '9aae4cab-8ee3-4bc1-8e05-990894869c2e';

  print('======================================================================');
  print('STARTING TRANSACTION: BEGIN');
  print('======================================================================');
  await conn.execute('BEGIN;');

  try {
    // ------------------------------------------------------------------------
    // CASE A: INSERT TEST CUSTOMER
    // ------------------------------------------------------------------------
    print('\n======================================================================');
    print('CASE A: INSERT TEST CUSTOMER (initial_balance=100, currency=USD, direction=DEBIT)');
    print('======================================================================');
    await conn.execute('SAVEPOINT case_a;');

    final custRes = await conn.execute('''
      INSERT INTO public.customers (name, code, initial_balance, currency, initial_balance_direction, company_type, company_id)
      VALUES ('TEST_CUSTOMER_PROBE', '125110', 100, 'USD', 'DEBIT', 'export', '$companyId')
      RETURNING id, code, name, initial_balance, currency, initial_balance_direction, account_id;
    ''');
    print('Inserted Customer:');
    print('  ID: ${custRes[0][0]} | Code: ${custRes[0][1]} | Name: ${custRes[0][2]} | InitBal: ${custRes[0][3]} ${custRes[0][4]} | Dir: ${custRes[0][5]} | Account: ${custRes[0][6]}');

    print('\n--- Query: SELECT * FROM journal_entries WHERE source_id LIKE \'customers_%\' ORDER BY id DESC LIMIT 1; ---');
    final jeA = await conn.execute('''
      SELECT id, entry_number, entry_date, source_type, source_id, description, status, company_id 
      FROM public.journal_entries 
      WHERE source_id LIKE 'customers_%' 
      ORDER BY id DESC LIMIT 1;
    ''');
    int? jeIdA;
    if (jeA.isNotEmpty) {
      jeIdA = jeA[0][0] as int;
      print('Row 1: [id: ${jeA[0][0]}, entry_number: ${jeA[0][1]}, entry_date: ${jeA[0][2]}, source_type: ${jeA[0][3]}, source_id: ${jeA[0][4]}, description: ${jeA[0][5]}, status: ${jeA[0][6]}, company_id: ${jeA[0][7]}]');
    }

    print('\n--- Query: SELECT * FROM account_ledger_entries WHERE journal_entry_id = $jeIdA; ---');
    final aleA = await conn.execute('''
      SELECT id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description 
      FROM public.account_ledger_entries 
      WHERE journal_entry_id = $jeIdA 
      ORDER BY id ASC;
    ''');
    for (int i = 0; i < aleA.length; i++) {
      print('Row ${i + 1}: [id: ${aleA[i][0]}, journal_entry_id: ${aleA[i][1]}, account_id: ${aleA[i][2]}, debit: ${aleA[i][3]}, credit: ${aleA[i][4]}, currency: ${aleA[i][5]}, base_amt: ${aleA[i][6]}, description: ${aleA[i][7]}]');
    }

    await conn.execute('ROLLBACK TO SAVEPOINT case_a;');
    print('Savepoint case_a rolled back.');

    // ------------------------------------------------------------------------
    // CASE B: INSERT NEW SHAREHOLDER WITHOUT account_id
    // ------------------------------------------------------------------------
    print('\n======================================================================');
    print('CASE B: INSERT NEW SHAREHOLDER WITHOUT account_id (usd=200, egp=0)');
    print('======================================================================');
    await conn.execute('SAVEPOINT case_b;');

    final shB = await conn.execute('''
      INSERT INTO public.shareholders (name, code, initial_balance_usd, initial_balance_egp, initial_balance_direction, company_id)
      VALUES ('شريك تجريبي جديد', '232199', 200, 0, 'CREDIT', '$companyId')
      RETURNING id;
    ''');
    final shIdB = shB[0][0];

    print('\n--- Query: SELECT account_id FROM shareholders WHERE id = \'$shIdB\'; ---');
    final checkShAcct = await conn.execute('''
      SELECT id, name, code, account_id, initial_balance_usd, initial_balance_egp 
      FROM public.shareholders 
      WHERE id = '$shIdB';
    ''');
    print('Row 1: [id: ${checkShAcct[0][0]}, name: ${checkShAcct[0][1]}, code: ${checkShAcct[0][2]}, account_id: ${checkShAcct[0][3]}, initial_usd: ${checkShAcct[0][4]}, initial_egp: ${checkShAcct[0][5]}]');

    print('\n--- Query: SELECT * FROM account_ledger_entries WHERE journal_entry_id IN (SELECT id FROM journal_entries WHERE source_id = \'shareholders_\' || \'$shIdB\'); ---');
    final aleB = await conn.execute('''
      SELECT id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description 
      FROM public.account_ledger_entries 
      WHERE journal_entry_id IN (SELECT id FROM public.journal_entries WHERE source_id = 'shareholders_$shIdB')
      ORDER BY id ASC;
    ''');
    for (int i = 0; i < aleB.length; i++) {
      print('Row ${i + 1}: [id: ${aleB[i][0]}, journal_entry_id: ${aleB[i][1]}, account_id: ${aleB[i][2]}, debit: ${aleB[i][3]}, credit: ${aleB[i][4]}, currency: ${aleB[i][5]}, base_amt: ${aleB[i][6]}, description: ${aleB[i][7]}]');
    }

    await conn.execute('ROLLBACK TO SAVEPOINT case_b;');
    print('Savepoint case_b rolled back.');

    // ------------------------------------------------------------------------
    // CASE C: UPDATE EXISTING SHAREHOLDER (عماد) WITH initial_balance_usd=1000
    // ------------------------------------------------------------------------
    print('\n======================================================================');
    print('CASE C: UPDATE EXISTING SHAREHOLDER (عماد) WITH initial_balance_usd=1000');
    print('======================================================================');
    await conn.execute('SAVEPOINT case_c;');

    await conn.execute('''
      UPDATE public.shareholders 
      SET initial_balance_usd = 1000, initial_balance_egp = 0
      WHERE name = 'عماد';
    ''');

    final emadId = '7b533e4b-70c1-4204-ae6c-bfdb73351fa6';
    print('\n--- Query: SELECT * FROM journal_entries WHERE source_id = \'shareholders_\' || \'$emadId\'; ---');
    final jeC = await conn.execute('''
      SELECT id, entry_number, entry_date, source_type, source_id, description, status 
      FROM public.journal_entries 
      WHERE source_id = 'shareholders_$emadId';
    ''');
    int? jeIdC;
    if (jeC.isNotEmpty) {
      jeIdC = jeC[0][0] as int;
      print('Row 1: [id: ${jeC[0][0]}, entry_number: ${jeC[0][1]}, entry_date: ${jeC[0][2]}, source_type: ${jeC[0][3]}, source_id: ${jeC[0][4]}, description: ${jeC[0][5]}, status: ${jeC[0][6]}]');
    }

    print('\n--- Query: SELECT * FROM account_ledger_entries WHERE journal_entry_id = $jeIdC; ---');
    final aleC = await conn.execute('''
      SELECT id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description 
      FROM public.account_ledger_entries 
      WHERE journal_entry_id = $jeIdC 
      ORDER BY id ASC;
    ''');
    print('Total rows count: ${aleC.length}');
    for (int i = 0; i < aleC.length; i++) {
      print('Row ${i + 1}: [id: ${aleC[i][0]}, journal_entry_id: ${aleC[i][1]}, account_id: ${aleC[i][2]}, debit: ${aleC[i][3]}, credit: ${aleC[i][4]}, currency: ${aleC[i][5]}, base_amt: ${aleC[i][6]}, description: ${aleC[i][7]}]');
    }

    await conn.execute('ROLLBACK TO SAVEPOINT case_c;');
    print('Savepoint case_c rolled back.');

    // ------------------------------------------------------------------------
    // CASE D: INSERT TEST SUPPLIER
    // ------------------------------------------------------------------------
    print('\n======================================================================');
    print('CASE D: INSERT TEST SUPPLIER (initial_balance=250, direction=CREDIT)');
    print('======================================================================');
    await conn.execute('SAVEPOINT case_d;');

    final supD = await conn.execute('''
      INSERT INTO public.suppliers (name, code, supplier_code, initial_balance, initial_balance_direction, account_id, company_id)
      VALUES ('TEST_SUPPLIER_TRIGGER_PROBE', '211110', '211110', 250, 'CREDIT', 5104, '$companyId')
      RETURNING id, code, name, initial_balance, initial_balance_direction, account_id;
    ''');
    final supIdD = supD[0][0];
    print('Inserted Supplier:');
    print('  ID: $supIdD | Code: ${supD[0][1]} | Name: ${supD[0][2]} | InitBal: ${supD[0][3]} | Dir: ${supD[0][4]} | Account: ${supD[0][5]}');

    print('\n--- Query: SELECT * FROM journal_entries WHERE source_id = \'suppliers_\' || \'$supIdD\'; ---');
    final jeD = await conn.execute('''
      SELECT id, entry_number, entry_date, source_type, source_id, description, status 
      FROM public.journal_entries 
      WHERE source_id = 'suppliers_$supIdD';
    ''');
    int? jeIdD;
    if (jeD.isNotEmpty) {
      jeIdD = jeD[0][0] as int;
      print('Row 1: [id: ${jeD[0][0]}, entry_number: ${jeD[0][1]}, entry_date: ${jeD[0][2]}, source_type: ${jeD[0][3]}, source_id: ${jeD[0][4]}, description: ${jeD[0][5]}, status: ${jeD[0][6]}]');
    }

    print('\n--- Query: SELECT * FROM account_ledger_entries WHERE journal_entry_id = $jeIdD; ---');
    final aleD = await conn.execute('''
      SELECT id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description 
      FROM public.account_ledger_entries 
      WHERE journal_entry_id = $jeIdD 
      ORDER BY id ASC;
    ''');
    print('Total rows count: ${aleD.length}');
    for (int i = 0; i < aleD.length; i++) {
      print('Row ${i + 1}: [id: ${aleD[i][0]}, journal_entry_id: ${aleD[i][1]}, account_id: ${aleD[i][2]}, debit: ${aleD[i][3]}, credit: ${aleD[i][4]}, currency: ${aleD[i][5]}, base_amt: ${aleD[i][6]}, description: ${aleD[i][7]}]');
    }

    await conn.execute('ROLLBACK TO SAVEPOINT case_d;');
    print('Savepoint case_d rolled back.');

    // ------------------------------------------------------------------------
    // CASE E: INSERT TEST TRANSPORT SUPPLIER
    // ------------------------------------------------------------------------
    print('\n======================================================================');
    print('CASE E: INSERT TEST TRANSPORT SUPPLIER (initial_balance=300, direction=CREDIT)');
    print('======================================================================');
    await conn.execute('SAVEPOINT case_e;');

    final tsE = await conn.execute('''
      INSERT INTO public.transport_suppliers (name, code, initial_balance, initial_balance_direction, company_id)
      VALUES ('مورد نقل تجريبي', '99001', 300, 'CREDIT', '$companyId')
      RETURNING id, code, name, initial_balance, initial_balance_direction, account_id;
    ''');
    final tsIdE = tsE[0][0];
    print('Inserted Transport Supplier:');
    print('  ID: $tsIdE | Code: ${tsE[0][1]} | Name: ${tsE[0][2]} | InitBal: ${tsE[0][3]} | Dir: ${tsE[0][4]} | Account: ${tsE[0][5]}');

    print('\n--- Query: SELECT * FROM journal_entries WHERE source_id = \'transport_suppliers_\' || \'$tsIdE\'; ---');
    final jeE = await conn.execute('''
      SELECT id, entry_number, entry_date, source_type, source_id, description, status 
      FROM public.journal_entries 
      WHERE source_id = 'transport_suppliers_$tsIdE';
    ''');
    int? jeIdE;
    if (jeE.isNotEmpty) {
      jeIdE = jeE[0][0] as int;
      print('Row 1: [id: ${jeE[0][0]}, entry_number: ${jeE[0][1]}, entry_date: ${jeE[0][2]}, source_type: ${jeE[0][3]}, source_id: ${jeE[0][4]}, description: ${jeE[0][5]}, status: ${jeE[0][6]}]');
    }

    print('\n--- Query: SELECT * FROM account_ledger_entries WHERE journal_entry_id = $jeIdE; ---');
    final aleE = await conn.execute('''
      SELECT id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description 
      FROM public.account_ledger_entries 
      WHERE journal_entry_id = $jeIdE 
      ORDER BY id ASC;
    ''');
    print('Total rows count: ${aleE.length}');
    for (int i = 0; i < aleE.length; i++) {
      print('Row ${i + 1}: [id: ${aleE[i][0]}, journal_entry_id: ${aleE[i][1]}, account_id: ${aleE[i][2]}, debit: ${aleE[i][3]}, credit: ${aleE[i][4]}, currency: ${aleE[i][5]}, base_amt: ${aleE[i][6]}, description: ${aleE[i][7]}]');
    }

    await conn.execute('ROLLBACK TO SAVEPOINT case_e;');
    print('Savepoint case_e rolled back.');

  } finally {
    print('\n======================================================================');
    print('EXECUTING FINAL ROLLBACK: ALL TEST DATA DISCARDED');
    print('======================================================================');
    await conn.execute('ROLLBACK;');
    print('✅ Transaction fully rolled back. Database is 100% untouched.');
    await conn.close();
  }
}
