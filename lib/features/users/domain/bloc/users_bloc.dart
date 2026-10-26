import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/shared_prefs/shared_prefs_service.dart';
import '../../../login/data/models/user_model.dart';
import '../../../organization/data/repositories/organization_repository.dart';
import '../../../settings/data/repositories/user_repository.dart';

part 'users_event.dart';
part 'users_state.dart';

class UsersBloc extends Bloc<UsersEvent, UsersState> {
  UsersBloc({
    required this.organizationRepository,
    required this.userRepository,
  }) : super(UsersInitial()) {
    on<UsersFetchRequested>(_onUsersFetchRequested);
    on<UserAdded>(_onUserAdded);
    on<UserRemoved>(_onUserRemoved);
    on<SelectUser>(_onUserSelected);
    on<UsersReordered>(_onUsersReordered);
  }

  final OrganizationRepository organizationRepository;
  final UserRepository userRepository;

  List<UserModel> get users => _users;
  UserModel? _selectedUser;

  List<UserModel> _users = [];

  Future<void> _onUsersFetchRequested(
  UsersFetchRequested event,
  Emitter<UsersState> emit,
) async {
  // 0) Ako već ima u memoriji, odmah prikaži
  if (_users.isNotEmpty) {
    emit(UsersFetchingSuccess(List.from(_users)));
    return;
  } else {
    emit(UsersFetching());

    // 1) Učitaj lokalni cache (redoslijed)
    final localUsers = await SharedPrefsService.instance.getUsers();
    if (localUsers.isNotEmpty) {
      _users = localUsers.where((u) => u.isActive).toList();
      emit(UsersFetchingSuccess(List.from(_users)));
    }
  }

  // 2) Uvijek povuci remote da osvježiš podatke
  final usersResult = await organizationRepository.getOrganizationUsers(
    appState.organizationId!,
  );

  if (usersResult.isFailure) {
    // Ako već imaš nešto prikazano, ne ruši UI
    return;
  }

  final remoteUsers = (usersResult.success ?? [])
      .where((u) => u.isActive)
      .toList();

  // 3) Merge: remote DATA + local ORDER
  final merged = _mergeRemoteDataWithLocalOrder(
    localOrdered: _users,     // trenutno stanje (lokalni redoslijed)
    remoteFresh: remoteUsers, // svježi podaci
  );

  _users = merged;

  emit(UsersFetchingSuccess(List.from(_users)));
  await SharedPrefsService.instance.setUsers(_users);

}


  Future<void> _onUsersFetchRequested2(
    UsersFetchRequested event,
    Emitter<UsersState> emit,
  ) async {
    if (_users.isNotEmpty) {
      emit(UsersFetchingSuccess(List.from(_users)));
      return;
    }

    emit(UsersFetching());

   final localUsers = await SharedPrefsService.instance.getUsers();
    if(localUsers.isNotEmpty){
      _users = localUsers;
      emit(UsersFetchingSuccess(List.from(_users)));
      return;
    }

    final users = await organizationRepository.getOrganizationUsers(
      appState.organizationId!,
    );

    if (users.isFailure) {
      return;
    }

    _users = (users.success ?? []).where((u) => u.isActive).toList();

    emit(UsersFetchingSuccess(List.from(_users)));
  }

  Future<void> _onUserAdded(UserAdded event, Emitter<UsersState> emit) async {
    emit(UsersAdding());

    final result = await userRepository.createEmployee(
      name: event.user.name ?? '',
      lastName: event.user.surname ?? '',
      username: event.user.username ?? '',
      email: event.user.email,
    );

    if (result.isFailure) {
      // bez ovoga state ostaje UsersAdding i dugme se vrti zauvijek
      final error = result.failure.toString();
      emit(
        UsersAddingFailure(
          error.contains('already-exists')
              ? 'Korisnik sa ovim emailom već postoji.'
              : 'Dodavanje zaposlenog nije uspjelo. Pokušajte ponovo.',
        ),
      );
      return;
    }

    if (result.success != null) {
      _users.add(result.success!);
      emit(UsersFetchingSuccess(List.from(_users)));
      if((await SharedPrefsService.instance.getUsers()).isNotEmpty){
          await SharedPrefsService.instance.addUser(result.success!);
      }
    }
  }

  Future<void> _onUserRemoved(
    UserRemoved event,
    Emitter<UsersState> emit,
  ) async {
    _users.removeWhere((user) => user.id == event.userId);

    emit(UsersFetchingSuccess(List.from(_users)));

    final result = await userRepository.deleteEmployee(
      employeeUid: event.userId,
    );

    if (result.isFailure) {
      return;
    }
     if((await SharedPrefsService.instance.getUsers()).isNotEmpty){
          await SharedPrefsService.instance.removeUserById(event.userId);
      }
  }

  void _onUserSelected(SelectUser event, Emitter<UsersState> emit) {
    _selectedUser = _users.firstWhere((user) => user.id == event.userId);
    emit(UserSelected(user: _selectedUser!));
  }

Future<void> _onUsersReordered(
  UsersReordered event,
  Emitter<UsersState> emit,
) async {

    final item = _users.removeAt(event.oldIndex);
      _users.insert(event.newIndex, item);

  final userIds = _users
        .map((e) => e.id ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

  if (_users.isEmpty || userIds.isEmpty) return;

  // mapa postojećih usera po ID-u
  final byId = <String, UserModel>{
    for (final u in _users)
      if (u.id != null) u.id!: u,
  };

  // složi novu listu po redoslijedu iz eventa
  final reordered = <UserModel>[];
  for (final id in userIds) {
    final user = byId[id];
    if (user != null) reordered.add(user);
  }

  // dodaj eventualne korisnike koji nisu bili u orderedUserIds
  // (defanzivno da ništa ne izgubiš)
  for (final u in _users) {
    if (!reordered.contains(u)) {
      reordered.add(u);
    }
  }

  _users = reordered;

  // opcionalno: sačuvaj lokalno redoslijed

  emit(UsersFetchingSuccess(List.from(_users)));

  await SharedPrefsService.instance.setUsers(_users);

}


  void clearState() {
    _users.clear();
    _selectedUser = null;
  }

  List<UserModel> _mergeRemoteDataWithLocalOrder({
  required List<UserModel> localOrdered,
  required List<UserModel> remoteFresh,
}) {
  // mapa remote usera po id-u (najnoviji podaci)
  final remoteById = <String, UserModel>{
    for (final u in remoteFresh)
      if (u.id != null && u.id!.isNotEmpty) u.id!: u,
  };

  final result = <UserModel>[];
  final usedIds = <String>{};

  // A) zadrži lokalni redoslijed, ali uzmi remote verzije usera
  for (final local in localOrdered) {
    final id = local.id;
    if (id == null || id.isEmpty) continue;

    final remoteUser = remoteById[id];
    if (remoteUser != null) {
      result.add(remoteUser); // svježi podaci, lokalni položaj
      usedIds.add(id);
    }
    // ako ga remote nema -> preskoči (obrisan/deaktiviran)
  }

  // B) dodaj nove remote usere koji nisu bili u lokalnoj listi (na kraj)
  for (final remote in remoteFresh) {
    final id = remote.id;
    if (id == null || id.isEmpty) continue;

    if (!usedIds.contains(id)) {
      result.add(remote);
      usedIds.add(id);
    }
  }

  return result;
}

}
