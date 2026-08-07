import 'package:flutter/material.dart';

import '../../../controllers/viewport_controller.dart';

class ScrollCoordinator {
  ScrollCoordinator({
    required this.viewportController,
  }) {
    horizontal.addListener(_onHorizontalScroll);
    vertical.addListener(_onVerticalScroll);
  }

  final ViewportController viewportController;

  final ScrollController horizontal = ScrollController();
  final ScrollController vertical = ScrollController();

  void _onHorizontalScroll() {
    viewportController.setScroll(
      x: horizontal.offset,
      y: viewportController.viewport.scrollY,
    );
  }

  void _onVerticalScroll() {
    viewportController.setScroll(
      x: viewportController.viewport.scrollX,
      y: vertical.offset,
    );
  }

  void dispose() {
    horizontal.dispose();
    vertical.dispose();
  }
}