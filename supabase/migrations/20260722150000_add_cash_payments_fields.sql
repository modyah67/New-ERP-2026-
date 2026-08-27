-- =====================================================================
-- Migration: add_cash_payments_fields
-- تاريخ الإنشاء: 2026-07-22
-- السبب: توثيق بأثر رجعي (retroactive) لتغييرات تمت فعليًا على remote
--        عبر `supabase db query --linked` مباشرة، بدون ملف migration.
-- هذا الملف لا يمثل تنفيذًا جديدًا، بل تسجيل تاريخي للحالة الفعلية
--        الموجودة بالفعل على قاعدة البيانات، مكتوب بصيغة idempotent
--        بحيث لا يفشل ولا يكرر التنفيذ لو اشتغل على بيئة جديدة.
-- =====================================================================

-- إضافة الأعمدة الجديدة (لو مش موجودة أصلاً)
ALTER TABLE cash_payments
  ADD COLUMN IF NOT EXISTS customer_id integer,
  ADD COLUMN IF NOT EXISTS account_id integer,
  ADD COLUMN IF NOT EXISTS mode text DEFAULT 'other'::text,
  ADD COLUMN IF NOT EXISTS description text;

-- تعديل supplier_id ليصبح nullable
ALTER TABLE cash_payments
  ALTER COLUMN supplier_id DROP NOT NULL;

-- إزالة الـ Foreign Key القديم على supplier_id (لو لسه موجود)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
    WHERE tc.table_name = 'cash_payments'
      AND kcu.column_name = 'supplier_id'
      AND tc.constraint_type = 'FOREIGN KEY'
  ) THEN
    EXECUTE (
      SELECT 'ALTER TABLE cash_payments DROP CONSTRAINT ' || tc.constraint_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_name = 'cash_payments'
        AND kcu.column_name = 'supplier_id'
        AND tc.constraint_type = 'FOREIGN KEY'
      LIMIT 1
    );
  END IF;
END $$;

-- إضافة FK على customer_id (لو مش موجود)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'cash_payments'
      AND constraint_name = 'cash_payments_customer_id_fkey'
  ) THEN
    ALTER TABLE cash_payments
      ADD CONSTRAINT cash_payments_customer_id_fkey
      FOREIGN KEY (customer_id) REFERENCES customers(id);
  END IF;
END $$;

-- إضافة FK على account_id (لو مش موجود)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'cash_payments'
      AND constraint_name = 'cash_payments_account_id_fkey'
  ) THEN
    ALTER TABLE cash_payments
      ADD CONSTRAINT cash_payments_account_id_fkey
      FOREIGN KEY (account_id) REFERENCES accounts(id);
  END IF;
END $$;
