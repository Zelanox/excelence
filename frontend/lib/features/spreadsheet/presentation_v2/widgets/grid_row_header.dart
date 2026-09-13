import 'package:flutter/material.dart';

/// Displays the row number (1, 2, 3, ...) for one row.
///
/// Like [GridColumnHeader], this is pure/stateless - a row's NUMBER never
/// changes based on spreadsheet content or selection.
class GridRowHeader extends StatelessWidget {
  const GridRowHeader({
    super.key,
    required this.rowIndex,
  });

  final int rowIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(
          right: BorderSide(color: Colors.grey.shade400),
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '${rowIndex + 1}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
