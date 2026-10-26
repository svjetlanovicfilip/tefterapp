import 'package:calendar_view/calendar_view.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/cubits/calendar_type_view/calendar_type_view_cubit.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../common/widgets/logo_widget.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../../../common/widgets/toggle_button_group.dart';
import '../../../../config/style/colors.dart';
import '../../../login/data/models/user_model.dart';
import '../../../users/domain/bloc/users_bloc.dart';
import '../../data/models/calendar_type_enum.dart';
import '../../data/models/slot.dart';
import '../../domain/bloc/slot_bloc.dart';
import '../modals/employee_dropdown_menu.dart';
import '../widgets/calendar_day_view.dart';
import '../widgets/calendar_tefter_view.dart';
import '../widgets/calendar_week_view.dart';
import 'book_appointment_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CalendarTypeViewCubit get _calendarTypeViewCubit =>
      getIt<CalendarTypeViewCubit>();

  final SlotBloc _slotBloc = getIt<SlotBloc>();
  final UsersBloc _usersBloc = getIt<UsersBloc>();
  final _dayViewKey = GlobalKey<DayViewState>();
  final _weekViewKey = GlobalKey<WeekViewState>();
  final _filterIconKey = GlobalKey();

  /// Termini koji su trenutno u EventController-u, po id-u.
  final _displayedSlots = <String, Slot>{};

  @override
  void initState() {
    super.initState();

    // Defer controller updates until after the first frame to avoid
    // setState/markNeedsBuild during build of ancestor widgets.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller =
          CalendarControllerProvider.of<Slot>(context).controller
            // kontroler živi duže od ekrana, pa mogu ostati termini prethodne sesije
            ..removeWhere((_) => true);
      final selectedUserId = appState.currentSelectedUserId;
      _syncCalendarEvents(
        controller,
        _slotBloc.slots
            .where((slot) => slot.employeeIds.contains(selectedUserId))
            .toList(),
      );
    });

  }

  /// Mijenja samo termine koji su dodani, izmijenjeni ili obrisani, umjesto
  /// da na svaku promjenu briše i ponovo dodaje sve.
  void _syncCalendarEvents(EventController<Slot> controller, List<Slot> slots) {
    final newSlots = {
      for (final slot in slots)
        if (slot.id != null) slot.id!: slot,
    };

    final removedIds =
        _displayedSlots.keys
            .where((id) => _displayedSlots[id] != newSlots[id])
            .toSet();
    final addedSlots =
        newSlots.values
            .where((slot) => _displayedSlots[slot.id] != slot)
            .toList();

    if (removedIds.isNotEmpty) {
      controller.removeWhere((event) => removedIds.contains(event.event?.id));
    }
    if (addedSlots.isNotEmpty) {
      controller.addAll(
        addedSlots.map((slot) => slot.toCalendarEventData()).toList(),
      );
    }

    _displayedSlots
      ..clear()
      ..addAll(newSlots);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SlotBloc, SlotState>(
      bloc: _slotBloc,
      listenWhen: (previous, current) => previous != current,
      // Termini idu kroz listener u EventController, pa se ekran builda
      // samo kad se uđe u loading ili izađe iz njega.
      buildWhen:
          (previous, current) =>
              previous is SlotStateLoading || current is SlotStateLoading,
      listener: (context, state) {
        if (state is ErrorLoadingSlots) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
          return;
        } else if (state is SlotsLoaded) {
          _syncCalendarEvents(
            CalendarControllerProvider.of<Slot>(context).controller,
            state.selectedUserSlots,
          );
        }
      },
      builder: (context, state) {
        if (state is SlotStateLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.amber500),
            ),
            backgroundColor: AppColors.white,
          );
        }

        return Scaffold(
          appBar: CustomAppBar(
            automaticallyImplyLeading: false,
            title: Row(
              spacing: 8,
              children: [
                const LogoWidget(),
                Expanded(
                  child: Text(
                    appState.userOrganization?.title ?? 'Tefter',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              BlocBuilder<UsersBloc, UsersState>(
                bloc: _usersBloc,
                buildWhen:
                    (previous, current) =>
                        current is UsersFetchingSuccess ||
                        current is UsersFetching,
                builder: (context, state) {
                  if (state is UsersFetchingSuccess && state.users.isNotEmpty) {
                    return GestureDetector(
                      onTap:
                          () => showEmployeeFilterMenu(
                            context: context,

                            filterIconKey: _filterIconKey,
                            onSelected: (userId) {
                              _usersBloc.add(SelectUser(userId: userId));
                              _slotBloc.add(UserChanged(userId: userId));
                            },
                            users: state.users,
                          ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: const BoxDecoration(
                          color: AppColors.slate700,
                          shape: BoxShape.circle,
                        ),
                        key: _filterIconKey,
                        child: const Icon(
                          Icons.filter_list,
                          size: 24,
                          color: AppColors.white,
                        ),
                      ),
                    );
                  }

                  return _buildEmptyWidget();
                },
              ),
              GestureDetector(
                onTap: () => context.pushNamed(Routes.settings),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.slate700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 24,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.slate900,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton:
              BlocBuilder<CalendarTypeViewCubit, CalendarType>(
                bloc: _calendarTypeViewCubit,
                builder: (context, cubitState) {
                  return PrimaryButton(
                    icon: Icons.add,
                    onTap: () {
                      late DateTime currentDate;

                      if (cubitState == CalendarType.day) {
                        currentDate =
                            _dayViewKey.currentState?.currentDate ??
                            DateTime.now();
                      } else {
                        currentDate =
                            _weekViewKey.currentState?.currentDate ??
                            DateTime.now();
                      }

                      currentDate =
                          currentDate.isBefore(DateTime.now())
                              ? DateTime.now()
                              : currentDate;

                      context.pushNamed(
                        Routes.bookAppointment,
                        arguments: BookAppointmentScreenArguments(
                          selectedDate: currentDate,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(30),
                  );
                },
              ),
          body: SafeArea(
            child: CustomScrollView(
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: BlocBuilder<CalendarTypeViewCubit, CalendarType>(
                      bloc: _calendarTypeViewCubit,
                      builder: (context, calendarCubitState) {
                        return ToggleButtonGroup(
                          onSelectionChanged: (value) {
                            _calendarTypeViewCubit.toggleCalendarType(value);
                            // Novi prikaz uvijek kreće od današnjeg dana.
                            _slotBloc.add(
                              DisplayedDateChanged(date: DateTime.now()),
                            );
                          },
                          selectedCalendarType: calendarCubitState,
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                BlocBuilder<CalendarTypeViewCubit, CalendarType>(
                  bloc: _calendarTypeViewCubit,
                  builder: (context, cubitState) {
                    if (cubitState == CalendarType.tefter) {
                      return _buildEmptyWidget();
                    }

                    return BlocBuilder<UsersBloc, UsersState>(
                      bloc: _usersBloc,
                      buildWhen: (previous, current) => current is UserSelected,
                      builder: (context, userState) {
                        UserModel? selectedUser;
                        if (userState is UserSelected) {
                          selectedUser = userState.user;
                        } else {
                          selectedUser =
                              appState.currentSelectedUserId != null
                                  ? _usersBloc.users.firstWhereOrNull(
                                    (user) =>
                                        user.id ==
                                        appState.currentSelectedUserId,
                                  )
                                  : null;
                        }

                        if (selectedUser != null) {
                          return SliverToBoxAdapter(
                            child: Center(
                              child: Text(
                                '${selectedUser.name ?? ''} ${selectedUser.surname ?? ''}',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          );
                        }

                        return _buildEmptyWidget();
                      },
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                BlocBuilder<CalendarTypeViewCubit, CalendarType>(
                  bloc: _calendarTypeViewCubit,
                  builder: (context, state) {
                    return SliverFillRemaining(
                      child:
                          state == CalendarType.day
                              ? CalendarDayView(dayViewKey: _dayViewKey)
                              : state == CalendarType.week
                              ? CalendarWeekView(weekViewKey: _weekViewKey)
                              : BlocBuilder<UsersBloc, UsersState>(
                                bloc: _usersBloc,
                                buildWhen:
                                    (previous, current) =>
                                        current is UsersFetchingSuccess ||
                                        current is UsersFetching,
                                builder: (context, userState) {
                                  return CalendarTefterView(
                                    employees:
                                        userState is UsersFetchingSuccess
                                            ? userState.users
                                            : getIt<UsersBloc>().users,
                                  );
                                },
                              ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyWidget() {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}
