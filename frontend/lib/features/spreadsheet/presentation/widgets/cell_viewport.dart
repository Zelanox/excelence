import 'package:flutter/material.dart';

class CellViewport extends StatelessWidget {
  const CellViewport({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: const Text(
        "Cell Viewport",
        style: TextStyle(
          fontSize: 20,
          color: Colors.grey,
        ),
      ),
    );
  }
}