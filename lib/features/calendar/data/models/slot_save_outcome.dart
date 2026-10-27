/// Rezultat upisa termina kroz Cloud Function `saveSlot`.
enum SlotSaveOutcome {
  saved,

  /// Drugi termin istog zaposlenog je upisan u međuvremenu.
  overlapping,

  /// Termin je obrisan dok je bio otvoren.
  slotMissing,

  /// Nema interneta ili funkcija (još) nije deployovana; termin se upisuje
  /// direktno, bez atomske provjere.
  serverUnavailable,
}
