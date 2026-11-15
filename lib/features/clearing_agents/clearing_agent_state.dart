import 'package:equatable/equatable.dart';
import '../../data/models/clearing_agent_model.dart';

abstract class ClearingAgentState extends Equatable {
  const ClearingAgentState();

  @override
  List<Object?> get props => [];
}

class ClearingAgentInitial extends ClearingAgentState {
  const ClearingAgentInitial();
}

class ClearingAgentLoading extends ClearingAgentState {
  const ClearingAgentLoading();
}

// ── Per-currency balance breakdown ──────────────────────────────────────────
class ClearingCurrencyBalance extends Equatable {
  final String currency;
  final String symbol;
  final double nativeCurrentBalance;
  final double nativeInitialBalance;
  final double egpCurrentBalance;
  final double egpInitialBalance;
  final int agentCount;

  const ClearingCurrencyBalance({
    required this.currency,
    required this.symbol,
    this.nativeCurrentBalance = 0.0,
    this.nativeInitialBalance = 0.0,
    this.egpCurrentBalance = 0.0,
    this.egpInitialBalance = 0.0,
    this.agentCount = 0,
  });

  static const Map<String, String> _symbols = {
    'EGP': 'ج.م',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  factory ClearingCurrencyBalance.empty(String currency) => ClearingCurrencyBalance(
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
        agentCount,
      ];
}

class _ClearingCurrencyAccum {
  final String currency;
  double nativeCurrent = 0;
  double nativeInitial = 0;
  double egpCurrent = 0;
  double egpInitial = 0;
  int count = 0;

  _ClearingCurrencyAccum(this.currency);
}

class ClearingAgentLoaded extends ClearingAgentState {
  final List<ClearingAgentModel> agents;
  final String searchQuery;
  final String typeFilter;
  final bool hasMore;
  final bool isFetchingMore;

  // ── Type counts ──
  final int seaCount; // بحري
  final int airCount; // جوي

  /// Per-currency breakdowns (EGP, USD, EUR, GBP)
  final Map<String, ClearingCurrencyBalance> balanceByCurrency;

  /// Grand total balance converted to base currency (EGP)
  final double totalCurrentBalanceEgp;

  /// Grand total opening balance converted to base currency (EGP)
  final double totalInitialBalanceEgp;

  /// Exchange rates snapshot used for conversion (currency -> rate_to_egp)
  final Map<String, double> exchangeRates;

  const ClearingAgentLoaded({
    required this.agents,
    this.searchQuery = '',
    this.typeFilter = 'all',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.seaCount = 0,
    this.airCount = 0,
    this.balanceByCurrency = const {},
    this.totalCurrentBalanceEgp = 0.0,
    this.totalInitialBalanceEgp = 0.0,
    this.exchangeRates = const {'EGP': 1.0},
  });

  factory ClearingAgentLoaded.fromList({
    required List<ClearingAgentModel> agents,
    String searchQuery = '',
    String typeFilter = 'all',
    bool hasMore = true,
    bool isFetchingMore = false,
    Map<String, double> rates = const {'EGP': 1.0},
  }) {
    const symbols = {'EGP': 'ج.م', 'USD': '\$', 'EUR': '€', 'GBP': '£'};
    int sea = 0;
    int air = 0;
    final Map<String, _ClearingCurrencyAccum> accum = {};

    for (final a in agents) {
      if (a.brokerType == 'جوي') {
        air++;
      } else {
        sea++;
      }

      final ccy = (a.currency.isEmpty ? 'EGP' : a.currency).toUpperCase();
      final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);

      final acc = accum.putIfAbsent(ccy, () => _ClearingCurrencyAccum(ccy));
      acc.nativeCurrent += a.balance;
      acc.nativeInitial += a.initialBalance;
      acc.egpCurrent += a.balance * rate;
      acc.egpInitial += a.initialBalance * rate;
      acc.count++;
    }

    final Map<String, ClearingCurrencyBalance> byC = {};
    double totalCurrent = 0;
    double totalInitial = 0;

