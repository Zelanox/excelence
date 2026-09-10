import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';
import '../services/spreadsheet_service.dart';
import 'spreadsheet_view.dart';
import '../../shell/widgets/formula_bar.dart';

class SpreadsheetFeature extends StatefulWidget {
  const SpreadsheetFeature({
    super.key,
  });

  @override
  State<SpreadsheetFeature> createState() => _SpreadsheetFeatureState();
}

class _SpreadsheetFeatureState extends State<SpreadsheetFeature> {
  late final SpreadsheetController spreadsheetController;
  late final ViewportController viewportController;
  late final FocusNode spreadsheetFocusNode;

  @override
  void initState() {
    super.initState();

    final api = ApiClient(
      baseUrl: "http://localhost:8000",
    );

    final service = SpreadsheetService(api);

    spreadsheetController = SpreadsheetController(service);
    viewportController = ViewportController();
    spreadsheetFocusNode = FocusNode(
      debugLabel: 'SpreadsheetViewportFocus',
    );

    spreadsheetController.loadDocument('test.xlsx');
  }

  @override
  void dispose() {
    spreadsheetController.dispose();
    viewportController.dispose();
    spreadsheetFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FormulaBar(
          spreadsheetController: spreadsheetController,
          viewportController: viewportController,
          spreadsheetFocusNode: spreadsheetFocusNode,
        ),
        Expanded(
          child: SpreadsheetView(
            controller: spreadsheetController,
            viewportController: viewportController,
            focusNode: spreadsheetFocusNode,
          ),
        ),
      ],
    );
  }
}