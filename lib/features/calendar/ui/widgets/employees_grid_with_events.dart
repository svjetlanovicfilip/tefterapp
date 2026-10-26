import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../config/style/colors.dart';
import '../../../login/data/models/user_model.dart';
import '../../../service/domain/bloc/service_bloc.dart';
import '../../../settings/domain/bloc/clients_bloc.dart';
import '../../data/models/slot.dart';
import '../../domain/utils/utils.dart';
import '../screens/book_appointment_screen.dart';
import 'calendar_tefter_view.dart';

class EmployeesGridWithEvents extends StatelessWidget {
  const EmployeesGridWithEvents({
    required this.employeesCount,
    required this.employees,
    required this.colWidth,
    required this.rowHeight,
    required this.rowsCount,
    required this.startHour,
    required this.slots,
    super.key,
  });

  final int employeesCount;
  final List<UserModel> employees;
  final double colWidth;
  final double rowHeight;
  final int rowsCount;
  final int startHour;
  final List<Slot> slots;

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalHeight = rowsCount * rowHeight;
    final displayDate =
        context
            .findAncestorStateOfType<CalendarTefterViewState>()
            ?.currentDate ??
        DateTime.now();

    // px per minute
    final pxPerMinute = rowHeight / 30; // 30 min = rowHeight

    final userIdToColumn = <String, int>{};
    final users = employees;
    for (var i = 0; i < users.length; i++) {
      final u = users[i];
      if (u.id != null && u.id!.isNotEmpty) {
        userIdToColumn[u.id!] = i;
      }
    }

    return SizedBox(
      height: totalHeight,
      child: Stack(
        children: [
          // Grid underlay, also captures taps for creating new appointment
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final local = details.localPosition;
                final row = (local.dy / rowHeight).floor().clamp(
                  0,
                  rowsCount - 1,
                );
                // Compute selected start time for the tapped row (30-min granularity)
                final hour = startHour + (row ~/ 2);
                final minute = (row % 2) * 30;
                final selectedDateTime = DateTime(
                  displayDate.year,
                  displayDate.month,
                  displayDate.day,
                  hour,
                  minute,
                );
                // Disallow creating new appointments in the past (consistent with day/week views)
                if (selectedDateTime.isBefore(DateTime.now())) {
                  return;
                }
                // Determine clicked column and pass its user to BookAppointment
                if (employeesCount > 0 && colWidth > 0) {
                  final col = (local.dx / colWidth).floor().clamp(
                    0,
                    employeesCount - 1,
                  );
                  final tappedUserId = employees[col].id;
                  // Prepare args including preselected employee if present
                  final args = BookAppointmentScreenArguments(
                    selectedDate: selectedDateTime,
                    selectedStart: selectedDateTime,
                    preselectedEmployeeIds:
                        (tappedUserId != null && tappedUserId.isNotEmpty)
                            ? [tappedUserId]
                            : null,
                  );

                  context.pushNamed(Routes.bookAppointment, arguments: args);
                  return;
                }

                context.pushNamed(
                  Routes.bookAppointment,
                  arguments: BookAppointmentScreenArguments(
                    selectedDate: selectedDateTime,
                    selectedStart: selectedDateTime,
                  ),
                );
              },
              child: Column(children: buildGridRows()),
            ),
          ),
          // Events overlay (single user for now)
          ...buildEventWidgets(
            userIdToColumn,
            displayDate,
            pxPerMinute,
            context,
          ),
        ],
      ),
    );
  }

  List<Widget> buildGridRows() {
    return List.generate(rowsCount, (row) {
      return SizedBox(
        height: rowHeight,
        child: Row(
          children: [
            for (var i = 0; i < employeesCount; i++)
              Container(
                width: colWidth,
                decoration: const BoxDecoration(
                  color: AppColors.slate50,
                  border: Border(
                    top: BorderSide(color: AppColors.slate500),
                    right: BorderSide(color: AppColors.slate500),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  List<Widget> buildEventWidgets(
    Map<String, int> userIdToColumn,
    DateTime displayDate,
    double pxPerMinute,
    BuildContext context,
  ) {
    if (userIdToColumn.isEmpty) return const [];

    return slots
        .where((s) => DateUtils.isSameDay(s.startDateTime, displayDate))
        .map((s) {
          final start = s.startDateTime;
          final end =
              s.endDateTime ?? s.startDateTime.add(const Duration(minutes: 30));
          final startMinutes = ((start.hour - startHour) * 60) + start.minute;
          final durationMinutes = end
              .difference(start)
              .inMinutes
              .clamp(15, 24 * 60);
          const double inset = 2;
          final rawTop = startMinutes * pxPerMinute;
          final rawHeight = durationMinutes * pxPerMinute;
          final top = rawTop + inset;
          final double heightRaw = rawHeight - (inset * 2);
          final double height = heightRaw < 4 ? 4 : heightRaw;
          var title = s.title ?? '';
          final fontSize =
              (durationMinutes <= 15 ? durationMinutes - 4 - 2 : 14)
                  .toDouble(); // 4px padding

          // resolve client name

          final client = getIt<ClientsBloc>().clients.firstWhereOrNull(
            (c) => c.id == s.clientId,
          );
          if (client != null && client.name.isNotEmpty) {
            title = client.name;
          } else if ((s.clientName ?? '').isNotEmpty) {
            title = s.clientName!;
          } else {
            title = s.serviceIds
                .map((id) => getIt<ServiceBloc>().getServiceById(id)?.title)
                .join(', ');
          }
          final showText = height >= 18;
          // Create a tile per employee that belongs to this slot and is visible
          final tiles = <Widget>[];
          for (final userId in s.employeeIds) {
            final colIndex = userIdToColumn[userId];
            if (colIndex == null) continue;
            final left = (colIndex * colWidth) + inset;
            final width = (colWidth - 1) - (inset * 2);
            final bg = colorForColumn(colIndex);
            const textColor = AppColors.white;
            tiles.add(
              Positioned(
                left: left,
                top: top,
                width: width,
                height: height,
                child: InkWell(
                  onTap: () {
                    context.pushNamed(
                      Routes.bookAppointment,
                      arguments: BookAppointmentScreenArguments(slot: s),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child:
                        !showText
                            ? const SizedBox.shrink()
                            : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: fontSize,
                                  ),
                                ),
                              ],
                            ),
                  ),
                ),
              ),
            );
          }
          return Stack(children: tiles);
        })
        .toList();
  }

  Color colorForColumn(int columnIndex) {
    final palette = buildDeterministicPalette();
    if (palette.isEmpty) return Colors.blue;
    return palette[columnIndex % palette.length];
  }
}
