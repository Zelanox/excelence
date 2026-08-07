import 'package:flutter/material.dart';

class ScrollCoordinator {
  ScrollCoordinator();

  final ScrollController horizontal = ScrollController();
  final ScrollController vertical = ScrollController();

  void dispose() {
    horizontal.dispose();
    vertical.dispose();
  }
}