import '../../core/utils.dart';

/// Definition and metadata for supplier code ranges
class SupplierCategoryRange {
  final String categoryKey;
  final String label;
  final int minCode;
  final int maxCode;
  final int capacity;
  final String hint;

  const SupplierCategoryRange({
    required this.categoryKey,
    required this.label,
    required this.minCode,
    required this.maxCode,
    this.capacity = 10000,
    required this.hint,
  });

  bool contains(int code) => code >= minCode && code <= maxCode;
}

/// Structured currency opening balance entry
class SupplierCurrencyBalance {
  final String currency;
  final double amount;
  final String direction; // 'CREDIT' or 'DEBIT'
  final double exchangeRate; // FX rate against EGP

  const SupplierCurrencyBalance({
    required this.currency,
    this.amount = 0.0,
    this.direction = 'CREDIT',
    this.exchangeRate = 1.0,
  });

  /// Converted balance in Egyptian Pounds (EGP)
  double get amountInEgp => amount * (exchangeRate > 0 ? exchangeRate : 1.0);

  /// Signed amount: positive for CREDIT (له), negative for DEBIT (عليه)
  double get signedAmount => direction == 'CREDIT' ? amount : -amount;
  double get signedAmountInEgp => direction == 'CREDIT' ? amountInEgp : -amountInEgp;

  /// Currency symbol (e.g., $, €, £, ج.م)
  String get symbol => SupplierModel.getCurrencySymbol(currency);

  Map<String, dynamic> toMap() => {
    'currency': currency,
    'amount': amount,
    'direction': direction,
    'exchange_rate': exchangeRate,
    'amount_egp': amountInEgp,
  };

  factory SupplierCurrencyBalance.fromMap(Map<String, dynamic> map) {
    return SupplierCurrencyBalance(
      currency: map['currency']?.toString() ?? 'EGP',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      direction: map['direction']?.toString() ?? 'CREDIT',
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
    );
  }

  SupplierCurrencyBalance copyWith({
    String? currency,
    double? amount,
    String? direction,
    double? exchangeRate,
  }) {
    return SupplierCurrencyBalance(
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      exchangeRate: exchangeRate ?? this.exchangeRate,
    );
  }
}

class SupplierModel {
  final String? id;
  final String supplierCode;
  final String name;
  final String phone;
  final String address;
  final double initialBalance;
  final String initialBalanceDirection;
  final double outstandingBalance;
  final double? _pendingExpectedBalance;
  final String currency;
  final String createdAt;
  final String supplierType; // 'crop', 'packaging', 'shared'
  final int? accountId; // Direct Master Account ID binding (Level-5 control account)
  final List<String> categories; // Operational services or deduction categories

  // ── Multi-Currency Support (Applicable to Any Supplier Type) ──
  final bool isMultiCurrency;
  final List<String> supportedCurrencies;
  final String cropCurrency;
  final String packagingCurrency;
  final Map<String, SupplierCurrencyBalance> initialBalancesByCurrency;
  final Map<String, double> currentBalancesByCurrency;

  // ── Scalable 5-Digit Category Range Constants ──
  static const cropRange = SupplierCategoryRange(
    categoryKey: 'crop',
    label: 'موردين المحاصيل',
    minCode: 50000,
    maxCode: 59999,
    capacity: 10000,
    hint: 'مثال: 50000 (نطاق 50000 - 59999)',
  );

  static const transportRange = SupplierCategoryRange(
    categoryKey: 'transport',
    label: 'موردين النقل',
    minCode: 60000,
    maxCode: 69999,
    capacity: 10000,
    hint: 'مثال: 60000 (نطاق 60000 - 69999)',
  );

  static const packagingRange = SupplierCategoryRange(
    categoryKey: 'packaging',
    label: 'موردين مواد التعبئة والتغليف',
    minCode: 70000,
    maxCode: 74999,
    capacity: 5000,
    hint: 'مثال: 70000 (نطاق 70000 - 74999)',
  );

  static const sharedRange = SupplierCategoryRange(
    categoryKey: 'shared',
    label: 'الموردين المشتركين (محاصيل وتعبئة)',
    minCode: 75000,
    maxCode: 79999,
    capacity: 5000,
    hint: 'مثال: 75000 (نطاق 75000 - 79999)',
  );

