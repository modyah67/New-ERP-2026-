import 'package:equatable/equatable.dart';
import '../../data/models/shipping_company_model.dart';

abstract class ShippingCompanyState extends Equatable {
  const ShippingCompanyState();

  @override
  List<Object?> get props => [];
}

class ShippingCompanyInitial extends ShippingCompanyState {
  const ShippingCompanyInitial();
}

class ShippingCompanyLoading extends ShippingCompanyState {
  const ShippingCompanyLoading();
}

// ── Per-currency balance breakdown ──────────────────────────────────────────
class ShippingCurrencyBalance extends Equatable {
  final String currency;
  final String symbol;
  final double nativeCurrentBalance;
  final double nativeInitialBalance;
  final double egpCurrentBalance;
  final double egpInitialBalance;
  final int companyCount;

  const ShippingCurrencyBalance({
    required this.currency,
    required this.symbol,
    this.nativeCurrentBalance = 0.0,
    this.nativeInitialBalance = 0.0,
    this.egpCurrentBalance = 0.0,
    this.egpInitialBalance = 0.0,
    this.companyCount = 0,
  });

  static const Map<String, String> _symbols = {
    'EGP': 'ج.م',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  factory ShippingCurrencyBalance.empty(String currency) => ShippingCurrencyBalance(
        currency: currency,
        symbol: _symbols[currency] ?? currency,
      );

  @override
  List<Object?> get props => [
        currency,
        nativeCurrentBalance,
        nativeInitialBalance,
        egpCurrentBalance,
        egpInitialBalance,
        companyCount,
      ];
}

class _ShippingCurrencyAccum {
  final String currency;
  double nativeCurrent = 0;
  double nativeInitial = 0;
  double egpCurrent = 0;
  double egpInitial = 0;
  int count = 0;

  _ShippingCurrencyAccum(this.currency);
}

class ShippingCompanyLoaded extends ShippingCompanyState {
  final List<ShippingCompanyModel> companies;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;

  /// Per-currency breakdowns (EGP, USD, EUR, GBP)
  final Map<String, ShippingCurrencyBalance> balanceByCurrency;

  /// Grand total balance converted to base currency (EGP)
  final double totalCurrentBalanceEgp;

  /// Grand total opening balance converted to base currency (EGP)
  final double totalInitialBalanceEgp;

  /// Exchange rates snapshot used for conversion (currency -> rate_to_egp)
  final Map<String, double> exchangeRates;

  const ShippingCompanyLoaded({
    required this.companies,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.balanceByCurrency = const {},
    this.totalCurrentBalanceEgp = 0.0,
    this.totalInitialBalanceEgp = 0.0,
    this.exchangeRates = const {'EGP': 1.0},
  });

  factory ShippingCompanyLoaded.fromList({
    required List<ShippingCompanyModel> companies,
    String searchQuery = '',
    bool hasMore = true,
    bool isFetchingMore = false,
    Map<String, double> rates = const {'EGP': 1.0},
  }) {
    const symbols = {'EGP': 'ج.م', 'USD': '\$', 'EUR': '€', 'GBP': '£'};
    final Map<String, _ShippingCurrencyAccum> accum = {};

    for (final c in companies) {
      final ccy = (c.currency.isEmpty ? 'EGP' : c.currency).toUpperCase();
      final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);

      final acc = accum.putIfAbsent(ccy, () => _ShippingCurrencyAccum(ccy));
      acc.nativeCurrent += c.balance;
      acc.nativeInitial += c.initialBalance;
      acc.egpCurrent += c.balance * rate;
      acc.egpInitial += c.initialBalance * rate;
      acc.count++;
    }

    final Map<String, ShippingCurrencyBalance> byC = {};
    double totalCurrent = 0;
    double totalInitial = 0;

    for (final entry in accum.entries) {
      final acc = entry.value;
      byC[entry.key] = ShippingCurrencyBalance(
        currency: entry.key,
        symbol: symbols[entry.key] ?? entry.key,
        nativeCurrentBalance: acc.nativeCurrent,
        nativeInitialBalance: acc.nativeInitial,
        egpCurrentBalance: acc.egpCurrent,
        egpInitialBalance: acc.egpInitial,
        companyCount: acc.count,
      );
      totalCurrent += acc.egpCurrent;
      totalInitial += acc.egpInitial;
    }

    return ShippingCompanyLoaded(
      companies: companies,
      searchQuery: searchQuery,
      hasMore: hasMore,
      isFetchingMore: isFetchingMore,
      balanceByCurrency: byC,
      totalCurrentBalanceEgp: totalCurrent,
      totalInitialBalanceEgp: totalInitial,
      exchangeRates: rates,
    );
  }

  /// Returns active currencies in canonical display order [EGP, USD, EUR, GBP, ...]
  List<ShippingCurrencyBalance> get activeCurrencies {
    const order = ['EGP', 'USD', 'EUR', 'GBP'];
    final result = <ShippingCurrencyBalance>[];
    for (final c in order) {
      if (balanceByCurrency.containsKey(c)) result.add(balanceByCurrency[c]!);
    }
    for (final entry in balanceByCurrency.entries) {
      if (!order.contains(entry.key)) result.add(entry.value);
    }
    return result;
  }

  ShippingCompanyLoaded copyWith({
    List<ShippingCompanyModel>? companies,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
    Map<String, ShippingCurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    Map<String, double>? exchangeRates,
  }) {
    if (companies != null) {
      return ShippingCompanyLoaded.fromList(
        companies: companies,
        searchQuery: searchQuery ?? this.searchQuery,
        hasMore: hasMore ?? this.hasMore,
        isFetchingMore: isFetchingMore ?? this.isFetchingMore,
        rates: exchangeRates ?? this.exchangeRates,
      );
    }
    return ShippingCompanyLoaded(
      companies: this.companies,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      balanceByCurrency: balanceByCurrency ?? this.balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp ?? this.totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp ?? this.totalInitialBalanceEgp,
      exchangeRates: exchangeRates ?? this.exchangeRates,
    );
  }

  @override
  List<Object?> get props => [
        companies,
        searchQuery,
        hasMore,
        isFetchingMore,
        balanceByCurrency,
        totalCurrentBalanceEgp,
        totalInitialBalanceEgp,
        exchangeRates,
      ];
}

class ShippingCompanyError extends ShippingCompanyState {
  final String message;
  const ShippingCompanyError({required this.message});

  @override
  List<Object?> get props => [message];
}

class ShippingCompanyFormState extends ShippingCompanyState {
  final bool isEditing;
  final ShippingCompanyModel? editingCompany;
  final bool isSaving;

  const ShippingCompanyFormState({
    this.isEditing = false,
    this.editingCompany,
    this.isSaving = false,
  });

  ShippingCompanyFormState copyWith({
    bool? isEditing,
    ShippingCompanyModel? editingCompany,
    bool? isSaving,
    bool clearEditingCompany = false,
  }) {
    return ShippingCompanyFormState(
      isEditing: isEditing ?? this.isEditing,
      editingCompany: clearEditingCompany ? null : (editingCompany ?? this.editingCompany),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [isEditing, editingCompany, isSaving];
}
