class ClearingAgentModel {
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
      'city': city,
      'country': country,
      'gmail': gmail,
      'broker_type': brokerType,
      'contact_person_name': contactPersonName,
      'contact_person_phone': contactPersonPhone,
      'contact_person_email': contactPersonEmail,
      'balance': balance,
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
