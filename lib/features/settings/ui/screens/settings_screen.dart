import 'package:flutter/material.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/cubits/calendar_type_view/calendar_type_view_cubit.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../config/style/colors.dart';
import '../../../authentication/domain/bloc/authentication_bloc.dart';
import '../../../calendar/domain/bloc/slot_bloc.dart';
import '../../../login/data/models/user_role.dart';
import '../../../service/domain/bloc/service_bloc.dart';
import '../../../users/domain/bloc/users_bloc.dart';
import '../../domain/bloc/clients_bloc.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: Text('Vaša podešavanja')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            spacing: 12,
            children: [
              if (appState.currentUser?.role == UserRole.orgOwner)
                _SettingsMenuItem(
                  label: 'Upravljanje zaposlenima',
                  icon: Icons.group_outlined,
                  onTap: () {
                    context.pushNamed(Routes.employeesScreen);
                  },
                ),
              _SettingsMenuItem(
                label: 'Klijenti',
                icon: Icons.person_outline,
                onTap: () {
                  context.pushNamed(Routes.clientsScreen);
                },
              ),
              if (appState.currentUser?.role == UserRole.orgOwner)
                _SettingsMenuItem(
                  label: 'Cjenovnik',
                  icon: Icons.local_offer_outlined,
                  onTap: () {
                    context.pushNamed(Routes.serviceListScreen);
                  },
                ),
              if (appState.currentUser?.role == UserRole.orgOwner)
                _SettingsMenuItem(
                  label: 'Mjesečni izvještaj',
                  icon: Icons.calendar_month_outlined,
                  onTap: () {
                    context.pushNamed(Routes.employeeReport);
                  },
                ),
              _SettingsMenuItem(
                label: 'Odjavite se',
                icon: Icons.lock_outline,
                isDestructive: true,
                onTap: () async {
                  await showLogoutDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showLogoutDialog(BuildContext context) async {
  void logout() {
    getIt<AuthenticationBloc>().add(AuthenticationLogoutRequested());
    getIt<UsersBloc>().clearState();
    appState.clearState();
    getIt<SlotBloc>().clearState();
    getIt<ServiceBloc>().clearState();
    getIt<ClientsBloc>().clearState();
    getIt<CalendarTypeViewCubit>().clear();
    context.pushNamedAndRemoveUntil(Routes.login);
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          'Odjava!',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: Colors.black),
        ),
        content: Text(
          'Da li ste sigurni da želite da se odjavite?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.black),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('Odustani'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: logout,
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(AppColors.red600),
                ),
                child: const Text('Odjavi se'),
              ),
            ],
          ),
        ],
      );
    },
  );

  return result ?? false;
}

class _SettingsMenuItem extends StatelessWidget {
  const _SettingsMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Ako je true -> crven tekst, ikonica i chevron (za "Odjavite se")
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final accentColor = isDestructive ? AppColors.red600 : AppColors.amber500;

    final trailingColor = isDestructive ? AppColors.red600 : AppColors.amber500;
    final textColor = isDestructive ? AppColors.red600 : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.white,
          ),
          child: Row(
            children: [
              Icon(icon, color: accentColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: trailingColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
