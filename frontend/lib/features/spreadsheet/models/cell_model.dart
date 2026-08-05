class CellModel {
  const CellModel({
    required this.row,
    required this.column,
    this.value = "",
    this.formula,
    this.isSelected = false,
    this.isEditing = false,
  });

  final int row;
  final int column;

  final String value;
  final String? formula;

  final bool isSelected;
  final bool isEditing;

  CellModel copyWith({
    int? row,
    int? column,
    String? value,
    String? formula,
    bool? isSelected,
    bool? isEditing,
  }) {
    return CellModel(
      row: row ?? this.row,
      column: column ?? this.column,
      value: value ?? this.value,
      formula: formula ?? this.formula,
      isSelected: isSelected ?? this.isSelected,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}