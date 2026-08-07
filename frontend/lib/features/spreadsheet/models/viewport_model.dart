class ViewportModel {
  final double scrollX;
  final double scrollY;
  final double zoom;

  const ViewportModel({
    this.scrollX = 0,
    this.scrollY = 0,
    this.zoom = 1.0,
  });

  ViewportModel copyWith({
    double? scrollX,
    double? scrollY,
    double? zoom,
  }) {
    return ViewportModel(
      scrollX: scrollX ?? this.scrollX,
      scrollY: scrollY ?? this.scrollY,
      zoom: zoom ?? this.zoom,
    );
  }
}