part of 'slot_bloc.dart';

sealed class SlotEvent {
  const SlotEvent();
}

class InitListener extends SlotEvent {}

class DisplayedDateChanged extends SlotEvent {
  const DisplayedDateChanged({required this.date});
  final DateTime date;
}

class UserChanged extends SlotEvent {
  const UserChanged({required this.userId});
  final String userId;
}

class AddNewSlot extends SlotEvent {
  const AddNewSlot(this.slot);
  final Slot slot;
}

class UpdateSlot extends SlotEvent {
  const UpdateSlot(this.slot);
  final Slot slot;
}

class UpdateSlotNote extends SlotEvent {
  const UpdateSlotNote({required this.slotId, required this.note});
  final String slotId;
  final String note;
}

class DeleteSlot extends SlotEvent {
  const DeleteSlot(this.slotId);
  final String slotId;
}

class _WeekSnapshotArrived extends SlotEvent {
  const _WeekSnapshotArrived({
    required this.week,
    required this.listenerId,
    required this.snapshot,
  });
  final DateTime week;
  final int listenerId;
  final QuerySnapshot<Map<String, dynamic>> snapshot;
}

class _ClockTicked extends SlotEvent {}

class _WeekListenerFailed extends SlotEvent {
  const _WeekListenerFailed({required this.error, required this.stackTrace});
  final Object error;
  final StackTrace stackTrace;
}
