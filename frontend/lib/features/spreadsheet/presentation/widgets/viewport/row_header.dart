import 'package:flutter/material.dart';
import 'cell_metrics.dart';

class RowHeader extends StatelessWidget {
  const RowHeader({super.key, required ScrollController controller,});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: CellMetrics.rowHeaderWidth,
      color: Colors.grey.shade200,
      alignment: Alignment.topCenter,
      child: const Text("Rows"),
    );
  }
}   