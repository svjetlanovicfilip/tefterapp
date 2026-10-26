import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../features/authentication/domain/bloc/authentication_bloc.dart';
import '../../../features/calendar/data/models/slot.dart';
import '../../../features/calendar/domain/bloc/slot_bloc.dart';
import '../../../features/service/domain/bloc/service_bloc.dart';
import '../../../features/settings/domain/bloc/clients_bloc.dart';
import '../../../features/users/domain/bloc/users_bloc.dart';

part 'app_init_event.dart';
part 'app_init_state.dart';

class AppInitBloc extends Bloc<AppInitEvent, AppInitState> {
  AppInitBloc({
    required this.authBloc,
    required this.slotBloc,
    required this.serviceBloc,
    required this.usersBloc,
    required this.clientsBloc,
  }) : super(AppInitInitial()) {
    on<AppInitStarted>(_onStarted);
    on<AppInitAfterLogin>(_onAfterLogin);
  }

  final AuthenticationBloc authBloc;
  final SlotBloc slotBloc;
  final ServiceBloc serviceBloc;
  final UsersBloc usersBloc;
  final ClientsBloc clientsBloc;

  Future<void> _onStarted(
    AppInitStarted event,
    Emitter<AppInitState> emit,
  ) async {
    emit(AppInitLoading());

    authBloc.add(AuthenticationCheckRequested());

    await authBloc.stream.firstWhere(
      (s) => s.status != AuthenticationStatus.unknown,
    );

    if (authBloc.state.status != AuthenticationStatus.authenticated) {
      emit(AppInitUnauthenticated());
      return;
    }

    final slots = await _initDepsAndGetSlots();

    emit(AppInitReady(slots: slots));
  }

  Future<void> _onAfterLogin(
    AppInitAfterLogin event,
    Emitter<AppInitState> emit,
  ) async {
    emit(AppInitLoading());

    final slots = await _initDepsAndGetSlots();
    emit(AppInitReady(slots: slots));
  }

  Future<List<Slot>> _initDepsAndGetSlots() async {
    slotBloc.add(InitListener());
    serviceBloc.add(InitServiceListener());
    usersBloc.add(UsersFetchRequested());
    clientsBloc.add(ClientsInitListener());

    final results = await Future.wait([
      slotBloc.stream.firstWhere((s) => s is SlotsLoaded),
      serviceBloc.stream.firstWhere((s) => s.status == ServiceStatus.loaded),
      usersBloc.stream.firstWhere((s) => s is UsersFetchingSuccess),
      clientsBloc.stream.firstWhere((s) => s is ClientsFetchingSuccess),
    ]);

    return (results[0] as SlotsLoaded).slots;
  }
}
