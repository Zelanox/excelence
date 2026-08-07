import 'package:flutter/foundation.dart';

@immutable
class ViewportState {
  const ViewportState({
    this.scrollX = 0,
    this.scrollY = 0,
    this.zoom = 1.0,
  });

  final double scrollX;
  final double scrollY;
  final double zoom;

  ViewportState copyWith({
    double? scrollX,
    double? scrollY,
    double? zoom,
  }) {
    return ViewportState(
      scrollX: scrollX ?? this.scrollX,
      scrollY: scrollY ?? this.scrollY,
      zoom: zoom ?? this.zoom,
    );
  }
}