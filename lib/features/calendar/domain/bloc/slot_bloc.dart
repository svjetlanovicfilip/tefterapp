import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../../../common/di/di_container.dart';
import '../../../../common/models/result.dart';
import '../../data/models/slot.dart';
import '../../data/models/slot_save_outcome.dart';
import '../../data/repositories/calendar_repository.dart';

part 'slot_event.dart';
part 'slot_state.dart';

/// Termini se slušaju po sedmicama (ponedjeljak 00:00 - sljedeći ponedjeljak
/// 00:00) za cijelu organizaciju. Uvijek su žive tekuća i sljedeća sedmica
/// (da promjene za danas i narednih 7 dana stižu odmah, gdje god korisnik
/// bio u kalendaru) i prikazana sedmica ±1. Sve ostale sedmice se gase, tako
/// da broj aktivnih listenera nikad ne prelazi 5.
class SlotBloc extends Bloc<SlotEvent, SlotState> {
  SlotBloc(this.calendarRepository) : super(const SlotStateInitial()) {
    on<InitListener>(_onInit);
    on<DisplayedDateChanged>(_onDisplayedDateChanged);
    on<UserChanged>(_onUserChanged);
    on<_WeekSnapshotArrived>(_onWeekSnapshotArrived);
    on<_WeekListenerFailed>(_onWeekListenerFailed);
    on<_ClockTicked>(_onClockTicked);
    on<AddNewSlot>(_onAddNewSlot);
    on<UpdateSlot>(_onUpdateSlot);
    on<UpdateSlotNote>(_onUpdateSlotNote);
    on<DeleteSlot>(_onDeleteSlot);
  }

  final CalendarRepository calendarRepository;

  /// Bez interneta Firestore drži upis u redu i šalje ga kad se veza vrati,
  /// a Future se ne završava do tada. Nakon ovog vremena upis smatramo
  /// sačuvanim, da ekran ne čeka beskonačno.
  static const _writeTimeout = Duration(seconds: 10);

  static const _overlapMessage =
      'Termin se preklapa s drugim terminom. Molimo Vas izaberite drugi termin.';
  static const _saveFailedMessage = 'Termin nije sačuvan. Pokušajte ponovo.';

  final _weekListeners =
      <DateTime, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final _weekSlots = <DateTime, Map<String, Slot>>{};

  /// Id aktivnog listenera po sedmici. Snapshot ugašenog listenera koji je
  /// još čekao u redu događaja se ignoriše.
  final _weekListenerIds = <DateTime, int>{};
  int _nextListenerId = 0;

  /// Sedmice za koje je stigao snapshot sa servera, pa su podaci potpuni.
  final _loadedWeeks = <DateTime>{};

  DateTime _displayedDate = DateTime.now();
  int _version = 0;

  /// Provjerava da li je počela nova sedmica dok je aplikacija otvorena, da
  /// se sidro (tekuća + sljedeća sedmica) pomjeri i bez navigacije. Dok je
  /// aplikacija u pozadini tajmer miruje, pa se provjera desi po povratku.
  Timer? _clockTimer;
  DateTime? _anchorWeek;

  /// Svi trenutno učitani termini organizacije (svi zaposleni).
  List<Slot> get slots =>
      _weekSlots.values.expand((weekSlots) => weekSlots.values).toList();

