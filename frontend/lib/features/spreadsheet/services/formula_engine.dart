import 'package:flutter/foundation.dart';

import '../models/cell_model.dart';
import '../models/spreadsheet_model.dart';

class FormulaEngine {
  const FormulaEngine();

  static const String errorValue = '#ERROR!';

  String evaluate(
    String formula,
    SpreadsheetModel spreadsheet, {
    Set<String> resolving = const {},
  }) {
    try {
      debugPrint(
        '[FormulaEngine.context] activeSheetIndex=${spreadsheet.activeSheetIndex} '
        'sheetName="${spreadsheet.activeSheet.name}" '
        'rowCount=${spreadsheet.activeSheet.rows.length} '
        'columnCount=${spreadsheet.activeSheet.rows.isEmpty ? 0 : spreadsheet.activeSheet.rows.first.cells.length}',
      );
      if (!formula.startsWith('=')) {
        return errorValue;
      }

      final parser = _FormulaParser(formula.substring(1), (reference) {
          if (resolving.contains(reference)) {
            throw const FormatException();
          }

          final cell = _cellForReference(
            spreadsheet,
            reference,
          );

          final cellFormula = cell.formula;
          if (cellFormula != null) {
            final nextResolving = Set<String>.from(resolving)
              ..add(reference);
            final value = evaluate(
              cellFormula,
              spreadsheet,
              resolving: nextResolving,
            );
            final numericValue = double.tryParse(value);
            return numericValue == null
                ? const _ResolvedValue.error()
                : _ResolvedValue.numeric(numericValue);
          }

          final numericValue = double.tryParse(cell.value);
          return numericValue == null
              ? const _ResolvedValue.empty()
              : _ResolvedValue.numeric(numericValue);
        });
      final result = parser.parse();

      return _formatNumber(result);
    } catch (error, stackTrace) {
      debugPrint(
        '[FormulaEngine.error] formula="$formula" '
        'type=${error.runtimeType} message=$error\n'
        'stack=$stackTrace',
      );
      return errorValue;
    }
  }

  Set<String> extractReferences(String formula) {
    try {
      if (!formula.startsWith('=')) {
        return <String>{};
      }

      final parser = _FormulaParser(
        formula.substring(1),
        (_) => const _ResolvedValue.numeric(0),
      );
      parser.parse();
      return parser.references;
    } catch (_) {
      return <String>{};
    }
  }

  CellModel _cellForReference(
    SpreadsheetModel spreadsheet,
    String reference,
  ) {
    final match = RegExp(r'^([A-Z]+)([1-9][0-9]*)$').firstMatch(reference);
    if (match == null) {
      throw const FormatException();
    }

    final column = _columnIndex(match.group(1)!);
    final row = int.parse(match.group(2)!) - 1;
    final sheet = spreadsheet.activeSheet;

    if (row < 0 || row >= sheet.rows.length ||
        column < 0 || column >= sheet.rows[row].cells.length) {
      debugPrint(
        '[FormulaEngine.reference] INVALID $reference -> '
        'row=$row column=$column '
        'activeSheet=${spreadsheet.activeSheetIndex}',
      );
      throw const FormatException();
    }

    final cell = sheet.rows[row].cells[column];
    debugPrint(
      '[FormulaEngine.reference] $reference -> '
      'row=$row column=$column '
      'activeSheet=${spreadsheet.activeSheetIndex} '
      'value="${cell.value}" formula="${cell.formula}"',
    );

    return cell;
  }

  int _columnIndex(String columnText) {
    var index = 0;

    for (final character in columnText.codeUnits) {
      index = index * 26 + character - 64;
    }

    return index - 1;
  }

  String _formatNumber(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }

    return value.toString();
  }
}

class _FormulaParser {
  _FormulaParser(this._input, this._resolveReference);

  final String _input;
  final _ResolvedValue Function(String reference) _resolveReference;
  final Set<String> references = <String>{};
  int _position = 0;

  double parse() {
    final result = _parseExpression();
    _skipWhitespace();

    if (_position != _input.length) {
      throw const FormatException();
    }

    return result;
  }

