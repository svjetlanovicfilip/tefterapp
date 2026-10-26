import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/shared_prefs/shared_prefs_service.dart';
import '../../data/client.dart';
import '../../data/repositories/client_repository.dart';
import '../cubit/client_picker_cubit.dart';

part 'clients_event.dart';
part 'clients_state.dart';

class ClientsBloc extends Bloc<ClientsEvent, ClientsState> {
  ClientsBloc({required this.clientRepository, required this.clientPickerCubit})
    : super(ClientsInitial()) {
    on<ClientsInitListener>(_onInitListener);
    on<ClientsFetchRequested>(_onFetchClients);
    on<ClientAdded>(_onClientAdded);
    on<ClientRemoved>(_onClientRemoved);
    on<ClientUpdated>(_onClientUpdated);
    on<ClientsSearched>(_onClientsSearched);
    on<ClientSelected>(_onClientSelected);
  }

  final ClientRepository clientRepository;

  final ClientPickerCubit clientPickerCubit;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clientsListener;

  /// Povremena puna sinhronizacija, za slučaj da je delta-sync nešto
  /// propustio (npr. Firestore je izbacio dokumente iz keša).
  static const _fullSyncInterval = Duration(days: 7);

  List<Client> get clients => _clients;

  final List<Client> _clients = [];

  Future<void> _onInitListener(
    ClientsInitListener event,
    Emitter<ClientsState> emit,
  ) async {
    emit(ClientsFetching());

    final orgId = appState.organizationId;
    if (orgId == null) {
      emit(ClientsFetchingSuccess(_clients));
      return;
    }

    await _clientsListener?.cancel();
    _clients
      ..clear()
      // Klijenti iz Firestore keša se prikazuju odmah i ne troše readove.
      ..addAll(await clientRepository.getCachedClients(organizationId: orgId));
    if (_clients.isNotEmpty) {
      _sortClients();
      emit(ClientsFetchingSuccess(List.from(_clients)));
    }

    // Sa servera se onda čitaju samo klijenti izmijenjeni nakon posljednje
    // izmjene koju već imamo. Bez updatedAt-a (prvo pokretanje, keš prije
    // migracije) ili kad je prošlo dovoljno vremena, čitaju se svi.
    final lastFullSync = await SharedPrefsService.instance.getClientsFullSyncAt(
      orgId,
    );
    final isFullSyncDue =
        lastFullSync == null ||
        DateTime.now().difference(lastFullSync) > _fullSyncInterval;
    final since = isFullSyncDue ? null : _latestUpdatedAt();

    _clientsListener = clientRepository
        .listenForClientChanges(organizationId: orgId, since: since)
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final id = change.doc.id;

              switch (change.type) {
                case DocumentChangeType.added:
                case DocumentChangeType.modified:
                  final client = Client.fromJson(change.doc.data() ?? {}, id);
                  final index = _clients.indexWhere((c) => c.id == id);
                  if (index != -1) {
                    _clients[index] = client;
                  } else {
                    _clients.add(client);
                  }
                  break;
                case DocumentChangeType.removed:
                  // U delta modu "removed" znači samo da dokument trenutno ne
                  // odgovara upitu (npr. lokalna izmjena čeka serverski
                  // updatedAt). Klijenti se ne brišu, nego dobiju
                  // isActive: false, pa ih tada ne uklanjamo.
                  if (since == null) {
                    _clients.removeWhere((c) => c.id == id);
                  }
                  break;
              }
            }
            _sortClients();

            if (since == null && !snapshot.metadata.isFromCache) {
              unawaited(
                SharedPrefsService.instance.setClientsFullSyncAt(
                  orgId,
                  DateTime.now(),
                ),
              );
            }

