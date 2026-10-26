import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get_it/get_it.dart';

import '../../blocs/app_init/bloc/app_init_bloc.dart';
import '../../features/authentication/data/datasources/authentication_remote_datasource.dart';
import '../../features/authentication/data/repositories/authentication_repository.dart';
import '../../features/authentication/data/repositories/authentication_repository_impl.dart';
import '../../features/authentication/domain/bloc/authentication_bloc.dart';
import '../../features/calendar/data/datasources/calendar_remote_datasource.dart';
import '../../features/calendar/data/repositories/calendar_repository.dart';
import '../../features/calendar/data/repositories/calendar_repository_impl.dart';
import '../../features/calendar/domain/bloc/slot_bloc.dart';
import '../../features/client_history/data/datasources/client_history_remote_datasource.dart';
import '../../features/client_history/data/repositories/client_history_repository.dart';
import '../../features/client_history/data/repositories/client_history_repository_impl.dart';
import '../../features/client_history/domain/bloc/client_history_bloc.dart';
import '../../features/employee_report/data/datasources/employee_report_remote_datasource.dart';
import '../../features/employee_report/data/repositories/employee_report_repository.dart';
import '../../features/employee_report/data/repositories/employee_report_repository_impl.dart';
import '../../features/employee_report/domain/bloc/employee_report_bloc.dart';
import '../../features/employees/domain/cubit/employees_picker_cubit.dart';
import '../../features/login/data/datasources/login_remote_datasource.dart';
import '../../features/login/data/repositories/login_repository.dart';
import '../../features/login/data/repositories/login_repository_impl.dart';
import '../../features/login/domain/bloc/login_bloc.dart';
import '../../features/organization/data/datasources/organization_remote_datasource.dart';
import '../../features/organization/data/repositories/organization_repository.dart';
import '../../features/organization/data/repositories/organization_repository_impl.dart';
import '../../features/service/data/datasources/service_remote_datasource.dart';
import '../../features/service/data/repositories/service_repository.dart';
import '../../features/service/data/repositories/service_repository_impl.dart';
import '../../features/service/domain/bloc/service_bloc.dart';
import '../../features/settings/data/datasources/client_remote_datasource.dart';
import '../../features/settings/data/datasources/user_remote_datasource.dart';
import '../../features/settings/data/repositories/client_repository.dart';
import '../../features/settings/data/repositories/client_repository_impl.dart';
import '../../features/settings/data/repositories/user_repository.dart';
import '../../features/settings/data/repositories/user_repository_impl.dart';
import '../../features/settings/domain/bloc/clients_bloc.dart';
import '../../features/settings/domain/cubit/client_picker_cubit.dart';
import '../../features/users/domain/bloc/users_bloc.dart';
import '../app_state/app_state.dart';
import '../cubits/calendar_type_view/calendar_type_view_cubit.dart';
import '../services/firebase_remote_config_service.dart';
import '../services/force_update_service.dart';
import '../services/push_notification_service.dart';

final getIt = GetIt.instance;

final appState = AppState();

