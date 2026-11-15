SELECT s.id, s.name, b.*
FROM public.suppliers s
LEFT JOIN LATERAL public.get_supplier_true_balances_by_currency() b ON b.supplier_id = s.id
WHERE s.id = '6ea8d5c7-6a94-4155-836a-0cfed467f6de';
