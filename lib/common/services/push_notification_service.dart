import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/calendar/data/repositories/calendar_repository.dart';
import '../../features/calendar/ui/screens/book_appointment_screen.dart';
import '../constants/routes.dart';
import '../di/di_container.dart';
import '../shared_prefs/shared_prefs_service.dart';

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

  /// Plugin se koristi samo na Androidu: tamo sistem ne prikazuje push dok je
  /// aplikacija otvorena. Na iOS-u to radi sistem sam.
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    // Isti id šalje i Cloud Function, pa sve notifikacije termina idu u
    // isti kanal.
    'termini',
    'Termini',
    description: 'Novi, izmijenjeni i otkazani termini.',
    importance: Importance.high,
  );

  bool _isUserSignedIn = false;

  /// Da li prijavljeni korisnik želi notifikacije na ovom uređaju.
  bool _isEnabled = true;

  /// Termin iz notifikacije na koju je korisnik tapnuo prije nego što je
  /// aplikacija bila spremna (npr. aplikacija je bila ugašena).
  String? _pendingSlotId;

  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Poziva se jednom, odmah nakon inicijalizacije Firebase-a.
  Future<void> init() async {
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

    if (Platform.isIOS) {
      // Notifikacija sa zvukom i dok je aplikacija otvorena; tap stiže kroz
      // onMessageOpenedApp kao i inače.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else if (Platform.isAndroid) {
      await _initLocalNotifications();
    }

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _onNotificationOpened(initialMessage);
    }
  }

  Future<void> _initLocalNotifications() async {
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(
          '@mipmap/ic_launcher_monochrome',
        ),
      ),
      onDidReceiveNotificationResponse:
          (response) => _onLocalNotificationTapped(response.payload),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);

    // Aplikacija je ugašena, a korisnik je tapnuo notifikaciju koju je
    // aplikacija ranije prikazala.
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _onLocalNotificationTapped(launchDetails!.notificationResponse?.payload);
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

    _isEnabled = await isEnabled();
    if (!_isEnabled) {
      // Ako odjava tokena ranije nije uspjela (npr. bez interneta), uređaj bi
      // i dalje dobijao notifikacije.
      await _unregisterToken();
      return;
    }

    try {
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _registerCurrentToken();
    } on Exception catch (e, stackTrace) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, stackTrace));
    }
  }

  /// Poziva se prije odjave, dok je korisnik još autentifikovan.
  Future<void> onUserSignedOut() async {
    _isUserSignedIn = false;
    _pendingSlotId = null;

    await _unregisterToken();
  }

  /// Izbor korisnika iz podešavanja. Podrazumijevano su notifikacije uključene.
  Future<bool> isEnabled() async {
    final userId = appState.currentUser?.id;
    if (userId == null) return true;

    return SharedPrefsService.instance.getPushNotificationsEnabled(userId);
  }

  /// Da li su notifikacije za aplikaciju isključene u podešavanjima telefona.
  /// Tada ih aplikacija ne može uključiti sama.
  Future<bool> isBlockedBySystem() async {
    final settings = await messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.denied;
  }

  /// Uključuje ili isključuje notifikacije na ovom uređaju. Vraća false ako
  /// ih nije moguće uključiti jer ih telefon blokira.
  Future<bool> setEnabled({required bool enabled}) async {
    final userId = appState.currentUser?.id;
    if (userId == null) return false;

    if (!enabled) {
      _isEnabled = false;
      await SharedPrefsService.instance.setPushNotificationsEnabled(
        userId,
        enabled: false,
      );
      await _unregisterToken();
      return true;
    }

    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }

    _isEnabled = true;
    await SharedPrefsService.instance.setPushNotificationsEnabled(
      userId,
      enabled: true,
    );

    // Greška pri registraciji (npr. bez interneta) ne znači da telefon
    // blokira notifikacije; token se ponovo registruje pri sljedećoj prijavi.
    try {
      await _registerCurrentToken();
    } on Exception catch (e, stackTrace) {
      unawaited(FirebaseCrashlytics.instance.recordError(e, stackTrace));
    }
    return true;
  }

  Future<void> _registerCurrentToken() async {
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
  }

  Future<void> _unregisterToken() async {
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

  /// Payload je id termina; prazan kad notifikacija ne vodi na termin.
  void _onLocalNotificationTapped(String? slotId) {
    if (slotId == null || slotId.isEmpty) return;

    if (!_isUserSignedIn) {
      _pendingSlotId = slotId;
      return;
    }
    unawaited(openSlot(slotId));
  }

  /// Na Androidu sistem ne prikazuje push dok je aplikacija otvorena, pa ga
  /// prikazujemo kao lokalnu notifikaciju. Na iOS-u ga prikazuje sistem.
  void _onForegroundMessage(RemoteMessage message) {
    if (!Platform.isAndroid || !_isUserSignedIn || !_isEnabled) return;

    final notification = message.notification;
    if (notification == null) return;

    final slotId = _slotIdFrom(message);

    unawaited(
      _localNotifications.show(
        // Nova notifikacija za isti termin zamjenjuje prethodnu.
        (slotId ?? message.messageId ?? '').hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: slotId,
      ),
    );
  }
}
