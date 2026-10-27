import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../common/models/result.dart';
import '../models/slot.dart';
import '../models/slot_save_outcome.dart';

abstract class CalendarRepository {
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForSlotsStartingBetween({
    required DateTime from,
    required DateTime to,
  });
  Future<Result<Slot?, Exception>> getSlotById(String slotId);
  String newSlotId();
  Future<Result<SlotSaveOutcome, Exception>> saveSlotAtomically(
    Slot slot, {
    required bool isNew,
  });
  Future<Result<String, Exception>> createSlot(Slot slot);
  Future<Result<bool, Exception>> updateSlot(Slot slot);
  Future<Result<bool, Exception>> updateSlotNote({
    required String slotId,
    required String note,
  });
  Future<Result<bool, Exception>> deleteSlot(String slotId);
  Future<Result<bool, Exception>> isSlotOverlapping({
    required DateTime newStart,
    required DateTime newEnd,
    required String userId,
    String? excludeSlotId,
  });
}
