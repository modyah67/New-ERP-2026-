import 'package:equatable/equatable.dart';
import '../../data/models/supplier_model.dart';

// ── Supplier States ──────────────────────────────

abstract class SupplierState extends Equatable {
  const SupplierState();

  @override
  List<Object?> get props => [];
}

class SupplierInitial extends SupplierState {
  const SupplierInitial();
}

class SupplierLoading extends SupplierState {
  const SupplierLoading();
}

// ── Per-currency balance breakdown ──────────────────────────────────────────
//
// Avoids naïve cross-currency summation (EGP + USD ≠ meaningful number).
// Holds both the native amount and the EGP-converted equivalent.

class CurrencyBalance extends Equatable {
  final String currency;
  final String symbol;
  final double nativeCurrentBalance;
  final double nativeInitialBalance;
  final double egpCurrentBalance;  // nativeCurrentBalance * rateToEgp
  final double egpInitialBalance;
  final int supplierCount;

  const CurrencyBalance({
    required this.currency,
    required this.symbol,
    this.nativeCurrentBalance = 0.0,
    this.nativeInitialBalance = 0.0,
    this.egpCurrentBalance = 0.0,
    this.egpInitialBalance = 0.0,
    this.supplierCount = 0,
  });

  static const Map<String, String> _symbols = {
    'EGP': 'ج.م',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  factory CurrencyBalance.empty(String currency) => CurrencyBalance(
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
        supplierCount,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────

class SupplierLoaded extends SupplierState {
  final List<SupplierModel> suppliers;
  final String searchQuery;
  final bool hasMore;
  final bool isFetchingMore;

  // ── Type counts ──
  final int cropCount;
  final int packagingCount;
  final int sharedCount;

  /// Per-currency breakdowns — the only safe way to display balance totals.
  /// Keys are ISO currency codes: 'EGP', 'USD', 'EUR', 'GBP'
  final Map<String, CurrencyBalance> balanceByCurrency;

  /// Grand total outstanding balance converted to EGP (for single-figure display).
  final double totalCurrentBalanceEgp;

  /// Grand total initial balance converted to EGP.
  final double totalInitialBalanceEgp;

  /// Exchange rates snapshot used for conversion (currency -> rate_to_egp).
  final Map<String, double> exchangeRates;

  const SupplierLoaded({
    required this.suppliers,
    this.searchQuery = '',
    this.hasMore = true,
    this.isFetchingMore = false,
    this.cropCount = 0,
    this.packagingCount = 0,
    this.sharedCount = 0,
    this.balanceByCurrency = const {},
    this.totalCurrentBalanceEgp = 0.0,
    this.totalInitialBalanceEgp = 0.0,
    this.exchangeRates = const {'EGP': 1.0},
  });

  /// Factory that derives all KPI fields correctly — without cross-currency summation.
  ///
  /// [rates] must be a map from currency ISO code → rate-to-EGP (e.g. {'USD': 50.0}).
  /// EGP always has an implicit rate of 1.0.
  factory SupplierLoaded.fromList({
    required List<SupplierModel> suppliers,
    String searchQuery = '',
    bool hasMore = true,
    bool isFetchingMore = false,
    Map<String, double> rates = const {'EGP': 1.0},
  }) {
    const symbols = {'EGP': 'ج.م', 'USD': '\$', 'EUR': '€', 'GBP': '£'};
    int crop = 0, packaging = 0, shared = 0;
    final Map<String, _CurrencyAccum> accum = {};

    for (final s in suppliers) {
      // ── Type counts ──
      switch (s.supplierType) {
        case 'crop':
          crop++;
          break;
        case 'packaging':
          packaging++;
          break;
        default:
          shared++;
      }

      // ── Currency aggregation (keeps native amounts separate & converts to EGP) ──
      if (s.supportsMultiCurrency && s.initialBalancesByCurrency.isNotEmpty) {
        // Disaggregate each native currency into its respective bucket
        s.initialBalancesByCurrency.forEach((curKey, curBal) {
          if (curBal.amount > 0) {
            final ccy = curKey.toUpperCase();
            final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? curBal.exchangeRate);
            final signedAmt = curBal.signedAmount;
            final egpAmt = signedAmt * (rate > 0 ? rate : 1.0);

            final a = accum.putIfAbsent(ccy, () => _CurrencyAccum(ccy));
            a.nativeInitial += signedAmt;
            a.egpInitial += egpAmt;
            a.count++;
          }
        });

        if (s.currentBalancesByCurrency.isNotEmpty) {
          s.currentBalancesByCurrency.forEach((curKey, curBal) {
            final ccy = curKey.toUpperCase();
            final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);
            final a = accum.putIfAbsent(ccy, () => _CurrencyAccum(ccy));
            a.nativeCurrent += curBal;
            a.egpCurrent += curBal * rate;
          });
        } else if ((s.outstandingBalance - s.totalInitialBalanceInEgp).abs() < 0.01) {
          s.initialBalancesByCurrency.forEach((curKey, curBal) {
            if (curBal.amount > 0) {
              final ccy = curKey.toUpperCase();
              final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? curBal.exchangeRate);
              final signedAmt = curBal.signedAmount;
              final egpAmt = signedAmt * (rate > 0 ? rate : 1.0);
              final a = accum.putIfAbsent(ccy, () => _CurrencyAccum(ccy));
              a.nativeCurrent += signedAmt;
              a.egpCurrent += egpAmt;
            }
          });
        } else {
          final activeCurrencies = s.initialBalancesByCurrency.values
              .where((b) => b.amount > 0)
              .toList();
          if (activeCurrencies.length == 1) {
            final ccy = activeCurrencies.first.currency.toUpperCase();
            final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);
            final a = accum.putIfAbsent(ccy, () => _CurrencyAccum(ccy));
            final nativeAmt = rate > 0 ? (s.outstandingBalance / rate) : s.outstandingBalance;
            a.nativeCurrent += nativeAmt;
            a.egpCurrent += s.outstandingBalance;
          } else {
            // Attribute to base currency bucket EGP
            final a = accum.putIfAbsent('EGP', () => _CurrencyAccum('EGP'));
            a.nativeCurrent += s.outstandingBalance;
            a.egpCurrent += s.outstandingBalance;
          }
        }
      } else {
        final ccy = (s.currency.isEmpty || s.currency == 'MULTI')
            ? 'EGP'
            : s.currency.toUpperCase();
        final rate = ccy == 'EGP' ? 1.0 : (rates[ccy] ?? 1.0);
        final initialSigned = s.initialBalanceDirection == 'DEBIT'
            ? -s.initialBalance
            : s.initialBalance;

        double nativeCur;
        double egpCur;
        if (ccy == 'EGP') {
          nativeCur = s.outstandingBalance;
          egpCur = s.outstandingBalance;
        } else if (s.currentBalancesByCurrency.containsKey(ccy)) {
          nativeCur = s.currentBalancesByCurrency[ccy]!;
          egpCur = nativeCur * rate;
        } else {
          if ((s.outstandingBalance - initialSigned).abs() < 0.01) {
            nativeCur = initialSigned;
            egpCur = initialSigned * rate;
          } else {
            egpCur = s.outstandingBalance;
            nativeCur = rate > 0 ? (s.outstandingBalance / rate) : s.outstandingBalance;
          }
        }

        final a = accum.putIfAbsent(ccy, () => _CurrencyAccum(ccy));
        a.nativeCurrent += nativeCur;
        a.nativeInitial += initialSigned;
        a.egpCurrent += egpCur;
        a.egpInitial += initialSigned * rate;
        a.count++;
      }
    }

