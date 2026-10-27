import 'dart:math' show min;

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import '../../../../common/di/di_container.dart';
import '../../../calendar/data/models/slot.dart';
import '../../../login/data/models/user_model.dart';
import '../../../service/data/models/service_type.dart';
import '../../../service/domain/bloc/service_bloc.dart';
import '../../../settings/data/client.dart';
import '../../../settings/domain/bloc/clients_bloc.dart';
import '../../../users/domain/bloc/users_bloc.dart';
import '../../data/models/employee_report.dart';
import '../../data/models/slot_details.dart';
import '../../data/repositories/employee_report_repository.dart';

part 'employee_report_event.dart';
part 'employee_report_state.dart';

class EmployeeReportBloc
    extends Bloc<EmployeeReportEvent, EmployeeReportState> {
  EmployeeReportBloc({required this.employeeReportRepository})
    : super(EmployeeReportInitial()) {
    on<EmployeeReportFetchRequested>(_onEmployeeReportFetchRequested);
    on<EmployeeChanged>(_onEmployeeChanged);
    on<EmployeeMonthChanged>(_onEmployeeMonthChanged);
    on<EmployeeYearChanged>(_onEmployeeYearChanged);
    on<LoadEmployeeSlotsHistory>(_onLoadEmployeeSlotsHistory);
  }

  final EmployeeReportRepository employeeReportRepository;

  String _selectedEmployeeId = '';
  int _selectedMonth = -1;
  String _selectedYear = '';

  final List<SlotDetails> _slots = [];

  final _pageSize = 20;
  int _currentPage = 0;

  bool _isInitial = true;

  List<ServiceType> get _services => getIt<ServiceBloc>().state.services;
  List<UserModel> get _users => getIt<UsersBloc>().users;
  List<Client> get _clients => getIt<ClientsBloc>().clients;

  // Usluga koja je u međuvremenu obrisana se preskače.
  List<ServiceType> _getServicesFromSlot(List<String> serviceIds) =>
      serviceIds
          .map(
            (id) => _services.firstWhereOrNull((service) => service.id == id),
          )
          .nonNulls
          .toList();

  Future<void> _onEmployeeReportFetchRequested(
    EmployeeReportFetchRequested event,
    Emitter<EmployeeReportState> emit,
  ) async {
    if (_isInitial) {
      _isInitial = false;
    }

    if (!isEverythingSelected()) {
      emit(EmployeeReportInitial());
      return;
    }

    emit(EmployeeReportFetching());

    final from = DateTime(int.parse(_selectedYear), _selectedMonth + 1);
    // Prvi dan sljedećeg mjeseca u 00:00, ne uključuje se.
    final to = DateTime(int.parse(_selectedYear), _selectedMonth + 2);

    final QuerySnapshot<Map<String, dynamic>> result;
    try {
      result = await employeeReportRepository.getEmployeeMonthlyReport(
        employeeId: _selectedEmployeeId,
        from: from,
        to: to,
      );
    } on Exception catch (_) {
      emit(
        const EmployeeReportFailure(
          message: 'Izvještaj nije učitan. Pokušajte ponovo.',
        ),
      );
      return;
    }

    // Upit vraća i termine koji počinju prije mjeseca a završavaju u njemu;
    // takav termin pripada prethodnom mjesecu.
    final slots =
        result.docs
            .map((doc) => Slot.fromJson(doc.data(), doc.id))
            .where((slot) => !slot.startDateTime.isBefore(from))
            .toList();

    final employee = _users.firstWhereOrNull(
      (user) => user.id == _selectedEmployeeId,
    );

    double totalEarnings = 0;
    final totalSlots = slots.length;
    var totalServices = 0;

    // total clients are the number of unique client ids in the slots
    final totalClients = slots.map((slot) => slot.clientId).toSet().length;

    // clear the slots list
    _slots.clear();

    for (final slot in slots) {
      final services = _getServicesFromSlot(slot.serviceIds);

      final totalServicePrice = services.fold<double>(
        0,
        (total, service) => total + service.price,
      );

      //earnings are divided by the number of employees
      final earnings = totalServicePrice / slot.employeeIds.length;

      totalEarnings += earnings;

      totalServices += services.length;

      _slots.add(
        SlotDetails(
          startDateTime: slot.startDateTime,
          endDateTime: slot.endDateTime ?? DateTime.now(),
          services: services,
          client: _clients.firstWhereOrNull(
            (client) => client.id == slot.clientId,
          ),
          title: slot.title,
          employeeIds: slot.employeeIds,
          earnings: earnings,
        ),
      );
    }

    final report = EmployeeReport(
      employeeId: _selectedEmployeeId,
      employeeName: employee?.name ?? '',
      employeeEmail: employee?.email ?? '',
      totalEarnings: totalEarnings,
      totalSlots: totalSlots,
      totalClients: totalClients,
      totalServices: totalServices,
    );

    emit(EmployeeReportFetched(report: report));
  }

  void _onEmployeeChanged(
    EmployeeChanged event,
    Emitter<EmployeeReportState> emit,
  ) {
    if (_selectedEmployeeId == event.employeeId) {
      return;
    }

    _selectedEmployeeId = event.employeeId;

    if (_isInitial) {
      emit(EmployeeSelected());
      return;
    }

    if (!isEverythingSelected()) {
      return;
    }

    emit(EmployeeReportFetching());

    add(EmployeeReportFetchRequested());
  }

  void _onEmployeeMonthChanged(
    EmployeeMonthChanged event,
    Emitter<EmployeeReportState> emit,
  ) {
    if (_selectedMonth == event.month) {
      return;
    }

    _selectedMonth = event.month;

    if (_isInitial) {
      return;
    }

    if (!isEverythingSelected()) {
      emit(EmployeeReportInitial());
      return;
    }

    emit(EmployeeReportFetching());

    add(EmployeeReportFetchRequested());
  }

  void _onEmployeeYearChanged(
    EmployeeYearChanged event,
    Emitter<EmployeeReportState> emit,
  ) {
    if (_selectedYear == event.year) {
      return;
    }

    _selectedYear = event.year;

    if (_isInitial) {
      return;
    }

    if (!isEverythingSelected()) {
      emit(EmployeeReportInitial());
      return;
    }

    emit(EmployeeReportFetching());

    add(EmployeeReportFetchRequested());
  }

  Future<void> _onLoadEmployeeSlotsHistory(
    LoadEmployeeSlotsHistory event,
    Emitter<EmployeeReportState> emit,
  ) async {
    if (event.isInitial) {
      _currentPage = 0;
    }

    emit(EmployeeSlotsHistoryLoading());

    // Frontend pagination from in-memory list `_slots`
    final startIndex = _currentPage * _pageSize;
    if (startIndex >= _slots.length) {
      emit(const EmployeeSlotsHistoryLoaded(slots: []));
      return;
    }

    final endIndex = min(startIndex + _pageSize, _slots.length);
    final page = _slots.sublist(startIndex, endIndex);

    emit(EmployeeSlotsHistoryLoaded(slots: List<SlotDetails>.from(page)));
    _currentPage++;
  }

  bool isEverythingSelected() =>
      _selectedEmployeeId.isNotEmpty &&
      _selectedMonth != -1 &&
      _selectedYear.isNotEmpty;

  void resetState() {
    _selectedEmployeeId = '';
    _selectedMonth = -1;
    _selectedYear = '';
    _isInitial = true;
    _slots.clear();
    _currentPage = 0;
  }
}
