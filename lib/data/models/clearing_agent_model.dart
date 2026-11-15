class ClearingAgentModel {
  // ── Scalable 5-Digit Category Range Constants ──
  static const int maritimeMinCode = 20000;
  static const int maritimeMaxCode = 24999;
  static const int maritimeCapacity = 5000;
  static const String maritimeCodeHint = 'مثال: 20000 (نطاق 20000 - 24999)';

  static const int airMinCode = 25000;
  static const int airMaxCode = 29999;
  static const int airCapacity = 5000;
  static const String airCodeHint = 'مثال: 25000 (نطاق 25000 - 29999)';

  static bool isMaritime(String? type) =>
      type == null || type.trim().isEmpty || type.trim() == 'بحري' || type.trim().toLowerCase() == 'maritime' || type.trim().toLowerCase() == 'sea';

  static int getMinCode(String? type) => isMaritime(type) ? maritimeMinCode : airMinCode;
  static int getMaxCode(String? type) => isMaritime(type) ? maritimeMaxCode : airMaxCode;
  static String getHint(String? type) => isMaritime(type) ? maritimeCodeHint : airCodeHint;
  static String getLabel(String? type) => isMaritime(type) ? 'المخلص الجمركي (بحري)' : 'المخلص الجمركي (جوي)';

  static String? validateClearingAgentCode(String? code, String? brokerType) {
    if (code == null || code.trim().isEmpty) {
      return 'كود المخلص مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }
    final min = getMinCode(brokerType);
    final max = getMaxCode(brokerType);
    final label = getLabel(brokerType);
    if (num < min || num > max) {
      return 'كود $label يجب أن يكون بين $min و $max';
    }
    return null;
  }

  final String? id;
  final String code;
  final String name;
  final String phone;
  final String city;
  final String country;
  final String gmail;
  final String brokerType;
  final String contactPersonName;
  final String contactPersonPhone;
  final String contactPersonEmail;
  final List<Map<String, dynamic>> addresses;
  final double balance;
  final double initialBalance;
  final String initialBalanceDirection;
  final String currency;
  final String createdAt;

  const ClearingAgentModel({
    this.id,
    this.code = '',
    required this.name,
    this.phone = '',
    this.city = '',
    this.country = '',
    this.gmail = '',
    this.brokerType = 'بحري',
    this.contactPersonName = '',
    this.contactPersonPhone = '',
    this.contactPersonEmail = '',
    this.addresses = const [],
    this.balance = 0.0,
    this.initialBalance = 0.0,
    this.initialBalanceDirection = 'CREDIT',
    this.currency = 'EGP',
    required this.createdAt,
  });

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

  factory ClearingAgentModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return ClearingAgentModel(
      id: map['id']?.toString(),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      phone: str(map['phone']) ?? '',
      city: str(map['city']) ?? '',
      country: str(map['country']) ?? '',
      gmail: str(map['gmail']) ?? '',
      brokerType: str(map['broker_type']) ?? 'بحري',
      contactPersonName: str(map['contact_person_name']) ?? '',
      contactPersonPhone: str(map['contact_person_phone']) ?? '',
      contactPersonEmail: str(map['contact_person_email']) ?? '',
      addresses: map['addresses'] is List
          ? (map['addresses'] as List).map((a) => Map<String, dynamic>.from(a as Map)).toList()
          : [],
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
      'city': city,
      'country': country,
      'gmail': gmail,
      'broker_type': brokerType,
      'contact_person_name': contactPersonName,
      'contact_person_phone': contactPersonPhone,
      'contact_person_email': contactPersonEmail,
      'balance': balance,
      'current_balance': balance,
      'initial_balance': initialBalance,
      'initial_balance_direction': initialBalanceDirection,
      'currency': currency,
      'created_at': createdAt,
    };
  }

  ClearingAgentModel copyWith({
    String? id,
    String? code,
    String? name,
    String? phone,
    String? city,
    String? country,
    String? gmail,
    String? brokerType,
    String? contactPersonName,
    String? contactPersonPhone,
    String? contactPersonEmail,
    List<Map<String, dynamic>>? addresses,
    double? balance,
    double? initialBalance,
    String? initialBalanceDirection,
    String? currency,
    String? createdAt,
  }) {
    return ClearingAgentModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      country: country ?? this.country,
      gmail: gmail ?? this.gmail,
      brokerType: brokerType ?? this.brokerType,
      contactPersonName: contactPersonName ?? this.contactPersonName,
      contactPersonPhone: contactPersonPhone ?? this.contactPersonPhone,
      contactPersonEmail: contactPersonEmail ?? this.contactPersonEmail,
      addresses: addresses ?? this.addresses,
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
      other is ClearingAgentModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