  double _parseExpression() {
    var result = _parseTerm();

    while (true) {
      _skipWhitespace();

      if (_match('+')) {
        result += _parseTerm();
      } else if (_match('-')) {
        result -= _parseTerm();
      } else {
        return result;
      }
    }
  }

  double _parseTerm() {
    var result = _parseFactor();

    while (true) {
      _skipWhitespace();

      if (_match('*')) {
        result *= _parseFactor();
      } else if (_match('/')) {
        final divisor = _parseFactor();
        if (divisor == 0) {
          throw const FormatException();
        }
        result /= divisor;
      } else {
        return result;
      }
    }
  }

  double _parseFactor() {
    _skipWhitespace();

    if (_match('+')) {
      return _parseFactor();
    }

    if (_match('-')) {
      return -_parseFactor();
    }

    if (_match('(')) {
      final result = _parseExpression();
      _skipWhitespace();
      if (!_match(')')) {
        throw const FormatException();
      }
      return result;
    }

    if (_position < _input.length && _isDigit(_input[_position])) {
      return _parseNumber();
    }

    final identifier = _parseIdentifier();
    _skipWhitespace();

    if (_match('(')) {
      return _parseFunction(identifier);
    }

    return _parseCellReference(identifier);
  }

  double _parseNumber() {
    final start = _position;
    var hasDecimal = false;

    while (_position < _input.length) {
      final character = _input[_position];
      if (_isDigit(character)) {
        _position++;
      } else if (character == '.' && !hasDecimal) {
        hasDecimal = true;
        _position++;
      } else {
        break;
      }
    }

    final text = _input.substring(start, _position);
    final value = double.tryParse(text);
    if (value == null) {
      throw const FormatException();
    }

    return value;
  }

  double _parseCellReference(String? columnText) {
    final parsedColumnText = columnText ?? _parseIdentifier();
    final rowStart = _position;

    while (_position < _input.length && _isDigit(_input[_position])) {
      _position++;
    }

    if (parsedColumnText.isEmpty || rowStart == _position) {
      throw const FormatException();
    }

    final rowNumber = int.tryParse(
      _input.substring(rowStart, _position),
    );
    if (rowNumber == null || rowNumber <= 0) {
      throw const FormatException();
    }

    final reference = '$parsedColumnText$rowNumber';
    debugPrint('[FormulaEngine.parseReference] reference="$reference"');
    references.add(reference);
    final resolved = _resolveReference(reference);
    if (resolved.error || resolved.value == null) {
      throw const FormatException();
    }
    return resolved.value!;
  }

  double _parseFunction(String functionName) {
    final arguments = <_FormulaArgument>[];
    _skipWhitespace();

    if (!_match(')')) {
      while (true) {
        arguments.add(_parseArgument());
        _skipWhitespace();

        if (_match(')')) {
          break;
        }
        if (!_match(',')) {
          throw const FormatException();
        }
      }
    }

    if (arguments.any((argument) => argument.error)) {
      throw const FormatException();
    }

    final values = arguments.expand((argument) => argument.values).toList();
    switch (functionName) {
      case 'SUM':
        return values.fold(0.0, (sum, value) => sum + value);
      case 'AVERAGE':
        if (values.isEmpty) {
          throw const FormatException();
        }
        return values.reduce((sum, value) => sum + value) / values.length;
      case 'MIN':
        if (values.isEmpty) {
          throw const FormatException();
        }
        return values.reduce((min, value) => min < value ? min : value);
      case 'MAX':
        if (values.isEmpty) {
          throw const FormatException();
        }
        return values.reduce((max, value) => max > value ? max : value);
      case 'COUNT':
        return values.length.toDouble();
      default:
        throw const FormatException();
    }
  }

  _FormulaArgument _parseArgument() {
    _skipWhitespace();
    final start = _position;
    final identifier = _parseIdentifier();
    _skipWhitespace();

    if (identifier.isNotEmpty &&
        _position < _input.length &&
        _isDigit(_input[_position])) {
      _position = start;
      return _parseReferenceArgument();
    }

    if (identifier.isNotEmpty && _match('(')) {
      final value = _parseFunction(identifier);
      return _FormulaArgument([value]);
    }

    _position = start;
    return _FormulaArgument([_parseExpression()]);
  }

