import 'package:flutter/material.dart';

import '../../spreadsheet/presentation/spreadsheet_view.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: SpreadsheetView(),
    );
  }
}