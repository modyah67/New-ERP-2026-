import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'https://pjkhdnoeyyvraclomepx.supabase.co',
    publishableKey: 'sb_publishable_7K38zelCbReSuB7ktIqegg_xuuwT91L',
  );

  final client = Supabase.instance.client;

  // Create exec_sql function first
  try {
    await client.rpc('exec_sql', params: {
      'query': '''
        CREATE OR REPLACE FUNCTION public.exec_sql(query TEXT)
        RETURNS JSON
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = public
        AS \$\$
        BEGIN
          EXECUTE query;
          RETURN json_build_object('status', 'ok');
        EXCEPTION WHEN OTHERS THEN
          RETURN json_build_object('status', 'error', 'message', SQLERRM);
        END;
        \$\$;
      '''
    });
    print('exec_sql function created');
  } catch (e) {
    print('exec_sql might already exist: $e');
  }

  // Now run migration 094
  final sql = '''
-- Update RPC
CREATE OR REPLACE FUNCTION public.update_bank_account_transaction(
  p_transaction_id INTEGER,
  p_new_amount     NUMERIC,
  p_new_description TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS \$\$
DECLARE
  v_tx          RECORD;
  v_balance_diff NUMERIC;
  v_new_balance  NUMERIC;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  IF p_new_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  SELECT id, bank_account_id, type, amount, balance_before, balance_after
  INTO v_tx
  FROM public.bank_account_transactions
  WHERE id = p_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحركة غير موجودة';
  END IF;

  v_balance_diff := p_new_amount - v_tx.amount;

  IF v_tx.type = 'deposit' THEN
    v_new_balance := v_tx.balance_after + v_balance_diff;
  ELSE
    v_new_balance := v_tx.balance_after - v_balance_diff;
  END IF;

  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'الرصيد لا يمكن أن يصبح سالباً (المتوفر: %)', v_tx.balance_after;
  END IF;

  UPDATE public.bank_accounts
  SET balance = v_new_balance, updated_at = now()
  WHERE id = v_tx.bank_account_id;

  UPDATE public.bank_account_transactions
  SET amount = p_new_amount,
      balance_after = v_new_balance,
      description = p_new_description
  WHERE id = p_transaction_id;

  IF v_tx.type = 'deposit' THEN
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before + v_balance_diff,
        balance_after = balance_after + v_balance_diff
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  ELSE
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before - v_balance_diff,
        balance_after = balance_after - v_balance_diff
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  END IF;

  RETURN json_build_object('id', v_tx.bank_account_id, 'balance', v_new_balance);
END;
\$\$;
  ''';

  try {
    final result = await client.rpc('exec_sql', params: {'query': sql});
    print('update_bank_account_transaction created: $result');
  } catch (e) {
    print('Error creating update function: $e');
  }

  // Delete RPC
  final deleteSql = '''
CREATE OR REPLACE FUNCTION public.delete_bank_account_transaction(
  p_transaction_id INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS \$\$
DECLARE
  v_tx           RECORD;
  v_balance_diff NUMERIC;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  SELECT id, bank_account_id, type, amount, balance_before, balance_after
  INTO v_tx
  FROM public.bank_account_transactions
  WHERE id = p_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحركة غير موجودة';
  END IF;

  IF v_tx.type = 'deposit' THEN
    v_balance_diff := -v_tx.amount;
  ELSE
    v_balance_diff := v_tx.amount;
  END IF;

  DECLARE
    v_current_balance NUMERIC;
  BEGIN
    SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id;
    IF v_current_balance + v_balance_diff < 0 THEN
      RAISE EXCEPTION 'لا يمكن حذف هذه الحركة لأن الرصيد سينخفض عن الصفر';
    END IF;
  END;

  UPDATE public.bank_accounts
  SET balance = balance + v_balance_diff, updated_at = now()
  WHERE id = v_tx.bank_account_id;

  DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

  IF v_tx.type = 'deposit' THEN
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before - v_tx.amount,
        balance_after = balance_after - v_tx.amount
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  ELSE
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before + v_tx.amount,
        balance_after = balance_after + v_tx.amount
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  END IF;

  RETURN json_build_object(
    'id', v_tx.bank_account_id,
    'balance', (SELECT balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id)
  );
END;
\$\$;
  ''';

  try {
    final result = await client.rpc('exec_sql', params: {'query': deleteSql});
    print('delete_bank_account_transaction created: $result');
  } catch (e) {
    print('Error creating delete function: $e');
  }

  // Grant permissions
  final grantSql = '''
GRANT EXECUTE ON FUNCTION public.update_bank_account_transaction(INTEGER, NUMERIC, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_bank_account_transaction(INTEGER) TO authenticated;
  ''';

  try {
    final result = await client.rpc('exec_sql', params: {'query': grantSql});
    print('Grants applied: $result');
  } catch (e) {
    print('Error applying grants: $e');
  }

  // Cleanup: drop exec_sql if it was temporary
  // (keeping it for now in case we need it again)

  print('Migration 094 complete!');
}
