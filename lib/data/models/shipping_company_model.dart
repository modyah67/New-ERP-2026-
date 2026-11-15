class ShippingCompanyModel {
  // ── Scalable 5-Digit Category Range Constants ──
  static const int minCode = 90000;
  static const int maxCode = 99999;
  static const int capacity = 10000;
  static const String codeHint = 'مثال: 90000 (نطاق 90000 - 99999)';

  static String? validateShippingCompanyCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'كود شركة الشحن مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }
    if (num < minCode || num > maxCode) {
      return 'كود شركة الشحن يجب أن يكون بين $minCode و $maxCode (السعة: $capacity شركة)';
    }
    return null;
  }

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

  double get currentBalance => balance;

  String get currencySymbol {
    switch (currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'EGP':
      default:
        return 'ج.م';
    }
  }

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
      balance: (numVal(map['current_balance']) ?? numVal(map['balance']))?.toDouble() ?? 0.0,
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
      'current_balance': balance,
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
