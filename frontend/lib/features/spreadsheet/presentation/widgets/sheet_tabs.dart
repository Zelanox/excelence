import 'package:flutter/material.dart';
import '../../presentation/widgets/viewport/cell_metrics.dart';

class SheetTabs extends StatelessWidget {
  const SheetTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CellMetrics.columnHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 8),
          Chip(label: Text("Sheet1")),
        ],
      ),
    );
  }
}