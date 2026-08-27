import 'package:equatable/equatable.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/account_model.dart';

abstract class AccountingState extends Equatable {
  const AccountingState();

  @override
  List<Object?> get props => [];
}

class AccountingInitial extends AccountingState {
  const AccountingInitial();
}

class AccountingLoading extends AccountingState {
  const AccountingLoading();
}

class AccountingLoaded extends AccountingState {
  final List<CustomerModel> customers;
  final List<SupplierModel> suppliers;
  final List<AccountModel> accounts;
  final DateTime entryDate;
  final bool isSaving;

  const AccountingLoaded({
    required this.customers,
    required this.suppliers,
    required this.accounts,
    required this.entryDate,
    this.isSaving = false,
  });

  AccountingLoaded copyWith({
    List<CustomerModel>? customers,
    List<SupplierModel>? suppliers,
    List<AccountModel>? accounts,
    DateTime? entryDate,
    bool? isSaving,
  }) {
    return AccountingLoaded(
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      accounts: accounts ?? this.accounts,
      entryDate: entryDate ?? this.entryDate,
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        customers,
        suppliers,
        accounts,
        entryDate,
        isSaving,
      ];
}

class AccountingError extends AccountingState {
  final String message;

  const AccountingError({required this.message});

  @override
  List<Object?> get props => [message];
}
