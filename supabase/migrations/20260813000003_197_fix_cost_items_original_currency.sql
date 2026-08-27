BEGIN;

UPDATE public.shipment_cost_items
SET original_currency = supplier_currency
WHERE original_currency IS NULL AND supplier_currency IS NOT NULL;

-- Also call the RPC to recalculate vendor balances correctly
SELECT public.rpc_sync_vendor_balances_and_ledger();

COMMIT;
