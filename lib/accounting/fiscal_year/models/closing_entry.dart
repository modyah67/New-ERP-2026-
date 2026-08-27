import 'package:equatable/equatable.dart';

class ClosingEntry extends Equatable {
  final int? id;
  final int fiscalYearId;
  final String entryType;
  final String accountCode;
  final String? accountName;
  final String? accountType;
  final double debit;
  final double credit;
  final dynamic currencySnapshot;
  final int? entryNumber;
  final int? transactionId;
  final String? description;
  final DateTime createdAt;

  const ClosingEntry({
    this.id,
    required this.fiscalYearId,
    this.entryType = 'CLOSE_REVENUE',
    required this.accountCode,
    this.accountName,
    this.accountType,
    this.debit = 0,
    this.credit = 0,
    this.currencySnapshot,
    this.entryNumber,
    this.transactionId,
    this.description,
    required this.createdAt,
  });

  factory ClosingEntry.fromJson(Map<String, dynamic> json) {
    return ClosingEntry(
      id: json['id'] as int?,
      fiscalYearId: json['fiscal_year_id'] as int,
      entryType: json['entry_type'] as String,
      accountCode: json['account_code'] as String,
      accountName: json['account_name'] as String?,
      accountType: json['account_type'] as String?,
      debit: (json['debit'] as num?)?.toDouble() ?? 0.0,
      credit: (json['credit'] as num?)?.toDouble() ?? 0.0,
      currencySnapshot: json['currency_snapshot'],
      entryNumber: json['entry_number'] as int?,
      transactionId: json['transaction_id'] as int?,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'fiscal_year_id': fiscalYearId,
      'entry_type': entryType,
      'account_code': accountCode,
      'account_name': accountName,
      'account_type': accountType,
      'debit': debit,
      'credit': credit,
      'currency_snapshot': currencySnapshot,
      'entry_number': entryNumber,
      'transaction_id': transactionId,
      'description': description,
    };
  }

  ClosingEntry copyWith({
    int? id,
    int? fiscalYearId,
    String? entryType,
    String? accountCode,
    String? accountName,
    String? accountType,
    double? debit,
    double? credit,
    dynamic currencySnapshot,
    int? entryNumber,
    int? transactionId,
    String? description,
  }) {
    return ClosingEntry(
      id: id ?? this.id,
      fiscalYearId: fiscalYearId ?? this.fiscalYearId,
      entryType: entryType ?? this.entryType,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      accountType: accountType ?? this.accountType,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      currencySnapshot: currencySnapshot ?? this.currencySnapshot,
      entryNumber: entryNumber ?? this.entryNumber,
      transactionId: transactionId ?? this.transactionId,
      description: description ?? this.description,
      createdAt: createdAt,
    );
  }

  bool get isDebit => debit > 0;
  bool get isCredit => credit > 0;

  @override
  List<Object?> get props => [id, fiscalYearId, entryType, accountCode, debit, credit];
}
