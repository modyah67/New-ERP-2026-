CREATE OR REPLACE FUNCTION rpc_wipe_all_demo_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    t text;
    target_tables text[] := ARRAY[
        'shipment_cost_items',
        'export_shipment_items',
        'shipment_breakdowns',
        'shipment_lot_allocations',
        'export_shipments',
        'proforma_invoices',
        'packing_order_cost_items',
        'packing_order_items',
        'packing_order_sortings',
        'pallet_packing_allocations',
        'packing_orders',
        'packing_recipes',
        'stock_movements',
        'stock_batches',
        'stock_batch_items',
        'inventory_transactions',
        'lots',
        'warehouses',
        'products',
        'product_categories',
        'fruit_types',
        'fruit_catalog',
        'treasury_transactions',
        'employee_custodies',
        'bank_account_transactions',
        'supplier_settlements',
        'cash_payments',
        'sales_invoice_items',
        'sales_invoices',
        'purchase_invoice_items',
        'purchase_invoices',
        'purchases',
        'transactions',
        'journal_entries',
        'ledger_entries',
        'account_ledger_entries',
        'financial_audit_log',
        'audit_logs',
        'audit_logs_text',
        'invoice_edits',
        'customers',
        'suppliers',
        'clearing_agents',
        'shipping_companies',
        'shareholders'
    ];
BEGIN
    SET session_replication_role = 'replica';

    FOREACH t IN ARRAY target_tables
    LOOP
        IF EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = t
            AND table_type = 'BASE TABLE'
        ) THEN
            EXECUTE format('TRUNCATE TABLE public.%I RESTART IDENTITY CASCADE;', t);
        END IF;
    END LOOP;

    SET session_replication_role = 'origin';

    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'treasury_balances'
        AND table_type = 'BASE TABLE'
    ) THEN
        INSERT INTO "public"."treasury_balances" (treasury_id, currency, balance)
        SELECT id, 'EGP', 0.00 FROM "public"."treasuries"
        ON CONFLICT (treasury_id, currency) DO UPDATE SET balance = 0.00;

        INSERT INTO "public"."treasury_balances" (treasury_id, currency, balance)
        SELECT id, 'USD', 0.00 FROM "public"."treasuries"
        ON CONFLICT (treasury_id, currency) DO UPDATE SET balance = 0.00;

        INSERT INTO "public"."treasury_balances" (treasury_id, currency, balance)
        SELECT id, 'EUR', 0.00 FROM "public"."treasuries"
        ON CONFLICT (treasury_id, currency) DO UPDATE SET balance = 0.00;
    END IF;

    IF EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'bank_accounts'
        AND table_type = 'BASE TABLE'
    ) THEN
        UPDATE "public"."bank_accounts" SET balance = 0.00;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'تم تصفير وتطهير جميع بيانات التجربة بما فيها المخازن والأصناف بنجاح. النظام جاهز للتشغيل الفعلي.'
    );
END;
$$;
