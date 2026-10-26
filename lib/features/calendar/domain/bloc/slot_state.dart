part of 'slot_bloc.dart';

sealed class SlotState extends Equatable {
  const SlotState();

  @override
  List<Object?> get props => [];
}

class SlotStateInitial extends SlotState {
  const SlotStateInitial();

  @override
  List<Object?> get props => [];
}

class SlotStateLoading extends SlotState {
  const SlotStateLoading();

  @override
  List<Object?> get props => [];
}

class SlotsLoaded extends SlotState {
  const SlotsLoaded({
    required this.slots,
    required this.selectedUserId,
    required this.version,
  });

  /// Termini svih zaposlenih iz učitanih sedmica.
  final List<Slot> slots;
  final String selectedUserId;
  final int version;

  List<Slot> get selectedUserSlots =>
      slots.where((slot) => slot.employeeIds.contains(selectedUserId)).toList();

  @override
  List<Object?> get props => [version];
}

class ErrorLoadingSlots extends SlotState {
  const ErrorLoadingSlots({required this.errorMessage});

  final String errorMessage;

  @override
  List<Object?> get props => [errorMessage];
}
