import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../controllers/spreadsheet_controller.dart';
import '../controllers/viewport_controller.dart';
import '../services/spreadsheet_service.dart';
import 'spreadsheet_view.dart';
import '../models/spreadsheet_model.dart';

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

  @override
  void initState() {
    super.initState();

    final api = ApiClient(
      baseUrl: "http://localhost:8000",
    );

    final service = SpreadsheetService(api);

    spreadsheetController = SpreadsheetController(service);
    viewportController = ViewportController();

    spreadsheetController.loadMockData();
  }

  @override
  void dispose() {
    spreadsheetController.dispose();
    viewportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpreadsheetView(
      controller: spreadsheetController,
      viewportController: viewportController,
      spreadsheet: spreadsheetController.spreadsheet!,
    );
  }
}