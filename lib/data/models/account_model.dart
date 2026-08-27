class AccountModel {
  final String? id;
  final String code;
  final String name;
  final String? accountName;
  final String type;
  final String? parentId;
  final double balance;
  final bool isActive;
  final DateTime? deletedAt;

  /// Per-currency balances: { 'EGP': 100000.0, 'USD': 5000.0, ... }
  /// Populated from account_ledger_entries grouped by currency.
  final Map<String, double> balancesByCurrency;

  AccountModel({
    this.id,
    required this.code,
    required this.name,
    this.accountName,
    required this.type,
    this.parentId,
    this.balance = 0.0,
    this.isActive = true,
    this.deletedAt,
    this.balancesByCurrency = const {},
  });

  bool get isArchived => deletedAt != null;

  static const Map<String, String> _standardArabicNames = {
    // Codes
    '1000': 'الصندوق والنقدية',
    '1010': 'حسابات البنوك',
    '1020': 'العملاء (مدينون)',
    '1030': 'مخزون المحاصيل',
    '1031': 'مخزون الإنتاج التام',
    '1040': 'مخزون مواد التعبئة والتغليف',
    '1050': 'مصروفات التصدير والشحن',
    '2000': 'الموردون (دائنون)',
    '2100': 'الخصوم المتداولة الأخرى',
    '2106': 'وسيط هالك مواد التعبئة',
    '2107': 'وسيط هالك المحاصيل',
    '2120': 'دفعات مقدمة للموردين',
    '3000': 'حقوق الملكية / رأس المال',
    '3001': 'رأس مال المالك - ج.م',
    '3002': 'رأس مال المالك - دولار',
    '3003': 'رأس مال المالك - يورو',
    '3004': 'رأس مال المالك - جنيه إسترليني',
    '3100': 'الأرباح المحتجزة',
    '3101': 'رأس مال المساهمين',
    '3200': 'أرباح السنة الجارية',
    '3300': 'احتياطي رأس المال',
    '3900': 'الأرصدة الافتتاحية',
    '3901': 'الأرصدة الافتتاحية - ج.م',
    '3902': 'الأرصدة الافتتاحية - دولار',
    '3903': 'الأرصدة الافتتاحية - يورو',
    '3904': 'الأرصدة الافتتاحية - إسترليني',
    '4000': 'إيرادات المبيعات',
    '4100': 'الإيرادات العامة',
    '4110': 'إيرادات المبيعات المحلية',
    '41101': 'الإيرادات العامة',
    '4200': 'إيرادات التصدير',
    '4300': 'إيرادات أخرى',
    '5000': 'تكلفة البضاعة المباعة',
    '51101': 'مصروفات عامة',
    '51102': 'هالك وفاقد المحاصيل',
    '51103': 'تسوية وفرز المحاصيل',
    '51104': 'هالك وفاقد مواد التعبئة والتغليف',
    '6000': 'المصروفات العمومية والإدارية',
    '6100': 'مصروفات الرواتب والأجور',
    '6200': 'مصروفات الإيجار',
    '6300': 'مصروفات الكهرباء والمياه',
    '6400': 'مصروفات الصيانة والإصلاح',
    '6500': 'مصروفات النقل والانتقالات',
    '6600': 'مصروفات البوفيه والضيافة',
    '6700': 'مصروفات الدعاية والإعلان',
    '6800': 'مصروفات بنكية',
    '6900': 'مصروفات متنوعة',
    '7000': 'حساب المشتريات',
    // English names
    'cash': 'الصندوق والنقدية',
    'bank': 'حسابات البنوك',
    'accounts receivable': 'العملاء (مدينون)',
    'inventory': 'مخزون المحاصيل',
    'produce inventory': 'مخزون المحاصيل',
    'finished goods inventory': 'مخزون الإنتاج التام',
    'packing materials inventory': 'مخزون مواد التعبئة والتغليف',
    'export expenses': 'مصروفات التصدير',
    'accounts payable': 'الموردون (دائنون)',
    'supplier advances': 'دفعات مقدمة للموردين',
    'owner equity': 'حقوق الملكية / رأس المال',
    'equity': 'حقوق الملكية',
    'sales revenue': 'إيرادات المبيعات',
    'general revenue': 'الإيرادات العامة',
    'export revenue': 'إيرادات التصدير',
    'other revenue': 'إيرادات أخرى',
    'other revenues': 'إيرادات أخرى',
    'local revenue': 'الإيرادات المحلية',
    'local sales revenue': 'إيرادات المبيعات المحلية',
    'services revenue': 'إيرادات الخدمات',
    'interest income': 'إيرادات الفوائد',
    'investment income': 'إيرادات الاستثمار',
    'rental income': 'إيرادات الإيجار',
    'gain on asset disposal': 'أرباح بيع أصول',
    'cost of goods sold': 'تكلفة البضاعة المباعة',
    'expenses': 'المصروفات',
    'general expenses': 'مصروفات عمومية',
    'purchase account': 'حساب المشتريات',
    'assets': 'الأصول',
    'liabilities': 'الخصوم',
    'current assets': 'الأصول المتداولة',
    'fixed assets': 'الأصول الثابتة',
    'current liabilities': 'الخصوم المتداولة',
    'non-current liabilities': 'الخصوم غير المتداولة',
    'revenues': 'الإيرادات',
    'operating expenses': 'المصروفات التشغيلية',
    'administrative expenses': 'المصروفات الإدارية',
    'tax': 'الضرائب',
    'vat': 'ضريبة القيمة المضافة',
    'retained earnings': 'الأرباح المبقاة / المرحلة',
    'capital': 'رأس المال',
    'salaries': 'الرواتب والأجور',
    'rent': 'الإيجار',
    'utilities': 'المنافع والخدمات',
    'electricity': 'الكهرباء والمياه',
    'water': 'المياه',
    'maintenance': 'الصيانة والإصلاح',
    'transportation': 'النقل والانتقالات',
    'freight': 'الشحن والنولون',
    'customs': 'الجمارك والتخليص',
    'hospitality': 'الضيافة والبوفيه',
    'advertising': 'الدعاية والإعلان',
    'marketing': 'التسويق والإعلان',
    'bank charges': 'مصروفات ورسوم بنكية',
    'bank fees': 'رسوم بنكية',
    'interest expense': 'مصروفات الفوائد',
    'office supplies': 'أدوات مكتبية ومطبوعات',
    'legal and professional': 'أتعاب قانونية ومهنية',
    'depreciation': 'مصروف الإهلاك',
    'miscellaneous': 'مصروفات نثرية ومتنوعة',
  };

  static bool _hasArabicChars(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  /// Localized Arabic name for the account.
  String get displayName {
    // 1. If accountName has Arabic characters, use it
    if (accountName != null && accountName!.trim().isNotEmpty) {
      if (_hasArabicChars(accountName!)) {
        return accountName!.trim();
      }
    }
    // 2. If name has Arabic characters, use it
    if (name.trim().isNotEmpty && _hasArabicChars(name)) {
      return name.trim();
    }
    // 3. Match standard mapping by code
    if (_standardArabicNames.containsKey(code.trim())) {
      return _standardArabicNames[code.trim()]!;
    }
    // 4. Match standard mapping by English name (lowercased)
    final lowerName = name.trim().toLowerCase();
    if (_standardArabicNames.containsKey(lowerName)) {
      return _standardArabicNames[lowerName]!;
    }
    final lowerAccName = (accountName ?? '').trim().toLowerCase();
    if (_standardArabicNames.containsKey(lowerAccName)) {
      return _standardArabicNames[lowerAccName]!;
    }
    // 5. Fallback to accountName or name or code
    if (accountName != null && accountName!.trim().isNotEmpty) {
      return accountName!.trim();
    }
    return name.trim().isNotEmpty ? name.trim() : code;
  }

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    final rawAccountName = (map['account_name'] ?? map['arabic_name'])?.toString();
    final rawName = (map['name'] ?? '').toString();

    return AccountModel(
      id: map['id']?.toString(),
      code: (map['account_code'] ?? map['code'] ?? '').toString(),
      name: rawName.isNotEmpty ? rawName : (rawAccountName ?? ''),
      accountName: rawAccountName,
      type: (map['account_type'] ?? map['type'] ?? 'asset').toString(),
      parentId: map['parent_id']?.toString(),
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      isActive: (map['is_active'] as bool?) ?? true,
      deletedAt: map['deleted_at'] != null
          ? DateTime.tryParse(map['deleted_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'account_code': code,
      'name': name,
      'account_name': (accountName != null && accountName!.isNotEmpty) ? accountName : displayName,
      'account_type': type,
      'parent_id': parentId,
      'balance': balance,
      'is_active': isActive,
    };
  }

  AccountModel copyWith({
    String? id,
    String? code,
    String? name,
    String? accountName,
    String? type,
    String? parentId,
    double? balance,
    bool? isActive,
    DateTime? deletedAt,
    Map<String, double>? balancesByCurrency,
  }) {
    return AccountModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      accountName: accountName ?? this.accountName,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      deletedAt: deletedAt ?? this.deletedAt,
      balancesByCurrency: balancesByCurrency ?? this.balancesByCurrency,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