void setupDependencies() {
  //firebase instances
  final firebaseAuth = FirebaseAuth.instance;
  final firebaseFirestore = FirebaseFirestore.instance;
  final firebaseFunc = FirebaseFunctions.instance;

  getIt
    //services
    ..registerSingleton<FirebaseRemoteConfigService>(
      FirebaseRemoteConfigService(),
    )
    ..registerSingleton<ForceUpdateService>(
      ForceUpdateService(getIt<FirebaseRemoteConfigService>()),
    )
    //datasources
    ..registerSingleton<AuthenticationRemoteDatasource>(
      AuthenticationRemoteDatasource(
        firebaseAuth: firebaseAuth,
        firebaseFirestore: firebaseFirestore,
      ),
    )
    ..registerSingleton<LoginRemoteDatasource>(
      LoginRemoteDatasource(
        firebaseAuth: firebaseAuth,
        firebaseFirestore: firebaseFirestore,
      ),
    )
    ..registerSingleton<CalendarRemoteDatasource>(
      CalendarRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    ..registerSingleton<UserRemoteDatasource>(
      UserRemoteDatasource(functions: firebaseFunc, firebaseAuth: firebaseAuth),
    )
    ..registerSingleton<ClientRemoteDatasource>(
      ClientRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    ..registerSingleton<OrganizationRemoteDatasource>(
      OrganizationRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    ..registerSingleton<ServiceRemoteDatasource>(
      ServiceRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    ..registerSingleton<ClientHistoryRemoteDatasource>(
      ClientHistoryRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    ..registerSingleton<EmployeeReportRemoteDatasource>(
      EmployeeReportRemoteDatasource(firebaseFirestore: firebaseFirestore),
    )
    //repositories
    ..registerSingleton<LoginRepository>(
      LoginRepositoryImpl(
        loginRemoteDatasource: getIt<LoginRemoteDatasource>(),
      ),
    )
    ..registerSingleton<AuthenticationRepository>(
      AuthenticationRepositoryImpl(
        authenticationRemoteDatasource: getIt<AuthenticationRemoteDatasource>(),
      ),
    )
    ..registerSingleton<CalendarRepository>(
      CalendarRepositoryImpl(
        calendarRemoteDatasource: getIt<CalendarRemoteDatasource>(),
      ),
    )
    ..registerSingleton<PushNotificationService>(
      PushNotificationService(
        messaging: FirebaseMessaging.instance,
        functions: FirebaseFunctions.instanceFor(region: 'europe-west1'),
        calendarRepository: getIt<CalendarRepository>(),
      ),
    )
    ..registerSingleton<UserRepository>(
      UserRepositoryImpl(remote: getIt<UserRemoteDatasource>()),
    )
    ..registerSingleton<OrganizationRepository>(
      OrganizationRepositoryImpl(
        organizationRemoteDatasource: getIt<OrganizationRemoteDatasource>(),
      ),
    )
    ..registerSingleton<ClientRepository>(
      ClientRepositoryImpl(
        clientRemoteDatasource: getIt<ClientRemoteDatasource>(),
      ),
    )
    ..registerSingleton<ServiceRepository>(
      ServiceRepositoryImpl(
        serviceRemoteDatasource: getIt<ServiceRemoteDatasource>(),
      ),
    )
    ..registerSingleton<ClientHistoryRepository>(
      ClientHistoryRepositoryImpl(
        clientHistoryRemoteDatasource: getIt<ClientHistoryRemoteDatasource>(),
      ),
    )
    ..registerSingleton<EmployeeReportRepository>(
      EmployeeReportRepositoryImpl(
        employeeReportRemoteDatasource: getIt<EmployeeReportRemoteDatasource>(),
      ),
    )
    //cubits
    ..registerLazySingleton<CalendarTypeViewCubit>(CalendarTypeViewCubit.new)
    ..registerLazySingleton<EmployeesPickerCubit>(EmployeesPickerCubit.new)
    ..registerLazySingleton<ClientPickerCubit>(ClientPickerCubit.new)
    //blocs
    ..registerFactory<LoginBloc>(
      () => LoginBloc(
        loginRepository: getIt<LoginRepository>(),
        authenticationRepository: getIt<AuthenticationRepository>(),
        organizationRepository: getIt<OrganizationRepository>(),
      ),
    )
    ..registerLazySingleton<AuthenticationBloc>(
      () => AuthenticationBloc(
        authenticationRepository: getIt<AuthenticationRepository>(),
        organizationRepository: getIt<OrganizationRepository>(),
        pushNotificationService: getIt<PushNotificationService>(),
      ),
    )
    ..registerLazySingleton<SlotBloc>(
      () => SlotBloc(getIt<CalendarRepository>()),
    )
    ..registerLazySingleton<ServiceBloc>(
      () => ServiceBloc(getIt<ServiceRepository>()),
    )
    ..registerLazySingleton<UsersBloc>(
      () => UsersBloc(
        organizationRepository: getIt<OrganizationRepository>(),
        userRepository: getIt<UserRepository>(),
      ),
    )
    ..registerLazySingleton<ClientsBloc>(
      () => ClientsBloc(
        clientRepository: getIt<ClientRepository>(),
        clientPickerCubit: getIt<ClientPickerCubit>(),
      ),
    )
    ..registerFactory<ClientHistoryBloc>(
      () => ClientHistoryBloc(
        clientHistoryRepository: getIt<ClientHistoryRepository>(),
      ),
    )
    ..registerLazySingleton<AppInitBloc>(
      () => AppInitBloc(
        authBloc: getIt<AuthenticationBloc>(),
        slotBloc: getIt<SlotBloc>(),
        serviceBloc: getIt<ServiceBloc>(),
        usersBloc: getIt<UsersBloc>(),
        clientsBloc: getIt<ClientsBloc>(),
      ),
    )
    ..registerLazySingleton<EmployeeReportBloc>(
      () => EmployeeReportBloc(
        employeeReportRepository: getIt<EmployeeReportRepository>(),
      ),
    );
}