  static const stationRange = SupplierCategoryRange(
    categoryKey: 'station',
    label: 'موردين المحطات',
    minCode: 85000,
    maxCode: 89999,
    capacity: 5000,
    hint: 'مثال: 85000 (نطاق 85000 - 89999)',
  );

  static const deductionsRange = SupplierCategoryRange(
    categoryKey: 'deduction',
    label: 'موردين التخصيمات',
    minCode: 40000,
    maxCode: 49999,
    capacity: 10000,
    hint: 'مثال: 40000 (نطاق 40000 - 49999)',
  );

  static const shippingRange = SupplierCategoryRange(
    categoryKey: 'shipping',
    label: 'شركات الشحن',
    minCode: 90000,
    maxCode: 99999,
    capacity: 10000,
    hint: 'مثال: 90000 (نطاق 90000 - 99999)',
  );

  static SupplierCategoryRange getCategoryRange(String type) {
    switch (type.toLowerCase()) {
      case 'crop':
        return cropRange;
      case 'deduction':
      case 'deductions':
        return deductionsRange;
      case 'transport':
        return transportRange;
      case 'packaging':
      case 'sticker':
        return packagingRange;
      case 'shared':
        return sharedRange;
      case 'station':
        return stationRange;
      case 'shipping':
        return shippingRange;
      default:
        return cropRange;
    }
  }

