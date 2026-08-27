import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/account_dao.dart';
import '../../data/models/account_model.dart';
import '../../core/constants.dart';
import '../../core/data_change_event_bus.dart';
import 'account_state.dart';

class AccountCubit extends Cubit<AccountState> {
  final AccountDao _dao = AccountDao();

  // ── Form state ──
  AccountFormState _formState = const AccountFormState();
  AccountFormState get formState => _formState;

  // ── Form controllers ──
  final formKey = GlobalKey<FormState>();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final codeFocus = FocusNode();
  final nameFocus = FocusNode();

  // ── Stream subscriptions ──
  late final StreamSubscription<void> _accountsSub;

  static const typeLabels = {
    AccountType.asset: 'أصول',
    AccountType.liability: 'خصوم',
    AccountType.equity: 'حقوق ملكية',
    AccountType.revenue: 'إيرادات',
    AccountType.expense: 'مصروفات',
  };

  AccountCubit() : super(const AccountInitial()) {
    _accountsSub =
        DataChangeEventBus.instance.accountsStream.listen((_) => loadAll());
  }

  // ── Load ──

  Future<void> loadAll() async {
    emit(const AccountLoading());
    try {
      final accounts = await _dao.getAll();
      emit(AccountLoaded(accounts: accounts));
    } catch (e) {
      emit(AccountError(message: 'حدث خطأ: $e'));
    }
  }

  // ── Search ──

  void onSearchChanged(String query) {
    final currentState = state;
    if (currentState is AccountLoaded) {
      emit(currentState.copyWith(searchQuery: query));
    }
  }

  // ── Prepare form for ADD ──

  void prepareAddForm() {
    _formState = const AccountFormState(isEditing: false);
    codeController.clear();
    nameController.clear();
  }

  // ── Prepare form for EDIT ──

  void prepareEditForm(AccountModel account) {
    _formState = AccountFormState(
      isEditing: true,
      editingAccount: account,
      selectedType: account.type,
      selectedParentId: int.tryParse(account.parentId ?? ''),
    );
    codeController.text = account.code;
    nameController.text = account.name;
  }

  // ── Save ──

  Future<bool> save() async {
    if (_formState.isSaving) return false;
    if (!formKey.currentState!.validate()) return false;

    final code = codeController.text.trim();
    final name = nameController.text.trim();

    final codeExists = await _dao.codeExists(
      code,
      excludeId: _formState.editingAccount?.id?.toString(),
    );
    if (codeExists) {
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    try {
      if (_formState.editingAccount == null) {
        await _dao.insert(AccountModel(
          code: code,
          name: name,
          type: _formState.selectedType,
          parentId: _formState.selectedParentId?.toString(),
        ));
      } else {
        await _dao.update(_formState.editingAccount!.copyWith(
          code: code,
          name: name,
          type: _formState.selectedType,
          parentId: _formState.selectedParentId?.toString(),
        ));
      }
      await loadAll();
      DataChangeEventBus.instance.notifyAccountsChanged();
      return true;
    } catch (e) {
      return false;
    } finally {
      _formState = _formState.copyWith(isSaving: false);
    }
  }

  // ── Delete ──

  Future<String?> deleteAccount(AccountModel account) async {
    if (account.id == null) return 'معرف الحساب غير صالح';

    try {
      final result = await _dao.delete(account.id!.toString());
      if (result.success) {
        await loadAll();
        DataChangeEventBus.instance.notifyAccountsChanged();
        return null;
      }
      return result.message ?? 'فشل حذف الحساب';
    } catch (e) {
      return 'فشل حذف الحساب: $e';
    }
  }

  // ── Helpers ──

  String typeLabel(String type) => typeLabels[type] ?? type;

  Color typeColor(String type) {
    switch (type) {
      case AccountType.asset:
        return const Color(0xFF1565C0);
      case AccountType.liability:
        return const Color(0xFFC62828);
      case AccountType.equity:
        return const Color(0xFF6A1B9A);
      case AccountType.revenue:
        return const Color(0xFF2E7D32);
      case AccountType.expense:
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF757575);
    }
  }

  // ── Parent dropdown data ──
  List<AccountModel> get rootAccounts {
    final currentState = state;
    if (currentState is AccountLoaded) {
      return currentState.rootAccounts;
    }
    return [];
  }

  @override
  void onChange(Change<AccountState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    _accountsSub.cancel();
    codeController.dispose();
    nameController.dispose();
    codeFocus.dispose();
    nameFocus.dispose();
    return super.close();
  }
}
