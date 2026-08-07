import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';
import 'cell_metrics.dart';
import 'grid_painter.dart';

class CellCanvas extends StatelessWidget {
  const CellCanvas({
    super.key,
    required this.horizontalController,
    required this.verticalController,
    required this.viewportController,
  });

  final ScrollController horizontalController;
  final ScrollController verticalController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        viewportController.selectFromPixel(
          x: details.localPosition.dx,
          y: details.localPosition.dy,
        );
      },
      child: SingleChildScrollView(
        controller: verticalController,
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: CellMetrics.columnWidth * 26,
            height: CellMetrics.rowHeight * 100,
            child: const CustomPaint(
              painter: GridPainter(),
            ),
          ),
        ),
      ),
    );
  }
}