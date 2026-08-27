# DATABASE_STRUCTURE.md

## Complete Object Inventory

### Extensions
| Extension | Purpose |
|-----------|---------|
| `uuid-ossp` | UUID generation (uuid_generate_v4) |
| `pg_trgm` | Trigram text search (GIN indexes) |

### Tables (80 total)

#### Master Data (Preserved)
| Table | Description |
|-------|-------------|
| `profiles` | User profiles (extends auth.users) |
| `users` | User compatibility view/table |
| `warehouses` | Warehouse locations |
| `currencies` | Currency definitions |
| `product_categories` | Product categories (hierarchical) |
| `products` | Product catalog |
| `customers` | Customer master data |
| `suppliers` | Supplier master data |
| `accounts` | Chart of accounts |
| `settings` | System settings |
| `company_profile` | Company information |
| `fruit_types` | Fruit type catalog |
| `raw_materials` | Raw materials catalog |
| `stations` | Production stations |
| `clearing_agents` | Clearing/customs agents |
| `shipping_companies` | Shipping company directory |
| `bank_accounts` | Bank account definitions |
| `expense_categories` | Expense category definitions |
| `treasuries` | Treasury definitions |
| `subscription_plans` | Subscription plan definitions |
| `tenants` | Multi-tenant definitions |
| `tenant_users` | Tenant-user associations |
| `user_roles` | User role assignments |
| `pricing_rules` | Pricing rule definitions |
| `unit_conversions` | Unit conversion factors |
| `packing_recipes` | Packing recipe definitions |
| `invoice_numbering` | Invoice sequence configuration |
| `fiscal_years` | Fiscal year definitions |

#### Runtime Data (Wipeable)
| Table | Description |
|-------|-------------|
| `purchase_invoices` | Purchase invoice headers |
| `purchase_invoice_items` | Purchase invoice line items |
| `sales_invoices` | Sales invoice headers |
| `sales_invoice_items` | Sales invoice line items |
| `export_shipments` | Export shipment headers |
| `export_shipment_items` | Export shipment line items |
| `proforma_invoices` | Proforma invoice headers |
| `proforma_invoice_items` | Proforma invoice line items |
| `stock_batches` | Stock batch tracking (FIFO) |
| `stock_movements` | Stock movement history |
| `stock_transfers` | Station-to-station transfers |
| `transactions` | Financial journal entries |
| `ledger_entries` | Customer/supplier ledger entries |
| `cash_receipts` | Customer payment receipts |
| `cash_payments` | Supplier payment records |
| `cashbox_transactions` | Cashbox transaction history |
| `treasury_transactions` | Treasury transaction history |
| `treasury_balances` | Treasury balance records |
| `bank_account_transactions` | Bank transaction history |
| `cheques` | Cheque management |
| `lot_receipts` | Fruit lot receipts |
| `lot_grading_results` | Lot grading outcomes |
| `lot_returns` | Lot return records |
| `packing_orders` | Packing order headers |
| `packing_order_sortings` | Packing order sorting records |
| `packing_order_cost_items` | Packing order cost breakdown |
| `station_products` | Station product inventory |
| `station_product_batches` | Station batch tracking |
| `shipment_cost_breakdown` | Export shipment costs |
| `shipment_cost_allocations` | Cost allocation records |
| `shipment_recipe_snapshots` | Recipe snapshots per shipment |
| `shipment_profitability_snapshots` | Profitability per shipment |
| `supplier_settlements` | Supplier settlement records |
| `prep_center_cost_items` | Prep center cost records |
| `general_cost_items` | General cost records |
| `cost_report_items` | Cost report line items |
| `cost_report_categories` | Cost report categories |
| `crop_purchases` | Crop purchase records |
| `shareholder_profit_distributions` | Profit distribution records |
| `finished_goods` | Finished goods inventory |
| `raw_material_transactions` | Raw material transaction history |
| `invoice_edits` | Invoice edit audit trail |
| `audit_logs` | General audit logs |
| `audit_logs_text` | Audit log text storage |
| `approval_history` | Approval workflow history |
| `notifications` | User notifications |
| `backup_history` | Backup history |
| `statement_notes` | Statement annotation notes |
| `exchange_rates` | Exchange rate history |
| `profit_distribution_settings` | Profit distribution configuration |
| `fiscal_year_audit_log` | Fiscal year audit trail |
| `fiscal_year_closing_entries` | FY closing entries |
| `fiscal_year_closing_progress` | FY closing progress |
| `fiscal_year_closing_lock` | FY closing locks |
| `fiscal_year_backup_metadata` | FY backup metadata |
| `fiscal_year_inventory_snapshot` | FY inventory snapshot |
| `customer_addresses` | Customer address records |
| `supplier_addresses` | Supplier address records |

