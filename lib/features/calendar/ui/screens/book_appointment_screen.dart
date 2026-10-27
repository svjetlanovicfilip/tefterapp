import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../common/constants/routes.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../common/modals/delete_dialog.dart';
import '../../../../common/widgets/custom_app_bar.dart';
import '../../../../common/widgets/pickers/custom_time_picker_dialog.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../../../config/style/colors.dart';
import '../../../employees/domain/cubit/employees_picker_cubit.dart';
import '../../../service/domain/bloc/service_bloc.dart';
import '../../../settings/domain/bloc/clients_bloc.dart';
import '../../../settings/domain/cubit/client_picker_cubit.dart';
import '../../../settings/ui/screens/add_edit_client_screen.dart';
import '../../data/models/slot.dart';
import '../../domain/bloc/slot_bloc.dart';
import '../../domain/utils/utils.dart';
import '../widgets/label.dart';
import '../widgets/selected_client_list.dart';
import '../widgets/selected_employees_list.dart';
import '../widgets/selected_services_list.dart';
import '../widgets/time_input_field.dart';

class BookAppointmentScreenArguments {
  const BookAppointmentScreenArguments({
    this.slot,
    this.selectedDate,
    this.selectedStart,
    this.preselectedEmployeeIds,
  });

  final Slot? slot;
  final DateTime? selectedDate;
  final DateTime? selectedStart;
  final List<String>? preselectedEmployeeIds;
}

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({this.arguments, super.key});

  final BookAppointmentScreenArguments? arguments;

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  late TextEditingController titleController;

  late EmployeesPickerCubit _employeesPickerCubit;
  late ClientPickerCubit _clientPickerCubit;
  late ServiceBloc _serviceBloc;
  late ClientsBloc _clientsBloc;
  BookAppointmentScreenArguments? args;

  late DateTime selectedDate;
  DateTime? selectedStart;
  DateTime? selectedEnd;
  DateTime initialDate = DateTime.now();
  bool isEditing = false;
  bool isFormSubmitted = false;

  bool isTimeRangeValid = true;
  bool anyEmployeeSelected = true;
  bool anyServiceSelected = true;

  bool isSlotInPast = false;

  /// Čeka se SlotSaved ili greška iz SlotBloc-a; ekran se zatvara tek kad je
  /// termin sačuvan, da korisnik ne izgubi unos ako snimanje ne uspije.
  bool _isSaving = false;

  late final String selectedColor;

  @override
  void initState() {
    super.initState();
    _serviceBloc = getIt<ServiceBloc>();
    _clientsBloc = getIt<ClientsBloc>();
    _clientPickerCubit = getIt<ClientPickerCubit>();
    args = widget.arguments;
    isEditing = args?.slot != null;
    final random = Random();
    final colors = List<Color>.from(AppColors.possibleEventColors)
      ..shuffle(random);
    final length = colors.length;
    final eventIndex = random.nextInt(length);
    selectedColor = colors[eventIndex % colors.length].toARGB32().toString();
    isSlotInPast = args?.slot?.startDateTime.isBefore(DateTime.now()) ?? false;
    selectedStart = args?.selectedStart ?? args?.slot?.startDateTime;
    selectedEnd = args?.slot?.endDateTime;
    selectedDate =
        args?.slot?.startDateTime ?? args?.selectedDate ?? DateTime.now();
    titleController = TextEditingController(text: args?.slot?.title);

    _employeesPickerCubit = getIt<EmployeesPickerCubit>();

    if (args?.slot?.employeeIds != null && args!.slot!.employeeIds.isNotEmpty) {
      for (final employeeId in args!.slot!.employeeIds) {
        _employeesPickerCubit.pickEmployee(
          employeeId: employeeId,
          isPicked: true,
        );
      }
    } else if ((args?.preselectedEmployeeIds ?? []).isNotEmpty) {
      for (final employeeId in args!.preselectedEmployeeIds!) {
        if (employeeId.isNotEmpty) {
          _employeesPickerCubit.pickEmployee(
            employeeId: employeeId,
            isPicked: true,
          );
        }
      }
    } else {
      final fallback = appState.currentSelectedUserId ?? '';
      if (fallback.isNotEmpty) {
        _employeesPickerCubit.pickEmployee(
          employeeId: fallback,
          isPicked: true,
        );
      }
    }
    _serviceBloc.add(AttachService(serviceIds: args?.slot?.serviceIds ?? []));
    if (args?.slot?.clientId != null) {
      final selectedClient = _clientsBloc.clients.firstWhereOrNull(
        (client) => client.id == args?.slot?.clientId,
      );
      if (selectedClient != null) {
        _clientPickerCubit.pickClient(client: selectedClient);
      } else {
        _clientPickerCubit.unpickClient();
      }
    } else {
      _clientPickerCubit.unpickClient();
    }
  }

  Future<TimeOfDay?> pickTime(TimeOfDay initialTime) {
    return showCustomTimePicker(context: context, initialTime: initialTime);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MultiBlocListener(
      listeners: [
        BlocListener<EmployeesPickerCubit, Map<String, bool>>(
          bloc: _employeesPickerCubit,
          listener: (context, state) {
            setState(() {
              anyEmployeeSelected = state.values.any((value) => value);
            });
          },
        ),
        BlocListener<SlotBloc, SlotState>(
          bloc: getIt<SlotBloc>(),
          listenWhen:
              (previous, current) =>
                  _isSaving &&
                  (current is SlotSaved || current is ErrorLoadingSlots),
          listener: (context, state) {
            setState(() => _isSaving = false);

            if (state is SlotSaved) {
              Navigator.of(context).pop();
            } else if (state is ErrorLoadingSlots) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
            }
          },
        ),
        BlocListener<ServiceBloc, ServiceState>(
          bloc: _serviceBloc,
          listener: (context, state) {
            if (isFormSubmitted) {
              setState(() {
                anyServiceSelected = state.selectedServices.isNotEmpty;
              });
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: CustomAppBar(
          title: Text(isEditing ? 'Izmijenite termin' : 'Dodajte termin'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSlotInPast) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amber300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.slate600,
                        ),
                        Expanded(
                          child: Column(
                            spacing: 4,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Upozorenje',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.slate800,
                                ),
                              ),
                              Text(
                                'Termin je već prošao. Možete izmijeniti samo detalje usluge.',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.slate600,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                SelectedEmployeesList(
                  anyEmployeeSelected: anyEmployeeSelected,
                  disabled: isSlotInPast,
                ),
                const SizedBox(height: 20),
                const Label(title: 'Datum'),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: !isSlotInPast ? _pickDate : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.slate200,
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          color: AppColors.slate800,
                        ),
                        Text(
                          formatDateLong(selectedDate),
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  spacing: 16,
                  children: [
                    Expanded(
                      child: TimeInputField(
                        isTimeRangeValid: isTimeRangeValid,
                        label: 'Početak',
                        selectedDateTime: selectedStart,
                        onTimeSelected: _onStartTimeSelected,
                        disabled: isSlotInPast,
                      ),
                    ),
                    Expanded(
                      child: TimeInputField(
                        isTimeRangeValid: isTimeRangeValid,
                        label: 'Kraj',
                        selectedDateTime: selectedEnd,
                        onTimeSelected: _onEndTimeSelected,
                        disabled: isSlotInPast,
                      ),
                    ),
                  ],
                ),

                if (!isTimeRangeValid) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Vrijeme nije pravilno uneseno. Molimo vas da provjerite početak i kraj termina.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.red600,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                const Label(title: 'Klijent'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        child: SelectedClientList(disabled: isSlotInPast),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap:
                          isSlotInPast
                              ? null
                              : () {
                                context.pushNamed(
                                  Routes.addEditClientsScreen,
                                  arguments: const AddEditClientScreenArgs(
                                    isClientAddedFromAppointment: true,
                                  ),
                                );
                              },
                      child: Icon(
                        Icons.person_add,
                        size: 34,
                        color:
                            isSlotInPast
                                ? AppColors.slate400
                                : AppColors.amber500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Label(title: 'Usluga'),
                const SizedBox(height: 8),
                SelectedServicesList(
                  anyServiceSelected: anyServiceSelected,
                  disabled: isSlotInPast,
                ),
                const SizedBox(height: 20),
                const Label(title: 'Detalji usluge'),
                const SizedBox(height: 8),
                TextField(
                  controller: titleController,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Unesite detalje usluge...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.slate400,
                        width: 2,
                      ),
                    ),
                    fillColor: AppColors.slate200,
                    hintStyle: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.slate500,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  onTap: handleSubmit,
                  isLoading: _isSaving,
                  title: isSlotInPast ? 'Sačuvaj napomenu' : 'Potvrdi',
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.all(10),
                ),
                const SizedBox(height: 12),
                if (isEditing && !isSlotInPast)
                  PrimaryButton(
                    onTap:
                        () => showDeleteDialog(
                          context: context,
                          title: 'Izbrišite termin',
                          description:
                              'Da li ste sigurni da želite da izbrišete ovaj termin?',
                          onDelete: handleDelete,
                        ),
                    title: 'Izbrišite termin',
                    borderRadius: BorderRadius.circular(12),
                    backgroundColor: AppColors.red600,
                    padding: const EdgeInsets.all(10),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    _employeesPickerCubit.clear();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: initialDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      currentDate: selectedDate,
      confirmText: 'Potvrdi',
      cancelText: 'Odustani',
      initialDate: initialDate,
      helpText: 'Odaberi datum',
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        if (selectedStart != null) {
          selectedStart = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            selectedStart!.hour,
            selectedStart!.minute,
          );
        }
        if (selectedEnd != null) {
          selectedEnd = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            selectedEnd!.hour,
            selectedEnd!.minute,
          );
        }
      });
      _validateTimeRange();
    }
  }

  Future<void> _onStartTimeSelected() async {
    final timeOfDay = TimeOfDay.fromDateTime(selectedStart ?? DateTime.now());
    final picked = await pickTime(timeOfDay);
    if (picked == null) return;
    setState(() {
      selectedStart = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        picked.hour,
        picked.minute,
      );
    });
    _validateTimeRange();
  }

  Future<void> _onEndTimeSelected() async {
    final timeOfDay = TimeOfDay.fromDateTime(selectedEnd ?? DateTime.now());

    final picked = await pickTime(timeOfDay);

    if (picked == null) return;

    setState(() {
      selectedEnd = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        picked.hour,
        picked.minute,
      );
    });

    _validateTimeRange();
  }

  Future<void> handleSubmit() async {
    final title = titleController.text.trim();

    // Na prošlom terminu može se mijenjati samo napomena.
    if (isSlotInPast) {
      _saveNote(title);
      return;
    }

    setState(() {
      isFormSubmitted = true;
    });

    _validateTimeRange();

    final employeeIds =
        _employeesPickerCubit.state.keys
            .where((key) => _employeesPickerCubit.state[key] ?? false)
            .toList();

    final serviceIds =
        _serviceBloc.state.selectedServices.map((e) => e.id ?? '').toList();

    if (employeeIds.isEmpty || !anyEmployeeSelected) {
      setState(() {
        anyEmployeeSelected = false;
      });
    }

    if (serviceIds.isEmpty || !anyServiceSelected) {
      setState(() {
        anyServiceSelected = false;
      });
    }

    if (!isTimeRangeValid || !anyEmployeeSelected || !anyServiceSelected) {
      return;
    }

    final clientId = _clientPickerCubit.state?.id;
    final clientName = _clientPickerCubit.state?.name;

    final newSlot = Slot(
      id: args?.slot?.id,
      startDateTime: selectedStart ?? DateTime.now(),
      endDateTime: selectedEnd ?? DateTime.now(),
      title: title,
      color: args?.slot?.color ?? selectedColor,
      serviceIds: serviceIds,
      employeeIds: employeeIds,
      clientId: clientId,
      clientName: clientName,
    );

    final originalSlot = args?.slot;
    if (originalSlot != null && _isOnlyNoteChanged(originalSlot, newSlot)) {
      _saveNote(title);
      return;
    }

    setState(() => _isSaving = true);
    if (isEditing) {
      getIt<SlotBloc>().add(UpdateSlot(newSlot));
    } else {
      getIt<SlotBloc>().add(AddNewSlot(newSlot));
    }
  }

  void _saveNote(String note) {
    final slotId = args?.slot?.id;
    if (slotId == null) return;

    setState(() => _isSaving = true);
    getIt<SlotBloc>().add(UpdateSlotNote(slotId: slotId, note: note));
  }

  /// Ako su vrijeme, zaposleni, usluge i klijent isti, ne treba provjeravati
  /// preklapanje (koje bi moglo odbiti i samu izmjenu napomene).
  bool _isOnlyNoteChanged(Slot original, Slot updated) {
    const setEquality = SetEquality<String>();

    return original.startDateTime == updated.startDateTime &&
        original.endDateTime == updated.endDateTime &&
        original.clientId == updated.clientId &&
        setEquality.equals(
          original.employeeIds.toSet(),
          updated.employeeIds.toSet(),
        ) &&
        setEquality.equals(
          original.serviceIds.toSet(),
          updated.serviceIds.toSet(),
        );
  }

  void handleDelete() {
    getIt<SlotBloc>().add(DeleteSlot(args?.slot?.id ?? ''));
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  void _validateTimeRange() {
    if (!isFormSubmitted) return;

    if (selectedStart == null || selectedEnd == null) {
      setState(() {
        isTimeRangeValid = false;
      });
      return;
    } else if (selectedStart != null &&
        selectedStart!.isBefore(DateTime.now())) {
      setState(() {
        isTimeRangeValid = false;
      });
    } else if (selectedEnd != null &&
        selectedStart != null &&
        selectedStart!.isAfter(selectedEnd!)) {
      setState(() {
        isTimeRangeValid = false;
      });
    } else if (selectedEnd != null &&
        selectedStart != null &&
        selectedEnd!.isBefore(DateTime.now())) {
      setState(() {
        isTimeRangeValid = false;
      });
    } else if (selectedEnd != null &&
        selectedStart != null &&
        (selectedEnd!.isAtSameMomentAs(selectedStart!))) {
      setState(() {
        isTimeRangeValid = false;
      });
    } else {
      setState(() {
        isTimeRangeValid = true;
      });
    }
  }
}
