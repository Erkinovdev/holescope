
import 'package:flutter/material.dart';

/// Рисует знак Holescope (геометрия 1:1 с assets/figma/logo.svg, коробка 96×96).
void drawMark(Canvas canvas, Offset center, double size, {required Color amber, required Color hole, double eye = 1, double ring = 1}) {
  final k = size / 96;
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(k);
  final a = Paint()..color = amber.withValues(alpha: ring);
  canvas.drawCircle(const Offset(48, 48), 38.88, Paint()..color = a.color..style = PaintingStyle.stroke..strokeWidth = 6.72);
  for (final r in const [Rect.fromLTWH(44.64, 0, 6.72, 21.12), Rect.fromLTWH(44.64, 74.88, 6.72, 21.12), Rect.fromLTWH(0, 44.64, 21.12, 6.72), Rect.fromLTWH(74.88, 44.64, 21.12, 6.72)]) {
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3.36)), a);
  }
  if (eye > 0) {
    canvas.drawOval(Rect.fromCenter(center: const Offset(48, 48), width: 44.16, height: 25.92), Paint()..color = amber.withValues(alpha: eye));
    canvas.drawOval(Rect.fromCenter(center: const Offset(48, 50.4), width: 28.8, height: 14.4), Paint()..color = hole.withValues(alpha: eye));
  }
  canvas.restore();
}

