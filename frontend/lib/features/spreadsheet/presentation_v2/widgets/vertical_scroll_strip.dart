import 'package:flutter/material.dart';

/// A vertical scroll bar that lives in its own strip of the layout, beside
/// the grid rather than on top of it.
///
/// Always visible (even when there is nothing to scroll, when it shows a
/// full-length, inactive thumb), draggable, and click-the-track to jump.
/// It drives [controller] directly - the same ScrollController the grid's
/// TableView uses - so it has no dependency on how scroll notifications
/// travel through the table.
///
/// Which side of the screen it sits on is decided by the parent's layout
/// (see SpreadsheetGrid: it is the last child of a Row, so it is on the
/// right in LTR and the left in RTL). The one direction-aware detail here
/// is the separator line, drawn on the strip's START edge - the side
/// that faces the grid in either direction.
class VerticalScrollStrip extends StatefulWidget {
  const VerticalScrollStrip({
    super.key,
    required this.controller,
    this.refresh,
    this.width = 14,
  });

  final ScrollController controller;

  /// Anything else that should redraw the strip - e.g. the spreadsheet
  /// controller, whose row changes alter how much there is to scroll
  /// without moving the scroll position itself.
  final Listenable? refresh;

  final double width;

  @override
  State<VerticalScrollStrip> createState() => _VerticalScrollStripState();
}

/// Everything needed to draw and hit-test the thumb, for one track height.
class _ThumbMetrics {
  const _ThumbMetrics({
    required this.track,
    required this.thumbLength,
    required this.thumbTop,
    required this.maxScrollExtent,
    required this.viewportDimension,
  });

  final double track;
  final double thumbLength;
  final double thumbTop;
  final double maxScrollExtent;
  final double viewportDimension;

  bool get canScroll => maxScrollExtent > 0 && track > thumbLength;
}

class _VerticalScrollStripState extends State<VerticalScrollStrip> {
  static const double _minThumbLength = 28;

  bool _isHovering = false;
  bool _isDragging = false;

  /// Where within the thumb the pointer grabbed it, so the thumb doesn't
  /// jump to centre itself under the cursor when a drag starts.
  double _grabOffset = 0;

  /// The scroll metrics the strip was last DRAWN with. Layout (not build)
  /// is what updates a scroll position's extents, so a build can see
  /// stale ones; after each frame we compare and redraw once if they moved.
  double _drawnMax = -1;
  double _drawnViewport = -1;

  late Listenable _listenable;

  @override
  void initState() {
    super.initState();
    _listenable = _buildListenable();
  }

  @override
  void didUpdateWidget(VerticalScrollStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller ||
        oldWidget.refresh != widget.refresh) {
      _listenable = _buildListenable();
    }
  }

  Listenable _buildListenable() {
    final refresh = widget.refresh;

    return refresh == null
        ? widget.controller
        : Listenable.merge([widget.controller, refresh]);
  }

  ScrollPosition? get _position {
    final controller = widget.controller;

    if (!controller.hasClients || controller.positions.length != 1) {
      return null;
    }

    final position = controller.position;

    return position.hasContentDimensions ? position : null;
  }

  _ThumbMetrics _metrics(double track) {
    final position = _position;

    if (position == null || track <= 0) {
      return _ThumbMetrics(
        track: track,
        thumbLength: track,
        thumbTop: 0,
        maxScrollExtent: 0,
        viewportDimension: 0,
      );
    }

    final maxScroll = position.maxScrollExtent;
    final viewport = position.viewportDimension;
    final content = maxScroll + viewport;

    if (maxScroll <= 0 || content <= 0) {
      // Nothing to scroll: a full-length thumb that can't move.
      return _ThumbMetrics(
        track: track,
        thumbLength: track,
        thumbTop: 0,
        maxScrollExtent: 0,
        viewportDimension: viewport,
      );
    }

    final thumbLength = (track * viewport / content)
        .clamp(_minThumbLength < track ? _minThumbLength : track, track)
        .toDouble();
    final range = track - thumbLength;
    final fraction = (position.pixels / maxScroll).clamp(0.0, 1.0).toDouble();

    return _ThumbMetrics(
      track: track,
      thumbLength: thumbLength,
      thumbTop: range * fraction,
      maxScrollExtent: maxScroll,
      viewportDimension: viewport,
    );
  }

  /// Scrolls so the thumb's top edge is at [desiredThumbTop] (clamped).
  void _scrollToThumbTop(double desiredThumbTop, _ThumbMetrics metrics) {
    if (!metrics.canScroll || !widget.controller.hasClients) {
      return;
    }

    final range = metrics.track - metrics.thumbLength;
    final fraction = (desiredThumbTop / range).clamp(0.0, 1.0).toDouble();

    widget.controller.jumpTo(fraction * metrics.maxScrollExtent);
  }

  void _handleDragStart(DragStartDetails details, _ThumbMetrics metrics) {
    final y = details.localPosition.dy;
    final onThumb = y >= metrics.thumbTop && y <= metrics.thumbTop + metrics.thumbLength;

    setState(() => _isDragging = true);

    if (onThumb) {
      _grabOffset = y - metrics.thumbTop;
    } else {
      // Grabbing the bare track: centre the thumb on the pointer, then
      // keep dragging from there.
      _grabOffset = metrics.thumbLength / 2;
      _scrollToThumbTop(y - _grabOffset, metrics);
    }
  }

  void _handleDragUpdate(DragUpdateDetails details, _ThumbMetrics metrics) {
    _scrollToThumbTop(details.localPosition.dy - _grabOffset, metrics);
  }

  void _handleTapDown(TapDownDetails details, _ThumbMetrics metrics) {
    final y = details.localPosition.dy;
    final onThumb = y >= metrics.thumbTop && y <= metrics.thumbTop + metrics.thumbLength;

    if (!onThumb) {
      _scrollToThumbTop(y - metrics.thumbLength / 2, metrics);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final metrics = _metrics(constraints.maxHeight);

            // Redraw once after layout if the scroll extents changed since
            // this frame was built (rows added, window resized...).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }

              final position = _position;
              final max = position?.maxScrollExtent ?? 0;
              final viewport = position?.viewportDimension ?? 0;

              if (max != _drawnMax || viewport != _drawnViewport) {
                setState(() {});
              }
            });
            _drawnMax = metrics.maxScrollExtent;
            _drawnViewport = metrics.viewportDimension;

            final active = metrics.canScroll;
            final highlighted = _isHovering || _isDragging;

            final thumbColor = !active
                ? Colors.grey.shade300
                : highlighted
                    ? Colors.grey.shade600
                    : Colors.grey.shade400;

            return MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _handleTapDown(details, metrics),
                onVerticalDragStart: (details) =>
                    _handleDragStart(details, metrics),
                onVerticalDragUpdate: (details) =>
                    _handleDragUpdate(details, _metrics(constraints.maxHeight)),
                onVerticalDragEnd: (_) => setState(() => _isDragging = false),
                onVerticalDragCancel: () => setState(() => _isDragging = false),
                child: Container(
                  width: widget.width,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    // The strip's START edge faces the grid in both
                    // directions (right-hand strip in LTR has its start on
                    // the left; left-hand strip in RTL has it on the right).
                    border: BorderDirectional(
                      start: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: metrics.thumbTop,
                        height: metrics.thumbLength,
                        left: 2,
                        right: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: thumbColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
