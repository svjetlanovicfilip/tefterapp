import 'package:calendar_view/calendar_view.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../../../common/constants/routes.dart';
import '../../../../common/di/di_container.dart';
import '../../../../common/extensions/context_extension.dart';
import '../../../../config/style/colors.dart';
import '../../../service/data/models/service_type.dart';
import '../../../service/domain/bloc/service_bloc.dart';
import '../../../settings/data/client.dart';
import '../../../settings/domain/bloc/clients_bloc.dart';
import '../../data/models/slot.dart';
import '../../domain/bloc/slot_bloc.dart';
import '../../domain/utils/utils.dart';
import '../screens/book_appointment_screen.dart';

class CalendarDayView extends StatelessWidget {
  const CalendarDayView({required this.dayViewKey, super.key});

  final GlobalKey<DayViewState> dayViewKey;

  SlotBloc get _slotBloc => getIt<SlotBloc>();

  List<ServiceType> get _services => getIt<ServiceBloc>().state.services;
  List<Client> get _clients => getIt<ClientsBloc>().clients;

  @override
  Widget build(BuildContext context) {
    return DayView<Slot>(
      key: dayViewKey,
      initialDay: dayViewKey.currentState?.currentDate ?? DateTime.now(),
      controller: CalendarControllerProvider.of<Slot>(context).controller,
      startHour: 5,
      scrollPhysics: const ClampingScrollPhysics(),
      showHalfHours: true,
      heightPerMinute: 2,
      timeLineWidth: 80,
      verticalLineOffset: 0,
      dateStringBuilder:
          (date, {secondaryDate}) =>
              '${formatWeekday(date.weekday - 1)} ${date.day}.${date.month}.${date.year}',
      halfHourIndicatorSettings: const HourIndicatorSettings(
        dashSpaceWidth: 8,
        color: AppColors.slate300,
        height: 2,
        lineStyle: LineStyle.dashed,
      ),
      backgroundColor: AppColors.slate50,
      headerStyle: HeaderStyle(
        decoration: const BoxDecoration(color: AppColors.white),
        headerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        headerTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.slate800,
        ),
      ),
      showVerticalLine: false,
      hourIndicatorSettings: const HourIndicatorSettings(
        color: AppColors.slate300,
        height: 2,
      ),
      liveTimeIndicatorSettings: const LiveTimeIndicatorSettings(height: 2),
      timeLineBuilder: (date) {
        return Transform.translate(
          offset: const Offset(0, -7.5),
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              '${date.hour < 10 ? '0${date.hour}' : date.hour}:${date.minute == 0 ? '00' : date.minute}',
              style: const TextStyle(color: AppColors.slate500),
            ),
          ),
        );
      },

      eventTileBuilder: (date, events, boundary, startDuration, endDuration) {
        var isEventLessThan15Minutes = false;
        var canFitHeightForTime = false;
        var canFitHeightForNote = false;

        final clientId = events.first.event?.clientId;
        final client = _clients.firstWhereOrNull(
          (client) => client.id == clientId,
        );

        final services = events.first.event?.serviceIds
            .map(
              (id) => _services.firstWhereOrNull((service) => service.id == id),
            )
            .map((service) => service?.title)
            .join(', ');

        final title =
            client?.name ?? events.first.event?.clientName ?? services ?? '';
        final timeRange = formatDateRange(startDuration, endDuration);
        final note = events.first.event?.title;
        final color = events.first.event?.color;

        var titleStyle = const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        );
        const timeStyle = TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        );
        const noteStyle = TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        );

        // Layout constants used both for rendering and measurement
        const double horizontalPadding = 8;
        const double verticalPadding = 4;
        const double verticalSpacing = 4;

        final duration = endDuration.difference(startDuration).inMinutes;

        final noteHeight = textSize(note ?? '', noteStyle).height;

        // Available sizes inside the tile (content box)
        final eventHeight = boundary.shortestSide - verticalPadding;

        final titleHeight = textSize(title, titleStyle).height;

        if (duration <= 20 && duration >= 15) {
          final contentHeight = eventHeight - titleHeight;
          if (contentHeight > 5) {
            titleStyle = titleStyle.copyWith(fontSize: 12);
          }
        } else if (duration < 15) {
          isEventLessThan15Minutes = true;
        } else {
          final timeHeight = textSize(timeRange, timeStyle).height;

          // Check vertical fit for time: it must fit under title (with spacing)
          canFitHeightForTime = eventHeight > (titleHeight + timeHeight + 10);

          if (note != null && note.isNotEmpty && duration >= 60) {
            canFitHeightForNote =
                eventHeight >
                (titleHeight +
                    verticalSpacing * 2 +
                    timeHeight +
                    noteHeight +
                    10);
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Color(int.parse(color!)),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.symmetric(vertical: 2).copyWith(right: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isEventLessThan15Minutes) ...[
                Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
                if (canFitHeightForTime) ...[
                  const SizedBox(height: verticalSpacing),
                  Text(timeRange, maxLines: 1, style: timeStyle),
                ],
                if (canFitHeightForNote && note != null && note.isNotEmpty) ...[
                  const SizedBox(height: verticalSpacing),
                  Text(
                    note,
                    maxLines: 2,
                    style: noteStyle,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ],
              ],
            ],
          ),
        );
      },

      onEventTap: (events, date) {
        final event = events.first;
        final eventSlot = event.event as Slot;

        context.pushNamed(
          Routes.bookAppointment,
          arguments: BookAppointmentScreenArguments(slot: eventSlot),
        );
      },

      onPageChange: (date, page) {
        _slotBloc.add(DisplayedDateChanged(date: date));
      },
      onDateTap: (date) {
        // generateTestData();
        if (date.isBefore(DateTime.now())) {
          return;
        }

        context.pushNamed(
          Routes.bookAppointment,
          arguments: BookAppointmentScreenArguments(
            selectedDate: date,
            selectedStart: date,
          ),
        );
      },
      onHeaderTitleTap: (date) async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          currentDate: date,
          confirmText: 'Potvrdi',
          cancelText: 'Odustani',
          initialDate: date,
          helpText: 'Odaberite datum',
        );
        if (picked == null) return;
        await dayViewKey.currentState?.animateToDate(
          picked,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
    );
  }
}
