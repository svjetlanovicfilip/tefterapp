import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/services/push_notification_service.dart';
import '../../../organization/data/repositories/organization_repository.dart';
import '../../data/repositories/authentication_repository.dart';

part 'authentication_event.dart';
part 'authentication_state.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  AuthenticationBloc({
    required this.authenticationRepository,
    required this.organizationRepository,
    required this.pushNotificationService,
  }) : super(const AuthenticationState()) {
    on<AuthenticationCheckRequested>(_onAuthenticationCheckRequested);
    on<AuthenticationLogoutRequested>(_onAuthenticationLogoutRequested);
  }

  final AuthenticationRepository authenticationRepository;
  final OrganizationRepository organizationRepository;
  final PushNotificationService pushNotificationService;

  Future<void> _onAuthenticationCheckRequested(
    AuthenticationCheckRequested event,
    Emitter<AuthenticationState> emit,
  ) async {
    final user = authenticationRepository.isUserAuthenticated();
    if (user.isFailure) {
      emit(state.copyWith(status: AuthenticationStatus.unauthenticated));
      return;
    }

    final userProfile = await authenticationRepository.getUserProfile(
      user.success?.uid ?? '',
    );

    if (userProfile.isFailure) {
      emit(state.copyWith(status: AuthenticationStatus.unauthenticated));
      return;
    }

    if (userProfile.success?.organizationId == null) {
      emit(state.copyWith(status: AuthenticationStatus.unauthenticated));
      return;
    }

    final organization = await organizationRepository.getUserOrganization(
      userProfile.success!.organizationId!,
    );

    if (organization.isFailure) {
      emit(state.copyWith(status: AuthenticationStatus.unauthenticated));
      return;
    }

    appState
      ..currentUser = userProfile.success!
      ..currentSelectedUserId = userProfile.success!.id
      ..organizationId = userProfile.success!.organizationId
      ..userOrganization = organization.success;

    // Set user identifier for Crashlytics
    unawaited(
      FirebaseCrashlytics.instance.setUserIdentifier(
        userProfile.success!.email,
      ),
    );

    emit(state.copyWith(status: AuthenticationStatus.authenticated));
  }

  Future<void> _onAuthenticationLogoutRequested(
    AuthenticationLogoutRequested event,
    Emitter<AuthenticationState> emit,
  ) async {
    // Token se briše dok je korisnik još prijavljen.
    await pushNotificationService.onUserSignedOut();
    await authenticationRepository.logout();
    emit(state.copyWith(status: AuthenticationStatus.unauthenticated));
  }
}
