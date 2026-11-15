// AccountLedgerResult — Unified result model for account ledger queries
//
// Contains all computed values needed to display account entries:
// opening balance, running balances, totals, and sorted entries.
// This model is produced by AccountLedgerService and consumed
// by the Account Journal Entries Dialog.

class AccountLedgerResult {
  /// Opening balance before the period (computed server-side)
  final double openingBalance;

  /// Closing balance at end of period
  final double closingBalance;

  /// Total debit within the period
  final double totalDebit;

  /// Total credit within the period
  final double totalCredit;

  /// Number of transactions in the period
  final int transactionCount;

  /// Primary currency for this account
  final String currency;

  /// Whether this account has credit-normal nature
  final bool isCreditNormal;

  /// Account type string (asset, liability, equity, revenue, expense)
  final String accountType;

  /// Sorted list of entries with running balances pre-computed
  final List<AccountLedgerEntry> entries;

  const AccountLedgerResult({
    required this.openingBalance,
    required this.closingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.transactionCount,
    required this.currency,
    required this.isCreditNormal,
    required this.accountType,
    required this.entries,
  });

  /// Net movement during the period
  double get netMovement => totalDebit - totalCredit;

  static const empty = AccountLedgerResult(
    openingBalance: 0,
    closingBalance: 0,
    totalDebit: 0,
    totalCredit: 0,
    transactionCount: 0,
    currency: 'EGP',
    isCreditNormal: false,
    accountType: 'asset',
    entries: [],
  );
}

/// A single ledger entry with pre-computed running balance
class AccountLedgerEntry {
  /// Unique row ID from account_ledger_entries
  final String id;

  /// Transaction date (entry_date from journal_entries)
  final DateTime date;

  /// Journal entry number (e.g., JE-000123)
  final String? entryNumber;

  /// Source/reference type (e.g., purchase_invoice, supplier_payment, etc.)
  final String? referenceType;

  /// Source/reference ID
  final String? referenceId;

  /// Description / memo
  final String description;

  /// Debit amount (raw from ledger)
  final double debit;

  /// Credit amount (raw from ledger)
  final double credit;

  /// Pre-computed running balance after this entry
  final double runningBalance;

  /// Currency of this entry
  final String currency;

  /// Account code
  final String accountCode;

  /// Account display name
  final String accountName;

  /// Cost Center ID/code
  final String? costCenterId;

  /// Cost Center display name
  final String? costCenterName;

  /// Created at timestamp (for deterministic ordering)
  final String createdAt;

  /// Multi-currency original amounts and exchange rate
  final double? foreignDebit;
  final double? foreignCredit;
  final String? foreignCurrency;
  final double? exchangeRate;

  const AccountLedgerEntry({
    required this.id,
    required this.date,
    this.entryNumber,
    this.referenceType,
    this.referenceId,
    required this.description,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    required this.currency,
    required this.accountCode,
    required this.accountName,
    this.costCenterId,
    this.costCenterName,
    required this.createdAt,
    this.foreignDebit,
    this.foreignCredit,
    this.foreignCurrency,
    this.exchangeRate,
  });

  /// Whether this entry is a debit entry
  bool get isDebit => debit > 0;

  /// The effective amount (whichever side is non-zero)
  double get amount => debit > 0 ? debit : credit;

  /// Arabic label for the reference type
  String get referenceTypeLabel {
    switch (referenceType?.toLowerCase()) {
      case 'purchase_invoice':
      case 'purchase':
        return 'فاتورة مشتريات';
      case 'purchase_return':
        return 'مرتجع مشتريات';
      case 'supplier_payment':
        return 'سداد مورد';
      case 'sales_invoice':
      case 'invoice':
        return 'فاتورة مبيعات';
      case 'sales_return':
        return 'مرتجع مبيعات';
      case 'customer_receipt':
      case 'receipt':
      case 'receive':
        return 'تحصيل عميل';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'treasury_transfer':
      case 'treasury':
        return 'حركة خزينة';
      case 'bank_transfer':
      case 'bank':
        return 'حركة بنكية';
      case 'expense':
        return 'مصروف';
      case 'manual':
      case 'manual_journal':
        return 'قيد يدوي';
      case 'packing_order':
        return 'أمر تعبئة';
      case 'shipment':
      case 'export_shipment':
        return 'شحنة تصدير';
      case 'clearing':
        return 'تخليص جمركي';
      case 'cash_payment':
        return 'سداد نقدي';
      case 'cash_receipt':
        return 'قبض نقدي';
      case 'cheque':
        return 'شيك';
      case 'transfer':
        return 'تحويل';
      case 'lot_purchase':
        return 'شراء لوط';
      case 'lot_return':
        return 'مرتجع لوط';
      case 'closing':
        return 'قيد إقفال';
      default:
        if (referenceType == null || referenceType!.isEmpty) {
          return 'قيد محاسبي';
        }
        return referenceType!;
    }
  }
}