  static DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  static DateTime _addWeeks(DateTime weekStart, int weeks) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 7 * weeks);

  Set<DateTime> _desiredWeeks() {
    final currentWeek = _anchorWeek = _weekStart(DateTime.now());
    final displayedWeek = _weekStart(_displayedDate);

    return {
      currentWeek,
      _addWeeks(currentWeek, 1),
      _addWeeks(displayedWeek, -1),
      displayedWeek,
      _addWeeks(displayedWeek, 1),
    };
  }

  void _syncWeekListeners(Emitter<SlotState> emit) {
    final desiredWeeks = _desiredWeeks();

    final obsoleteWeeks =
        _weekListeners.keys
            .where((week) => !desiredWeeks.contains(week))
            .toList();
    for (final week in obsoleteWeeks) {
      unawaited(_weekListeners.remove(week)?.cancel());
      _weekListenerIds.remove(week);
      _weekSlots.remove(week);
      _loadedWeeks.remove(week);
    }

    for (final week in desiredWeeks) {
      if (_weekListeners.containsKey(week)) continue;

      final listenerId = _nextListenerId++;
      _weekListenerIds[week] = listenerId;
      _weekListeners[week] = calendarRepository
          .listenForSlotsStartingBetween(from: week, to: _addWeeks(week, 1))
          .listen(
            (snapshot) => add(
              _WeekSnapshotArrived(
                week: week,
                listenerId: listenerId,
                snapshot: snapshot,
              ),
            ),
            onError:
                (Object error, StackTrace stackTrace) => add(
                  _WeekListenerFailed(error: error, stackTrace: stackTrace),
                ),
          );
    }

    if (obsoleteWeeks.isNotEmpty) {
      _emitLoaded(emit);
    }
  }

  void _emitLoaded(Emitter<SlotState> emit) {
    emit(
      SlotsLoaded(
        slots: slots,
        selectedUserId: appState.currentSelectedUserId ?? '',
        version: ++_version,
      ),
    );
  }

  void _cancelAllListeners() {
    _clockTimer?.cancel();
    _clockTimer = null;
    for (final listener in _weekListeners.values) {
      unawaited(listener.cancel());
    }
    _weekListeners.clear();
    _weekListenerIds.clear();
    _weekSlots.clear();
    _loadedWeeks.clear();
  }

  void _onInit(InitListener event, Emitter<SlotState> emit) {
    emit(const SlotStateLoading());

    _cancelAllListeners();
    _displayedDate = DateTime.now();
    _syncWeekListeners(emit);

    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => add(_ClockTicked()),
    );
  }

  void _onClockTicked(_ClockTicked event, Emitter<SlotState> emit) {
    if (_weekStart(DateTime.now()) != _anchorWeek) {
      _syncWeekListeners(emit);
    }
  }

  void _onDisplayedDateChanged(
    DisplayedDateChanged event,
    Emitter<SlotState> emit,
  ) {
    _displayedDate = event.date;
    _syncWeekListeners(emit);
  }

  void _onUserChanged(UserChanged event, Emitter<SlotState> emit) {
    if (event.userId == appState.currentSelectedUserId) {
      return;
    }

    // Termini svih zaposlenih su već učitani, filter je lokalni.
    appState.currentSelectedUserId = event.userId;
    _emitLoaded(emit);
  }

  void _onWeekSnapshotArrived(
    _WeekSnapshotArrived event,
    Emitter<SlotState> emit,
  ) {
    // Snapshot može stići nakon što je listener za tu sedmicu već ugašen
    // (i možda zamijenjen novim).
    if (_weekListenerIds[event.week] != event.listenerId) {
      return;
    }

    final weekSlots = _weekSlots.putIfAbsent(event.week, () => {});
    for (final change in event.snapshot.docChanges) {
      final id = change.doc.id;

      switch (change.type) {
        case DocumentChangeType.added:
        case DocumentChangeType.modified:
          weekSlots[id] = Slot.fromJson(change.doc.data() ?? {}, id);
          break;
        case DocumentChangeType.removed:
          weekSlots.remove(id);
          break;
      }
    }

    // Snapshot iz keša može biti nepotpun, pa se na njega ne oslanja
    // lokalna provjera preklapanja.
    if (!event.snapshot.metadata.isFromCache) {
      _loadedWeeks.add(event.week);
    }
    _emitLoaded(emit);
  }

  void _onWeekListenerFailed(
    _WeekListenerFailed event,
    Emitter<SlotState> emit,
  ) {
    unawaited(
      FirebaseCrashlytics.instance.recordError(event.error, event.stackTrace),
    );
    // Emitujemo ono što imamo da AppInitBloc ne bi ostao zaglavljen na splashu.
    _emitLoaded(emit);
  }

  /// Ako su sve sedmice koje termin može dodirnuti žive, preklapanje se
  /// provjerava lokalno, bez ijednog reada.
  Future<bool?> _isOverlapping(Slot slot, String userId) async {
    final start = slot.startDateTime;
    final end = slot.endDateTime!;

    // Termin iz prethodne sedmice može trajati preko ponoći u novu sedmicu.
    final weeksToCheck = {
      _weekStart(start.subtract(const Duration(days: 1))),
      _weekStart(start),
      _weekStart(end),
    };

    if (_loadedWeeks.containsAll(weeksToCheck)) {
      return slots.any(
        (other) =>
            other.id != slot.id &&
            other.employeeIds.contains(userId) &&
            other.startDateTime.isBefore(end) &&
            (other.endDateTime ?? other.startDateTime).isAfter(start),
      );
    }

    final result = await calendarRepository.isSlotOverlapping(
      newStart: start,
      newEnd: end,
      userId: userId,
      excludeSlotId: slot.id,
    );

    return result.isFailure ? null : result.success;
  }

  /// Vraća poruku greške ili null ako je termin validan.
  Future<String?> _validateSlot(Slot slot) async {
    if (slot.endDateTime == null) {
      return 'Molimo Vas izaberite početak i kraj termina.';
    }

    for (final userId in slot.employeeIds) {
      final isOverlapping = await _isOverlapping(slot, userId);

      if (isOverlapping == null) {
        return 'Provjera termina nije uspjela. Provjerite internet konekciju i pokušajte ponovo.';
      }

      if (isOverlapping) {
        return _overlapMessage;
      }
    }

    return null;
  }

  Future<void> _onAddNewSlot(AddNewSlot e, Emitter<SlotState> emit) async {
    final slot =
        e.slot.id == null
            ? e.slot.copyWith(id: calendarRepository.newSlotId())
            : e.slot;
    await _saveSlot(slot, isNew: true, emit: emit);
  }

  Future<void> _onUpdateSlot(UpdateSlot e, Emitter<SlotState> emit) =>
      _saveSlot(e.slot, isNew: false, emit: emit);

  /// Lokalna provjera daje brz odgovor, a konačnu provjeru i upis radi
  /// Cloud Function u jednoj transakciji, pa dva uređaja ne mogu u isto
  /// vrijeme zakazati isti termin. Bez interneta termin se upisuje direktno,
  /// samo uz lokalnu provjeru.
  Future<void> _saveSlot(
    Slot slot, {
    required bool isNew,
    required Emitter<SlotState> emit,
  }) async {
    emit(const SlotStateInitial());

    final errorMessage = await _validateSlot(slot);
    if (errorMessage != null) {
      emit(ErrorLoadingSlots(errorMessage: errorMessage));
      return;
    }

    final atomicResult = await calendarRepository.saveSlotAtomically(
      slot,
      isNew: isNew,
    );
    if (atomicResult.isFailure) {
      emit(const ErrorLoadingSlots(errorMessage: _saveFailedMessage));
      return;
    }

    switch (atomicResult.success!) {
      case SlotSaveOutcome.saved:
        break;
      case SlotSaveOutcome.overlapping:
        emit(const ErrorLoadingSlots(errorMessage: _overlapMessage));
        return;
      case SlotSaveOutcome.slotMissing:
        emit(const ErrorLoadingSlots(errorMessage: 'Termin više ne postoji.'));
        return;
      case SlotSaveOutcome.serverUnavailable:
        final result =
            isNew
                ? await calendarRepository
                    .createSlot(slot)
                    .timeout(_writeTimeout, onTimeout: () => Result.success(''))
                : await calendarRepository
                    .updateSlot(slot)
                    .timeout(
                      _writeTimeout,
                      onTimeout: () => Result.success(true),
                    );
        if (result.isFailure) {
          emit(const ErrorLoadingSlots(errorMessage: _saveFailedMessage));
          return;
        }
    }

    emit(SlotSaved(version: ++_version));
  }

  /// Samo napomena: bez provjere preklapanja, pa radi i na prošlim terminima
  /// i kad se termin već preklapa s nekim drugim.
  Future<void> _onUpdateSlotNote(
    UpdateSlotNote e,
    Emitter<SlotState> emit,
  ) async {
    emit(const SlotStateInitial());

    final result = await calendarRepository
        .updateSlotNote(slotId: e.slotId, note: e.note)
        .timeout(_writeTimeout, onTimeout: () => Result.success(true));
    if (result.isFailure) {
      emit(
        const ErrorLoadingSlots(
          errorMessage: 'Napomena nije sačuvana. Pokušajte ponovo.',
        ),
      );
      return;
    }

    emit(SlotSaved(version: ++_version));
  }

  Future<void> _onDeleteSlot(DeleteSlot e, Emitter<SlotState> emit) async {
    final result = await calendarRepository.deleteSlot(e.slotId);
    if (result.isFailure) {
      emit(ErrorLoadingSlots(errorMessage: result.failure?.toString() ?? ''));
      return;
    }
  }

  void clearState() {
    _cancelAllListeners();
  }

  @override
  Future<void> close() {
    _cancelAllListeners();
    return super.close();
  }
}
