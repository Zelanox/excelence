import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../controllers/spreadsheet_controller.dart';
import '../services/spreadsheet_service.dart';
import 'spreadsheet_view.dart';

class SpreadsheetFeature extends StatefulWidget {
  const SpreadsheetFeature({
    super.key,
  });

  @override
  State<SpreadsheetFeature> createState() => _SpreadsheetFeatureState();
}

class _SpreadsheetFeatureState extends State<SpreadsheetFeature> {
  late final SpreadsheetController controller;

  @override
  void initState() {
    super.initState();

    final api = ApiClient(
      baseUrl: "http://localhost:8000",
    );

    final service = SpreadsheetService(api);

    controller = SpreadsheetController(service);

    controller.loadMockData();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpreadsheetView(
      controller: controller,
    );
  }
}