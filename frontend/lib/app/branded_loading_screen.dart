import 'dart:math' as math;

import 'package:flutter/material.dart';

class BrandedLoadingScreen extends StatefulWidget {
  const BrandedLoadingScreen({super.key});

  @override
  State<BrandedLoadingScreen> createState() => _BrandedLoadingScreenState();
}

class _BrandedLoadingScreenState extends State<BrandedLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;

    return Semantics(
      label: 'Excelence loading',
      liveRegion: true,
      child: ColoredBox(
        color: background,
        child: Center(
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final pulse = math.sin(_animation.value * math.pi * 2);
              final scale = 1 + pulse * 0.025;
              final glowOpacity = 0.10 + (pulse + 1) * 0.045;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size.square(220),
                          painter: _LoadingOrbitPainter(_animation.value),
                        ),
                        Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 164,
                            height: 148,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF00A99D,
                                  ).withValues(alpha: glowOpacity),
                                  blurRadius: 28,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const CustomPaint(
                              painter: _ZeliumExcelenceMarkPainter(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Excelence',
                    style: TextStyle(
                      color: Color(0xFF087F78),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoadingOrbitPainter extends CustomPainter {
  const _LoadingOrbitPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bounds = Rect.fromCircle(center: center, radius: 101);
    final track = Paint()
      ..color = const Color(0xFF00A99D).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final orbit = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF43D6C6), Color(0xFF008C83)],
      ).createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    canvas.drawCircle(center, 101, track);
    canvas.drawArc(
      bounds,
      progress * math.pi * 2,
      math.pi * 1.15,
      false,
      orbit,
    );
  }

  @override
  bool shouldRepaint(_LoadingOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ZeliumExcelenceMarkPainter extends CustomPainter {
  const _ZeliumExcelenceMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 164, size.height / 148);
    canvas.save();
    canvas.translate(
      (size.width - 164 * scale) / 2,
      (size.height - 148 * scale) / 2,
    );
    canvas.scale(scale);

    final zPaint = Paint()
      ..color = const Color(0xFF25C5B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round;
    final ePaint = Paint()
      ..color = const Color(0xFF087F78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round;

    final z = Path()
      ..moveTo(28, 35)
      ..lineTo(100, 35)
      ..lineTo(37, 113)
      ..lineTo(105, 113);
    final e = Path()
      ..moveTo(101, 35)
      ..lineTo(139, 35)
      ..moveTo(101, 74)
      ..lineTo(132, 74)
      ..moveTo(101, 113)
      ..lineTo(139, 113);

    canvas.drawPath(z, zPaint);
    canvas.drawPath(e, ePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ZeliumExcelenceMarkPainter oldDelegate) => false;
}
