import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/cubits/calendar_type_view/calendar_type_view_cubit.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/services/push_notification_service.dart';
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
              const _NotificationsSettingsItem(),
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

/// Uključivanje i isključivanje push notifikacija na ovom uređaju.
class _NotificationsSettingsItem extends StatefulWidget {
  const _NotificationsSettingsItem();

  @override
  State<_NotificationsSettingsItem> createState() =>
      _NotificationsSettingsItemState();
}

class _NotificationsSettingsItemState extends State<_NotificationsSettingsItem>
    with WidgetsBindingObserver {
  final PushNotificationService _pushNotificationService =
      getIt<PushNotificationService>();

  bool _isEnabled = true;
  bool _isBlockedBySystem = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Korisnik se možda vraća iz podešavanja telefona.
    if (state == AppLifecycleState.resumed) {
      unawaited(_onReturnedToApp());
    }
  }

  Future<void> _loadState() async {
    final isEnabled = await _pushNotificationService.isEnabled();
    final isBlockedBySystem =
        await _pushNotificationService.isBlockedBySystem();
    if (!mounted) return;

    setState(() {
      _isEnabled = isEnabled;
      _isBlockedBySystem = isBlockedBySystem;
      _isLoading = false;
    });
  }

  Future<void> _onReturnedToApp() async {
    final wasBlocked = _isBlockedBySystem;
    await _loadState();

    // Notifikacije su upravo dozvoljene na telefonu, pa registrujemo token.
    if (wasBlocked && !_isBlockedBySystem && _isEnabled) {
      await _pushNotificationService.setEnabled(enabled: true);
    }
  }

  Future<void> _onChanged(bool enabled) async {
    setState(() {
      _isEnabled = enabled;
      _isLoading = true;
    });

    final isChanged = await _pushNotificationService.setEnabled(
      enabled: enabled,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (!isChanged) {
        // Telefon ne dozvoljava notifikacije.
        _isEnabled = false;
        _isBlockedBySystem = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSystemWarning = _isBlockedBySystem && !_isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.amber500,
                  size: 22,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Notifikacije',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _isEnabled && !_isBlockedBySystem,
                  activeTrackColor: AppColors.amber500,
                  onChanged: _isLoading ? null : _onChanged,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                showSystemWarning
                    ? 'Notifikacije su isključene u podešavanjima telefona.'
                    : 'Obavještenja o novim, izmijenjenim i otkazanim terminima.',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      showSystemWarning ? AppColors.red600 : AppColors.slate500,
                ),
              ),
            ),
            if (showSystemWarning)
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: TextButton(
                  onPressed:
                      () => AppSettings.openAppSettings(
                        type: AppSettingsType.notification,
                      ),
                  child: const Text('Otvori podešavanja'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