            add(ClientsFetchRequested());
          },
          onError: (Object error, StackTrace stackTrace) {
            unawaited(
              FirebaseCrashlytics.instance.recordError(error, stackTrace),
            );
            // da AppInitBloc ne ostane zaglavljen ako keš nije imao klijente
            add(ClientsFetchRequested());
          },
        );
  }

  Timestamp? _latestUpdatedAt() {
    Timestamp? latest;
    for (final client in _clients) {
      final updatedAt = client.updatedAt;
      if (updatedAt != null &&
          (latest == null || updatedAt.compareTo(latest) > 0)) {
        latest = updatedAt;
      }
    }
    return latest;
  }

  /// Najnoviji klijenti prvi, kao ranije orderBy('createdAt', descending).
  void _sortClients() {
    _clients.sort((a, b) {
      final aCreatedAt = a.createdAt;
      final bCreatedAt = b.createdAt;
      // tek kreiran klijent još nema serverski createdAt
      if (aCreatedAt == null) return bCreatedAt == null ? 0 : -1;
      if (bCreatedAt == null) return 1;
      return bCreatedAt.compareTo(aCreatedAt);
    });
  }

  Future<void> _onFetchClients(
    ClientsFetchRequested event,
    Emitter<ClientsState> emit,
  ) async => emit(ClientsFetchingSuccess(List.from(_clients)));

  Future<void> _onClientAdded(
    ClientAdded event,
    Emitter<ClientsState> emit,
  ) async {
    emit(ClientsAdding());

    final orgId = appState.organizationId;

    if (orgId == null) {
      return;
    }

    try {
      final clientId = await clientRepository.createClient(event.client, orgId);

      final createdClient = Client(
        id: clientId,
        name: event.client.name,
        phoneNumber: event.client.phoneNumber,
        description: event.client.description,
        createdAt: event.client.createdAt,
        isActive: event.client.isActive,
      );

      //if client is added from appointment, pick it
      if (event.isClientAddedFromAppointment) {
        clientPickerCubit.pickClient(client: createdClient);
      }
    } on Exception catch (_) {
      // Ako želiš: dodaj ClientsFailure state
      // Za sada možeš bar vratiti prethodno stanje ili prazan:
      emit(ClientsFetchingSuccess(List.from(_clients)));
    }
  }

  Future<void> _onClientUpdated(
    ClientUpdated event,
    Emitter<ClientsState> emit,
  ) async {
    emit(ClientsAdding());

    final orgId = appState.organizationId;
    if (orgId == null) {
      // nema orgId -> vrati listu kakva je
      emit(ClientsFetchingSuccess(List.from(_clients)));
      return;
    }

    final updated = event.client;
    final updatedId = updated.id;

    if (updatedId == null || updatedId.isEmpty) {
      emit(ClientsFetchingSuccess(List.from(_clients)));
      return;
    }

    try {
      // 1) update in database and listen for changes
      await clientRepository.updateClient(updated, orgId);
    } on Exception catch (_) {
      // bez Failure state-a, vraćamo trenutno stanje
      emit(ClientsFetchingSuccess(List.from(_clients)));
    }
  }

  Future<void> _onClientRemoved(
    ClientRemoved event,
    Emitter<ClientsState> emit,
  ) async {
    final organizationId = appState.organizationId;
    if (organizationId == null) return;

    try {
      // 1) prvo soft-delete na backendu
      await clientRepository.deleteClient(event.clientId, organizationId);
    } on Exception catch (e) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current),
      );
      // ako imaš Failure state, emituj njega; u suprotnom vrati listu kakva je bila
      emit(ClientsFetchingSuccess(List.from(_clients)));
    }
  }

  void clearState() {
    _clients.clear();
    _clientsListener?.cancel();
  }

  void _onClientsSearched(ClientsSearched event, Emitter<ClientsState> emit) {
    if (_clients.isEmpty) {
      return;
    }

    final searchQuery = event.searchQuery;
    if (searchQuery.isEmpty) {
      emit(ClientsFetchingSuccess(List.from(_clients)));
      return;
    }

    final clients =
        _clients
            .where(
              (client) =>
                  client.name.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();

    emit(ClientsSearchSuccess(List.from(clients)));
  }

  void _onClientSelected(ClientSelected event, Emitter<ClientsState> emit) {
    if (event.clientId == null) {
      return;
    }

    final client = _clients.firstWhere((client) => client.id == event.clientId);
    emit(ClientsSelectSuccess(client));
  }
}
