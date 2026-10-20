import 'package:flutter_test/flutter_test.dart';

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
}
