// Weight-unit conversion at the presentation boundary.
//
// The database and every domain entity hold weight in kilograms, always.
// The kg/lbs toggle is a *view* preference: convert on the way in (parse)
// and on the way out (render), never in storage. See BUG-01.

const double kLbsPerKg = 2.20462262185;

const String kUnitKg = 'kg';
const String kUnitLbs = 'lbs';

/// Canonical kg -> the user's display unit.
double kgToDisplay(double kg, String unit) =>
    unit == kUnitLbs ? kg * kLbsPerKg : kg;

/// A value typed in the user's display unit -> canonical kg for storage.
double displayToKg(double value, String unit) =>
    unit == kUnitLbs ? value / kLbsPerKg : value;

/// Renders a canonical-kg weight in [unit], trimming a trailing ".0".
String formatWeight(double kg, String unit, {int decimals = 1}) {
  final v = kgToDisplay(kg, unit);
  final s = v.toStringAsFixed(decimals);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}
