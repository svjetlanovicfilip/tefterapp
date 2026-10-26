import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../common/di/di_container.dart';
import '../../../../config/style/colors.dart';
import '../../../login/data/models/user_model.dart';
import '../../domain/bloc/slot_bloc.dart';
import '../../domain/utils/utils.dart';
import 'employees_grid_with_events.dart';

class CalendarTefterView extends StatefulWidget {
  const CalendarTefterView({required this.employees, super.key});

  final List<UserModel> employees;

  @override
  State<CalendarTefterView> createState() => CalendarTefterViewState();
}

class CalendarTefterViewState extends State<CalendarTefterView> {
  final double _timeLineWidth = 80;
  final double _rowHeight = 90;
  final int _startHour = 5;
  final int _endHour = 24;
  final ScrollController _hBodyController = ScrollController();
  final ScrollController _hHeaderController = ScrollController();
  final ScrollController _vController = ScrollController();
  DateTime currentDate = DateTime.now();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    getIt<SlotBloc>().add(DisplayedDateChanged(date: currentDate));
  }

  @override
  void dispose() {
    _hBodyController.dispose();
    _hHeaderController.dispose();
    _vController.dispose();
    super.dispose();
  }

  String _initials(String name, String? surname) {
    final n = name.isNotEmpty ? name[0] : '';
    final s = (surname != null && surname.isNotEmpty) ? surname[0] : '';
    return (n + s).toUpperCase();
  }

  void _syncHeaderFromBody() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_hHeaderController.hasClients) {
      _hHeaderController.jumpTo(_hBodyController.offset);
    }
    _isSyncing = false;
  }

  void _syncBodyFromHeader() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_hBodyController.hasClients) {
      _hBodyController.jumpTo(_hHeaderController.offset);
    }
    _isSyncing = false;
  }

  @override
  Widget build(BuildContext context) {
    // Sync header <-> body horizontal scroll
    _hBodyController.removeListener(_syncHeaderFromBody);
    _hHeaderController.removeListener(_syncBodyFromHeader);
    _hBodyController.addListener(_syncHeaderFromBody);
    _hHeaderController.addListener(_syncBodyFromHeader);

    final employees = widget.employees;
    final rowsCount = (_endHour - _startHour) * 2; // 30-min rows
    // Responsive column width: fill available space if few employees, otherwise scroll.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final headerAvailableWidth = (screenWidth - _timeLineWidth).clamp(
      0,
      double.infinity,
    );
    const double minColWidth = 80;
    final colWidth =
        (employees.isEmpty
                ? 0
                : (headerAvailableWidth / employees.length).floorToDouble() <
                    minColWidth
                ? minColWidth
                : (headerAvailableWidth / employees.length).floorToDouble())
            .toDouble();
    final tableWidth =
        (employees.isEmpty ? 0 : employees.length * colWidth).toDouble();
    return Column(
      children: [
        // Date navigation header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 30),
                onPressed: () {
                  setState(() {
                    currentDate = currentDate.subtract(const Duration(days: 1));
                  });
                  getIt<SlotBloc>().add(
                    DisplayedDateChanged(date: currentDate),
                  );
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      currentDate: currentDate,
                      confirmText: 'Potvrdi',
                      cancelText: 'Odustani',
                      initialDate: currentDate,
                      helpText: 'Odaberite datum',
                    );
                    if (picked == null) return;
                    setState(() => currentDate = picked);
                    getIt<SlotBloc>().add(
                      DisplayedDateChanged(date: currentDate),
                    );
                  },
                  child: Center(
                    child: Text(
                      '${formatWeekday(currentDate.weekday - 1)} ${currentDate.day}.${currentDate.month}.${currentDate.year}',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate800,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 30),
                onPressed: () {
                  setState(() {
                    currentDate = currentDate.add(const Duration(days: 1));
                  });
                  getIt<SlotBloc>().add(
                    DisplayedDateChanged(date: currentDate),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 2, color: AppColors.slate200),
        // Header row with initials (pinned vertically, scrolls horizontally with body)
        SizedBox(
          height: 48,
          child: Row(
            children: [
              // Fill left corner under header with white to avoid dark rectangle
              Container(width: _timeLineWidth, color: AppColors.slate50),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  controller: _hHeaderController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final u in employees)
                        Container(
                          width: colWidth,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.slate50,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Builder(
                            builder: (context) {
                              final username = (u.username ?? '').trim();
                              final hasUsername = username.isNotEmpty;
                              final label =
                                  hasUsername
                                      ? username
                                      : _initials(u.name ?? '', u.surname);
                              final fontSize =
                                  (hasUsername ? 12 : 16).toDouble();
                              return Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.slate900,
                                  fontWeight: FontWeight.w700,
                                  fontSize: fontSize,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.slate200),
        // One vertical scroll for both timeline and body
        Expanded(
          child: SingleChildScrollView(
            controller: _vController,
            physics: const ClampingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline column (pinned horizontally)
                SizedBox(
                  width: _timeLineWidth,
                  child: Column(
                    children: List.generate(rowsCount, (idx) {
                      final hour = _startHour + (idx ~/ 2);
                      final minute = (idx % 2) * 30;
                      return SizedBox(
                        height: _rowHeight / 2,
                        child: Container(
                          alignment: Alignment.topLeft,
                          padding: const EdgeInsets.only(left: 16, top: 6),
                          decoration: const BoxDecoration(
                            color: AppColors.slate50,
                            border: Border(
                              top: BorderSide(color: AppColors.slate500),
                              right: BorderSide(color: AppColors.slate500),
                            ),
                          ),
                          child: Text(
                            '${hour.toString().padLeft(2, '0')}:${minute == 0 ? '00' : '30'}',
                            style: const TextStyle(color: AppColors.slate500),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Body with single horizontal scroll synced with header
                Expanded(
                  child: Scrollbar(
                    controller: _hBodyController,
                    child: SingleChildScrollView(
                      controller: _hBodyController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: SizedBox(
                        width: tableWidth,
                        child: BlocBuilder<SlotBloc, SlotState>(
                          bloc: getIt<SlotBloc>(),
                          buildWhen:
                              (previous, current) => current is SlotsLoaded,
                          builder: (context, slotState) {
                            final slots =
                                slotState is SlotsLoaded
                                    ? slotState.slots
                                    : getIt<SlotBloc>().slots;
                            return EmployeesGridWithEvents(
                              employeesCount: employees.length,
                              employees: employees,
                              colWidth: colWidth,
                              rowHeight: _rowHeight / 2,
                              rowsCount: rowsCount,
                              startHour: _startHour,
                              slots: slots,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
