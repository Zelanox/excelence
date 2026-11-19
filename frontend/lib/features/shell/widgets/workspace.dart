import 'package:flutter/material.dart';

import '../../spreadsheet/controllers/spreadsheet_controller.dart';
import '../../spreadsheet/controllers/viewport_controller.dart';
import '../../spreadsheet/presentation_v2/spreadsheet_feature_v2.dart';
import '../startup_status.dart';
import 'no_document_view.dart';

/// The grid, or - once startup has finished and nothing is open and nothing
/// is being opened - the "No document open" screen.
class Workspace extends StatelessWidget {
  const Workspace({
    super.key,
    required this.spreadsheetController,
    required this.viewportController,
    required this.startup,
    this.onRetry,
  });

  final SpreadsheetController spreadsheetController;
  final ViewportController viewportController;
  final StartupStatus startup;

  /// Offered on the "No document open" screen when startup failed.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedBuilder(
        animation: Listenable.merge([spreadsheetController, startup]),
        builder: (context, _) {
          final showNoDocument = startup.done &&
              !spreadsheetController.hasDocument &&
              !spreadsheetController.isLoadingDocument;

          if (showNoDocument) {
            return NoDocumentView(
              spreadsheetController: spreadsheetController,
              problem: startup.problem,
              onRetry: startup.problem == null ? null : onRetry,
            );
          }

          return SpreadsheetFeatureV2(
            spreadsheetController: spreadsheetController,
            viewportController: viewportController,
          );
        },
      ),
    );
  }
}
