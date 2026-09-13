import 'package:flutter/material.dart';

import '../../spreadsheet/presentation_v2/spreadsheet_screen_v2.dart';

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
      child: Row(
        children: [
          const Icon(Icons.folder_open),
          const SizedBox(width: 10),
          const Icon(Icons.save),
          const SizedBox(width: 10),
          const Icon(Icons.undo),
          const SizedBox(width: 10),
          const Icon(Icons.redo),
          const Spacer(),
          // TEMPORARY test entry point for the new (v2) UI rebuild.
          // Remove this once v2 replaces v1, or once a permanent
          // settings-based toggle is built instead.
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SpreadsheetScreenV2(),
                ),
              );
            },
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Try new UI'),
          ),
        ],
      ),
    );
  }
}