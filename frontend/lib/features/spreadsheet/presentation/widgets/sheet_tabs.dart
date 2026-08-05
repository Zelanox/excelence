import 'package:flutter/material.dart';

class SheetTabs extends StatelessWidget {
  const SheetTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
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