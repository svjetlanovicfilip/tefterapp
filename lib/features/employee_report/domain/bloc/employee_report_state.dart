part of 'employee_report_bloc.dart';

sealed class EmployeeReportState extends Equatable {
  const EmployeeReportState();

  @override
  List<Object> get props => [];
}

final class EmployeeReportInitial extends EmployeeReportState {}

final class EmployeeReportFetching extends EmployeeReportState {}

final class EmployeeReportFetched extends EmployeeReportState {
  const EmployeeReportFetched({required this.report});
  final EmployeeReport report;

  @override
  List<Object> get props => [report];
}

final class EmployeeReportFailure extends EmployeeReportState {
  const EmployeeReportFailure({required this.message});
  final String message;

  @override
  List<Object> get props => [message];
}

final class EmployeeSelected extends EmployeeReportState {}

final class EmployeeSlotsHistoryLoading extends EmployeeReportState {}

final class EmployeeSlotsHistoryLoaded extends EmployeeReportState {
  const EmployeeSlotsHistoryLoaded({required this.slots});
  final List<SlotDetails> slots;

  @override
  List<Object> get props => [slots];
}
