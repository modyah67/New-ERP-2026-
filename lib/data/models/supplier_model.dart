class SupplierModel {
  final String? id;
  final String supplierCode;
  final String name;
  final String phone;
  final String address;
  final double initialBalance;
  final String initialBalanceDirection;
  final double outstandingBalance;
  final String currency;
  final String createdAt;

  const SupplierModel({
    this.id,
    required this.supplierCode,
    required this.name,
    this.phone = '',
    this.address = '',
    this.initialBalance = 0.0,
    this.initialBalanceDirection = 'CREDIT',
    this.outstandingBalance = 0.0,
    this.currency = 'EGP',
    this.createdAt = '',
  });

  String get displayName => '$supplierCode - $name';

  String get currencySymbol {
    switch (currency) {
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'EGP': return 'ج.م';
      default: return currency;
    }
  }

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    String str(dynamic v) => v?.toString() ?? '';
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    String code = str(map['supplier_code']);
    if (code.isEmpty) code = str(map['code']);
    if (code.isEmpty) {
      final legacyId = map['legacy_id'];
      if (legacyId != null) {
        code = 'SUP${legacyId.toString().padLeft(4, '0')}';
      } else {
        code = 'SUP-${str(map['id']).substring(0, 4).toUpperCase()}';
      }
    }

    final initialBal = numVal(map['initial_balance'])?.toDouble() ?? 0.0;
    final outstandingBal = map['computed_balance'] is num
        ? (map['computed_balance'] as num).toDouble()
        : (numVal(map['outstanding_balance'])?.toDouble() ?? initialBal);

    return SupplierModel(
      id: map['id']?.toString(),
      supplierCode: code,
      name: str(map['name']),
      phone: str(map['phone']),
      address: str(map['address']),
      initialBalance: initialBal,
      initialBalanceDirection: str(map['initial_balance_direction']).isNotEmpty ? str(map['initial_balance_direction']) : 'CREDIT',
      outstandingBalance: outstandingBal,
      currency: str(map['currency']).isNotEmpty ? str(map['currency']) : 'EGP',
      createdAt: str(map['created_at']) ?? '',
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      if (id != null) 'id': id,
      'supplier_code': supplierCode,
      'code': supplierCode,
      'name': name,
      'phone': phone,
      'address': address,
      'initial_balance': initialBalance,
      'initial_balance_direction': initialBalanceDirection,
      'outstanding_balance': outstandingBalance,
      'currency': currency,
    };
  }

  SupplierModel copyWith({
    String? id,
    String? supplierCode,
    String? name,
    String? phone,
    String? address,
    double? initialBalance,
    String? initialBalanceDirection,
    double? outstandingBalance,
    String? currency,
    String? createdAt,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      supplierCode: supplierCode ?? this.supplierCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      initialBalance: initialBalance ?? this.initialBalance,
      initialBalanceDirection: initialBalanceDirection ?? this.initialBalanceDirection,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierModel && supplierCode == other.supplierCode;

  @override
  int get hashCode => supplierCode.hashCode;
}
