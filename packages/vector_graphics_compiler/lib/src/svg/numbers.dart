import 'dart:math' as math;

/// Parses a [rawDouble] `String` to a `double`.
///
/// The [rawDouble] might include a unit (`px`, `em` or `ex`)
/// which is stripped off when parsed to a `double`.
///
/// Passing `null` will return `null`.
double? parseDouble(String? rawDouble, {bool tryParse = false}) {
  assert(tryParse != null); // ignore: unnecessary_null_comparison
  if (rawDouble == null) {
    return null;
  }

  rawDouble = rawDouble
      .replaceFirst('rem', '')
      .replaceFirst('em', '')
      .replaceFirst('ex', '')
      .replaceFirst('px', '')
      .trim();

  if (tryParse) {
    return double.tryParse(rawDouble);
  }
  return double.parse(rawDouble);
}

/// Convert [degrees] to radians.
double radians(double degrees) => degrees * math.pi / 180;

/// Parses a `rawDouble` `String` to a `double`
/// taking into account absolute and relative units
/// (`px`, `em` or `ex`).
///
/// `rem`, `em`, and `ex` are currently parsed but
/// sizing is deferred until runtime.
///
/// The `rawDouble` might include a unit which is
/// stripped off when parsed to a `double`.
///
/// Passing `null` will return `null`.
double? parseDoubleWithUnits(
  String? rawDouble, {
  bool tryParse = false,
}) {
  final double? value = parseDouble(
    rawDouble,
    tryParse: tryParse,
  );

  return value;
}
