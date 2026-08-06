import 'package:flutter/material.dart';

import '../../models/cell_model.dart';

class SpreadsheetCell extends StatelessWidget {
  const SpreadsheetCell({
    super.key,
    required this.cell,
  });

  final CellModel cell;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cell.isSelected
            ? Colors.blue.shade100
            : Colors.white,
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Text(
        cell.value,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}