    final Map<String, CurrencyBalance> byC = {};
    double totalCurrent = 0;
    double totalInitial = 0;

    for (final entry in accum.entries) {
      final a = entry.value;
      byC[entry.key] = CurrencyBalance(
        currency: entry.key,
        symbol: symbols[entry.key] ?? entry.key,
        nativeCurrentBalance: a.nativeCurrent,
        nativeInitialBalance: a.nativeInitial,
        egpCurrentBalance: a.egpCurrent,
        egpInitialBalance: a.egpInitial,
        supplierCount: a.count,
      );
      totalCurrent += a.egpCurrent;
      totalInitial += a.egpInitial;
    }

    return SupplierLoaded(
      suppliers: suppliers,
      searchQuery: searchQuery,
      hasMore: hasMore,
      isFetchingMore: isFetchingMore,
      cropCount: crop,
      packagingCount: packaging,
      sharedCount: shared,
      balanceByCurrency: byC,
      totalCurrentBalanceEgp: totalCurrent,
      totalInitialBalanceEgp: totalInitial,
      exchangeRates: rates,
    );
  }

  /// Returns currencies sorted in canonical display order [EGP, USD, EUR, GBP, …].
  List<CurrencyBalance> get activeCurrencies {
    const order = ['EGP', 'USD', 'EUR', 'GBP'];
    final result = <CurrencyBalance>[];
    for (final c in order) {
      if (balanceByCurrency.containsKey(c)) result.add(balanceByCurrency[c]!);
    }
    for (final entry in balanceByCurrency.entries) {
      if (!order.contains(entry.key)) result.add(entry.value);
    }
    return result;
  }

  SupplierLoaded copyWith({
    List<SupplierModel>? suppliers,
    String? searchQuery,
    bool? hasMore,
    bool? isFetchingMore,
    Map<String, double>? exchangeRates,
  }) {
    final newSuppliers = suppliers ?? this.suppliers;
    final newRates = exchangeRates ?? this.exchangeRates;
    // Recompute KPIs whenever supplier list or rates change
    if (suppliers != null || exchangeRates != null) {
      return SupplierLoaded.fromList(
        suppliers: newSuppliers,
        searchQuery: searchQuery ?? this.searchQuery,
        hasMore: hasMore ?? this.hasMore,
        isFetchingMore: isFetchingMore ?? this.isFetchingMore,
        rates: newRates,
      );
    }
    return SupplierLoaded(
      suppliers: newSuppliers,
      searchQuery: searchQuery ?? this.searchQuery,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      cropCount: cropCount,
      packagingCount: packagingCount,
      sharedCount: sharedCount,
      balanceByCurrency: balanceByCurrency,
      totalCurrentBalanceEgp: totalCurrentBalanceEgp,
      totalInitialBalanceEgp: totalInitialBalanceEgp,
      exchangeRates: newRates,
    );
  }

  @override
  List<Object?> get props => [
        suppliers,
        searchQuery,
        hasMore,
        isFetchingMore,
        cropCount,
        packagingCount,
        sharedCount,
        balanceByCurrency,
        totalCurrentBalanceEgp,
        totalInitialBalanceEgp,
        exchangeRates,
      ];
}

// ── Private accumulator (not exported) ──────────────────────────────────────
class _CurrencyAccum {
  final String ccy;
  double nativeCurrent = 0;
  double nativeInitial = 0;
  double egpCurrent = 0;
  double egpInitial = 0;
  int count = 0;
  _CurrencyAccum(this.ccy);
}

// ─────────────────────────────────────────────────────────────────────────────

class SupplierError extends SupplierState {
  final String message;

  const SupplierError({required this.message});

  @override
  List<Object?> get props => [message];
}

class SupplierFormState extends SupplierState {
  final bool isEditing;
  final SupplierModel? editingSupplier;
  final bool isSaving;

  const SupplierFormState({
    this.isEditing = false,
    this.editingSupplier,
    this.isSaving = false,
  });

  SupplierFormState copyWith({
    bool? isEditing,
    SupplierModel? editingSupplier,
    bool? isSaving,
    bool clearEditingSupplier = false,
  }) {
    return SupplierFormState(
      isEditing: isEditing ?? this.isEditing,
      editingSupplier:
          clearEditingSupplier ? null : (editingSupplier ?? this.editingSupplier),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        isEditing,
        editingSupplier,
        isSaving,
      ];
}

