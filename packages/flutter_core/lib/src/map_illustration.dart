import 'package:flutter/material.dart';
import 'theme.dart';
import 'widgets.dart';

/// Illustrative (non-geographic) map matching the approved designs.
class MapIllustration extends StatelessWidget {
  final double height;
  final bool showPerson;
  const MapIllustration({super.key, this.height = 200, this.showPerson = true});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TamreedyRadii.card),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: TamreedyColors.border),
          borderRadius: BorderRadius.circular(TamreedyRadii.card),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            PositionedDirectional(
              top: 12,
              end: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip('مسار توضيحي'),
                    const SizedBox(width: 6),
                    Text(
                      '2.4 كم',
                      style: tamText(size: 11, color: TamreedyColors.subtext),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0.55, -0.25),
              child: _pin(Icons.home_outlined, TamreedyColors.navy),
            ),
            if (showPerson)
              Align(
                alignment: const Alignment(-0.6, 0.35),
                child: _pin(Icons.person_outline, TamreedyColors.teal),
              ),
            Align(
              alignment: const Alignment(-0.7, -0.6),
              child: Text(
                'المزة',
                style: tamText(
                  size: 11,
                  weight: FontWeight.w700,
                  color: TamreedyColors.subtext,
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0.7, 0.75),
              child: Text(
                'دمشق',
                style: tamText(
                  size: 11,
                  weight: FontWeight.w700,
                  color: TamreedyColors.subtext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pin(IconData icon, Color color) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Icon(icon, color: Colors.white, size: 18),
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = TamreedyColors.mapBase);
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(s.width * .1, 0),
      Offset(s.width * .25, s.height),
      road,
    );
    canvas.drawLine(
      Offset(s.width * .5, 0),
      Offset(s.width * .58, s.height),
      road,
    );
    canvas.drawLine(
      Offset(0, s.height * .25),
      Offset(s.width, s.height * .12),
      road,
    );
    canvas.drawLine(
      Offset(0, s.height * .55),
      Offset(s.width, s.height * .75),
      road,
    );
    final park = Paint()..color = const Color(0xFFCFE6DA);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * .15, s.height * .2, 56, 36),
        const Radius.circular(18),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s.width * .72, s.height * .62, 52, 52),
        const Radius.circular(24),
      ),
      park,
    );
    final route = Path()
      ..moveTo(s.width * .62, s.height * .3)
      ..cubicTo(
        s.width * .5,
        s.height * .3,
        s.width * .35,
        s.height * .4,
        s.width * .42,
        s.height * .6,
      )
      ..cubicTo(
        s.width * .5,
        s.height * .75,
        s.width * .72,
        s.height * .55,
        s.width * .66,
        s.height * .38,
      );
    final dash = Paint()
      ..color = const Color(0xFF0A87B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final m in route.computeMetrics()) {
      for (double d = 0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, d + 7), dash);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
