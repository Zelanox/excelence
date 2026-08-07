import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';

class SpreadsheetSelectionOverlay extends StatelessWidget {
  const SpreadsheetSelectionOverlay({
    super.key,
    required this.viewportController,
  });

  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    final selection = viewportController.selection;

    const cellWidth = 80.0;
    const cellHeight = 28.0;

    final left =
        selection.startColumn * cellWidth -
        viewportController.viewport.scrollX;

    final top =
        selection.startRow * cellHeight -
        viewportController.viewport.scrollY;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: cellWidth,
            height: cellHeight,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.blue,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}