  _FormulaArgument _parseReferenceArgument() {
    final columnText = _parseIdentifier();
    final rowStart = _position;
    while (_position < _input.length && _isDigit(_input[_position])) {
      _position++;
    }

    if (columnText.isEmpty || rowStart == _position) {
      throw const FormatException();
    }

    final rowNumber = int.tryParse(_input.substring(rowStart, _position));
    if (rowNumber == null || rowNumber <= 0) {
      throw const FormatException();
    }

    final startColumn = _columnIndex(columnText);
    final startRow = rowNumber - 1;
    if (!_match(':')) {
      final reference = '$columnText$rowNumber';
      references.add(reference);
      return _argumentForResolved(_resolveReference(reference));
    }

    final endColumnText = _parseIdentifier();
    final endRowStart = _position;
    while (_position < _input.length && _isDigit(_input[_position])) {
      _position++;
    }
    final endRowNumber = int.tryParse(
      _input.substring(endRowStart, _position),
    );
    if (endColumnText.isEmpty || endRowNumber == null || endRowNumber <= 0) {
      throw const FormatException();
    }

    final endColumn = _columnIndex(endColumnText);
    final endRow = endRowNumber - 1;
    debugPrint(
      '[FormulaEngine.parseRange] start="$columnText$rowNumber" '
      'end="$endColumnText$endRowNumber"',
    );
    final minRow = startRow < endRow ? startRow : endRow;
    final maxRow = startRow > endRow ? startRow : endRow;
    final minColumn = startColumn < endColumn ? startColumn : endColumn;
    final maxColumn = startColumn > endColumn ? startColumn : endColumn;
    final values = <double>[];

    for (var row = minRow; row <= maxRow; row++) {
      for (var column = minColumn; column <= maxColumn; column++) {
        final reference = _referenceFor(row, column);
        references.add(reference);
        final resolved = _resolveReference(reference);
        if (resolved.error) {
          return const _FormulaArgument.error();
        }
        if (resolved.value != null) {
          values.add(resolved.value!);
        }
      }
    }

    return _FormulaArgument(values);
  }

  _FormulaArgument _argumentForResolved(_ResolvedValue resolved) {
    if (resolved.error) {
      return const _FormulaArgument.error();
    }
    if (resolved.value == null) {
      return const _FormulaArgument(<double>[]);
    }
    return _FormulaArgument([resolved.value!]);
  }

  String _parseIdentifier() {
    final start = _position;
    while (_position < _input.length &&
        _isColumnLetter(_input[_position])) {
      _position++;
    }
    return _input.substring(start, _position);
  }

  String _referenceFor(int row, int column) {
    var value = column + 1;
    var columnName = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      columnName = String.fromCharCode(65 + remainder) + columnName;
      value = (value - 1) ~/ 26;
    }
    return '$columnName${row + 1}';
  }

  int _columnIndex(String columnText) {
    var index = 0;
    for (final character in columnText.codeUnits) {
      index = index * 26 + character - 64;
    }
    return index - 1;
  }

  bool _match(String character) {
    if (_position >= _input.length || _input[_position] != character) {
      return false;
    }

    _position++;
    return true;
  }

  void _skipWhitespace() {
    while (_position < _input.length &&
        _input[_position].trim().isEmpty) {
      _position++;
    }
  }

  bool _isDigit(String character) {
    return character.codeUnitAt(0) >= 48 &&
        character.codeUnitAt(0) <= 57;
  }

  bool _isColumnLetter(String character) {
    final code = character.codeUnitAt(0);
    return code >= 65 && code <= 90;
  }
}

class _FormulaArgument {
  const _FormulaArgument(this.values) : error = false;

  const _FormulaArgument.error()
      : values = const <double>[],
        error = true;

  final List<double> values;
  final bool error;
}

class _ResolvedValue {
  const _ResolvedValue.numeric(this.value) : error = false;

  const _ResolvedValue.empty()
      : value = null,
        error = false;

  const _ResolvedValue.error()
      : value = null,
        error = true;

  final double? value;
  final bool error;
}
