/// Converts a zero-based column index into its spreadsheet letter name.
///
/// 0 -> "A", 1 -> "B", ..., 25 -> "Z", 26 -> "AA", 27 -> "AB", ...
///
/// This is a pure function with no dependency on any controller or widget,
/// so it's trivially testable on its own.
String columnLetterName(int columnIndex) {
  var index = columnIndex;
  var name = '';

  while (index >= 0) {
    name = String.fromCharCode(65 + (index % 26)) + name;
    index = (index ~/ 26) - 1;
  }

  return name;
}
