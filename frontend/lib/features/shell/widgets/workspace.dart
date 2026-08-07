import 'package:flutter/material.dart';

import '../../spreadsheet/presentation/spreadsheet_feature.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: const SpreadsheetFeature(),
    );
  }
}