    for (final entry in accum.entries) {
      final acc = entry.value;
      byC[entry.key] = ClearingCurrencyBalance(
        currency: entry.key,
        symbol: symbols[entry.key] ?? entry.key,
        nativeCurrentBalance: acc.nativeCurrent,
        nativeInitialBalance: acc.nativeInitial,
        egpCurrentBalance: acc.egpCurrent,
        egpInitialBalance: acc.egpInitial,
        agentCount: acc.count,
      );
      totalCurrent += acc.egpCurrent;
      totalInitial += acc.egpInitial;
    }

    return ClearingAgentLoaded(
      agents: agents,
      searchQuery: searchQuery,
      typeFilter: typeFilter,
      hasMore: hasMore,
      isFetchingMore: isFetchingMore,
      seaCount: sea,
      airCount: air,
      balanceByCurrency: byC,
      totalCurrentBalanceEgp: totalCurrent,
      totalInitialBalanceEgp: totalInitial,
      exchangeRates: rates,
    );
  }

  /// Returns active currencies in canonical display order [EGP, USD, EUR, GBP, ...]
  List<ClearingCurrencyBalance> get activeCurrencies {
    const order = ['EGP', 'USD', 'EUR', 'GBP'];
    final result = <ClearingCurrencyBalance>[];
    for (final c in order) {
      if (balanceByCurrency.containsKey(c)) result.add(balanceByCurrency[c]!);
    }
    for (final entry in balanceByCurrency.entries) {
      if (!order.contains(entry.key)) result.add(entry.value);
    }
    return result;
  }

  ClearingAgentLoaded copyWith({
    List<ClearingAgentModel>? agents,
    String? searchQuery,
    String? typeFilter,
    bool? hasMore,
    bool? isFetchingMore,
    int? seaCount,
    int? airCount,
    Map<String, ClearingCurrencyBalance>? balanceByCurrency,
    double? totalCurrentBalanceEgp,
    double? totalInitialBalanceEgp,
    Map<String, double>? exchangeRates,
  }) {
    if (agents != null) {
      return ClearingAgentLoaded.fromList(
        agents: agents,
        searchQuery: searchQuery ?? this.searchQuery,
        typeFilter: typeFilter ?? this.typeFilter,
        hasMore: hasMore ?? this.hasMore,
        isFetchingMore: isFetchingMore ?? this.isFetchingMore,
        rates: exchangeRates ?? this.exchangeRates,
      );
    }
    return ClearingAgentLoaded(
      agents: this.agents,
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: typeFilter ?? this.typeFilter,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      seaCount: seaCount ?? this.seaCount,
      airCount: airCount ?? this.airCount,
      balanceByCurrency: balanceByCurrency ?? this.balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp ?? this.totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp ?? this.totalInitialBalanceEgp,
      exchangeRates: exchangeRates ?? this.exchangeRates,
    );
  }

  @override
  List<Object?> get props => [
        agents,
        searchQuery,
        typeFilter,
        hasMore,
        isFetchingMore,
        seaCount,
        airCount,
        balanceByCurrency,
        totalCurrentBalanceEgp,
        totalInitialBalanceEgp,
        exchangeRates,
      ];
}

class ClearingAgentError extends ClearingAgentState {
  final String message;
  const ClearingAgentError({required this.message});

  @override
  List<Object?> get props => [message];
}

class ClearingAgentFormState extends ClearingAgentState {
  final bool isEditing;
  final ClearingAgentModel? editingAgent;
  final bool isSaving;
  final int addressesVersion;

  const ClearingAgentFormState({
    this.isEditing = false,
    this.editingAgent,
    this.isSaving = false,
    this.addressesVersion = 0,
  });

  ClearingAgentFormState copyWith({
    bool? isEditing,
    ClearingAgentModel? editingAgent,
    bool? isSaving,
    bool clearEditingAgent = false,
    int? addressesVersion,
  }) {
    return ClearingAgentFormState(
      isEditing: isEditing ?? this.isEditing,
      editingAgent: clearEditingAgent ? null : (editingAgent ?? this.editingAgent),
      isSaving: isSaving ?? this.isSaving,
      addressesVersion: addressesVersion ?? this.addressesVersion,
    );
  }

  @override
  List<Object?> get props => [isEditing, editingAgent, isSaving, addressesVersion];
}
