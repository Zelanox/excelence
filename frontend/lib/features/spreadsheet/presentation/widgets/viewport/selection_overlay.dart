import 'package:flutter/material.dart';

class SpreadsheetSelectionOverlay extends StatelessWidget {
  const SpreadsheetSelectionOverlay({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: SizedBox.expand(),
    );
  }
}