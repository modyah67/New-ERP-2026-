class BankAccountModel {
  final int id;
  final String name;
  final String? nameEn;
  final String currency;
  final double balance;
  final double costBase;
  final double bookRate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  BankAccountModel({
    required this.id,
    required this.name,
    this.nameEn,
    required this.currency,
    required this.balance,
    this.costBase = 0.0,
    this.bookRate = 1.0,
    this.createdAt,
    this.updatedAt,
  });

  factory BankAccountModel.fromMap(Map<String, dynamic> map) {
    final cur = (map['currency'] ?? '').toString().toUpperCase();
    final bal = (map['balance'] is num) ? (map['balance'] as num).toDouble() : 0.0;
    final cost = (map['cost_base'] is num) ? (map['cost_base'] as num).toDouble() : 0.0;
    double rate = (map['book_rate'] is num) ? (map['book_rate'] as num).toDouble() : 1.0;

    if (cur == 'EGP') {
      rate = 1.0;
    } else {
      if (bal > 0 && cost > 0) {
        rate = cost / bal;
      } else if (rate <= 1.0) {
        rate = cur == 'USD' ? 50.0 : (cur == 'EUR' ? 54.0 : (cur == 'GBP' ? 63.0 : 50.0));
      }
    }

    return BankAccountModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}') ?? 0,
      name: map['name'] ?? '',
      nameEn: map['name_en'],
      currency: cur,
      balance: bal,
      costBase: cost,
      bookRate: rate,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }

  BankAccountModel copyWith({
    double? balance,
    double? costBase,
    double? bookRate,
  }) {
    return BankAccountModel(
      id: id,
      name: name,
      nameEn: nameEn,
      currency: currency,
      balance: balance ?? this.balance,
      costBase: costBase ?? this.costBase,
      bookRate: bookRate ?? this.bookRate,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
