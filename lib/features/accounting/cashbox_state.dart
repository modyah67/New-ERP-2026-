import 'package:equatable/equatable.dart';
import '../../data/models/cashbox_model.dart';

abstract class CashboxState extends Equatable {
  const CashboxState();

  @override
  List<Object?> get props => [];
}

class CashboxInitial extends CashboxState {
  const CashboxInitial();
}

class CashboxLoading extends CashboxState {
  const CashboxLoading();
}

class CashboxLoaded extends CashboxState {
  final List<CashboxModel> entries;
  final double currentBalance;
  final double totalIn;
  final double totalOut;
  final DateTime? fromDate;
  final DateTime? toDate;

  const CashboxLoaded({
    required this.entries,
    required this.currentBalance,
    required this.totalIn,
    required this.totalOut,
    this.fromDate,
    this.toDate,
  });

  CashboxLoaded copyWith({
    List<CashboxModel>? entries,
    double? currentBalance,
    double? totalIn,
    double? totalOut,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return CashboxLoaded(
      entries: entries ?? this.entries,
      currentBalance: currentBalance ?? this.currentBalance,
      totalIn: totalIn ?? this.totalIn,
      totalOut: totalOut ?? this.totalOut,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
    );
  }

  @override
  List<Object?> get props => [
        entries,
        currentBalance,
        totalIn,
        totalOut,
        fromDate,
        toDate,
      ];
}

class CashboxError extends CashboxState {
  final String message;

  const CashboxError({required this.message});

  @override
  List<Object?> get props => [message];
}
