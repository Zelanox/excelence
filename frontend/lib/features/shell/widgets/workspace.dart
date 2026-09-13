import 'package:flutter/material.dart';

import '../../spreadsheet/presentation_v2/spreadsheet_feature_v2.dart';

class Workspace extends StatelessWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: const SpreadsheetFeatureV2(),
    );
  }
}