import 'package:flutter/material.dart';

class RowHeader extends StatelessWidget {
  const RowHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      color: Colors.grey.shade200,
      alignment: Alignment.topCenter,
      child: const Text("Rows"),
    );
  }
}   