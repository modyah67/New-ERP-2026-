# Database ERD Overview

**Version:** 1.0.0  
**Tables:** 35+  
**Last Updated:** 2026-06-20

---

## 1. Core Domain Tables

### 1.1 Purchasing
```
purchase_invoices (id, supplier_id, invoice_number, date, total_amount, status, approval_status)
  └── purchase_invoice_items (id, invoice_id, product_id, quantity, unit_price, total_price)
        └── products (id, name, category, unit)
suppliers (id, name, phone, address)
```

### 1.2 Lot Management
```
lots (id, lot_number, purchase_invoice_id, product_id, received_qty, remaining_qty, status)
  └── lot_receipts (id, lot_id, purchase_invoice_item_id, quantity, date)
  └── stock_batches (id, lot_id, batch_number, product_id, quantity, unit_cost, status, warehouse_id)
  └── lot_grading_results (id, lot_id, stock_batch_id, grade, quantity, cost_per_kg)
```

### 1.3 Packing
```
packing_orders (id, lot_id, product_id, date, total_quantity, status)
  └── packing_recipes (id, packing_order_id, product_id, quantity, unit_cost, material_type)
```

### 1.4 Export Shipments
```
export_shipments (id, shipment_number, packing_order_id, status, total_qty, total_cost, total_revenue, cogs_posted, approval_status)
  └── shipment_cost_breakdown (id, export_shipment_id, category, amount, description)
  └── export_shipment_items (id, shipment_id, product_id, quantity, price)
```

### 1.5 Accounting
```
accounts (id, code, name, type, balance) [COA: 1000-6999]
transactions (id, account_id, date, type, amount, description, reference_type, reference_id, created_by)
```

### 1.6 Treasury
```
treasuries (id, name, type, balance, approval_status)
treasury_transactions (id, treasury_id, type, amount, balance_before, balance_after, description, reference_type, reference_id, created_by)
```

---

## 2. Enterprise Module Tables

### 2.1 Approvals
```
approval_history (id, entity_type, entity_id, from_status, to_status, action, comment, performed_by, created_at)
```

### 2.2 Notifications
```
notifications (id, user_id, type, severity, title, message, is_read, created_at)
```

### 2.3 Settings
```
company_profile (id, name, address, tax_id, phone, email, logo_url)
fiscal_years (id, name, start_date, end_date, is_active)
invoice_numbering (id, entity_type, prefix, start_number, format, current_number)
currencies (id, code, name, symbol, is_default, exchange_rate)
```

### 2.4 Backup
```
backup_history (id, file_name, file_size, status, performed_by, created_at)
```

---

## 3. Audit & System Tables

### 3.1 Audit
```
audit_logs_text (id, table_name, record_id, action, old_values, new_values, performed_by, created_at)
```

### 3.2 User Management
```
users (id, email, name, role, is_active, created_at)
user_roles (id, user_id, role, permissions)
```

---

## 4. Key Relationships

```
purchase_invoices
  → suppliers (M:1)
  → purchase_invoice_items (1:M)
    → products (M:1)

lots
  → purchase_invoices (M:1)
  → products (M:1)
  → lot_receipts (1:M)
    → purchase_invoice_items (M:1)
  → stock_batches (1:M)
    → lot_grading_results (1:M)

packing_orders
  → lots (M:1)
  → packing_recipes (1:M)
    → products (M:1)

export_shipments
  → packing_orders (M:1)
  → shipment_cost_breakdown (1:M)
  → export_shipment_items (1:M)

transactions
  → accounts (M:1)
  → export_shipments (polymorphic via reference_type/reference_id)

treasury_transactions
  → treasuries (M:1)
  → export_shipments (polymorphic via reference_type/reference_id)
```

---

## 5. Index Strategy

| Table | Key Index | Purpose |
|---|---|---|
| `stock_batches` | `(product_id, status, unit_cost) INCLUDE (quantity)` | Valuation queries |
| `export_shipments` | `(status, created_at DESC)` | Dashboard + listing |
| `export_shipments` | `(cogs_posted) WHERE cogs_posted = false` | Pending COGS scan |
| `transactions` | `(reference_type, reference_id)` | COGS lookup |
| `notifications` | `(user_id, is_read)` | User notification feed |
| `audit_logs_text` | `(table_name, record_id)` | Entity audit trail |

See `061_performance_indexes.sql` for complete index definitions.
