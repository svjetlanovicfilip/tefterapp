import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';

import '../../../../blocs/app_init/bloc/app_init_bloc.dart';
import '../../../../common/constants/routes.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/widgets/logo_widget.dart';
import '../../../../config/style/colors.dart';
import '../../domain/bloc/login_bloc.dart';
import '../widgets/login_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final LoginBloc _loginBloc = getIt<LoginBloc>();
  final AppInitBloc _appInitBloc = getIt<AppInitBloc>();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<LoginBloc, LoginState>(
          bloc: _loginBloc,
          listener: (context, state) {
            if (state.status == FormzSubmissionStatus.success) {
              _appInitBloc.add(AppInitAfterLogin());
            } else if (state.status == FormzSubmissionStatus.failure &&
                state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage ?? ''),
                  backgroundColor: AppColors.red600,
                ),
              );
            }
          },
        ),
        BlocListener<AppInitBloc, AppInitState>(
          bloc: _appInitBloc,
          listener: (context, state) {
            if (state is AppInitReady) {
              context.pushReplacementNamed(Routes.home);
            }
          },
        ),
      ],
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.slate900, AppColors.slate800],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LogoWidget(size: 32, radius: 40),
                        const SizedBox(height: 24),
                        Text(
                          'Dobrodošli nazad',
                          style: Theme.of(
                            context,
                          ).textTheme.headlineSmall?.copyWith(fontSize: 32),
                        ),

                        Text(
                          'Prijavite se za upravljanje vašim terminima',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 32),

                        LoginForm(loginBloc: _loginBloc),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