#### System Tables
| Table | Description |
|-------|-------------|
| `system_settings` | System-level settings |
| `export_invoices` | Export invoice compatibility view/table |

### Views (9)
| View | Based On |
|------|----------|
| `invoices` | sales_invoices |
| `invoice_items` | sales_invoice_items |
| `purchases` | purchase_invoices |
| `purchase_items` | purchase_invoice_items |
| `cashbox` | cashbox_transactions |
| `items` | products |
| `v_shareholders` | profit_distribution_settings |
| `latest_fruit_purchase_prices` | lot_receipts |
| `vw_cost_details_live` | packing_order_cost_items + shipments |

### Functions / RPCs (198)
See `extracted_functions.sql` for complete function bodies.

Key categories:
- Stock management (8): deduct_stock_fifo, create_batch_from_purchase, etc.
- Invoice/Purchase (2): create_invoice, create_purchase
- Cashbox (6): get_cashbox_balance, create_cashbox_transaction, etc.
- Treasury (12): create_treasury, deposit_treasury, withdraw_treasury, etc.
- Cheques (6): create_cheque, clear_cheque, cancel_cheque, etc.
- Bank (2): deposit_bank_account, withdraw_bank_account
- Lot processing (3): rpc_process_lot_receipt, rpc_reprocess_lot_receipt, rpc_process_lot_return
- Fiscal year (8): fiscal_years_before_upsert, validate_trial_balance, etc.
- Reporting (4): get_account_totals_rpc, get_balance_before_date_rpc, etc.
- Purchase RPCs (2): rpc_confirm_purchase, rpc_cancel_purchase
- Export RPCs (2): rpc_cancel_export_shipment, rpc_get_export_shipment_cancel_info
- Packing RPCs (2): rpc_confirm_packing_order, rpc_cancel_packing_order
- Admin (4): admin_create_user, admin_delete_user, admin_create_employee, etc.
- Utility (10+): set_updated_at, update_updated_at, handle_new_user, etc.
- Dashboard (4): get_dashboard_stats, get_expiring_items, etc.

### Triggers (50)
| Category | Count | Examples |
|----------|-------|---------|
| Auth | 1 | on_auth_user_created |
| Updated_at | 16 | update_products_updated_at, update_stock_batches_updated_at, etc. |
| Audit | 5 | audit_products, audit_stock_batches, etc. |
| Fiscal Year | 15+ | trg_check_fy_allows_* (inventory, financial, etc.) |
| Cheques | 1 | trg_cheques_updated_at |
| Fiscal Year Validation | 2 | trg_fiscal_years_before_insert, trg_fiscal_years_before_update |
| Entry Balance | 1 | check_entry_balance_trigger |

### RLS Policies (108)
- Permissive policies ("Allow all for authenticated") on 50+ tables
- Role-based policies for cheques, expense_categories, ledger_entries, bank_accounts, treasuries
- Tenant/subscription policies for multi-tenancy
- Profit distribution user-scoped policies

### Indexes (237)
See `schema_indexes_grants.sql` for complete index list.

Key categories:
- Product search indexes (GIN trigram on name)
- FIFO ordering indexes on stock_batches
- Foreign key lookup indexes on all FK columns
- Date range indexes for reporting
- Composite indexes for common queries
- Partial indexes for active records

### Sequences (2)
| Sequence | Used By |
|----------|---------|
| `fruit_type_code_seq` | fruit_types.code auto-generation |
| `raw_material_code_seq` | raw_materials.code auto-generation |
