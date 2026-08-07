import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';

class ScrollCoordinator {
  ScrollCoordinator({
    required this.viewportController,
  }) {
    horizontal.addListener(_onHorizontalScroll);
    vertical.addListener(_onVerticalScroll);

    viewportController.addListener(_syncViewport);
  }

  bool _syncing = false;

  final ViewportController viewportController;

  final ScrollController horizontal = ScrollController();
  final ScrollController vertical = ScrollController();

  void _onHorizontalScroll() {
    if (_syncing) return;

    viewportController.setScroll(
      x: horizontal.offset,
      y: viewportController.viewport.scrollY,
    );
  }

  void _onVerticalScroll() {
    if (_syncing) return;
    viewportController.setScroll(
      x: viewportController.viewport.scrollX,
      y: vertical.offset,
    );
  }

  void _syncViewport() {
    _syncing = true;

    if (horizontal.hasClients &&
        horizontal.offset != viewportController.viewport.scrollX) {
      horizontal.jumpTo(viewportController.viewport.scrollX);
    }

    if (vertical.hasClients &&
        vertical.offset != viewportController.viewport.scrollY) {
      vertical.jumpTo(viewportController.viewport.scrollY);
    }

    _syncing = false;
  }

  void dispose() {
    viewportController.removeListener(_syncViewport);
    
    horizontal.dispose();
    vertical.dispose();
  }
}