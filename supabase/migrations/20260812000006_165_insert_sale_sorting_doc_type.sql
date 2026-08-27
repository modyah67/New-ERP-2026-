BEGIN;

INSERT INTO sys_document_types (code, name, prefix) VALUES
  ('sale_sorting', 'Sale Sorting', 'SSRT')
ON CONFLICT (code) DO NOTHING;

COMMIT;
