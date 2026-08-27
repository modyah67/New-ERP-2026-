# User Manual — نظام المحاسبة

**Version:** 1.0.0  
**Language:** العربية

---

## 1. Getting Started

### 1.1 Login
1. Open the application
2. Enter your email and password
3. Click **تسجيل الدخول** (Login)

### 1.2 Dashboard Overview
After login, you'll see the main dashboard with:
- **شريط التنقل** (Navigation sidebar) — access all modules
- **لوحة التحكم** (Control panel) — quick actions
- **الإشعارات** (Notifications) — pending approvals and alerts

---

## 2. Purchasing Module

### 2.1 Create Purchase Invoice
1. Go to **المشتريات** (Purchases)
2. Click **إضافة فاتورة** (Add Invoice)
3. Select supplier, enter items, quantities, prices
4. Click **حفظ** (Save)

### 2.2 Receive Items
1. Go to **الاستلام** (Receiving)
2. Select the purchase invoice
3. Enter received quantities
4. Click **تأكيد الاستلام** (Confirm Receiving)

---

## 3. Lot & Grading Module

### 3.1 Create Lot
1. Go to **الدفعات** (Lots)
2. Click **إضافة دفعة** (Add Lot)
3. Select purchase invoice and product
4. Enter quantity and storage location

### 3.2 Grade Lot
1. Select a lot
2. Click **فرز** (Grade)
3. Enter quantities for each grade (A, B, C)
4. Click **تأكيد الفرز** (Confirm Grading)

---

## 4. Packing Module

### 4.1 Create Packing Order
1. Go to **التعبئة** (Packing)
2. Click **أمر تعبئة جديد** (New Packing Order)
3. Select graded batch
4. Enter packing quantities and materials

### 4.2 Add Packing Recipes
1. In the packing order, click **إضافة وصفة** (Add Recipe)
2. Select product (fruit/packing material)
3. Enter quantity and unit cost
4. Click **حفظ**

---

## 5. Export Shipment Module

### 5.1 Create Shipment
1. Go to **الشحن** (Exports)
2. Click **شحنة جديدة** (New Shipment)
3. Link to packing order
4. Enter shipment details

### 5.2 Cost Breakdown
1. Open a shipment
2. Go to **تبويب التكاليف** (Cost Breakdown)
3. Verify auto-generated cost categories
4. Adjust if needed

### 5.3 Shipment Invoice
1. Open a shipment
2. Go to **الفاتورة** (Invoice)
3. Click **معاينة** (Preview) to see PDF
4. Click **طباعة** (Print) to print

### 5.4 Profitability Analysis
1. Open a shipment
2. Go to **الربحية** (Profitability)
3. View revenue, costs, margin, per-carton analysis

---

## 6. Accounting Module

### 6.1 Chart of Accounts
1. Go to **دليل الحسابات** (Chart of Accounts)
2. View all accounts with codes and balances
3. Accounts are auto-seeded on first run

### 6.2 COGS Posting
- COGS is automatically posted when shipment status changes to **شُحنت** (Shipped) or **قيد النقل** (In Transit)
- Each posting creates a double-entry journal entry
- `cogs_posted` flag prevents duplicate posting

---

## 7. Treasury Module

### 7.1 View Treasury
1. Go to **الخزينة** (Treasury)
2. View all cash/cheque accounts
3. See current balances

### 7.2 Record Transaction
1. Click **تسجيل معاملة** (Record Transaction)
2. Select type (Receipt/Payment)
3. Enter amount and description
4. Click **تأكيد**

---

## 8. Notifications & Approvals

### 8.1 View Notifications
1. Click the bell icon 🔔 in the top bar
2. View all pending notifications
3. Click **تحديد الكل كمقروء** (Mark All Read)

### 8.2 Approval Workflow
1. Create an entity (purchase invoice, shipment, treasury)
2. Submit for approval using **تقديم للموافقة** button
3. Admins receive notification
4. Admin can **موافقة** (Approve) or **رفض** (Reject)

---

## 9. Executive Dashboard

### 9.1 Access
- From the main menu, click **لوحة القيادة** (Dashboard)

### 9.2 KPIs Displayed
- إجمالي الإيرادات (Total Revenue)
- إجمالي التكاليف (Total Costs)
- هامش الربح الإجمالي (Gross Margin %)
- عدد الشحنات (Shipment Count)
- الدفعات النشطة (Active Batches)
- Monthly trends chart
- Product distribution chart

---

## 10. Backup & Restore

### 10.1 Create Backup
1. Go to **النسخ الاحتياطي** (Backup)
2. Click **إنشاء نسخة احتياطية** (Create Backup)
3. Wait for validation and completion
4. View backup history

### 10.2 Restore
1. Go to **النسخ الاحتياطي** (Backup)
2. Select a backup from history
3. Click **استعادة** (Restore) ⚠️ This overwrites current data

---

## 11. System Settings

### 11.1 Company Profile
1. Go to **الإعدادات** (Settings)
2. Edit company name, address, tax ID, logo
3. Click **حفظ التغييرات** (Save Changes)

### 11.2 Invoice Numbering
- Set prefix, starting number, and format
- Example: `INV-2026-00001`

### 11.3 Fiscal Years
- Define fiscal year start/end dates
- Active year is used for default reporting

---

## 12. Security & Audit

### 12.1 Security Assessment
1. Go to **الأمان** (Security)
2. View 7-section security report
3. Score indicates overall security posture

### 12.2 Activity Center
1. Go to **النشاطات** (Activity)
2. View unified feed of all actions
3. Use filter chips to filter by type (Audit, Approvals, Notifications)

---

## 13. Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+N` | New entry (context-dependent) |
| `Ctrl+S` | Save current form |
| `Ctrl+F` | Search/filter |
| `F5` | Refresh current view |
| `Esc` | Close modal / go back |

---

## 14. Troubleshooting

| Problem | Solution |
|---|---|
| Cannot login | Check email/password; contact admin |
| Data not loading | Check internet connection; refresh (F5) |
| Error when posting | Check audit logs for details; contact support |
| Backup fails | Ensure database is accessible; check disk space |
