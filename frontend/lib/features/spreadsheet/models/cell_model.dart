import 'text_style_spec.dart';

class CellModel {
  const CellModel({
    required this.row,
    required this.column,
    this.value = "",
    this.formula,
    this.isSelected = false,
    this.isEditing = false,
    this.style = TextStyleSpec.empty,
  });

  final int row;
  final int column;

  final String value;
  final String? formula;

  final bool isSelected;
  final bool isEditing;

  /// This cell's own text-style overrides (bold, font, color, ...). Unset
  /// fields inherit from [SheetModel.textDefaults]. Formatting is
  /// independent of the cell's value, so editing, pasting or clearing a
  /// cell keeps its style - every place that rebuilds a cell must carry
  /// this over.
  final TextStyleSpec style;

  CellModel copyWith({
    int? row,
    int? column,
    String? value,
    String? formula,
    bool? isSelected,
    bool? isEditing,
    TextStyleSpec? style,
  }) {
    return CellModel(
      row: row ?? this.row,
      column: column ?? this.column,
      value: value ?? this.value,
      formula: formula ?? this.formula,
      isSelected: isSelected ?? this.isSelected,
      isEditing: isEditing ?? this.isEditing,
      style: style ?? this.style,
    );
  }
}