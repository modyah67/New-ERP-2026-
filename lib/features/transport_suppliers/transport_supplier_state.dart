import 'package:equatable/equatable.dart';
import '../../data/models/transport_supplier_model.dart';

abstract class TransportSupplierState extends Equatable {
  const TransportSupplierState();

  @override
  List<Object?> get props => [];
}

class TransportSupplierInitial extends TransportSupplierState {
  const TransportSupplierInitial();
}

class TransportSupplierLoading extends TransportSupplierState {
  const TransportSupplierLoading();
}

class TransportSupplierLoaded extends TransportSupplierState {
  final List<TransportSupplierModel> suppliers;
  final bool hasMore;
  final bool isFetchingMore;

  const TransportSupplierLoaded({
    required this.suppliers,
    this.hasMore = false,
    this.isFetchingMore = false,
  });

  double get totalBalance =>
      suppliers.fold(0.0, (sum, s) => sum + s.balance);

  double get totalCreditDues => suppliers.fold(
      0.0, (sum, s) => sum + (s.balance > 0 ? s.balance : 0.0));

  double get totalDebitAdvances => suppliers.fold(
      0.0, (sum, s) => sum + (s.balance < 0 ? s.balance.abs() : 0.0));

  TransportSupplierLoaded copyWith({
    List<TransportSupplierModel>? suppliers,
    bool? hasMore,
    bool? isFetchingMore,
  }) {
    return TransportSupplierLoaded(
      suppliers: suppliers ?? this.suppliers,
      hasMore: hasMore ?? this.hasMore,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
    );
  }

  @override
  List<Object?> get props => [suppliers, hasMore, isFetchingMore];
}

class TransportSupplierError extends TransportSupplierState {
  final String message;

  const TransportSupplierError({required this.message});

  @override
  List<Object?> get props => [message];
}

class TransportSupplierFormState extends Equatable {
  final bool isEditing;
  final TransportSupplierModel? editingSupplier;

  const TransportSupplierFormState({
    this.isEditing = false,
    this.editingSupplier,
  });

  @override
  List<Object?> get props => [isEditing, editingSupplier];
}
