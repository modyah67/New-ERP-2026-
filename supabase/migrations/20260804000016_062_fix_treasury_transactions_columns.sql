-- Migration 062: Fix treasury_transactions missing columns and legacy function
--
-- PROBLEM: The legacy rpc_process_treasury_transaction function expects
--   reference_type and reference_id columns on treasury_transactions,
--   but these columns were never created (schema uses source_type instead).
--
-- FIX:
--   1. Add reference_type and reference_id columns to treasury_transactions
--   2. Update rpc_process_treasury_transaction to use correct column names
--   3. Keep source_type for backward compatibility

-- Add missing columns
ALTER TABLE treasury_transactions 
ADD COLUMN IF NOT EXISTS reference_type TEXT,
ADD COLUMN IF NOT EXISTS reference_id UUID;

-- Update rpc_process_treasury_transaction to use both column sets
CREATE OR REPLACE FUNCTION rpc_process_treasury_transaction(
  p_treasury_id BIGINT,
  p_type TEXT,
  p_amount NUMERIC,
  p_balance_before NUMERIC,
  p_balance_after NUMERIC,
  p_description TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_treasury RECORD;
  v_new_balance NUMERIC;
  v_result JSONB;
BEGIN
  -- Lock treasury row
  SELECT * INTO v_treasury FROM treasuries WHERE id = p_treasury_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'treasury not found');
  END IF;

  -- Validate type
  IF p_type NOT IN ('receipt', 'payment') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid type, must be receipt or payment');
  END IF;

  -- Validate balance for payments
  IF p_type = 'payment' AND v_treasury.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient balance');
  END IF;

  -- Calculate new balance
  IF p_type = 'receipt' THEN
    v_new_balance := v_treasury.balance + p_amount;
  ELSE
    v_new_balance := v_treasury.balance - p_amount;
  END IF;

  -- Update treasury balance
  UPDATE treasuries SET balance = v_new_balance, updated_at = NOW() WHERE id = p_treasury_id;

  -- Insert transaction record (populate both column sets)
  INSERT INTO treasury_transactions (
    treasury_id, type, amount, balance_before, balance_after, 
    description, source_type, reference_type, reference_id, created_by
  ) VALUES (
    p_treasury_id, p_type, p_amount, v_treasury.balance, v_new_balance, 
    p_description, p_reference_type, p_reference_type, p_reference_id, p_user_id
  );

  -- Log audit
  INSERT INTO audit_logs_text (table_name, record_id, action, old_values, new_values, performed_by)
  VALUES ('treasuries', p_treasury_id::TEXT, p_type,
    jsonb_build_object('balance', v_treasury.balance),
    jsonb_build_object('balance', v_new_balance, 'amount', p_amount),
    p_user_id);

  v_result := jsonb_build_object(
    'success', true,
    'treasury_id', p_treasury_id,
    'type', p_type,
    'amount', p_amount,
    'balance_before', v_treasury.balance,
    'balance_after', v_new_balance
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_process_treasury_transaction(BIGINT, TEXT, NUMERIC, NUMERIC, NUMERIC, TEXT, TEXT, UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';