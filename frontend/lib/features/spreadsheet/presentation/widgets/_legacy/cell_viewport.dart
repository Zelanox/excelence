import 'package:flutter/material.dart';

import '../../controllers/spreadsheet_controller.dart';
import 'spreadsheet_row.dart';

class CellViewport extends StatelessWidget {
  const CellViewport({
    super.key,
    required this.controller,
  });

  final SpreadsheetController controller;

  @override
  Widget build(BuildContext context) {
    final spreadsheet = controller.spreadsheet;

    if (spreadsheet == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final sheet = spreadsheet.activeSheet;

    return ListView.builder(
      itemCount: sheet.rows.length,
      itemBuilder: (context, index) {
        return SpreadsheetRow(
          row: sheet.rows[index],
        );
      },
    );
  }
}