import 'package:flutter_test/flutter_test.dart';
import 'package:holescope/algo/params.dart';

void main() {
  test('параметры с сервера применяются', () {
    final p = AlgoParams.fromJson({'floor': 2.5, 'k_noise': 5, 'ri_bounds': [0.04, 0.06, 0.09, 0.14], 'unknown': 1});
    expect(p.floor, 2.5);
    expect(p.kNoise, 5.0);
    expect(p.riBounds, [0.04, 0.06, 0.09, 0.14]);
    expect(p.wheelbaseM, const AlgoParams().wheelbaseM);
  });

  test('мусор и значения вне диапазона заменяются встроенными', () {
    final p = AlgoParams.fromJson({'floor': 99, 'k_noise': 'x', 'smooth_samples': null, 'ri_bounds': [0.1, 0.05, 0.08, 0.13]});
    const d = AlgoParams();
    expect(p.floor, d.floor);
    expect(p.kNoise, d.kNoise);
    expect(p.smoothSamples, d.smoothSamples);
    expect(p.riBounds, d.riBounds);
  });

  test('пустой ответ = встроенные значения', () {
    final p = AlgoParams.fromJson({});
    expect(p.floor, const AlgoParams().floor);
  });
}
