import 'package:flutter/material.dart';

class Toolbar extends StatelessWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          Icon(Icons.folder_open),
          SizedBox(width: 10),
          Icon(Icons.save),
          SizedBox(width: 10),
          Icon(Icons.undo),
          SizedBox(width: 10),
          Icon(Icons.redo),
        ],
      ),
    );
  }
}