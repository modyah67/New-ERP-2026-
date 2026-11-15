import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChartOfAccountsService {
  final _client = Supabase.instance.client;

  static const defaultAccounts = [
    // Level 1 Roots
    {'account_code': '1', 'name': 'Assets', 'account_name': 'الأصول', 'account_type': 'asset'},
    {'account_code': '2', 'name': 'Liabilities & Equity', 'account_name': 'الخصوم وحقوق الملكية', 'account_type': 'liability'},
    {'account_code': '3', 'name': 'Expenses & Costs', 'account_name': 'المصروفات والتكاليف', 'account_type': 'expense'},
    {'account_code': '4', 'name': 'Revenues', 'account_name': 'الإيرادات', 'account_type': 'revenue'},
    {'account_code': '9', 'name': 'System & Intermediary Accounts', 'account_name': 'حسابات نظامية ووسيطة', 'account_type': 'system'},

    // Level 2 Major Groups
    {'account_code': '11', 'name': 'Non-Current Assets', 'account_name': 'أصول طويله الأجل', 'account_type': 'asset'},
    {'account_code': '12', 'name': 'Current Assets', 'account_name': 'أصول متداوله', 'account_type': 'asset'},
    {'account_code': '21', 'name': 'Current Liabilities', 'account_name': 'الخصوم المتداولة', 'account_type': 'liability'},
    {'account_code': '22', 'name': 'Non-Current Liabilities', 'account_name': 'الخصوم غير المتداولة', 'account_type': 'liability'},
    {'account_code': '23', 'name': 'Equity', 'account_name': 'حقوق الملكية', 'account_type': 'equity'},
    {'account_code': '31', 'name': 'Cost of Sales & Production', 'account_name': 'تكلفة النشاط والمبيعات', 'account_type': 'expense'},
    {'account_code': '32', 'name': 'General & Operating Expenses', 'account_name': 'المصروفات العمومية والإدارية والتشغيلية', 'account_type': 'expense'},
    {'account_code': '33', 'name': 'Financial & FX Expenses', 'account_name': 'المصروفات التمويلية وفروق العملة', 'account_type': 'expense'},
    {'account_code': '41', 'name': 'Operating Revenues', 'account_name': 'إيرادات النشاط', 'account_type': 'revenue'},
    {'account_code': '42', 'name': 'Other Revenues', 'account_name': 'إيرادات اخرى', 'account_type': 'revenue'},
    {'account_code': '91', 'name': 'Intermediary & Clearing Accounts', 'account_name': 'الحسابات الوسيطة والتسويات', 'account_type': 'system'},

    // Level 3 Sub-groups (Assets)
    {'account_code': '111', 'name': 'Fixed Assets', 'account_name': 'أصول ثابته', 'account_type': 'asset'},
    {'account_code': '121', 'name': 'Cash at Banks', 'account_name': 'النقديه بالبنوك', 'account_type': 'asset'},
    {'account_code': '122', 'name': 'Cash in Hand & Safes', 'account_name': 'النقديه بالصندوق', 'account_type': 'asset'},
    {'account_code': '123', 'name': 'Cash in Transit', 'account_name': 'النقديه بالطريق', 'account_type': 'asset'},
    {'account_code': '124', 'name': 'Inventory', 'account_name': 'المخزون', 'account_type': 'asset'},
    {'account_code': '125', 'name': 'Customers & Receivables', 'account_name': 'العملاء', 'account_type': 'asset'},
    {'account_code': '126', 'name': 'Other Debit Balances', 'account_name': 'أرصده مدينه أخرى', 'account_type': 'asset'},

    // Level 4 Analytical Control Groups (Assets)
    {'account_code': '1111', 'name': 'Integrated Fixed Assets', 'account_name': 'أصول ثابته متكامله', 'account_type': 'asset'},
    {'account_code': '1211', 'name': 'Debit Banks', 'account_name': 'بنوك مدينه', 'account_type': 'asset'},
    {'account_code': '1212', 'name': 'Cheques Under Collection', 'account_name': 'شيكات برسم التحصيل', 'account_type': 'asset'},
    {'account_code': '1221', 'name': 'Main Safes', 'account_name': 'الخزن الاساسيه', 'account_type': 'asset'},
    {'account_code': '1231', 'name': 'Cash Transfers', 'account_name': 'تحويلات نقديه', 'account_type': 'asset'},
    {'account_code': '1241', 'name': 'Inventory Control', 'account_name': 'المخزون', 'account_type': 'asset'},
    {'account_code': '1251', 'name': 'Customers Control', 'account_name': 'العملاء', 'account_type': 'asset'},
    {'account_code': '1261', 'name': 'Other Debit Balances Control', 'account_name': 'أرصده مدينه أخرى', 'account_type': 'asset'},

    // Level 5 Leaf / Posting Accounts (Assets)
    {'account_code': '11111', 'name': 'Fixed Assets - Lands', 'account_name': 'أصول ثابته أراضى', 'account_type': 'asset'},
    {'account_code': '11112', 'name': 'Fixed Assets - Buildings', 'account_name': 'أصول ثابته مباني', 'account_type': 'asset'},
    {'account_code': '11113', 'name': 'Fixed Assets - Furniture & Office', 'account_name': 'أصول ثابته أثاث ومعدات مكتبيه', 'account_type': 'asset'},
    {'account_code': '11114', 'name': 'Fixed Assets - Computers & IT', 'account_name': 'أصول ثابته اجهزه كمبيوتر', 'account_type': 'asset'},
    {'account_code': '11115', 'name': 'Fixed Assets - Passenger Vehicles', 'account_name': 'أصول ثابته سيارات ملاكي', 'account_type': 'asset'},
    {'account_code': '11116', 'name': 'Fixed Assets - Produce Transport Vehicles', 'account_name': 'أصول ثابته وسائل نقل المحاصيل', 'account_type': 'asset'},
    {'account_code': '12111', 'name': 'Commercial International Bank (CIB) - EGP', 'account_name': 'البنك التجاري الدولي CIB - جنيه مصري', 'account_type': 'asset'},
    {'account_code': '12112', 'name': 'Commercial International Bank (CIB) - USD', 'account_name': 'البنك التجاري الدولي CIB - دولار أمريكي', 'account_type': 'asset'},
    {'account_code': '12113', 'name': 'Commercial International Bank (CIB) - EUR', 'account_name': 'البنك التجاري الدولي CIB - يورو', 'account_type': 'asset'},
    {'account_code': '12114', 'name': 'Commercial International Bank (CIB) - GBP', 'account_name': 'البنك التجاري الدولي CIB - جنيه إسترليني', 'account_type': 'asset'},
    {'account_code': '12121', 'name': 'Cheques Under Collection', 'account_name': 'شيكات برسم التحصيل', 'account_type': 'asset'},
    {'account_code': '12211', 'name': 'Main Treasury - EGP', 'account_name': 'الخزينة الرئيسية - جنيه مصري', 'account_type': 'asset'},
    {'account_code': '12212', 'name': 'Main Treasury - USD', 'account_name': 'الخزينة الرئيسية - دولار أمريكي', 'account_type': 'asset'},
    {'account_code': '12213', 'name': 'Main Treasury - EUR', 'account_name': 'الخزينة الرئيسية - يورو', 'account_type': 'asset'},
    {'account_code': '12214', 'name': 'Main Treasury - GBP', 'account_name': 'الخزينة الرئيسية - جنيه إسترليني', 'account_type': 'asset'},
    {'account_code': '12311', 'name': 'Cash Transfers', 'account_name': 'تحويلات نقديه', 'account_type': 'asset'},
    {'account_code': '12312', 'name': 'Cheque Transfers', 'account_name': 'تحويلات شيكات', 'account_type': 'asset'},
    {'account_code': '12313', 'name': 'Foreign Currency Bank Transfers', 'account_name': 'تحويلات بنكيه عملات - خارجيه', 'account_type': 'asset'},
    {'account_code': '12314', 'name': 'Inter-Branch Bank Transfers', 'account_name': 'تحويلات بنكيه بين الفروع - داخليه', 'account_type': 'asset'},
    {'account_code': '12411', 'name': 'Packaging Materials Warehouse', 'account_name': 'مخزن التعبئه والتغليف', 'account_type': 'asset'},
    {'account_code': '12412', 'name': 'Raw Materials Purchases Warehouse', 'account_name': 'مخزن مشتريات خام', 'account_type': 'asset'},
    {'account_code': '12511', 'name': 'Export Customers', 'account_name': 'عملاء تصدير', 'account_type': 'asset'},
    {'account_code': '12512', 'name': 'Local Customers', 'account_name': 'عملاء محلي', 'account_type': 'asset'},
    {'account_code': '12611', 'name': 'Cash Advances', 'account_name': 'سلف نقديه', 'account_type': 'asset'},
    {'account_code': '12612', 'name': 'Temporary Cash Custody', 'account_name': 'عهد نقديه مؤقته', 'account_type': 'asset'},
    {'account_code': '12613', 'name': 'Permanent Cash Custody', 'account_name': 'عهد نقديه مستديمه', 'account_type': 'asset'},
    {'account_code': '12614', 'name': 'Tax Authority - Withholding Tax', 'account_name': 'جاري مصلحه الضرائب - خصم منبع', 'account_type': 'asset'},
    {'account_code': '12615', 'name': 'Other Debtors - Under Collection', 'account_name': 'ارصده مدينه اخرى - ارصده تحت التحصيل', 'account_type': 'asset'},
    {'account_code': '12616', 'name': 'Other Debtors - Legal Auditor Office', 'account_name': 'ارصده مدينه اخرى - مكتب المحاسب القانوني', 'account_type': 'asset'},

    // ROOT 2: LIABILITIES & EQUITY (الخصوم وحقوق الملكية)
    {'account_code': '2', 'name': 'Liabilities & Equity', 'account_name': 'الخصوم', 'account_type': 'liability'},
    {'account_code': '21', 'name': 'Current Liabilities', 'account_name': 'الخصوم المتداوله', 'account_type': 'liability'},
    {'account_code': '211', 'name': 'Suppliers & Notes Payable', 'account_name': 'الموردين وأوراق الدفع', 'account_type': 'liability'},
    {'account_code': '2111', 'name': 'Suppliers', 'account_name': 'الموردين', 'account_type': 'liability'},
    {'account_code': '2112', 'name': 'Notes Payable', 'account_name': 'أوراق الدفع', 'account_type': 'liability'},
    {'account_code': '21111', 'name': 'Local Produce Transport Suppliers', 'account_name': 'موردي النقل والسيارات', 'account_type': 'liability'},
    {'account_code': '21112', 'name': 'Packaging Materials Suppliers', 'account_name': 'موردي مواد التعبئة', 'account_type': 'liability'},
    {'account_code': '21113', 'name': 'Raw Crop Produce Suppliers', 'account_name': 'موردي مشتريات محاصيل', 'account_type': 'liability'},
    {'account_code': '21114', 'name': 'Shared Suppliers', 'account_name': 'موردين مشتركين', 'account_type': 'liability'},
    {'account_code': '21115', 'name': 'Shipping Companies', 'account_name': 'شركات الشحن', 'account_type': 'liability'},
    {'account_code': '21116', 'name': 'Customs Clearing Agents', 'account_name': 'مخلصي الجمارك', 'account_type': 'liability'},
    {'account_code': '21117', 'name': 'Station Suppliers Sub-ledger', 'account_name': 'موردي المحطات', 'account_type': 'liability'},
    {'account_code': '21118', 'name': 'Deductions Suppliers Sub-ledger', 'account_name': 'موردي التخصيمات', 'account_type': 'liability'},
    {'account_code': '21121', 'name': 'Notes Payable - CIB', 'account_name': 'أوراق دفع البنك التجاري الدولي CIB', 'account_type': 'liability'},
    {'account_code': '212', 'name': 'Liabilities to Government Entities', 'account_name': 'التزامات لجهات حكوميه', 'account_type': 'liability'},
    {'account_code': '2121', 'name': 'Taxes Control', 'account_name': 'الضرائب', 'account_type': 'liability'},
    {'account_code': '21211', 'name': 'Payroll Tax', 'account_name': 'ضريبه كسب العمل', 'account_type': 'liability'},
    {'account_code': '21212', 'name': 'Withholding Tax', 'account_name': 'ضريبه الخصم من الغير - الخصم والاضافه', 'account_type': 'liability'},
    {'account_code': '21213', 'name': 'VAT - Sales', 'account_name': 'ضريبه القيمه المضافه - المبيعات', 'account_type': 'liability'},
    {'account_code': '21214', 'name': 'Income Tax', 'account_name': 'ضريبه الدخل', 'account_type': 'liability'},
    {'account_code': '21215', 'name': 'Stamp Duty Tax', 'account_name': 'ضريبه الدمغه', 'account_type': 'liability'},
    {'account_code': '21216', 'name': 'Prior Years Tax', 'account_name': 'ضريبه سنوات سابقه', 'account_type': 'liability'},
    {'account_code': '2122', 'name': 'Social Insurance & Labor Office', 'account_name': 'هيئه التامينات الإجتماعيه ومكتب العمل', 'account_type': 'liability'},
    {'account_code': '21221', 'name': 'Social Insurance Authority', 'account_name': 'هيئه التامينات الإجتماعيه', 'account_type': 'liability'},
    {'account_code': '21222', 'name': 'Labor Office', 'account_name': 'مكتب العمل', 'account_type': 'liability'},
    {'account_code': '213', 'name': 'Other Credit Balances Group', 'account_name': 'أرصده دائنه أخرى', 'account_type': 'liability'},
    {'account_code': '2131', 'name': 'Other Credit Balances Control', 'account_name': 'أرصده دائنه أخرى', 'account_type': 'liability'},
    {'account_code': '21311', 'name': 'Accrued Expenses - Salaries', 'account_name': 'مصروفات مستحقه - مرتبات', 'account_type': 'liability'},
    {'account_code': '21312', 'name': 'Third Party Deposits', 'account_name': 'تأمينات لصالح الغير', 'account_type': 'liability'},
    {'account_code': '22', 'name': 'Long-Term Liabilities', 'account_name': 'الإلتزامات طويله الأجل', 'account_type': 'liability'},
    {'account_code': '221', 'name': 'Long-Term Liabilities Group', 'account_name': 'إلتزامات طويله الأجل', 'account_type': 'liability'},
    {'account_code': '2211', 'name': 'Long-Term Liabilities - Taxes', 'account_name': 'التزمات طويله الأجل ضرائب', 'account_type': 'liability'},
    {'account_code': '22111', 'name': 'Deferred Taxes', 'account_name': 'ضرائب مؤجله', 'account_type': 'liability'},
    {'account_code': '2212', 'name': 'Accumulated Depreciation Control', 'account_name': 'مجمع الإهلاك', 'account_type': 'liability'},
    {'account_code': '22121', 'name': 'Acc. Depr. - Land Improvements', 'account_name': 'مجمع اهلاك أصول ثابته اراضي', 'account_type': 'liability'},
    {'account_code': '22122', 'name': 'Acc. Depr. - Buildings', 'account_name': 'مجمع اهلاك أصول ثابته مباني', 'account_type': 'liability'},
    {'account_code': '22123', 'name': 'Acc. Depr. - Furniture & Office Eq.', 'account_name': 'مجمع اهلاك أصول ثابته أثاث ومعدات مكتبيه', 'account_type': 'liability'},
    {'account_code': '22124', 'name': 'Acc. Depr. - Computers & IT', 'account_name': 'مجمع اهلاك أصول ثابته اجهزه كمبيوتر', 'account_type': 'liability'},
    {'account_code': '22125', 'name': 'Acc. Depr. - Passenger Vehicles', 'account_name': 'مجمع اهلاك أصول ثابته سيارات ملاكي', 'account_type': 'liability'},
    {'account_code': '22126', 'name': 'Acc. Depr. - Produce Transport Vehicles', 'account_name': 'مجمع اهلاك أصول ثابته وسائل نقل المحاصيل', 'account_type': 'liability'},
    {'account_code': '23', 'name': 'Capital & Equity', 'account_name': 'راس المال وحقوق الملكيه', 'account_type': 'equity'},
    {'account_code': '231', 'name': 'Capital Group', 'account_name': 'رأس المال', 'account_type': 'equity'},
    {'account_code': '2311', 'name': 'Capital Control', 'account_name': 'رأس المال', 'account_type': 'equity'},
    {'account_code': '23111', 'name': 'Issued Capital', 'account_name': 'رأس المال المصدر', 'account_type': 'equity'},
    {'account_code': '23112', 'name': 'Capital Increase', 'account_name': 'زياده راس المال', 'account_type': 'equity'},
    {'account_code': '232', 'name': 'Shareholders Current Accounts Group', 'account_name': 'جاري مساهمين', 'account_type': 'equity'},
    {'account_code': '2321', 'name': 'Shareholders Current Accounts Control', 'account_name': 'جاري مساهمين', 'account_type': 'equity'},
    {'account_code': '23211', 'name': 'Current Account - Emad', 'account_name': 'جاري / عماد', 'account_type': 'equity'},
    {'account_code': '23212', 'name': 'Current Account - Abdelbatin', 'account_name': 'جاري / عبد الباطن', 'account_type': 'equity'},
    {'account_code': '23213', 'name': 'Current Account - Eslam', 'account_name': 'جاري / إسلام', 'account_type': 'equity'},
    {'account_code': '233', 'name': 'Legal Reserve Group', 'account_name': 'إحتياطي قانونى', 'account_type': 'equity'},
    {'account_code': '2331', 'name': 'Legal Reserve Control', 'account_name': 'إحتياطي قانونى', 'account_type': 'equity'},
    {'account_code': '23311', 'name': 'Legal Reserve', 'account_name': 'إحتياطى قانونى', 'account_type': 'equity'},
    {'account_code': '234', 'name': 'Retained Earnings / Losses Group', 'account_name': 'أرباح \\ خسائر مرحله', 'account_type': 'equity'},
    {'account_code': '2341', 'name': 'Retained Earnings / Losses Control', 'account_name': 'أرباح \\ خسائر مرحله', 'account_type': 'equity'},
    {'account_code': '23411', 'name': 'Retained Earnings / Losses', 'account_name': 'أرباح \\ خسائر مرحله', 'account_type': 'equity'},
    {'account_code': '2342', 'name': 'Opening Balance Suspense Control', 'account_name': 'فروق أرصدة افتتاحية', 'account_type': 'equity'},
    {'account_code': '23421', 'name': 'Opening Balance Suspense Account', 'account_name': 'رصيد افتتاحي', 'account_type': 'equity'},
    {'account_code': '235', 'name': 'Current Year Profit / Loss Group', 'account_name': 'أرباح \\ خسائر العام الحالى', 'account_type': 'equity'},
    {'account_code': '2351', 'name': 'Current Year Profit / Loss Control', 'account_name': 'أرباح \\ خسائر العام الحالى', 'account_type': 'equity'},
    {'account_code': '23511', 'name': 'Current Year Profit / Loss', 'account_name': 'أرباح \\ خسائر العام الحالى', 'account_type': 'equity'},


    {'account_code': '31111', 'name': 'Salaries Expense', 'account_name': 'مصروفات مرتبات', 'account_type': 'expense'},
    {'account_code': '31112', 'name': 'Social Insurance Expense', 'account_name': 'مصروفات تامينات اجتماعيه', 'account_type': 'expense'},
    {'account_code': '31221', 'name': 'Vehicle Maintenance & Operations', 'account_name': 'مصروفات صيانه وتشغيل سيارات', 'account_type': 'expense'},
    {'account_code': '31311', 'name': 'Cleaning & Buffet Expense', 'account_name': 'مصروفات النظافه والبوفيه', 'account_type': 'expense'},
    {'account_code': '31312', 'name': 'Utilities - Electricity, Water, Gas', 'account_name': 'مصروفات فواتير الكهرباء والمياه والغاز الطبيعي', 'account_type': 'expense'},
    {'account_code': '31318', 'name': 'General Maintenance Expense', 'account_name': 'مصروفات الصيانه العامه', 'account_type': 'expense'},
    {'account_code': '31310', 'name': 'Miscellaneous Administrative Expenses', 'account_name': 'المصروفات المتنوعه', 'account_type': 'expense'},
    {'account_code': '31411', 'name': 'Bank Interest Expense', 'account_name': 'مصروفات فوائد بنكيه', 'account_type': 'expense'},
    {'account_code': '31421', 'name': 'Bank Charges Expense', 'account_name': 'مصروفات بنكيه', 'account_type': 'expense'},
    {'account_code': '32211', 'name': 'FX Valuation Differences', 'account_name': 'فروق تقويم عمله', 'account_type': 'expense'},
    {'account_code': '33111', 'name': 'Packaging & Storage Inventory Expense', 'account_name': 'مصروفات مخزنية تعبئة وتغليف', 'account_type': 'expense'},

    // Cost of Sales Hierarchy (تكاليف المبيعات - 34)
    {'account_code': '34', 'name': 'Cost of Sales', 'account_name': 'تكاليف المبيعات', 'account_type': 'expense'},
    {'account_code': '341', 'name': 'Cost of Sales', 'account_name': 'تكاليف المبيعات', 'account_type': 'expense'},
    {'account_code': '3411', 'name': 'Cost of Sales Control', 'account_name': 'تكاليف المبيعات', 'account_type': 'expense'},
    {'account_code': '34111', 'name': 'Raw Material Purchase Costs - Sales Cost', 'account_name': 'تكاليف مشتريات خام - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34112', 'name': 'Tips & Gratuities - Sales Cost', 'account_name': 'مصروفات اكراميات - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34113', 'name': 'Labor Expenses - Sales Cost', 'account_name': 'مصروفات عماله - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34114', 'name': 'Transport & Handling - Sales Cost', 'account_name': 'مصروفات نقل ومشال - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34115', 'name': 'Royalty Expenses - Sales Cost', 'account_name': 'مصروفات رويالتي - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34116', 'name': 'Reefer Rental - Sales Cost', 'account_name': 'مصروفات ايجار برادات - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34117', 'name': 'Clearance Expenses - Sales Cost', 'account_name': 'مصروفات تخليص - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34118', 'name': 'Freight / Ocean Freight - Sales Cost', 'account_name': 'مصروفات شحن (نولون) - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34119', 'name': 'Sample Analysis - Sales Cost', 'account_name': 'مصروفات تحاليل عينات - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '34110', 'name': 'Other Miscellaneous - Sales Cost', 'account_name': 'مصروفات متنوعه اخرى - تكلفه بيع', 'account_type': 'expense'},
    {'account_code': '41111', 'name': 'Strawberry Sales', 'account_name': 'مبيعات فراوله', 'account_type': 'revenue'},
    {'account_code': '41112', 'name': 'Mango Sales', 'account_name': 'مبيعات مانجو', 'account_type': 'revenue'},
    {'account_code': '41113', 'name': 'Dates Sales', 'account_name': 'مبيعات بلح', 'account_type': 'revenue'},
    {'account_code': '41114', 'name': 'Blueberry Sales', 'account_name': 'مبيعات بلوبيرى', 'account_type': 'revenue'},
    {'account_code': '41121', 'name': 'Local Sorting Sales', 'account_name': 'مبيعات فرزه محلي', 'account_type': 'revenue'},
    {'account_code': '42111', 'name': 'Credit Interest - CIB', 'account_name': 'فوائد دائنه - بنك التجارى الدولى CIB', 'account_type': 'revenue'},
    {'account_code': '42121', 'name': 'Commissions', 'account_name': 'عمولات', 'account_type': 'revenue'},

    {'account_code': '9111', 'name': 'Packaging Waste Intermediary', 'account_name': 'وسيط هالك مواد التعبئة', 'account_type': 'expense'},
    {'account_code': '9112', 'name': 'Produce Waste Intermediary', 'account_name': 'وسيط هالك المحاصيل', 'account_type': 'expense'},
    {'account_code': '9121', 'name': 'Tax Intermediary', 'account_name': 'وسيط ضرائب', 'account_type': 'system'},
    {'account_code': '9122', 'name': 'Allocated Taxes', 'account_name': 'ضرائب محملة', 'account_type': 'system'},
    {'account_code': '9123', 'name': 'Admin Expenses Provision', 'account_name': 'مخصص / وسيط مصروفات إدارية', 'account_type': 'system'},
    {'account_code': '9124', 'name': 'Allocated Admin Expenses', 'account_name': 'مصروفات إدارية محملة', 'account_type': 'system'},
  ];

  /// Ensure all required accounts exist; skip if already present.
  Future<void> ensureDefaultAccounts() async {
    for (final acc in defaultAccounts) {
      try {
        final exists = await _client
            .from('accounts')
            .select('id')
            .eq('account_code', acc['account_code'] as String)
            .limit(1);
        if ((exists as List).isEmpty) {
          await _client.from('accounts').insert({
            'account_code': acc['account_code'],
            'name': acc['name'],
            'account_name': acc['account_name'],
            'account_type': acc['account_type'],
          });
          debugPrint('ChartOfAccounts: created account ${acc['account_code']} — ${acc['account_name']}');
        }
      } catch (e) {
        debugPrint('ChartOfAccounts: error seeding ${acc['account_code']}: $e');
      }
    }
  }

  /// Ensure the supplier advance account (2120) exists, creating it if it doesn't.
  Future<void> ensureSupplierAdvanceAccount() async {
    try {
      final exists = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', '2120')
          .limit(1);
      if ((exists as List).isEmpty) {
        await _client.from('accounts').insert({
          'account_code': '2120',
          'name': 'Supplier Advances',
          'account_name': 'دفعات مقدمة للموردين',
          'type': 'asset',
        });
        debugPrint('ChartOfAccounts: created Supplier Advances account (2120)');
      }
    } catch (e) {
      debugPrint('ChartOfAccounts: error ensuring 2120: $e');
      rethrow;
    }
  }

  /// Ensures the complete hierarchical structure for Cost of Sales (34 -> 341 -> 3411 -> 34111..34110)
  Future<void> ensureCostOfSalesHierarchy() async {
    try {
      final root3 = await _client.from('accounts').select('id').eq('account_code', '3').maybeSingle();
      if (root3 == null) return;
      final root3Id = root3['id'];

      // Level 2: 34
      final acct34 = await _client.from('accounts').select('id').eq('account_code', '34').maybeSingle();
      dynamic id34;
      if (acct34 == null) {
        final ins = await _client.from('accounts').insert({
          'account_code': '34',
          'name': 'Cost of Sales',
          'account_name': 'تكاليف المبيعات',
          'account_type': 'expense',
          'normal_balance': 'Debit',
          'level': 2,
          'is_leaf': false,
          'allow_posting': false,
          'parent_id': root3Id,
          'sort_order': 3400,
        }).select('id').single();
        id34 = ins['id'];
      } else {
        id34 = acct34['id'];
        await _client.from('accounts').update({
          'parent_id': root3Id,
          'level': 2,
          'is_leaf': false,
          'allow_posting': false,
        }).eq('id', id34);
      }

      // Level 3: 341
      final acct341 = await _client.from('accounts').select('id').eq('account_code', '341').maybeSingle();
      dynamic id341;
      if (acct341 == null) {
        final ins = await _client.from('accounts').insert({
          'account_code': '341',
          'name': 'Cost of Sales',
          'account_name': 'تكاليف المبيعات',
          'account_type': 'expense',
          'normal_balance': 'Debit',
          'level': 3,
          'is_leaf': false,
          'allow_posting': false,
          'parent_id': id34,
          'sort_order': 3410,
        }).select('id').single();
        id341 = ins['id'];
      } else {
        id341 = acct341['id'];
        await _client.from('accounts').update({
          'parent_id': id34,
          'level': 3,
          'is_leaf': false,
          'allow_posting': false,
        }).eq('id', id341);
      }

      // Level 4: 3411
      final acct3411 = await _client.from('accounts').select('id').eq('account_code', '3411').maybeSingle();
      dynamic id3411;
      if (acct3411 == null) {
        final ins = await _client.from('accounts').insert({
          'account_code': '3411',
          'name': 'Cost of Sales Control',
          'account_name': 'تكاليف المبيعات',
          'account_type': 'expense',
          'normal_balance': 'Debit',
          'level': 4,
          'is_leaf': false,
          'allow_posting': false,
          'parent_id': id341,
          'sort_order': 3411,
        }).select('id').single();
        id3411 = ins['id'];
      } else {
        id3411 = acct3411['id'];
        await _client.from('accounts').update({
          'parent_id': id341,
          'level': 4,
          'is_leaf': false,
          'allow_posting': false,
        }).eq('id', id3411);
      }

      // Level 5: 34111..34110
      final l5 = [
        {'code': '34111', 'name': 'Raw Material Purchase Costs - Sales Cost', 'ar': 'تكاليف مشتريات خام - تكلفه بيع', 'order': 34111},
        {'code': '34112', 'name': 'Tips & Gratuities - Sales Cost', 'ar': 'مصروفات اكراميات - تكلفه بيع', 'order': 34112},
        {'code': '34113', 'name': 'Labor Expenses - Sales Cost', 'ar': 'مصروفات عماله - تكلفه بيع', 'order': 34113},
        {'code': '34114', 'name': 'Transport & Handling - Sales Cost', 'ar': 'مصروفات نقل ومشال - تكلفه بيع', 'order': 34114},
        {'code': '34115', 'name': 'Royalty Expenses - Sales Cost', 'ar': 'مصروفات رويالتي - تكلفه بيع', 'order': 34115},
        {'code': '34116', 'name': 'Reefer Rental - Sales Cost', 'ar': 'مصروفات ايجار برادات - تكلفه بيع', 'order': 34116},
        {'code': '34117', 'name': 'Clearance Expenses - Sales Cost', 'ar': 'مصروفات تخليص - تكلفه بيع', 'order': 34117},
        {'code': '34118', 'name': 'Freight / Ocean Freight - Sales Cost', 'ar': 'مصروفات شحن (نولون) - تكلفه بيع', 'order': 34118},
        {'code': '34119', 'name': 'Sample Analysis - Sales Cost', 'ar': 'مصروفات تحاليل عينات - تكلفه بيع', 'order': 34119},
        {'code': '34110', 'name': 'Other Miscellaneous - Sales Cost', 'ar': 'مصروفات متنوعه اخرى - تكلفه بيع', 'order': 34110},
      ];

      for (final a in l5) {
        final existing = await _client.from('accounts').select('id').eq('account_code', a['code'] as String).maybeSingle();
        if (existing == null) {
          await _client.from('accounts').insert({
            'account_code': a['code'],
            'name': a['name'],
            'account_name': a['ar'],
            'account_type': 'expense',
            'normal_balance': 'Debit',
            'level': 5,
            'is_leaf': true,
            'allow_posting': true,
            'parent_id': id3411,
            'sort_order': a['order'],
          });
        } else {
          await _client.from('accounts').update({
            'parent_id': id3411,
            'level': 5,
            'is_leaf': true,
            'allow_posting': true,
          }).eq('id', existing['id']);
        }
      }
    } catch (e) {
      debugPrint('Error ensuring Cost of Sales hierarchy: $e');
    }
  }

  /// Get account ID by code. Returns null if not found.
  Future<int?> getAccountId(String code) async {
    try {
      final data = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', code)
          .maybeSingle();
      if (data == null) return null;
      final raw = data['id'];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  /// Get posting account ID by code (Level 5 / is_leaf = true). Returns null if not leaf or not found.
  Future<int?> getPostingAccountId(String code) async {
    try {
      final data = await _client
          .from('accounts')
          .select('id, is_leaf, is_active')
          .eq('account_code', code)
          .maybeSingle();
      if (data == null) return null;
      if (data['is_leaf'] != true || data['is_active'] == false) return null;
      final raw = data['id'];
      if (raw is int) return raw;
      return int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  /// Get all accounts.
  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final data = await _client
        .from('accounts')
        .select('id, account_code, name, account_name, account_type, balance, is_active')
        .order('account_code', ascending: true);
    return (data as List).cast<Map<String, dynamic>>();
  }
}
