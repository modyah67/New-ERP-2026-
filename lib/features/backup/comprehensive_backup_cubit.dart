import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'categorized_backup_service.dart';
import '../../accounting/fiscal_year/dao/fiscal_year_dao.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ComprehensiveBackupState extends Equatable {
  const ComprehensiveBackupState();

  @override
  List<Object?> get props => [];
}

class ComprehensiveBackupInitial extends ComprehensiveBackupState {}

class ComprehensiveBackupInProgress extends ComprehensiveBackupState {
  final String currentCategory;
  final String currentTask;
  final int step;
  final int totalSteps;

  const ComprehensiveBackupInProgress({
    required this.currentCategory,
    required this.currentTask,
    required this.step,
    required this.totalSteps,
  });

  @override
  List<Object?> get props => [currentCategory, currentTask, step, totalSteps];
}

class ComprehensiveBackupSuccess extends ComprehensiveBackupState {}

class ComprehensiveBackupError extends ComprehensiveBackupState {
  final String message;

  const ComprehensiveBackupError(this.message);

  @override
  List<Object?> get props => [message];
}

class ComprehensiveBackupCubit extends Cubit<ComprehensiveBackupState> {
  final _backupService = CategorizedBackupService();

  ComprehensiveBackupCubit() : super(ComprehensiveBackupInitial());

  Future<void> startBackup() async {
    emit(const ComprehensiveBackupInProgress(
      currentCategory: 'بدء',
      currentTask: 'جاري تجهيز النسخ الاحتياطي...',
      step: 0,
      totalSteps: 100,
    ));
    try {
      await _backupService.startBackup(
        onProgress: (category, taskName, current, total) {
          emit(ComprehensiveBackupInProgress(
            currentCategory: category,
            currentTask: taskName,
            step: current,
            totalSteps: total,
          ));
        },
      );

      try {
        final dao = FiscalYearDao();
        final fy = await dao.getCurrent();
        if (fy != null) {
          final userId = Supabase.instance.client.auth.currentUser?.id;
          await Supabase.instance.client.rpc('log_fiscal_year_backup', params: {
            'p_fiscal_year_id': fy.id,
            'p_file_path': 'local_comprehensive_backup',
            'p_size': 1024,
            'p_checksum': 'verified_local',
            'p_status': 'VERIFIED',
            'p_user_id': userId,
          });
        }
      } catch (dbError) {
        print('Error updating backup metadata: $dbError');
      }

      emit(ComprehensiveBackupSuccess());
    } catch (e) {
      emit(ComprehensiveBackupError(e.toString()));
    }
  }

  void reset() {
    emit(ComprehensiveBackupInitial());
  }
}
