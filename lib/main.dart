import 'dart:ui';

import 'package:calendar_view/calendar_view.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'common/constants/routes.dart';
import 'common/di/di_container.dart';
import 'common/shared_prefs/shared_prefs_service.dart';
import 'common/widgets/screens/splash_screen.dart';
import 'common/widgets/screens/update_screen.dart';
import 'config/style/theme.dart';
import 'features/calendar/data/models/slot.dart';
import 'features/calendar/ui/screens/book_appointment_screen.dart';
import 'features/calendar/ui/screens/home_screen.dart';
import 'features/client_history/ui/screens/client_history_screen.dart';
import 'features/employee_report/ui/screens/employee_report_screen.dart';
import 'features/employee_report/ui/screens/slot_list_screen.dart';
import 'features/login/ui/screens/forgot_password_screen.dart';
import 'features/login/ui/screens/login_screen.dart';
import 'features/service/data/models/service_type.dart';
import 'features/service/ui/screens/add_edit_service_screen.dart';
import 'features/service/ui/screens/service_list_screen.dart';
import 'features/settings/data/client.dart';
import 'features/settings/ui/screens/add_edit_client_screen.dart';
import 'features/settings/ui/screens/add_edit_employee_screen.dart';
import 'features/settings/ui/screens/change_password_screen.dart';
import 'features/settings/ui/screens/change_title_screen.dart';
import 'features/settings/ui/screens/clients_screen.dart';
import 'features/settings/ui/screens/employees_screen.dart';
import 'features/settings/ui/screens/settings_screen.dart';

Future<void> mainApp(FirebaseOptions options) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp(options: options);

  await SharedPrefsService.instance.init();

  setupDependencies();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  };
  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final EventController<Slot> _eventController;

  @override
  void initState() {
    super.initState();
    _eventController = EventController();
  }

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: lightTheme,
        initialRoute: Routes.splash,
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case Routes.splash:
              return CupertinoPageRoute(
                builder: (context) => const SplashScreen(),
              );
            case Routes.update:
              return CupertinoPageRoute(
                builder:
                    (context) => UpdateScreen(
                      isRequred: settings.arguments as bool? ?? false,
                    ),
              );
            case Routes.login:
              return CupertinoPageRoute(
                builder: (context) => const LoginScreen(),
              );
            case Routes.home:
              return CupertinoPageRoute(
                builder: (context) => const HomeScreen(),
              );
            case Routes.settings:
              return CupertinoPageRoute(
                builder: (context) => const SettingsScreen(),
              );
            case Routes.changePasswordScreen:
              return CupertinoPageRoute(
                builder: (context) => const ChangePasswordScreen(),
              );
            case Routes.changeTitleScreen:
              return CupertinoPageRoute(
                builder: (context) => const ChangeTitleScreen(),
              );
            case Routes.employeesScreen:
              return CupertinoPageRoute(
                builder: (context) => const EmployeesScreen(),
              );
            case Routes.addEditEmployeesScreen:
              return CupertinoPageRoute(
                builder: (context) => const AddEditEmployeeScreen(),
              );
            case Routes.bookAppointment:
              return CupertinoPageRoute(
                builder:
                    (context) => BookAppointmentScreen(
                      arguments:
                          settings.arguments as BookAppointmentScreenArguments?,
                    ),
              );
            case Routes.serviceListScreen:
              return CupertinoPageRoute(
                builder: (context) => const ServiceListScreen(),
              );
            case Routes.addEditServicesScreen:
              return CupertinoPageRoute(
                builder:
                    (context) => AddEditServiceScreen(
                      service: settings.arguments as ServiceType?,
                    ),
              );
            case Routes.forgotPassword:
              return CupertinoPageRoute(
                builder: (context) => const ForgotPasswordScreen(),
              );
            case Routes.clientHistory:
              return CupertinoPageRoute(
                builder:
                    (context) => ClientHistoryScreen(
                      client: settings.arguments as Client,
                    ),
              );
            case Routes.clientsScreen:
              return CupertinoPageRoute(
                builder: (context) => const ClientsScreen(),
              );
            case Routes.addEditClientsScreen:
              return CupertinoPageRoute(
                builder:
                    (context) => AddEditClientScreen(
                      args: settings.arguments as AddEditClientScreenArgs,
                    ),
              );
            case Routes.employeeReport:
              return CupertinoPageRoute(
                builder: (context) => const EmployeeReportScreen(),
              );
            case Routes.slotListScreen:
              return CupertinoPageRoute(
                builder: (context) => const SlotListScreen(),
              );
            default:
              return MaterialPageRoute(
                builder:
                    (context) =>
                        const Scaffold(body: Center(child: Text('404'))),
              );
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _eventController.dispose();
    super.dispose();
  }
}
