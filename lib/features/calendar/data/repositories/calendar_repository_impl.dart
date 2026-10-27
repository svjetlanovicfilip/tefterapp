import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../common/models/result.dart';
import '../datasources/calendar_remote_datasource.dart';
import '../models/slot.dart';
import 'calendar_repository.dart';

class CalendarRepositoryImpl implements CalendarRepository {
  CalendarRepositoryImpl({required this.calendarRemoteDatasource});

  final CalendarRemoteDatasource calendarRemoteDatasource;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> listenForSlotsStartingBetween({
    required DateTime from,
    required DateTime to,
  }) {
    return calendarRemoteDatasource.listenForSlotsStartingBetween(
      from: from,
      to: to,
    );
  }

  @override
  Future<Result<Slot?, Exception>> getSlotById(String slotId) {
    return calendarRemoteDatasource.getSlotById(slotId);
  }

  @override
  Future<Result<String, Exception>> createSlot(Slot slot) async {
    final result = await calendarRemoteDatasource.createSlot(slot);
    if (result.isFailure) {
      return Result.failure(result.failure as Exception);
    }

    return Result.success(result.success?.id ?? '');
  }

  @override
  Future<Result<bool, Exception>> updateSlot(Slot slot) async {
    final result = await calendarRemoteDatasource.updateSlot(slot);
    if (result.isFailure) {
      return Result.failure(result.failure as Exception);
    }

    return Result.success(result.success ?? false);
  }

  @override
  Future<Result<bool, Exception>> updateSlotNote({
    required String slotId,
    required String note,
  }) {
    return calendarRemoteDatasource.updateSlotNote(slotId: slotId, note: note);
  }

  @override
  Future<Result<bool, Exception>> deleteSlot(String slotId) async {
    final result = await calendarRemoteDatasource.deleteSlot(slotId);
    if (result.isFailure) {
      return Result.failure(result.failure as Exception);
    }

    return Result.success(result.success ?? false);
  }

  @override
  Future<Result<bool, Exception>> isSlotOverlapping({
    required DateTime newStart,
    required DateTime newEnd,
    required String userId,
    String? excludeSlotId,
  }) async {
    final result = await calendarRemoteDatasource.isSlotOverlapping(
      newStart: newStart,
      newEnd: newEnd,
      userId: userId,
      excludeSlotId: excludeSlotId,
    );
    if (result.isFailure) {
      return Result.failure(result.failure as Exception);
    }

    return Result.success(result.success ?? false);
  }
}
