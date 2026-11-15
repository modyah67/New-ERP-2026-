-- ============================================================================
-- Migration: Add export_shipment_no and customer_name to packing_orders
-- Allows associating a packing order with an export shipment number or customer
-- for easy identification, search, and filtering in the UI and exports.
-- ============================================================================

ALTER TABLE public.packing_orders 
ADD COLUMN IF NOT EXISTS export_shipment_no TEXT,
ADD COLUMN IF NOT EXISTS customer_name TEXT;

-- Create indexes for performance when searching and filtering
CREATE INDEX IF NOT EXISTS idx_packing_orders_export_shipment_no 
ON public.packing_orders(export_shipment_no);

CREATE INDEX IF NOT EXISTS idx_packing_orders_customer_name 
ON public.packing_orders(customer_name);

-- Update column comments for documentation
COMMENT ON COLUMN public.packing_orders.export_shipment_no IS 'رقم الشحنة التصديرية المرتبطة بأمر التعبئة (اختياري لتمييز أمر التعبئة)';
COMMENT ON COLUMN public.packing_orders.customer_name IS 'اسم العميل / المستورد المرتبط بأمر التعبئة (اختياري لتمييز أمر التعبئة)';
