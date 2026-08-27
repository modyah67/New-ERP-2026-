import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/models/shareholder_model.dart';
import 'shareholders_state.dart';

class ShareholdersCubit extends Cubit<ShareholdersState> {
  final _dao = ShareholderDao();

  ShareholdersCubit() : super(ShareholdersInitial());

  Future<void> loadAll() async {
    emit(ShareholdersLoading());
    try {
      final list = await _dao.getAll(limit: 1000);
      emit(ShareholdersLoaded(shareholders: list));
    } catch (e) {
      emit(ShareholdersError(e.toString()));
    }
  }

  Future<void> addShareholder(ShareholderModel shareholder) async {
    final currentState = state;
    if (currentState is ShareholdersLoaded) {
      emit(currentState.copyWith(isSaving: true));
      try {
        await _dao.insert(shareholder);
        final list = await _dao.getAll(limit: 1000);
        emit(ShareholdersLoaded(shareholders: list));
      } catch (e) {
        emit(ShareholdersError(e.toString()));
        emit(currentState.copyWith(isSaving: false));
      }
    }
  }

  Future<void> deleteShareholder(String code) async {
    final currentState = state;
    if (currentState is ShareholdersLoaded) {
      emit(currentState.copyWith(isSaving: true));
      try {
        await _dao.delete(code);
        final list = await _dao.getAll(limit: 1000);
        emit(ShareholdersLoaded(shareholders: list));
      } catch (e) {
        emit(ShareholdersError(e.toString()));
        emit(currentState.copyWith(isSaving: false));
      }
    }
  }

  Future<void> updateInitialBalance({
    required String id,
    required double egpBal,
    required String egpDir,
    required double usdBal,
    required String usdDir,
    required double eurBal,
    required String eurDir,
    required double gbpBal,
    required String gbpDir,
  }) async {
    final currentState = state;
    if (currentState is ShareholdersLoaded) {
      emit(currentState.copyWith(isSaving: true));
      try {
        await _dao.updateInitialBalance(
          id: id,
          egpBal: egpBal,
          egpDir: egpDir,
          usdBal: usdBal,
          usdDir: usdDir,
          eurBal: eurBal,
          eurDir: eurDir,
          gbpBal: gbpBal,
          gbpDir: gbpDir,
        );
        final list = await _dao.getAll(limit: 1000);
        emit(ShareholdersLoaded(shareholders: list));
      } catch (e) {
        emit(ShareholdersError(e.toString()));
        emit(currentState.copyWith(isSaving: false));
      }
    }
  }
}
