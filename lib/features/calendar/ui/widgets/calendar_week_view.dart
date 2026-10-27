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

class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({required this.weekViewKey, super.key});

  final GlobalKey<WeekViewState> weekViewKey;

  SlotBloc get _slotBloc => getIt<SlotBloc>();

  List<ServiceType> get _services => getIt<ServiceBloc>().state.services;
  List<Client> get _clients => getIt<ClientsBloc>().clients;

  @override
  Widget build(BuildContext context) {
    return WeekView<Slot>(
      initialDay: weekViewKey.currentState?.currentDate ?? DateTime.now(),
      scrollPhysics: const ClampingScrollPhysics(),
      key: weekViewKey,
      showHalfHours: true,
      heightPerMinute: 1.5,
      startHour: 5,
      timeLineWidth: 80,
      backgroundColor: AppColors.slate50,
      headerStringBuilder:
          (date, {secondaryDate}) =>
              '${date.day}.${date.month}.${date.year} - ${secondaryDate?.day}.${secondaryDate?.month}.${secondaryDate?.year}',
      weekDayBuilder: (weekDay) {
        final weekday = formatWeekday(weekDay.weekday - 1);

        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Text(
              weekday.substring(0, 3),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.slate800,
                fontSize: 12,
              ),
            ),
            Text(
              weekDay.day.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.slate800,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
      eventTileBuilder: (date, events, boundary, startDuration, endDuration) {
        var isEventLessThan15Minutes = false;
        var lines = 1;
        const double padding = 2;
        final clientId = events.first.event?.clientId;
        final client = _clients.firstWhereOrNull(
          (client) => client.id == clientId,
        );
        final title =
            client?.name ??
            events.first.event?.clientName ??
            events.first.event?.serviceIds
                .map(
                  (id) =>
                      _services.firstWhereOrNull((service) => service.id == id),
                )
                .map((service) => service?.title)
                .join(', ') ??
            '';
        final hasNote = (events.first.event?.title ?? '').isNotEmpty;
        var titleStyle = const TextStyle(color: AppColors.white, fontSize: 12);

        final titleHeight = textSize(title, titleStyle).height;

        final duration = endDuration.difference(startDuration);

        if (duration.inMinutes >= 15 && duration.inMinutes < 30) {
          final contentHeight = boundary.height - (padding * 2);

          if (contentHeight > titleHeight) {
            titleStyle = titleStyle.copyWith(fontSize: 10);
          } else {
            isEventLessThan15Minutes = true;
          }
        } else if (duration.inMinutes >= 30) {
          final contentHeight = boundary.height - (padding * 2);

          if (contentHeight >= titleHeight * 3) {
            lines = 3;
          } else if (contentHeight >= titleHeight * 2) {
            lines = 2;
          } else {
            lines = 1;
          }
        } else {
          isEventLessThan15Minutes = true;
        }

        return Container(
          decoration: BoxDecoration(
            color: events.first.event?.displayColor ?? AppColors.amber500,
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.symmetric(vertical: padding),
          padding: const EdgeInsets.all(padding),
          child:
              isEventLessThan15Minutes
                  ? const SizedBox.shrink()
                  : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: titleStyle,
                          maxLines: lines,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                      if (hasNote)
                        Icon(
                          Icons.sticky_note_2_outlined,
                          color: AppColors.white,
                          size: titleStyle.fontSize,
                        ),
                    ],
                  ),
        );
      },
      headerStyle: HeaderStyle(
        decoration: const BoxDecoration(color: AppColors.white),
        headerPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        headerTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.slate800,
        ),
      ),
      hourIndicatorSettings: const HourIndicatorSettings(
        color: AppColors.slate300,
        height: 2,
      ),
      halfHourIndicatorSettings: const HourIndicatorSettings(
        color: AppColors.slate300,
        height: 2,
      ),
      onPageChange: (date, page) {
        _slotBloc.add(DisplayedDateChanged(date: date));
      },
      onEventTap: (events, date) {
        final event = events.first;
        final eventSlot = event.event as Slot;

        context.pushNamed(
          Routes.bookAppointment,
          arguments: BookAppointmentScreenArguments(slot: eventSlot),
        );
      },
      onDateTap: (date) {
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
      pageTransitionCurve: Curves.linear,
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
        await weekViewKey.currentState?.animateToWeek(
          picked,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
    );
  }
}
