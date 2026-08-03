import 'package:flutter/material.dart';

class SpreadsheetPlaceholder extends StatelessWidget {
  const SpreadsheetPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        color: Colors.white,
        child: const Center(
          child: Text(
            "Spreadsheet View",
            style: TextStyle(
              fontSize: 24,
              color: Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}