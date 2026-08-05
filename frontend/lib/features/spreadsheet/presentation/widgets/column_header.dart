import 'package:flutter/material.dart';

class ColumnHeader extends StatelessWidget {
  const ColumnHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.centerLeft,
      child: const Text("Column Header"),
    );
  }
}