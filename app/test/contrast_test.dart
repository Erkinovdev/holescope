import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/core/theme.dart';

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  for (final (name, c) in [('dark', HpColors.dark), ('light', HpColors.light)]) {
    group('контраст ≥ 4.5:1 ($name)', () {
      final fg = {
        'text': c.text, 'muted': c.muted, 'amberText': c.amberText, 'smoothText': c.smoothText,
        'warnText': c.warnText, 'craterText': c.craterText,
      };
      for (final bg in {'bgBase': c.bgBase, 'surface': c.surface, 'raised': c.raised}.entries) {
        for (final f in fg.entries) {
          test('${f.key} на ${bg.key}', () => expect(ratio(f.value, bg.value), greaterThanOrEqualTo(4.5)));
        }
      }
      test('текст кнопки на янтарной заливке', () => expect(ratio(c.inverse, c.amber), greaterThanOrEqualTo(4.5)));
      test('amberText на amberDim', () => expect(ratio(c.amberText, c.amberDim), greaterThanOrEqualTo(4.5)));
    });
  }
}
