CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()
RETURNS TABLE (
  supplier_id uuid,
  true_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    s.id,
    (
      (CASE WHEN s.initial_balance_direction = 'CREDIT' THEN s.initial_balance ELSE -s.initial_balance END)
      + COALESCE((SELECT SUM(total_amount) FROM purchase_invoices WHERE supplier_id = s.id), 0)
      + COALESCE((SELECT SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END) FROM ledger_entries WHERE entity_type = 'supplier' AND entity_id = s.id::text), 0)
    ) AS true_balance
  FROM suppliers s;
$$;

GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated;
