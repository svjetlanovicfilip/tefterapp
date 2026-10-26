import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../config/style/colors.dart';
import '../../features/calendar/data/repositories/calendar_repository.dart';
import '../../features/calendar/ui/screens/book_appointment_screen.dart';
import '../constants/routes.dart';
import '../di/di_container.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Push notifikacije za termine. Notifikacije šalje Cloud Function
/// `notifySlotChange`, a u `data` dijelu poruke stižu `type`, `slotId` i
/// `orgId`.
class PushNotificationService {
  PushNotificationService({
    required this.messaging,
    required this.functions,
    required this.calendarRepository,
  });

  final FirebaseMessaging messaging;
  final FirebaseFunctions functions;
  final CalendarRepository calendarRepository;

  static const _bannerDuration = Duration(seconds: 8);

  bool _isUserSignedIn = false;

  /// Termin iz notifikacije na koju je korisnik tapnuo prije nego što je
  /// aplikacija bila spremna (npr. aplikacija je bila ugašena).
  String? _pendingSlotId;

  Timer? _bannerTimer;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Poziva se jednom, odmah nakon inicijalizacije Firebase-a.
  Future<void> init() async {
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _onNotificationOpened(initialMessage);
    }
  }

  /// Poziva se kad korisnik dođe na početni ekran (nakon prijave ili
  /// automatske prijave).
  Future<void> onUserSignedIn() async {
    _isUserSignedIn = true;

    final pendingSlotId = _pendingSlotId;
    _pendingSlotId = null;
    if (pendingSlotId != null) {
      unawaited(openSlot(pendingSlotId));
    }

    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerToken(token)),
      );

      // Na iOS-u FCM token postoji tek kad stigne APNs token.
      if (Platform.isIOS && await _waitForApnsToken() == null) {
        return;
      }

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } on Exception catch (e, stackTrace) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, stackTrace));
    }
  }

  /// Poziva se prije odjave, dok je korisnik još autentifikovan.
  Future<void> onUserSignedOut() async {
    _isUserSignedIn = false;
    _pendingSlotId = null;
    _hideBanner();

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    // Odjava čeka ovu metodu, pa sve mora imati timeout. Inače bi bez
    // interneta signOut mogao zakasniti i odjaviti sljedećeg korisnika.
    try {
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (token == null) return;

      await functions
          .httpsCallable('unregisterPushToken')
          .call(<String, dynamic>{'token': token})
          .timeout(const Duration(seconds: 5));
    } on Exception catch (e, stackTrace) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, stackTrace));
    }
  }

  Future<void> openSlot(String slotId) async {
    final result = await calendarRepository.getSlotById(slotId);
    final slot = result.success;

    if (slot == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            result.isFailure
                ? 'Termin trenutno nije moguće učitati.'
                : 'Termin više ne postoji.',
          ),
        ),
      );
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.popUntil(
      (route) => route.settings.name == Routes.home || route.isFirst,
    );
    unawaited(
      navigator.pushNamed(
        Routes.bookAppointment,
        arguments: BookAppointmentScreenArguments(slot: slot),
      ),
    );
  }

  Future<String?> _waitForApnsToken() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final apnsToken = await messaging.getAPNSToken();
      if (apnsToken != null) return apnsToken;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
  }

  Future<void> _registerToken(String token) async {
    try {
      await functions.httpsCallable('registerPushToken').call(<String, dynamic>{
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } on Exception catch (e, stackTrace) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, stackTrace));
    }
  }

  /// Vraća id termina samo ako je poruka za trenutnu organizaciju i termin
  /// još postoji.
  String? _slotIdFrom(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'deleted') return null;
    if (data['orgId'] != appState.organizationId) return null;

    final slotId = data['slotId'];
    return slotId is String && slotId.isNotEmpty ? slotId : null;
  }

  void _onNotificationOpened(RemoteMessage message) {
    if (!_isUserSignedIn) {
      // organizationId još nije poznat. openSlot traži termin u organizaciji
      // korisnika, pa termin iz druge organizacije neće biti pronađen.
      final slotId = message.data['slotId'];
      if (message.data['type'] != 'deleted' && slotId is String) {
        _pendingSlotId = slotId;
      }
      return;
    }

    final slotId = _slotIdFrom(message);
    if (slotId != null) {
      unawaited(openSlot(slotId));
    }
  }

  /// Dok je aplikacija otvorena sistem ne prikazuje notifikaciju, pa je
  /// prikazujemo kao banner na vrhu ekrana.
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint(
      'Push (aplikacija otvorena): ${message.notification?.title} '
      '${message.data}, prijavljen: $_isUserSignedIn',
    );
    if (!_isUserSignedIn) return;

    final notification = message.notification;
    final messenger = scaffoldMessengerKey.currentState;
    if (notification == null || messenger == null) return;

    final slotId = _slotIdFrom(message);

    _bannerTimer?.cancel();
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: AppColors.white,
          leading: const Icon(
            Icons.notifications_active,
            color: AppColors.amber500,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                notification.title ?? '',
                style: const TextStyle(
                  color: AppColors.slate800,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((notification.body ?? '').isNotEmpty)
                Text(
                  notification.body!,
                  style: const TextStyle(color: AppColors.slate600),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: _hideBanner, child: const Text('Zatvori')),
            if (slotId != null)
              TextButton(
                onPressed: () {
                  _hideBanner();
                  unawaited(openSlot(slotId));
                },
                child: const Text('Pogledaj termin'),
              ),
          ],
        ),
      );

    _bannerTimer = Timer(_bannerDuration, _hideBanner);
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    scaffoldMessengerKey.currentState?.hideCurrentMaterialBanner();
  }
}
