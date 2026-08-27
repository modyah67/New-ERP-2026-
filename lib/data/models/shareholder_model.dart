class ShareholderModel {
  final String? id;
  final String code;
  final String name;
  final double initialBalanceEgp;
  final double currentBalanceEgp;
  final double initialBalanceUsd;
  final double currentBalanceUsd;
  final double initialBalanceEur;
  final double currentBalanceEur;
  final double initialBalanceGbp;
  final double currentBalanceGbp;
  final double totalDepositsEgp;
  final double totalWithdrawalsEgp;
  final double totalDepositsUsd;
  final double totalWithdrawalsUsd;
  final double totalDepositsEur;
  final double totalWithdrawalsEur;
  final double totalDepositsGbp;
  final double totalWithdrawalsGbp;
  final String initialBalanceDirectionEgp;
  final String initialBalanceDirectionUsd;
  final String initialBalanceDirectionEur;
  final String initialBalanceDirectionGbp;
  final String createdAt;

  const ShareholderModel({
    this.id,
    this.code = '',
    required this.name,
    this.initialBalanceEgp = 0.0,
    this.currentBalanceEgp = 0.0,
    this.initialBalanceUsd = 0.0,
    this.currentBalanceUsd = 0.0,
    this.initialBalanceEur = 0.0,
    this.currentBalanceEur = 0.0,
    this.initialBalanceGbp = 0.0,
    this.currentBalanceGbp = 0.0,
    this.totalDepositsEgp = 0.0,
    this.totalWithdrawalsEgp = 0.0,
    this.totalDepositsUsd = 0.0,
    this.totalWithdrawalsUsd = 0.0,
    this.totalDepositsEur = 0.0,
    this.totalWithdrawalsEur = 0.0,
    this.totalDepositsGbp = 0.0,
    this.totalWithdrawalsGbp = 0.0,
    this.initialBalanceDirectionEgp = 'CREDIT',
    this.initialBalanceDirectionUsd = 'CREDIT',
    this.initialBalanceDirectionEur = 'CREDIT',
    this.initialBalanceDirectionGbp = 'CREDIT',
    required this.createdAt,
  });

  factory ShareholderModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return ShareholderModel(
      id: str(map['id']),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      initialBalanceEgp: numVal(map['initial_balance_egp'])?.toDouble() ?? 0.0,
      currentBalanceEgp: numVal(map['current_balance_egp'])?.toDouble() ?? 0.0,
      initialBalanceUsd: numVal(map['initial_balance_usd'])?.toDouble() ?? 0.0,
      currentBalanceUsd: numVal(map['current_balance_usd'])?.toDouble() ?? 0.0,
      initialBalanceEur: numVal(map['initial_balance_eur'])?.toDouble() ?? 0.0,
      currentBalanceEur: numVal(map['current_balance_eur'])?.toDouble() ?? 0.0,
      initialBalanceGbp: numVal(map['initial_balance_gbp'])?.toDouble() ?? 0.0,
      currentBalanceGbp: numVal(map['current_balance_gbp'])?.toDouble() ?? 0.0,
      totalDepositsEgp: numVal(map['total_deposits_egp'])?.toDouble() ?? 0.0,
      totalWithdrawalsEgp: numVal(map['total_withdrawals_egp'])?.toDouble() ?? 0.0,
      totalDepositsUsd: numVal(map['total_deposits_usd'])?.toDouble() ?? 0.0,
      totalWithdrawalsUsd: numVal(map['total_withdrawals_usd'])?.toDouble() ?? 0.0,
      totalDepositsEur: numVal(map['total_deposits_eur'])?.toDouble() ?? 0.0,
      totalWithdrawalsEur: numVal(map['total_withdrawals_eur'])?.toDouble() ?? 0.0,
      totalDepositsGbp: numVal(map['total_deposits_gbp'])?.toDouble() ?? 0.0,
      totalWithdrawalsGbp: numVal(map['total_withdrawals_gbp'])?.toDouble() ?? 0.0,
      initialBalanceDirectionEgp: str(map['initial_balance_direction_egp']) ?? 'CREDIT',
      initialBalanceDirectionUsd: str(map['initial_balance_direction_usd']) ?? 'CREDIT',
      initialBalanceDirectionEur: str(map['initial_balance_direction_eur']) ?? 'CREDIT',
      initialBalanceDirectionGbp: str(map['initial_balance_direction_gbp']) ?? 'CREDIT',
      createdAt: str(map['created_at']) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'initial_balance_egp': initialBalanceEgp,
      'current_balance_egp': currentBalanceEgp,
      'initial_balance_usd': initialBalanceUsd,
      'current_balance_usd': currentBalanceUsd,
      'initial_balance_eur': initialBalanceEur,
      'current_balance_eur': currentBalanceEur,
      'initial_balance_gbp': initialBalanceGbp,
      'current_balance_gbp': currentBalanceGbp,
      'initial_balance_direction_egp': initialBalanceDirectionEgp,
      'initial_balance_direction_usd': initialBalanceDirectionUsd,
      'initial_balance_direction_eur': initialBalanceDirectionEur,
      'initial_balance_direction_gbp': initialBalanceDirectionGbp,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'code': code,
      'name': name,
      'initial_balance_egp': initialBalanceEgp,
      'current_balance_egp': currentBalanceEgp,
      'initial_balance_usd': initialBalanceUsd,
      'current_balance_usd': currentBalanceUsd,
      'initial_balance_eur': initialBalanceEur,
      'current_balance_eur': currentBalanceEur,
      'initial_balance_gbp': initialBalanceGbp,
      'current_balance_gbp': currentBalanceGbp,
      'initial_balance_direction_egp': initialBalanceDirectionEgp,
      'initial_balance_direction_usd': initialBalanceDirectionUsd,
      'initial_balance_direction_eur': initialBalanceDirectionEur,
      'initial_balance_direction_gbp': initialBalanceDirectionGbp,
      'created_at': createdAt,
    };
  }

  ShareholderModel copyWith({
    String? id,
    String? code,
    String? name,
    double? initialBalanceEgp,
    double? currentBalanceEgp,
    double? initialBalanceUsd,
    double? currentBalanceUsd,
    double? initialBalanceEur,
    double? currentBalanceEur,
    double? initialBalanceGbp,
    double? currentBalanceGbp,
    double? totalDepositsEgp,
    double? totalWithdrawalsEgp,
    double? totalDepositsUsd,
    double? totalWithdrawalsUsd,
    double? totalDepositsEur,
    double? totalWithdrawalsEur,
    double? totalDepositsGbp,
    double? totalWithdrawalsGbp,
    String? initialBalanceDirectionEgp,
    String? initialBalanceDirectionUsd,
    String? initialBalanceDirectionEur,
    String? initialBalanceDirectionGbp,
    String? createdAt,
  }) {
    return ShareholderModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      initialBalanceEgp: initialBalanceEgp ?? this.initialBalanceEgp,
      currentBalanceEgp: currentBalanceEgp ?? this.currentBalanceEgp,
      initialBalanceUsd: initialBalanceUsd ?? this.initialBalanceUsd,
      currentBalanceUsd: currentBalanceUsd ?? this.currentBalanceUsd,
      initialBalanceEur: initialBalanceEur ?? this.initialBalanceEur,
      currentBalanceEur: currentBalanceEur ?? this.currentBalanceEur,
      initialBalanceGbp: initialBalanceGbp ?? this.initialBalanceGbp,
      currentBalanceGbp: currentBalanceGbp ?? this.currentBalanceGbp,
      totalDepositsEgp: totalDepositsEgp ?? this.totalDepositsEgp,
      totalWithdrawalsEgp: totalWithdrawalsEgp ?? this.totalWithdrawalsEgp,
      totalDepositsUsd: totalDepositsUsd ?? this.totalDepositsUsd,
      totalWithdrawalsUsd: totalWithdrawalsUsd ?? this.totalWithdrawalsUsd,
      totalDepositsEur: totalDepositsEur ?? this.totalDepositsEur,
      totalWithdrawalsEur: totalWithdrawalsEur ?? this.totalWithdrawalsEur,
      totalDepositsGbp: totalDepositsGbp ?? this.totalDepositsGbp,
      totalWithdrawalsGbp: totalWithdrawalsGbp ?? this.totalWithdrawalsGbp,
      initialBalanceDirectionEgp: initialBalanceDirectionEgp ?? this.initialBalanceDirectionEgp,
      initialBalanceDirectionUsd: initialBalanceDirectionUsd ?? this.initialBalanceDirectionUsd,
      initialBalanceDirectionEur: initialBalanceDirectionEur ?? this.initialBalanceDirectionEur,
      initialBalanceDirectionGbp: initialBalanceDirectionGbp ?? this.initialBalanceDirectionGbp,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShareholderModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
