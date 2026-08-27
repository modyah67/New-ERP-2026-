# Supabase Dashboard Setup Guide — Nova Soft ERP

## Prerequisites
- A Supabase project created at https://supabase.com
- Your project's **Project URL** and **anon public API key** (found in Project Settings > API)

---

## Step 1: Run the Migration SQL

1. Go to your Supabase project dashboard
2. Click **SQL Editor** in the left sidebar
3. Click **+ New Query**
4. Open the file `supabase/migrations/00001_initial_schema.sql` (in this repo)
5. Copy the entire contents and paste into the SQL Editor
6. Click **Run** (or press `Ctrl+Enter`)
7. Verify all 5 tables appear in **Table Editor** (left sidebar > Table Editor):
   - `customers`
   - `suppliers`
   - `company_addresses`
   - `products`
   - `export_invoices`

---

## Step 2: Verify RLS is Enabled

1. Go to **Authentication > Policies**
2. Confirm each table shows "RLS enabled" with a green badge
3. For each table, you should see 4 policies listed:
   - `Allow select for authenticated users`
   - `Allow insert for authenticated users`
   - `Allow update for authenticated users`
   - `Allow delete for authenticated users`
4. If any policies are missing, click **+ New Policy** on that table and select "Create a policy from scratch", then write:

   ```sql
   -- Example: select policy for customers
   create policy "Allow select for authenticated users" on public.customers
     for select using (auth.role() = 'authenticated');
   ```

   Repeat for insert/update/delete on each table.

---

## Step 3: Get Your API Credentials

1. Go to **Project Settings > API**
2. Copy the **Project URL** (looks like `https://xxxxx.supabase.co`)
3. Copy the **anon public** API key (NOT the `service_role` key)
4. In your Flutter app, create `.env` or update your config:

   ```dart
   // lib/core/supabase_config.dart
   class SupabaseConfig {
     static const String url = 'https://YOUR_PROJECT_ID.supabase.co';
     static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
   }
   ```

5. Initialize Supabase in `main.dart`:

   ```dart
   await Supabase.initialize(
     url: SupabaseConfig.url,
     anonKey: SupabaseConfig.anonKey,
   );
   ```

---

## Step 4: Configure Authentication (Email/Password)

1. Go to **Authentication > Providers**
2. Click **Email**
3. Toggle **Enable email confirmations** as desired:
   - **OFF** for development (users created without email verification)
   - **ON** for production
4. Click **Save**

---

## Step 5: Create a Test User

1. Go to **Authentication > Users**
2. Click **+ Invite user** or **+ Add user**
3. Enter an email and password
4. Click **Create user**
5. This user can now sign in from your Flutter app using:

   ```dart
   await Supabase.instance.client.auth.signInWithPassword(
     email: 'test@example.com',
     password: 'password123',
   );
   ```

---

## Step 6: Add Sample Data (Optional)

In SQL Editor, run:

```sql
-- Sample customer
insert into public.customers (name, phone) values ('DKI', '+201234567890');
insert into public.customers (name, phone) values ('BRUNO', '+201098765432');

-- Sample addresses
insert into public.company_addresses (company_id, company_type, label, full_address, country)
values (1, 'customer', 'المقر الرئيسي', 'دمياط - المنطقة الحرة', 'Egypt');

insert into public.company_addresses (company_id, company_type, label, full_address, country)
values (2, 'customer', 'المقر الرئيسي', 'الإسكندرية - ميناء الدخيلة', 'Egypt');

-- Sample products
insert into public.products (name_ar, name_en, sku, unit, sale_price, export_price)
values ('بصل أحمر', 'Red Onion', 'ON-RED-001', 'طن', 8500, 7200),
       ('بصل أبيض', 'White Onion', 'ON-WHT-002', 'طن', 8200, 6900),
       ('بطاطس', 'Potatoes', 'POT-001', 'طن', 6000, 5100);

-- Sample export invoice
insert into public.export_invoices (invoice_no, date, customer_id, transport_mode,
  total_cartons, total_pallets, total_net_weight, total_gross_weight)
values ('26/52/001', current_date, 1, 0, 1200, 20, 18000.0, 18440.0);
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | RLS blocking | Ensure user is authenticated; anon key only allows `authenticated` role |
| `relation "public.customers" does not exist` | SQL not run | Run the migration in SQL Editor |
| `column "name_ar" does not exist` | Old schema | Drop old tables and re-run migration, or run `ALTER TABLE` |
| Foreign key violation | `customer_id` doesn't exist | Insert customer first, then use that `id` |

---

## File Reference

| File | Purpose |
|---|---|
| `supabase/migrations/00001_initial_schema.sql` | Full DDL + RLS + triggers |
| `lib/data/dao/customer_dao.dart` | Customer CRUD with address stitching |
| `lib/data/dao/supplier_dao.dart` | Supplier CRUD with address stitching |
| `lib/data/dao/product_dao.dart` | Product CRUD |
| `lib/data/dao/export_invoice_dao.dart` | Export invoice CRUD with auto-invoice-no |
