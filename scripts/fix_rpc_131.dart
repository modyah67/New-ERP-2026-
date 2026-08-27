import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  String? password = Platform.environment['DB_PASS'];
  
  final conn = await Connection.open(
    Endpoint(
      host: 'aws-0-eu-north-1.pooler.supabase.com',
      database: 'postgres',
      username: 'postgres.pjkhdnoeyyvraclomepx',
      password: password,
      port: 5432,
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  try {
    print('Fixing rpc_sync_vendor_balances_and_ledger - removing ::text casts on reference_id...');
    await conn.execute(r'''
CREATE OR REPLACE FUNCTION public.rpc_sync_vendor_balances_and_ledger()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_total_cost NUMERIC;
    v_shipping_updated INT := 0;
    v_ca_updated INT := 0;
    v_le_upserted INT := 0;
    v_le_deleted INT := 0;
BEGIN
    -- Shipping companies: recalculate balance
    FOR r IN
        SELECT sci.vendor_id AS comp_id,
               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
        FROM public.shipment_cost_items sci
        WHERE sci.vendor_type = 'shipping_company' AND sci.vendor_id IS NOT NULL
        GROUP BY sci.vendor_id
    LOOP
        UPDATE public.shipping_companies
        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
        WHERE id = r.comp_id;
        v_shipping_updated := v_shipping_updated + 1;
    END LOOP;

    UPDATE public.shipping_companies sc
    SET balance = COALESCE(sc.initial_balance, 0) + COALESCE(sc.manual_adjustment, 0)
    WHERE sc.id NOT IN (
        SELECT DISTINCT vendor_id FROM public.shipment_cost_items
        WHERE vendor_type = 'shipping_company' AND vendor_id IS NOT NULL
    );

    -- Clearing agents: recalculate balance
    FOR r IN
        SELECT sci.vendor_id AS agent_id,
               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
        FROM public.shipment_cost_items sci
        WHERE sci.vendor_type = 'clearing_agent' AND sci.vendor_id IS NOT NULL
        GROUP BY sci.vendor_id
    LOOP
        UPDATE public.clearing_agents
        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
        WHERE id = r.agent_id;
        v_ca_updated := v_ca_updated + 1;
    END LOOP;

    UPDATE public.clearing_agents ca
    SET balance = COALESCE(ca.initial_balance, 0) + COALESCE(ca.manual_adjustment, 0)
    WHERE ca.id NOT IN (
        SELECT DISTINCT vendor_id FROM public.shipment_cost_items
        WHERE vendor_type = 'clearing_agent' AND vendor_id IS NOT NULL
    );

    -- Upsert ledger_entries for shipment_cost_items
    -- Delete orphaned entries
    DELETE FROM public.ledger_entries le
    WHERE le.reference_type = 'shipment_cost_item'
      AND le.reference_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM public.shipment_cost_items sci
          WHERE sci.id = le.reference_id::bigint
      );
    GET DIAGNOSTICS v_le_deleted = ROW_COUNT;

    -- Upsert entries for current items
    FOR r IN
        SELECT sci.id AS item_id,
               sci.vendor_type,
               sci.vendor_id,
               sci.supplier_id,
               sci.total_price,
               sci.exchange_rate,
               sci.original_currency,
               sci.description
        FROM public.shipment_cost_items sci
        WHERE sci.total_price > 0
    LOOP
        DECLARE
            v_entity_type TEXT;
            v_entity_id   TEXT;
            v_ledger_amount NUMERIC;
            v_ledger_currency TEXT;
            v_exists BIGINT;
        BEGIN
            IF r.vendor_type = 'shipping_company' AND r.vendor_id IS NOT NULL THEN
                v_entity_type := 'shipping_company';
                v_entity_id := r.vendor_id::text;
            ELSIF r.vendor_type = 'clearing_agent' AND r.vendor_id IS NOT NULL THEN
                v_entity_type := 'clearing_agent';
                v_entity_id := r.vendor_id::text;
            ELSIF r.supplier_id IS NOT NULL AND r.supplier_id != '' THEN
                v_entity_type := 'supplier';
                v_entity_id := r.supplier_id;
            ELSE
                CONTINUE;
            END IF;

            v_ledger_currency := COALESCE(NULLIF(r.original_currency, ''), 'EGP');
            IF v_ledger_currency != 'EGP' AND r.exchange_rate > 0 THEN
                v_ledger_amount := r.total_price / r.exchange_rate;
            ELSE
                v_ledger_amount := r.total_price;
            END IF;

            -- FIX: reference_id is integer, so compare with integer not text
            SELECT COUNT(*) INTO v_exists FROM public.ledger_entries
            WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id::integer;

            IF v_exists > 0 THEN
                UPDATE public.ledger_entries
                SET entity_type = v_entity_type,
                    entity_id = v_entity_id,
                    amount = v_ledger_amount,
                    currency = v_ledger_currency,
                    description = 'بند تكلفة شحنة: ' || COALESCE(r.description, '')
                WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id::integer;
            ELSE
                INSERT INTO public.ledger_entries (
                    entity_type, entity_id, entry_type, amount, currency,
                    reference_type, reference_id, description, created_by
                ) VALUES (
                    v_entity_type, v_entity_id, 'credit', v_ledger_amount, v_ledger_currency,
                    'shipment_cost_item', r.item_id::integer,
                    'بند تكلفة شحنة: ' || COALESCE(r.description, ''),
                    auth.uid()
                );
            END IF;
            v_le_upserted := v_le_upserted + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'shipping_updated', v_shipping_updated,
        'ca_updated', v_ca_updated,
        'ledger_upserted', v_le_upserted,
        'ledger_deleted', v_le_deleted
    );
END;
$$;
''');
    print('✅ rpc_sync_vendor_balances_and_ledger fixed!');

    // Now test it
    print('\nTesting the fixed RPC...');
    final result = await conn.execute('''SELECT public.rpc_sync_vendor_balances_and_ledger();''');
    print('✅ RPC test result: ' + result[0][0].toString());

  } catch (e) {
    print('❌ Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
