import 'dart:async';

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

  /// Koliko se najduže čeka na podatke prije ulaska u aplikaciju. Listeneri
  /// nastavljaju raditi, pa podaci koji kasne stignu i poslije.
  static const _initTimeout = Duration(seconds: 15);

  Future<void> _onStarted(
    AppInitStarted event,
    Emitter<AppInitState> emit,
  ) async {
    emit(AppInitLoading());

    authBloc.add(AuthenticationCheckRequested());

    // Ako provjera ne završi, korisnik ide na prijavu umjesto da ostane
    // na splashu.
    await _waitFor(
      authBloc.stream,
      (s) => s.status != AuthenticationStatus.unknown,
    ).timeout(_initTimeout, onTimeout: () {});

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

    await Future.wait([
      _waitFor(slotBloc.stream, (s) => s is SlotsLoaded),
      _waitFor(serviceBloc.stream, (s) => s.status == ServiceStatus.loaded),
      _waitFor(usersBloc.stream, (s) => s is UsersFetchingSuccess),
      _waitFor(clientsBloc.stream, (s) => s is ClientsFetchingSuccess),
    ]).timeout(_initTimeout, onTimeout: () => []);

    return slotBloc.slots;
  }

  /// Greška u jednom streamu ne smije zaustaviti ulazak u aplikaciju.
  Future<void> _waitFor<T>(Stream<T> stream, bool Function(T) test) async {
    try {
      await stream.firstWhere(test);
    } on Object catch (_) {}
  }
}
