class CustomerModel {
  // ── Scalable 5-Digit Category Range Constants ──
  static const int minCode = 12000;
  static const int maxCode = 19999;
  static const int capacity = 8000;
  static const String codeHint = 'مثال: 12000 (نطاق 12000 - 19999)';

  static String? validateCustomerCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'كود العميل مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }
    if (num < minCode || num > maxCode) {
      return 'كود العميل يجب أن يكون بين $minCode و $maxCode (السعة: $capacity عميل)';
    }
    return null;
  }

  final String? id;
  final String code;
  final String name;
  final String customerType;
  final int? accountId;
  final String phone;
  final String city;
  final String country;
  final String gmail;
  final String vatNumber;
  final String eoriNo;
  final String contactPersonName;
  final String contactPersonPhone;
  final String contactPersonEmail;
  final List<Map<String, dynamic>> addresses;
  final double balance;
  final double initialBalance;
  final String initialBalanceDirection;
  final String currency;
  final String createdAt;

  const CustomerModel({
    this.id,
    this.code = '',
    required this.name,
    this.customerType = 'export',
    this.accountId,
    this.phone = '',
    this.city = '',
    this.country = '',
    this.gmail = '',
    this.vatNumber = '',
    this.eoriNo = '',
    this.contactPersonName = '',
    this.contactPersonPhone = '',
    this.contactPersonEmail = '',
    this.addresses = const [],
    this.balance = 0.0,
    this.initialBalance = 0.0,
    this.initialBalanceDirection = 'DEBIT',
    this.currency = 'EGP',
    required this.createdAt,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    final addrRaw = map['addresses'];
    List<Map<String, dynamic>> addrs = [];
    if (addrRaw is List) {
      addrs = addrRaw.map((a) => Map<String, dynamic>.from(a as Map)).toList();
    }

    return CustomerModel(
      id: str(map['id']),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      customerType: str(map['company_type']) ?? str(map['customer_type']) ?? 'export',
      accountId: intVal(map['account_id']),
      phone: str(map['phone']) ?? '',
      city: str(map['city']) ?? '',
      country: str(map['country']) ?? '',
      gmail: str(map['gmail']) ?? '',
      vatNumber: str(map['vat_no']) ?? '',
      eoriNo: str(map['eori_no']) ?? '',
      contactPersonName: str(map['contact_person_name']) ?? '',
      contactPersonPhone: str(map['contact_person_phone']) ?? '',
      contactPersonEmail: str(map['contact_person_email']) ?? '',
      addresses: addrs,
      balance: numVal(map['balance'])?.toDouble() ?? 0.0,
      initialBalance: numVal(map['initial_balance'])?.toDouble() ?? 0.0,
      initialBalanceDirection: str(map['initial_balance_direction']) ?? 'DEBIT',
      currency: str(map['currency']) ?? 'EGP',
      createdAt: str(map['created_at']) ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'company_type': customerType,
      if (accountId != null) 'account_id': accountId,
      'phone': phone,
      'city': city,
      'country': country,
      'gmail': gmail,
      'vat_no': vatNumber,
      'eori_no': eoriNo,
      'contact_person_name': contactPersonName,
      'contact_person_phone': contactPersonPhone,
      'contact_person_email': contactPersonEmail,
      'balance': balance,
      'initial_balance_direction': initialBalanceDirection,
      'currency': currency,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'code': code,
      'name': name,
      'company_type': customerType,
      if (accountId != null) 'account_id': accountId,
      'phone': phone,
      'city': city,
      'country': country,
      'gmail': gmail,
      'vat_no': vatNumber,
      'eori_no': eoriNo,
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

  CustomerModel copyWith({
    String? id,
    String? code,
    String? name,
    String? customerType,
    int? accountId,
    String? phone,
    String? city,
    String? country,
    String? gmail,
    String? vatNumber,
    String? eoriNo,
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
    return CustomerModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      customerType: customerType ?? this.customerType,
      accountId: accountId ?? this.accountId,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      country: country ?? this.country,
      gmail: gmail ?? this.gmail,
      vatNumber: vatNumber ?? this.vatNumber,
      eoriNo: eoriNo ?? this.eoriNo,
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
      other is CustomerModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
