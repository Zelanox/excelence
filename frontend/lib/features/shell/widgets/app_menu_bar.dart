import 'package:flutter/material.dart';

class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: const Row(
        children: [
          Text("File"),
          SizedBox(width: 20),
          Text("Edit"),
          SizedBox(width: 20),
          Text("View"),
          SizedBox(width: 20),
          Text("Insert"),
          SizedBox(width: 20),
          Text("Data"),
          SizedBox(width: 20),
          Text("Tools"),
          SizedBox(width: 20),
          Text("Help"),
        ],
      ),
    );
  }
}