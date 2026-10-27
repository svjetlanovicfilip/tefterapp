import 'package:flutter/material.dart';

const weekdays = [
  'Ponedeljak',
  'Utorak',
  'Srijeda',
  'Četvrtak',
  'Petak',
  'Subota',
  'Nedjelja',
];

const months = [
  'Januar',
  'Februar',
  'Mart',
  'April',
  'Maj',
  'Jun',
  'Jul',
  'Avgust',
  'Septembar',
  'Oktobar',
  'Novembar',
  'Decembar',
];

String formatWeekday(int weekDay) {
  return weekdays[weekDay];
}

String formatDateLong(DateTime d) {
  return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
}

String formatDateRange(DateTime from, DateTime to) {
  String fmt(int v) => v.toString().padLeft(2, '0');
  final startStr = '${fmt(from.hour)}:${fmt(from.minute)}';
  final endStr = '${fmt(to.hour)}:${fmt(to.minute)}';
  return '$startStr - $endStr';
}

/// [style] treba biti stil kakav se zaista prikazuje (spojen sa
/// DefaultTextStyle), inače visina linije iz teme nije uračunata.
Size textSize(
  String text,
  TextStyle style, {
  int maxLines = 2,
  double maxWidth = double.infinity,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  return textPainter.size;
}

// Vraća ~30 jasno različitih boja. Boje su generisane ravnomjernim rasporedom po HSL nijansi,
// uz fiksnu saturaciju i svjetlinu – izbjegavamo nijanse iste boje.
List<Color> buildDeterministicPalette() {
  // 10 “normalnih” i čitkih boja (bez fluorescentnog izgleda),
  // stabilan redoslijed za mapiranje po indeksu kolone.
  return const <Color>[
    Colors.blue, // 1. kolona
    Colors.orange, // 5.
    Colors.green, // 4.
    Colors.deepOrange, // 6.
    Colors.indigo, // 2.
    Colors.red, // 7.
    Colors.purple, // 8.
    Colors.teal, // 3.
    Colors.brown, // 9.
    Colors.blueGrey, // 10.
  ];
}

int stableIndex(String key, int modulo) {
  // FNV-1a 32-bit hash yields stable mapping across sessions
  const fnvPrime = 0x01000193;
  const fnvOffset = 0x811C9DC5;
  var hash = fnvOffset;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash % modulo;
}
