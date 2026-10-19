import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/core/road_map.dart';
import 'package:holescope/services/api_client.dart';

import 'support/fake_api.dart';

void main() {
  test('ячейка карты: целые смещения превращаются в координаты с точностью до метра', () async {
    final api = fakeApi();
    final segs = await api.mapCell(4132, 6922, set: 'all');
    expect(segs.length, 4);
    final s = segs.firstWhere((x) => x.id == 2);
    expect(s.latA, closeTo(41.3270, 2e-6));
    expect(s.lonB, closeTo(69.2298, 2e-6));
    expect(s.cls, 'D');
    expect(s.direction, 1);
  });

  test('геометрия: линии сгруппированы по стилям, оценённые смещены на полосу, неоценённые нет', () {
    const a = SegmentDto(1, 41.3270, 69.2270, 41.3270, 69.2284, 'A', 'A', 1);
    const b = SegmentDto(2, 41.3270, 69.2270, 41.3270, 69.2284, 'A', 'A', -1);
    const c = SegmentDto(3, 41.3280, 69.2270, 41.3280, 69.2312, '', 'C', 1);
    final g = CellGeometry.build([a, b, c]);
    expect(g.segments, 3);
    // стиль «A» (класс ровности A): две линии (по одной на направление), по 4 числа
    final pts = g.lines[CellGeometry.styleA]!;
    expect(pts.length, 8);
    // направления разведены ≈ на 5 м (±2.5 м)
    final dy = (pts[1] - pts[5]).abs();
    expect(dy, closeTo(5.0, 0.2));
    // неоценённая местная дорога — стиль «minor», без смещения
    expect(g.lines[CellGeometry.styleMinor]!.length, 4);
    expect(g.lines.containsKey(CellGeometry.styleMajor), isFalse);
  });

  test('рисование крупной ячейки быстрое: геометрия 50 000 сегментов строится за доли секунды', () {
    final segs = [for (var k = 0; k < 50000; k++) SegmentDto(k, 41.30 + (k % 500) * 1e-5, 69.27 + (k ~/ 500) * 1e-5, 41.30 + (k % 500) * 1e-5 + 1e-5, 69.27 + (k ~/ 500) * 1e-5, k % 3 == 0 ? 'C' : '', 'B', 1)];
    final sw = Stopwatch()..start();
    CellGeometry.build(segs);
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });
}
