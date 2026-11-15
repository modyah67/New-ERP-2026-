class TransportSupplierModel {
  // ── Scalable 5-Digit Category Range Constants ──
  static const int minCode = 60000;
  static const int maxCode = 69999;
  static const int capacity = 10000;
  static const String codeHint = 'مثال: 60000 (نطاق 60000 - 69999)';

  static String? validateTransportCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'كود مورد النقل مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }
    if (num < minCode || num > maxCode) {
      return 'كود مورد النقل يجب أن يكون بين $minCode و $maxCode (السعة: $capacity مورد)';
    }
    return null;
  }

  final int? id;
  final String code;
  final String name;
  final String phone;
  final String email;
  final int? accountId;
  final double balance;
  final double truckBalance;
  final double initialBalance;
  final double initialTruckBalance;
  final String initialBalanceDirection;
  final String? notes;
  final String? companyId;
  final String createdAt;
  final String? updatedAt;

  const TransportSupplierModel({
    this.id,
    this.code = '',
    required this.name,
    this.phone = '',
    this.email = '',
    this.accountId,
    this.balance = 0.0,
    this.truckBalance = 0.0,
    this.initialBalance = 0.0,
    this.initialTruckBalance = 0.0,
    this.initialBalanceDirection = 'CREDIT',
    this.notes,
    this.companyId,
    required this.createdAt,
    this.updatedAt,
  });

  String get displayName => code.isNotEmpty ? '$code - $name' : name;

  factory TransportSupplierModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return TransportSupplierModel(
      id: intVal(map['id']),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      phone: str(map['phone']) ?? '',
      email: str(map['email']) ?? '',
      accountId: intVal(map['account_id']),
      balance: numVal(map['computed_balance'] ?? map['balance'])?.toDouble() ?? 0.0,
      truckBalance: numVal(map['computed_truck_balance'] ?? map['truck_balance'])?.toDouble() ?? 0.0,
      initialBalance: numVal(map['initial_balance'])?.toDouble() ?? 0.0,
      initialTruckBalance: numVal(map['initial_truck_balance'])?.toDouble() ?? 0.0,
      initialBalanceDirection: str(map['initial_balance_direction']) ?? 'CREDIT',
      notes: str(map['notes']),
      companyId: str(map['company_id']),
      createdAt: str(map['created_at']) ?? '',
      updatedAt: str(map['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'phone': phone,
      'email': email,
      if (accountId != null) 'account_id': accountId,
      'balance': balance,
      'truck_balance': truckBalance,
      'initial_balance': initialBalance,
      'initial_truck_balance': initialTruckBalance,
      'initial_balance_direction': initialBalanceDirection,
      'notes': notes,
      if (companyId != null) 'company_id': companyId,
      'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }

  TransportSupplierModel copyWith({
    int? id,
    String? code,
    String? name,
    String? phone,
    String? email,
    int? accountId,
    double? balance,
    double? truckBalance,
    double? initialBalance,
    double? initialTruckBalance,
    String? initialBalanceDirection,
    String? notes,
    String? companyId,
    String? createdAt,
    String? updatedAt,
  }) {
    return TransportSupplierModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      accountId: accountId ?? this.accountId,
      balance: balance ?? this.balance,
      truckBalance: truckBalance ?? this.truckBalance,
      initialBalance: initialBalance ?? this.initialBalance,
      initialTruckBalance: initialTruckBalance ?? this.initialTruckBalance,
      initialBalanceDirection:
          initialBalanceDirection ?? this.initialBalanceDirection,
      notes: notes ?? this.notes,
      companyId: companyId ?? this.companyId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportSupplierModel &&
          id != null &&
          other.id != null &&
          id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
