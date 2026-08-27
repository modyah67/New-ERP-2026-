class ShippingCompanyModel {
  final int? id;
  final String code;
  final String name;
  final String phone;
  final String email;
  final double balance;
  final double initialBalance;
  final String initialBalanceDirection;
  final String currency;
  final String createdAt;

  const ShippingCompanyModel({
    this.id,
    this.code = '',
    required this.name,
    this.phone = '',
    this.email = '',
    this.balance = 0.0,
    this.initialBalance = 0.0,
    this.initialBalanceDirection = 'CREDIT',
    this.currency = 'EGP',
    required this.createdAt,
  });

  String get displayName => '$code - $name';

  factory ShippingCompanyModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return ShippingCompanyModel(
      id: intVal(map['id']),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      phone: str(map['phone']) ?? '',
      email: str(map['email']) ?? '',
      balance: numVal(map['balance'])?.toDouble() ?? 0.0,
      initialBalance: numVal(map['initial_balance'])?.toDouble() ?? 0.0,
      initialBalanceDirection: str(map['initial_balance_direction']) ?? 'CREDIT',
      currency: str(map['currency']) ?? 'EGP',
      createdAt: str(map['created_at']) ?? '',
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'code': code,
      'name': name,
      'phone': phone,
      'email': email,
      'balance': balance,
      'initial_balance': initialBalance,
      'initial_balance_direction': initialBalanceDirection,
      'currency': currency,
      'created_at': createdAt,
    };
  }

  ShippingCompanyModel copyWith({
    int? id,
    String? code,
    String? name,
    String? phone,
    String? email,
    double? balance,
    double? initialBalance,
    String? initialBalanceDirection,
    String? currency,
    String? createdAt,
  }) {
    return ShippingCompanyModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      balance: balance ?? this.balance,
      initialBalance: initialBalance ?? this.initialBalance,
      initialBalanceDirection: initialBalanceDirection ?? this.initialBalanceDirection,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShippingCompanyModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
