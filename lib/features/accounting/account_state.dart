import 'package:equatable/equatable.dart';
import '../../data/models/account_model.dart';

abstract class AccountState extends Equatable {
  const AccountState();

  @override
  List<Object?> get props => [];
}

class AccountInitial extends AccountState {
  const AccountInitial();
}

class AccountLoading extends AccountState {
  const AccountLoading();
}

class AccountLoaded extends AccountState {
  final List<AccountModel> accounts;
  final String searchQuery;

  const AccountLoaded({
    required this.accounts,
    this.searchQuery = '',
  });

  AccountLoaded copyWith({
    List<AccountModel>? accounts,
    String? searchQuery,
  }) {
    return AccountLoaded(
      accounts: accounts ?? this.accounts,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<AccountModel> get filteredAccounts {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return accounts;
    return accounts.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.code.toLowerCase().contains(q);
    }).toList();
  }

  List<AccountModel> get rootAccounts =>
      accounts.where((a) => a.parentId == null).toList();

  Map<String, List<AccountModel>> get grouped {
    final map = <String, List<AccountModel>>{};
    for (final acc in accounts) {
      map.putIfAbsent(acc.type, () => []).add(acc);
    }
    return map;
  }

  @override
  List<Object?> get props => [accounts, searchQuery];
}

class AccountError extends AccountState {
  final String message;

  const AccountError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AccountFormState extends Equatable {
  final bool isEditing;
  final AccountModel? editingAccount;
  final String selectedType;
  final int? selectedParentId;
  final bool isSaving;

  const AccountFormState({
    this.isEditing = false,
    this.editingAccount,
    this.selectedType = 'asset',
    this.selectedParentId,
    this.isSaving = false,
  });

  AccountFormState copyWith({
    bool? isEditing,
    AccountModel? editingAccount,
    String? selectedType,
    int? selectedParentId,
    bool? isSaving,
    bool clearEditingAccount = false,
    bool clearSelectedParentId = false,
  }) {
    return AccountFormState(
      isEditing: isEditing ?? this.isEditing,
      editingAccount:
          clearEditingAccount ? null : (editingAccount ?? this.editingAccount),
      selectedType: selectedType ?? this.selectedType,
      selectedParentId: clearSelectedParentId
          ? null
          : (selectedParentId ?? this.selectedParentId),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  List<Object?> get props => [
        isEditing,
        editingAccount,
        selectedType,
        selectedParentId,
        isSaving,
      ];
}