  /// Strict code validation ensuring code strictly matches its assigned category range
  static String? validateSupplierCode(String? code, String supplierType) {
    if (code == null || code.trim().isEmpty) {
      return 'كود المورد مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }

    final range = getCategoryRange(supplierType);
    if (!range.contains(num)) {
      return 'كود ${range.label} يجب أن يكون بين ${range.minCode} و ${range.maxCode}';
    }
    return null;
  }

  /// Strict supplier name validation
  static String? validateSupplierName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'اسم المورد مطلوب';
    }
    if (name.trim().length < 2) {
      return 'اسم المورد قصير جداً (حرفان على الأقل)';
    }
    return null;
  }

  const SupplierModel({
    this.id,
    required this.supplierCode,
    required this.name,
    this.phone = '',
    this.address = '',
    this.initialBalance = 0.0,
    this.initialBalanceDirection = 'CREDIT',
    this.outstandingBalance = 0.0,
    double? pendingExpectedBalance = 0.0,
    this.currency = 'EGP',
    this.createdAt = '',
    this.supplierType = 'crop',
    this.accountId,
    this.categories = const [],
    this.isMultiCurrency = false,
    this.supportedCurrencies = const ['EGP', 'USD', 'EUR'],
    this.cropCurrency = 'USD',
    this.packagingCurrency = 'EGP',
    this.initialBalancesByCurrency = const {},
    this.currentBalancesByCurrency = const {},
  }) : _pendingExpectedBalance = pendingExpectedBalance;

  String get displayName => '$supplierCode - $name';
  String get category => supplierType;
  String get code => supplierCode;
  String get direction => initialBalanceDirection;
  double get balance => nativeCurrentBalance;

  int get codeNumber => int.tryParse(supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  bool get isCropSupplier => supplierType == 'crop' || supplierType == 'shared';
  bool get isPackagingSupplier => supplierType == 'packaging' || supplierType == 'shared';
  bool get isSharedSupplier => supplierType == 'shared';
  bool get isStationSupplier =>
      supplierType.toLowerCase() == 'station' || (codeNumber >= 85000 && codeNumber <= 89999);
  bool get isDeductionSupplier =>
      supplierType.toLowerCase() == 'deduction' ||
      supplierType.toLowerCase() == 'deductions' ||
      (codeNumber >= 40000 && codeNumber <= 49999);
  bool get isEgpOnlySupplier => isStationSupplier || isDeductionSupplier;

  static bool isEgpOnlyCategoryOrCode(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase().trim();
    final c = (code ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(c) ?? 0;
    if (t == 'station' || (num >= 85000 && num <= 89999)) return true;
    if (t == 'deduction' || t == 'deductions' || (num >= 40000 && num <= 49999)) return true;
    return false;
  }

  /// Total value of pending expected costs awaiting actual settlement
  double get pendingExpectedBalance => _pendingExpectedBalance ?? 0.0;

  /// Whether the supplier has pending expected costs awaiting actual settlement
  bool get hasPendingBalance => pendingExpectedBalance.abs() > 0.001;

  /// Formatted pending expected balance string
  String get formattedPendingExpectedBalance =>
      '${AppUtils.formatCurrency(pendingExpectedBalance)} ج.م';

  /// Total projected balance combining confirmed actual balance + pending expected balance
  double get totalProjectedBalance => outstandingBalance + pendingExpectedBalance;

  /// Formatted total projected balance string
  String get formattedTotalProjectedBalance =>
      '${AppUtils.formatCurrency(totalProjectedBalance)} ج.م';

  /// Whether this supplier supports transactions in multiple currencies.
  /// Decoupled from supplierType, can be enabled for crop, packaging, or shared.
  bool get supportsMultiCurrency => isMultiCurrency || currency == 'MULTI';

  /// Primary transaction currency
  String get primaryCurrency => isMultiCurrency
      ? (supportedCurrencies.isNotEmpty ? supportedCurrencies.first : 'EGP')
      : currency;

  /// Dynamic transaction currency selector based on stream type (crop vs packaging)
  String getCurrencyForTransactionType(String type) {
    if (!supportsMultiCurrency) return currency;
    switch (type.toLowerCase()) {
      case 'crop':
      case 'lot':
        return cropCurrency.isNotEmpty
            ? cropCurrency
            : (supportedCurrencies.contains('USD') ? 'USD' : primaryCurrency);
      case 'packaging':
      case 'material':
        return packagingCurrency.isNotEmpty
            ? packagingCurrency
            : (supportedCurrencies.contains('EGP') ? 'EGP' : primaryCurrency);
      default:
        return primaryCurrency;
    }
  }

  /// Total calculated opening balance in EGP across all configured currencies
  double get totalInitialBalanceInEgp {
    if (!supportsMultiCurrency || initialBalancesByCurrency.isEmpty) {
      return initialBalanceDirection == 'CREDIT' ? initialBalance : -initialBalance;
    }
    double total = 0.0;
    for (final item in initialBalancesByCurrency.values) {
      total += item.signedAmountInEgp;
    }
    return total;
  }

  /// Whether the supplier has active non-zero multi-currency initial balances
  bool get hasMultiCurrencyInitialBalance {
    if (!supportsMultiCurrency || initialBalancesByCurrency.isEmpty) return false;
    return initialBalancesByCurrency.values.any((b) => b.amount > 0);
  }

  /// Whether this supplier is registered in a foreign currency (non-EGP and non-MULTI)
  bool get isForeignCurrency => currency.isNotEmpty && currency != 'EGP' && currency != 'MULTI';

  /// Returns the current balance in the supplier's native registered currency.
  /// If [currentBalancesByCurrency] contains the registered currency, it takes precedence.
  double get nativeCurrentBalance {
    if (currentBalancesByCurrency.containsKey(currency)) {
      return currentBalancesByCurrency[currency]!;
    }
    if (currentBalancesByCurrency.isNotEmpty) {
      return currentBalancesByCurrency.values.first;
    }
    return outstandingBalance;
  }

  static String getCurrencySymbol(String cur) {
    switch (cur.toUpperCase()) {
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'EGP': return 'ج.م';
      default: return cur;
    }
  }

  /// Formats an amount with its currency code/symbol following standard ERP convention.
  /// Western currencies (GBP, USD, EUR) prefix the symbol (e.g., £100.00, $50.00).
  /// EGP suffixes the symbol (e.g., 6,000.00 ج.م).
  static String formatCurrency(
    double amount,
    String currencyCode, {
    bool isDebit = false,
    bool showDecimals = true,
  }) {
    final absVal = amount.abs();
    final sign = (amount < 0 || isDebit) ? '-' : '';
    final code = currencyCode.toUpperCase();
    final sym = getCurrencySymbol(code);
    final amtFormatted = showDecimals
        ? AppUtils.formatNumber(absVal)
        : (absVal.truncateToDouble() == absVal
            ? absVal.toStringAsFixed(0)
            : AppUtils.formatNumber(absVal));

    switch (code) {
      case 'GBP':
      case 'USD':
      case 'EUR':
        return '$sign$sym$amtFormatted';
      case 'EGP':
      default:
        return '$sign$amtFormatted $sym';
    }
  }

  /// Formatted native opening balance string with directional indicator (له / عليه)
  String get formattedInitialBalance {
    if (supportsMultiCurrency && initialBalancesByCurrency.isNotEmpty) {
      final activeEntries = initialBalancesByCurrency.values
          .where((b) => b.amount > 0)
          .toList();
      if (activeEntries.length > 1) {
        return activeEntries.map((b) {
          final amtFormatted = b.amount.toStringAsFixed(
              b.amount.truncateToDouble() == b.amount ? 0 : 2);
          final dir = b.direction.toUpperCase() == 'DEBIT' ? ' (عليه)' : ' (له)';
          return '$amtFormatted ${b.symbol}$dir';
        }).join(' | ');
      } else if (activeEntries.length == 1) {
        final b = activeEntries.first;
        final dir = b.direction.toUpperCase() == 'DEBIT' ? ' (عليه)' : ' (له)';
        return '${formatCurrency(b.amount, b.currency)}$dir';
      }
    }
    if (initialBalance == 0.0) return '0.00';
    final isDebit = initialBalanceDirection.toUpperCase() == 'DEBIT';
    final effCurrency = (currency == 'MULTI')
        ? (cropCurrency.isNotEmpty ? cropCurrency : 'EGP')
        : currency;
    final dir = isDebit ? ' (عليه)' : ' (له)';
    return '${formatCurrency(initialBalance, effCurrency)}$dir';
  }

  /// Map of active non-zero current balances for multi-currency display
  Map<String, double> get activeCurrentBalances {
    if (!supportsMultiCurrency) return {};
    final active = <String, double>{};
    currentBalancesByCurrency.forEach((k, v) {
      if (v.abs() > 0.001) active[k] = v;
    });
    return active;
  }

  /// Formatted native current balance string with directional indicator (له / عليه)
  String get formattedCurrentBalance {
    if (supportsMultiCurrency || isMultiCurrency || currency == 'MULTI') {
      if (currentBalancesByCurrency.isNotEmpty) {
        final activeEntries = currentBalancesByCurrency.entries
            .where((e) => e.value.abs() > 0.001)
            .toList();
        if (activeEntries.length > 1) {
          return activeEntries.map((e) {
            final amt = e.value;
            final sym = getCurrencySymbol(e.key);
            final amtFormatted = amt.abs().toStringAsFixed(
                amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
            final dir = amt > 0.001 ? ' (له)' : (amt < -0.001 ? ' (عليه)' : '');
            return '$amtFormatted $sym$dir';
          }).join(' | ');
        } else if (activeEntries.length == 1) {
          final e = activeEntries.first;
          final amt = e.value;
          final dir = amt > 0.001 ? ' (له)' : (amt < -0.001 ? ' (عليه)' : '');
          return '${formatCurrency(amt.abs(), e.key)}$dir';
        } else {
          return '0.00';
        }
      }
      if (outstandingBalance.abs() < 0.001) {
        return '0.00';
      }
      if (initialBalancesByCurrency.isNotEmpty) {
        return formattedInitialBalance;
      }
      return '0.00';
    }

    if (currentBalancesByCurrency.isNotEmpty) {
      final activeEntries = currentBalancesByCurrency.entries
          .where((e) => e.value.abs() > 0.001)
          .toList();
      if (activeEntries.length > 1) {
        return activeEntries.map((e) {
          final amt = e.value;
          final sym = getCurrencySymbol(e.key);
          final amtFormatted = amt.abs().toStringAsFixed(
              amt.abs().truncateToDouble() == amt.abs() ? 0 : 2);
          final dir = amt > 0.001 ? ' (له)' : (amt < -0.001 ? ' (عليه)' : '');
          return '$amtFormatted $sym$dir';
        }).join(' | ');
      } else if (activeEntries.length == 1) {
        final e = activeEntries.first;
        final amt = e.value;
        final dir = amt > 0.001 ? ' (له)' : (amt < -0.001 ? ' (عليه)' : '');
        return '${formatCurrency(amt.abs(), e.key)}$dir';
      } else {
        return '0.00';
      }
    }

    if (isForeignCurrency && currentBalancesByCurrency.containsKey(currency)) {
      final nativeBal = currentBalancesByCurrency[currency]!;
      final dir = nativeBal > 0.001 ? ' (له)' : (nativeBal < -0.001 ? ' (عليه)' : '');
      return '${formatCurrency(nativeBal.abs(), currency)}$dir';
    }

    final effCurrency = (currency == 'MULTI') ? 'EGP' : currency;
    final dir = outstandingBalance > 0.001 ? ' (له)' : (outstandingBalance < -0.001 ? ' (عليه)' : '');
    return '${formatCurrency(outstandingBalance.abs(), effCurrency)}$dir';
  }

  String get supplierTypeLabel {
    switch (supplierType) {
      case 'crop':
        return 'مورد محاصيل';
      case 'packaging':
        return 'مواد تعبئة وتغليف';
      case 'transport':
        return 'مورد نقل';
      case 'station':
        return 'مورد محطة';
      case 'deduction':
      case 'deductions':
        return 'مورد تخصيمات';
      case 'shared':
      default:
        return 'مورد مشترك';
    }
  }

  String get currencySymbol {
    if (supportsMultiCurrency && currency == 'MULTI') return '🌐 متعدد';
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
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

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
    final pendingExpectedBal = numVal(map['pending_expected_balance'])?.toDouble() ?? 0.0;

    final rawType = str(map['supplier_type']).toLowerCase().trim();
    final supplierType = (rawType == 'crop' ||
            rawType == 'packaging' ||
            rawType == 'station' ||
            rawType == 'deduction' ||
            rawType == 'deductions' ||
            rawType == 'transport')
        ? (rawType == 'deductions' ? 'deduction' : rawType)
        : 'shared';

    final isMulti = map['is_multi_currency'] == true || str(map['currency']) == 'MULTI';

    List<String> currencies = ['EGP', 'USD', 'EUR'];
    if (map['supported_currencies'] is List) {
      currencies = (map['supported_currencies'] as List).map((e) => e.toString()).toList();
    }

    // Parse multi-currency opening balances map
    final balancesByCur = <String, SupplierCurrencyBalance>{};
    if (map['initial_balances_by_currency'] is Map) {
      final m = map['initial_balances_by_currency'] as Map;
      m.forEach((k, v) {
        if (v is Map) {
          balancesByCur[k.toString()] =
              SupplierCurrencyBalance.fromMap(Map<String, dynamic>.from(v));
        }
      });
    } else if (map['initial_balance_snapshot'] is Map) {
      final snap = map['initial_balance_snapshot'] as Map;
      if (snap['currency_balances'] is Map) {
        final cb = snap['currency_balances'] as Map;
        cb.forEach((k, v) {
          if (v is Map) {
            balancesByCur[k.toString()] =
                SupplierCurrencyBalance.fromMap(Map<String, dynamic>.from(v));
          }
        });
      }
    }

    final currentBalancesByCur = <String, double>{};
    if (map['current_balances_by_currency'] is Map) {
      final m = map['current_balances_by_currency'] as Map;
      m.forEach((k, v) {
        if (v is num) {
          currentBalancesByCur[k.toString()] = v.toDouble();
        }
      });
    }

    List<String> categoriesList = [];
    if (map['categories'] is List) {
      categoriesList = (map['categories'] as List).map((e) => e.toString()).toList();
    } else if (map['initial_balances_by_currency'] is Map &&
        map['initial_balances_by_currency']['_categories'] is List) {
      categoriesList = (map['initial_balances_by_currency']['_categories'] as List)
          .map((e) => e.toString())
          .toList();
    }

    return SupplierModel(
      id: map['id']?.toString(),
      supplierCode: code,
      name: str(map['name']),
      phone: str(map['phone']),
      address: str(map['address']),
      initialBalance: initialBal,
      initialBalanceDirection: str(map['initial_balance_direction']).isNotEmpty ? str(map['initial_balance_direction']) : 'CREDIT',
      outstandingBalance: outstandingBal,
      pendingExpectedBalance: pendingExpectedBal,
      currency: isMulti ? 'MULTI' : (str(map['currency']).isNotEmpty ? str(map['currency']) : 'EGP'),
      createdAt: str(map['created_at']),
      supplierType: supplierType,
      accountId: intVal(map['account_id']),
      categories: categoriesList,
      isMultiCurrency: isMulti,
      supportedCurrencies: currencies,
      cropCurrency: str(map['crop_currency']).isNotEmpty ? str(map['crop_currency']) : 'USD',
      packagingCurrency: str(map['packaging_currency']).isNotEmpty ? str(map['packaging_currency']) : 'EGP',
      initialBalancesByCurrency: balancesByCur,
      currentBalancesByCurrency: currentBalancesByCur,
    );
  }

  Map<String, dynamic> toInsertMap() {
    // Ensure dbCurrency falls back safely to a valid single currency string
    // (like the first supported currency or EGP) to prevent Supabase PostgREST
    // constraint exceptions with the MULTI tag.
    final dbCurrency = (isMultiCurrency || currency == 'MULTI')
        ? (supportedCurrencies.isNotEmpty ? supportedCurrencies.first : 'EGP')
        : currency;

    // Calculate aggregated base initial balance for standard DB balance fields
    double computedInitialBal = initialBalance;
    String computedInitialDir = initialBalanceDirection;

    if (isMultiCurrency && initialBalancesByCurrency.isNotEmpty) {
      final netEgp = totalInitialBalanceInEgp;
      computedInitialBal = netEgp.abs();
      computedInitialDir = netEgp >= 0 ? 'CREDIT' : 'DEBIT';
    }

    final initialBalancesJson = <String, dynamic>{};
    initialBalancesByCurrency.forEach((k, v) {
      initialBalancesJson[k] = v.toMap();
    });
    if (categories.isNotEmpty) {
      initialBalancesJson['_categories'] = categories;
    }

    return {
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      'supplier_code': supplierCode,
      'code': supplierCode,
      'name': name,
      'phone': phone,
      'address': address,
      'supplier_type': supplierType,
      'initial_balance': computedInitialBal,
      'initial_balance_direction': computedInitialDir,
      'outstanding_balance': outstandingBalance,
      'currency': dbCurrency,
      if (categories.isNotEmpty) 'categories': categories,
      'is_multi_currency': isMultiCurrency,
      'supported_currencies': supportedCurrencies,
      'crop_currency': cropCurrency,
      'packaging_currency': packagingCurrency,
      'initial_balances_by_currency': initialBalancesJson,
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
    double? pendingExpectedBalance,
    String? currency,
    String? createdAt,
    String? supplierType,
    int? accountId,
    List<String>? categories,
    bool? isMultiCurrency,
    List<String>? supportedCurrencies,
    String? cropCurrency,
    String? packagingCurrency,
    Map<String, SupplierCurrencyBalance>? initialBalancesByCurrency,
    Map<String, double>? currentBalancesByCurrency,
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
      pendingExpectedBalance: pendingExpectedBalance ?? this.pendingExpectedBalance,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      supplierType: supplierType ?? this.supplierType,
      accountId: accountId ?? this.accountId,
      categories: categories ?? this.categories,
      isMultiCurrency: isMultiCurrency ?? this.isMultiCurrency,
      supportedCurrencies: supportedCurrencies ?? this.supportedCurrencies,
      cropCurrency: cropCurrency ?? this.cropCurrency,
      packagingCurrency: packagingCurrency ?? this.packagingCurrency,
      initialBalancesByCurrency: initialBalancesByCurrency ?? this.initialBalancesByCurrency,
      currentBalancesByCurrency: currentBalancesByCurrency ?? this.currentBalancesByCurrency,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierModel && supplierCode == other.supplierCode;

  @override
  int get hashCode => supplierCode.hashCode;
}
