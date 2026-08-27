// lib/data/models/statement_row_model.dart
// ─────────────────────────────────────────────
// One row in the statement table (expanded per item).
// Extracted from statement_controller.dart so it can be
// shared across all statement features without importing
// the old GetX controller.
// ─────────────────────────────────────────────

class StatementRow {
  final String transactionNumber;
  final String date;
  final String accountName;
  final String description;
  final double piecesCount;
  final double quantity;
  final double unitPrice;
  final double debit;
  final double credit;
  final double balance;
  final String type;
  final String createdAt;
  
  // Newly added fields for Unified Ledger Engine mapping
  final String? id;
  final String? referenceType;
  final String? referenceId;
  final String? currency;
  final String? accountCode;

  const StatementRow({
    required this.transactionNumber,
    required this.date,
    required this.accountName,
    required this.description,
    required this.piecesCount,
    required this.quantity,
    required this.unitPrice,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.type,
    required this.createdAt,
    this.id,
    this.referenceType,
    this.referenceId,
    this.currency,
    this.accountCode,
  });
}
