import 'package:equatable/equatable.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/statement_row_model.dart';

abstract class ClearingAgentStatementState extends Equatable {
  const ClearingAgentStatementState();
  @override
  List<Object?> get props => [];
}

class ClearingAgentStatementInitial extends ClearingAgentStatementState {
  const ClearingAgentStatementInitial();
}

class ClearingAgentStatementLoaded extends ClearingAgentStatementState {
  final List<ClearingAgentModel> agents;
  final ClearingAgentModel? selectedAgent;
  final List<StatementRow> statementRows;
  final double totalDebit;
  final double totalCredit;
  final double finalBalance;
  final int statementNumber;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Map<String, String> rowNotes;
  final double openingBalance;

  const ClearingAgentStatementLoaded({
    this.agents = const [],
    this.selectedAgent,
    this.statementRows = const [],
    this.totalDebit = 0,
    this.totalCredit = 0,
    this.finalBalance = 0,
    this.statementNumber = 0,
    this.fromDate,
    this.toDate,
    this.rowNotes = const {},
    this.openingBalance = 0,
  });

  ClearingAgentStatementLoaded copyWith({
    List<ClearingAgentModel>? agents,
    ClearingAgentModel? selectedAgent,
    bool clearSelectedAgent = false,
    List<StatementRow>? statementRows,
    double? totalDebit,
    double? totalCredit,
    double? finalBalance,
    int? statementNumber,
    DateTime? fromDate,
    DateTime? toDate,
    Map<String, String>? rowNotes,
    double? openingBalance,
  }) {
    return ClearingAgentStatementLoaded(
      agents: agents ?? this.agents,
      selectedAgent: clearSelectedAgent ? null : (selectedAgent ?? this.selectedAgent),
      statementRows: statementRows ?? this.statementRows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      finalBalance: finalBalance ?? this.finalBalance,
      statementNumber: statementNumber ?? this.statementNumber,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      rowNotes: rowNotes ?? this.rowNotes,
      openingBalance: openingBalance ?? this.openingBalance,
    );
  }

  @override
  List<Object?> get props => [agents, selectedAgent, statementRows, totalDebit, totalCredit, finalBalance, fromDate, toDate, rowNotes, openingBalance];
}

class ClearingAgentStatementError extends ClearingAgentStatementState {
  final String message;
  const ClearingAgentStatementError({required this.message});
  @override
  List<Object?> get props => [message];
}
