import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../../blocs/app_init/bloc/app_init_bloc.dart';
import '../../constants/routes.dart';
import '../../di/di_container.dart';
import '../../extensions/context_extension.dart';
import '../../services/firebase_remote_config_service.dart';
import '../../services/force_update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final AppInitBloc _appInitBloc = getIt<AppInitBloc>();
  late final ForceUpdateService _forceUpdateService =
      getIt<ForceUpdateService>();

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initialiseSDKs();
    });
  }

  Future<void> initialiseSDKs() async {
    try {
      await getIt<FirebaseRemoteConfigService>().setupRemoteConfig();
    } on Exception catch (_) {
    } finally {
      final hasUpdate = await _checkUpdate();

      if (!hasUpdate) {
        _appInitBloc.add(AppInitStarted());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppInitBloc, AppInitState>(
      bloc: _appInitBloc,
      listener: (context, state) {
        if (state is AppInitReady) {
          context.pushReplacementNamed(Routes.home);
        } else if (state is AppInitUnauthenticated) {
          context.pushReplacementNamed(Routes.login);
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFC107), Color(0xFFF59E0B)],
              stops: [0.0, 0.55],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Zilla Slab',
                fontSize: 64,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              child: AnimatedTextKit(
                animatedTexts: [
                  BounceAnimatedText('Tefter', bounceHeight: 200),
                ],
                isRepeatingAnimation: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _checkUpdate() async {
    final isUpdateRequired = await _forceUpdateService.isUpdateRequired();
    if (isUpdateRequired) {
      context.replace(Routes.update, arguments: true);

      return true;
    }

    final isUpdateAvailable = await _forceUpdateService.isUpdateAvailable();
    if (isUpdateAvailable) {
      context.replace(Routes.update, arguments: false);

      return true;
    }

    return false;
  }
}
