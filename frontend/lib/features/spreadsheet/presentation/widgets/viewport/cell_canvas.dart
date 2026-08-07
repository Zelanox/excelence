import 'package:flutter/material.dart';

class CellCanvas extends StatelessWidget {
  const CellCanvas({
    super.key,
    required ScrollController horizontalController,
    required ScrollController verticalController,
  });

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
    );
  }
}