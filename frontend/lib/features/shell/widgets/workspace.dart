import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/presentation_v2/spreadsheet_feature_v2.dart';

class Workspace extends StatelessWidget {
  const Workspace({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SpreadsheetFeatureV2(
        spreadsheetController: spreadsheetController,
        viewportController: viewportController,
      ),
    );
  }
}
